#!/bin/bash
# ==============================================================================
# L2TP/IPsec VPN Auto Installer (Hokage Legend Edition)
# OS Support: Ubuntu 20.04, 22.04, 24.04
# Features: Kernel Module Injection, Port Hijack Cleanup, xl2tpd 1.3.12 Downgrade
# ==============================================================================

# --- UBAH KREDENSIAL VPN ANDA DI SINI ---
VPN_USER="hokage"
VPN_PASS="legend123"
VPN_PSK="rahasia123"
# ----------------------------------------

# 1. Pengecekan Akses Root
if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root (gunakan sudo)."
  exit 1
fi

echo "[1/10] Membersihkan aplikasi konflik dan pembajak port (SoftEther)..."
systemctl stop vpnserver 2>/dev/null
systemctl disable vpnserver 2>/dev/null
killall vpnserver 2>/dev/null

echo "[2/10] Mengonfigurasi parameter Kernel (Sysctl) dan RP Filter..."
cat > /etc/sysctl.d/99-vpn-server.conf << EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.eth0.rp_filter = 0
EOF
sysctl --system

echo "[3/10] Menginstal dependensi sistem dan modul Kernel jaringan..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-modules-extra-$(uname -r) strongswan ppp net-tools iptables iptables-persistent nftables curl wget

echo "[4/10] Menyuntikkan Modul Kernel (L2TP, ESP, IPsec)..."
modprobe af_key
modprobe xfrm_user
modprobe xfrm4_tunnel
modprobe l2tp_ppp
modprobe pppol2tp
modprobe esp4
modprobe ah4
modprobe ipcomp

cat > /etc/modules-load.d/vpn-modules.conf << EOF
af_key
xfrm_user
xfrm4_tunnel
l2tp_ppp
esp4
ah4
ipcomp
EOF

echo "[5/10] Menghapus xl2tpd bawaan dan melakukan Downgrade ke versi 1.3.12..."
systemctl stop xl2tpd 2>/dev/null
apt-get remove --purge xl2tpd -y
wget -q http://archive.ubuntu.com/ubuntu/pool/universe/x/xl2tpd/xl2tpd_1.3.12-1.1_amd64.deb -O /tmp/xl2tpd.deb
dpkg -i /tmp/xl2tpd.deb
apt-get --fix-broken install -y
apt-mark hold xl2tpd
rm -f /tmp/xl2tpd.deb

echo "[6/10] Menulis konfigurasi StrongSwan (IPsec) mode Kompatibilitas Windows..."
cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    keyexchange=ikev1
    ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,aes128-sha1,3des-sha1!
EOF

cat > /etc/ipsec.secrets << EOF
: PSK "${VPN_PSK}"
EOF

echo "[7/10] Menulis konfigurasi L2TP (xl2tpd) tanpa Access Control..."
cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701
access control = no
ipsec saref = no

[lns default]
ip range = 10.10.10.10-10.10.10.100
local ip = 10.10.10.1
require chap = yes
refuse pap = yes
require authentication = yes
name = LinuxVPNserver
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

echo "[8/10] Menulis konfigurasi PPP dan kredensial pengguna..."
cat > /etc/ppp/options.xl2tpd << EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
mtu 1200
mru 1000
nodefaultroute
debug
proxyarp
connect-delay 5000
name LinuxVPNserver
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
EOF

cat > /etc/ppp/chap-secrets << EOF
# client        server  secret                  IP addresses
"${VPN_USER}"   *       "${VPN_PASS}"           *
EOF

echo "[9/10] Mengatur Firewall (Nftables & Iptables) dan NAT..."
# Dapatkan nama antarmuka jaringan utama
ETH=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')

# Flush firewall bawaan
nft flush ruleset 2>/dev/null
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Buka port prioritas tertinggi
iptables -I INPUT 1 -p udp --dport 500 -j ACCEPT
iptables -I INPUT 1 -p udp --dport 4500 -j ACCEPT
iptables -I INPUT 1 -p udp --dport 1701 -j ACCEPT
iptables -I INPUT 1 -p esp -j ACCEPT

# Aktifkan NAT (Internet Routing)
iptables -t nat -A POSTROUTING -o $ETH -j MASQUERADE
iptables -A FORWARD -i $ETH -j ACCEPT
iptables -A FORWARD -o $ETH -j ACCEPT

# Simpan Iptables agar permanen saat reboot
netfilter-persistent save
netfilter-persistent reload

echo "[10/10] Merestart seluruh layanan VPN..."
systemctl restart systemd-networkd 2>/dev/null
systemctl enable ipsec
systemctl enable xl2tpd
systemctl restart ipsec
systemctl restart xl2tpd

# Deteksi IP Publik Server
PUBLIC_IP=$(curl -s ifconfig.me)

echo ""
echo "======================================================================="
echo "                 INSTALASI VPN L2TP/IPSEC SELESAI!                     "
echo "======================================================================="
echo "Server IP (Host)    : ${PUBLIC_IP}"
echo "VPN Username        : ${VPN_USER}"
echo "VPN Password        : ${VPN_PASS}"
echo "Pre-Shared Key (PSK): ${VPN_PSK}"
echo "======================================================================="
echo "Di Windows Anda, pastikan tipe VPN diatur ke:"
echo "Layer 2 Tunneling Protocol with IPsec (L2TP/IPsec)"
echo "Allow these protocols -> Ceklis Microsoft CHAP Version 2 (MS-CHAP v2)"
echo "======================================================================="
