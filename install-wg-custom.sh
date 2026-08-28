#!/bin/bash
# =========================================================
# AUTO INSTALLER WIREGUARD (HOKAGE LEGEND EDITION)
# Anti-Silent Drop, Anti-Bentrok IP, Auto-Bypass Firewall
# =========================================================

echo "1. Menyiapkan sistem dan sinkronisasi waktu..."
apt-get update -y
apt-get install -y wireguard wireguard-tools qrencode iptables ntpdate curl dos2unix
ntpdate pool.ntp.org
timedatectl set-ntp true

echo "2. Mematikan sistem firewall modern yang mengganggu..."
systemctl stop wg-quick@wg0 2>/dev/null
systemctl stop ufw 2>/dev/null
systemctl disable ufw 2>/dev/null
systemctl stop firewalld 2>/dev/null
systemctl disable firewalld 2>/dev/null
nft flush ruleset 2>/dev/null

echo "3. Optimasi Kernel (Routing & Anti-Silent Drop)..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

echo "4. Membuat Kunci Kriptografi..."
mkdir -p /etc/wireguard
cd /etc/wireguard
rm -f server_private_key server_public_key
wg genkey | tee server_private_key | wg pubkey > server_public_key
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
SERVER_PRIV=$(cat server_private_key)
SERVER_PUB=$(cat server_public_key)

echo "5. Mendapatkan IP Publik & Interface otomatis..."
PUB_IP=$(curl -s ifconfig.me || wget -qO- ipv4.icanhazip.com)
NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

echo "6. Membuat konfigurasi wg0.conf..."
echo "[Interface]" > /etc/wireguard/wg0.conf
echo "Address = 10.66.66.1/24" >> /etc/wireguard/wg0.conf
echo "ListenPort = 51820" >> /etc/wireguard/wg0.conf
echo "PrivateKey = $SERVER_PRIV" >> /etc/wireguard/wg0.conf
echo "PostUp = iptables -t raw -I PREROUTING 1 -p udp --dport 51820 -j ACCEPT; iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE" >> /etc/wireguard/wg0.conf
echo "PostDown = iptables -t raw -D PREROUTING -p udp --dport 51820 -j ACCEPT; iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE" >> /etc/wireguard/wg0.conf
echo "" >> /etc/wireguard/wg0.conf
echo "[Peer]" >> /etc/wireguard/wg0.conf
echo "PublicKey = $CLIENT_PUB" >> /etc/wireguard/wg0.conf
echo "AllowedIPs = 10.66.66.2/32" >> /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf

echo "7. Menyalakan WireGuard secara permanen..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "8. Memasang Auto-Check Expired & Kuota (Crontab)..."
# Memastikan folder script ada dan file cron diberi izin eksekusi
mkdir -p /usr/bin/vpn-script/script/
chmod +x /usr/bin/vpn-script/script/wg-cron.sh 2>/dev/null

# Filter cron lama agar tidak ada jadwal ganda saat install ulang
crontab -l 2>/dev/null | grep -v "wg-cron.sh" > /tmp/cron_wg

# Tambahkan eksekusi otomatis setiap 1 jam sekali agar limit Megabytes lebih akurat
echo "0 * * * * /bin/bash /usr/bin/vpn-script/script/wg-cron.sh > /dev/null 2>&1" >> /tmp/cron_wg
crontab /tmp/cron_wg
rm -f /tmp/cron_wg

echo ""
echo "====================================================="
echo "      BERHASIL! COPY PROFIL INI KE WINDOWS ANDA      "
echo "====================================================="
echo "[Interface]"
echo "PrivateKey = $CLIENT_PRIV"
echo "Address = 10.66.66.2/24"
echo "DNS = 8.8.8.8, 8.8.4.4"
echo "MTU = 1280"
echo ""
echo "[Peer]"
echo "PublicKey = $SERVER_PUB"
echo "Endpoint = $PUB_IP:51820"
echo "AllowedIPs = 0.0.0.0/0, ::/0"
echo "PersistentKeepalive = 25"
echo "====================================================="
