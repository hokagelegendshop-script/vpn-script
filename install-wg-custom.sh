#!/bin/bash
# =========================================================
# MASTER AUTO INSTALLER (HOKAGE LEGEND EDITION)
# WireGuard + L2TP + PPTP + Telegram Bot Terintegrasi
# =========================================================
clear

echo "========================================================="
echo "        MENGUMPULKAN DATA BOT TELEGRAM HOKAGE            "
echo "========================================================="
read -p "Masukkan Token Bot Telegram Anda : " bot_token
read -p "Masukkan ID Telegram Admin Anda  : " admin_id
echo "========================================================="
echo "Memulai instalasi dalam 3 detik..."
sleep 3

echo -e "\n[1/12] Menyiapkan sistem dan sinkronisasi waktu..."
apt-get update -y
apt-get install -y wireguard wireguard-tools qrencode iptables ntpdate curl dos2unix python3 python3-pip pptpd
ntpdate pool.ntp.org
timedatectl set-ntp true

echo -e "\n[2/12] Mematikan sistem firewall modern yang mengganggu..."
systemctl stop wg-quick@wg0 2>/dev/null
systemctl stop ufw 2>/dev/null
systemctl disable ufw 2>/dev/null
systemctl stop firewalld 2>/dev/null
systemctl disable firewalld 2>/dev/null
nft flush ruleset 2>/dev/null

echo -e "\n[3/12] Optimasi Kernel (Routing & Anti-Silent Drop)..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

echo -e "\n[4/12] Membuat Kunci Kriptografi WireGuard..."
mkdir -p /etc/wireguard
cd /etc/wireguard
rm -f server_private_key server_public_key
wg genkey | tee server_private_key | wg pubkey > server_public_key
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
SERVER_PRIV=$(cat server_private_key)
SERVER_PUB=$(cat server_public_key)

echo -e "\n[5/12] Mendapatkan IP Publik & Interface otomatis..."
PUB_IP=$(curl -s ifconfig.me || wget -qO- ipv4.icanhazip.com)
NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

echo -e "\n[6/12] Membuat konfigurasi wg0.conf..."
cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV
PostUp = iptables -t raw -I PREROUTING 1 -p udp --dport 51820 -j ACCEPT; iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE; iptables -t nat -I PREROUTING 1 -d $PUB_IP -p udp --dport 51820 -j REDIRECT --to-ports 51820
PostDown = iptables -t raw -D PREROUTING -p udp --dport 51820 -j ACCEPT; iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE; iptables -t nat -D PREROUTING -d $PUB_IP -p udp --dport 51820 -j REDIRECT --to-ports 51820

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.66.66.2/32
EOF
chmod 600 /etc/wireguard/wg0.conf

echo -e "\n[7/12] Menyalakan WireGuard secara permanen..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo -e "\n[8/12] Memasang Auto-Check Expired & Kuota WireGuard..."
mkdir -p /usr/bin/vpn-script/script/
mkdir -p /usr/bin/vpn-script/dashboard-user/config-wg/
cat << 'EOF' > /usr/bin/vpn-script/script/wg-cron.sh
#!/bin/bash
today=$(date +%Y-%m-%d)
wg_conf="/etc/wireguard/wg0.conf"
grep "^### Client" "$wg_conf" | while read -r line; do
    user=$(echo "$line" | awk '{print $3}')
    exp_date=$(echo "$line" | awk '{print $4}')
    pubkey=$(grep -A 2 "^### Client $user\b" "$wg_conf" | grep "PublicKey" | awk '{print $3}')
    if [[ "$today" > "$exp_date" ]]; then
        wg set wg0 peer "$pubkey" remove
        sed -i "s/^### Client $user/### Expired $user/" "$wg_conf"
    fi
done
EOF
chmod +x /usr/bin/vpn-script/script/wg-cron.sh

echo -e "\n[9/12] Mengunduh Installer L2TP..."
wget -qO /tmp/install-l2tp https://github.com/hokagelegendshop-script/vpn-script/raw/refs/heads/main/install-l2tp
chmod +x /tmp/install-l2tp
bash /tmp/install-l2tp

echo -e "\n[10/12] Menginstal dan Mengonfigurasi PPTP (Native)..."
cat << 'EOF' > /etc/pptpd.conf
option /etc/ppp/pptpd-options
logwtmp
localip 10.20.20.1
remoteip 10.20.20.2-254
EOF

cat << 'EOF' > /etc/ppp/pptpd-options
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 8.8.4.4
proxyarp
nodefaultroute
lock
nobsdcomp
novj
novjccomp
nologfd
EOF

iptables -I INPUT 1 -p tcp --dport 1723 -j ACCEPT
iptables -I INPUT 1 -p gre -j ACCEPT
iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
netfilter-persistent save 2>/dev/null
systemctl restart pptpd
systemctl enable pptpd

echo -e "\n[11/12] Menginstal Library Telegram Bot..."
pip3 install pyTelegramBotAPI --break-system-packages 2>/dev/null || pip3 install pyTelegramBotAPI

echo -e "\n[12/12] Menanamkan Arsitektur Bot Hokage Legend..."
mkdir -p /usr/bin/vpn-script/bot-telegram/core

# config.py
cat <<EOF > /usr/bin/vpn-script/bot-telegram/config.py
BOT_TOKEN = "$bot_token"
ADMIN_ID = "$admin_id"
EOF

# ppp_manager.py (Core untuk L2TP, PPTP, SSTP)
cat << 'EOF' > /usr/bin/vpn-script/bot-telegram/core/ppp_manager.py
import subprocess
from datetime import datetime, timedelta

def create_ppp_account(username, password, exp_days, proto):
    username = username.strip()
    check_cmd = f"grep -qw '\"^{username}\"' /etc/ppp/chap-secrets || grep -qw '^{username}' /etc/ppp/chap-secrets"
    if subprocess.run(check_cmd, shell=True).returncode == 0:
        return False, f"❌ Gagal! Username '{username}' sudah terdaftar."

    exp_date = (datetime.now() + timedelta(days=int(exp_days))).strftime("%Y-%m-%d")
    
    with open("/etc/ppp/chap-secrets", "a") as f:
        f.write(f'"{username}" * "{password}" * # Exp: {exp_date}\n')
    
    ip = subprocess.check_output("curl -s ifconfig.me", shell=True, text=True).strip()
    
    try:
        psk = subprocess.check_output("awk -F'\"' '/PSK/ {print $2}' /etc/ipsec.secrets", shell=True, text=True).strip()
    except:
        psk = "rahasia123"

    msg = (
        f"✅ *AKUN {proto} BERHASIL DIBUAT* ✅\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"👤 *Username* : `{username}`\n"
        f"🔑 *Password* : `{password}`\n"
        f"🌐 *IP Server* : `{ip}`\n"
    )
    if proto in ["L2TP", "IPSec"]:
        msg += f"🔐 *IPSec PSK* : `{psk}`\n"
    
    msg += (
        f"⏳ *Expired*  : `{exp_date}` ({exp_days} Hari)\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"Silakan gunakan kredensial di atas untuk login."
    )
    return True, msg
EOF

# bot.py (Integrasi Multi-Step L2TP/PPTP)
cat << 'EOF' > /usr/bin/vpn-script/bot-telegram/bot.py
import telebot
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton, ForceReply
import config
from core import ppp_manager

bot = telebot.TeleBot(config.BOT_TOKEN)

def get_admin_menu():
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("🌐 WireGuard", callback_data="menu_wg"),
        InlineKeyboardButton("🔒 SSTP", callback_data="menu_sstp"),
        InlineKeyboardButton("🔑 PPTP", callback_data="menu_pptp"),
        InlineKeyboardButton("🛡️ L2TP", callback_data="menu_l2tp")
    )
    return markup

def get_submenu_markup(proto):
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("➕ Buat Akun", callback_data=f"{proto}_create"),
        InlineKeyboardButton("⏳ Perpanjang", callback_data=f"{proto}_extend")
    )
    markup.row(InlineKeyboardButton("🔙 Kembali", callback_data="show_menu"))
    return markup

def process_ppp_username(message, proto):
    username = message.text
    msg = bot.send_message(message.chat.id, f"🔑 Masukkan Password untuk klien `{username}`:", parse_mode='Markdown', reply_markup=ForceReply())
    bot.register_next_step_handler(msg, process_ppp_password, username, proto)

def process_ppp_password(message, username, proto):
    password = message.text
    msg = bot.send_message(message.chat.id, f"⏳ Masukkan masa aktif (Hari) untuk klien `{username}`:", parse_mode='Markdown', reply_markup=ForceReply())
    bot.register_next_step_handler(msg, process_ppp_expiry, username, password, proto)

def process_ppp_expiry(message, username, password, proto):
    try:
        exp_days = int(message.text)
        bot.send_message(message.chat.id, "⚙️ Memproses pembuatan akun ke database...")
        success, text = ppp_manager.create_ppp_account(username, password, exp_days, proto)
        bot.send_message(message.chat.id, text, parse_mode='Markdown')
    except ValueError:
        bot.send_message(message.chat.id, "❌ Error: Masa aktif harus berupa angka yang valid.")

@bot.message_handler(commands=['start'])
def send_welcome(message):
    chat_id = message.chat.id
    if str(chat_id) == config.ADMIN_ID:
        text = "🤖 *Selamat Datang Admin Hokage Legend* 🤖\nSilakan pilih menu layanan:"
        bot.send_message(chat_id, text, parse_mode='Markdown', reply_markup=get_admin_menu())

@bot.callback_query_handler(func=lambda call: True)
def callback_handler(call):
    chat_id = call.message.chat.id
    
    if call.data == "show_menu":
        bot.edit_message_text(chat_id=chat_id, message_id=call.message.message_id, text="🛠 *Menu Utama Admin*\nSilakan pilih layanan VPN:", parse_mode='Markdown', reply_markup=get_admin_menu())
        
    elif call.data in ["menu_wg", "menu_sstp", "menu_pptp", "menu_l2tp"]:
        proto = call.data.split("_")[1].upper()
        text = f"⚡ *Menu {proto}* ⚡\nSilakan pilih tindakan operasional:"
        bot.edit_message_text(chat_id=chat_id, message_id=call.message.message_id, text=text, parse_mode='Markdown', reply_markup=get_submenu_markup(proto.lower()))
        
    elif call.data in ["sstp_create", "pptp_create", "l2tp_create"]:
        proto = call.data.split("_")[0].upper()
        msg = bot.send_message(chat_id, f"👤 Masukkan *Username* untuk VPN {proto}:", parse_mode='Markdown', reply_markup=ForceReply())
        bot.register_next_step_handler(msg, process_ppp_username, proto)

if __name__ == "__main__":
    bot.infinity_polling()
EOF

cat <<EOF > /etc/systemd/system/hokage-bot.service
[Unit]
Description=Hokage Legend Telegram Bot
After=network.target

[Service]
User=root
WorkingDirectory=/usr/bin/vpn-script/bot-telegram
ExecStart=/usr/bin/python3 /usr/bin/vpn-script/bot-telegram/bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hokage-bot
systemctl restart hokage-bot

clear
echo "====================================================="
echo "    INSTALASI SELESAI & BOT TELEGRAM TELAH AKTIF     "
echo "====================================================="
echo "Silakan buka Telegram Anda dan ketik /start ke Bot!"
