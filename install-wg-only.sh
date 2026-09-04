#!/bin/bash
# =========================================================
# MASTER AUTO INSTALLER (HOKAGE LEGEND EDITION)
# Khusus WireGuard Saja (Isolated Mode)
# =========================================================
clear

echo "========================================================="
echo "          MEMULAI INSTALASI WIREGUARD ONLY               "
echo "========================================================="
echo "Memulai instalasi dalam 3 detik..."
sleep 3

echo -e "\n[1/7] Menyiapkan sistem dan sinkronisasi waktu..."
apt-get update -y
apt-get install -y wireguard wireguard-tools qrencode iptables ntpdate curl dos2unix
ntpdate pool.ntp.org
timedatectl set-ntp true

echo -e "\n[2/7] Mematikan sistem firewall modern yang mengganggu..."
systemctl stop wg-quick@wg0 2>/dev/null
systemctl stop ufw 2>/dev/null
systemctl disable ufw 2>/dev/null
systemctl stop firewalld 2>/dev/null
systemctl disable firewalld 2>/dev/null
nft flush ruleset 2>/dev/null

echo -e "\n[3/7] Optimasi Kernel (Routing & Anti-Silent Drop)..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

echo -e "\n[4/7] Membuat Kunci Kriptografi WireGuard..."
mkdir -p /etc/wireguard
cd /etc/wireguard
rm -f server_private_key server_public_key
wg genkey | tee server_private_key | wg pubkey > server_public_key
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
SERVER_PRIV=$(cat server_private_key)
SERVER_PUB=$(cat server_public_key)

echo -e "\n[5/7] Mendapatkan IP Publik & Interface otomatis..."
PUB_IP=$(curl -s ifconfig.me || wget -qO- ipv4.icanhazip.com)
NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

# Default port diset ke 40000 untuk menghindari bentrok dengan skrip lain
WG_PORT=40000

echo -e "\n[6/7] Membuat konfigurasi wg0.conf..."
cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.66.66.1/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
PostUp = iptables -I INPUT -p udp --dport $WG_PORT -j ACCEPT; iptables -I FORWARD -i wg0 -j ACCEPT; iptables -I FORWARD -o wg0 -j ACCEPT; iptables -t nat -I POSTROUTING -o $NIC -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT || true; iptables -D FORWARD -i wg0 -j ACCEPT || true; iptables -D FORWARD -o wg0 -j ACCEPT || true; iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE || true

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.66.66.2/32
EOF
chmod 600 /etc/wireguard/wg0.conf

echo -e "\n[7/7] Menyalakan WireGuard secara permanen..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

# --- GARANSI AUTO-START SETELAH REBOOT ---
systemctl enable netfilter-persistent 2>/dev/null
# -----------------------------------------
clear
echo "====================================================="
echo "   INSTALASI WIREGUARD SELESAI (PORT: $WG_PORT)      "
echo "====================================================="
echo "Silakan gunakan menu 'vpn' untuk mengelola akun."
