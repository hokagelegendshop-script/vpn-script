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
apt-get install -y wireguard wireguard-tools qrencode iptables ntpdate curl dos2unix python3 python3-pip
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
    limit_quota=$(echo "$line" | awk '{print $6}')
    pubkey=$(grep -A 2 "^### Client $user\b" "$wg_conf" | grep "PublicKey" | awk '{print $3}')
    
    if [[ "$today" > "$exp_date" ]]; then
        wg set wg0 peer "$pubkey" remove
        sed -i "s/^### Client $user/### Expired $user/" "$wg_conf"
        continue
    fi

    if [ -n "$limit_quota" ] && [ "$limit_quota" -gt 0 ]; then
        traffic=$(wg show wg0 transfer | grep "$pubkey")
        if [ -n "$traffic" ]; then
            rx_bytes=$(echo "$traffic" | awk '{print $2}')
            tx_bytes=$(echo "$traffic" | awk '{print $3}')
            total_mb=$(((rx_bytes + tx_bytes) / 1024 / 1024))
            if [ "$total_mb" -ge "$limit_quota" ]; then
                wg set wg0 peer "$pubkey" remove
                sed -i "s/^### Client $user/### QuotaExceeded $user/" "$wg_conf"
            fi
        fi
    fi
done
EOF
chmod +x /usr/bin/vpn-script/script/wg-cron.sh
crontab -l 2>/dev/null | grep -v "wg-cron.sh" > /tmp/cron_wg
echo "0 * * * * /bin/bash /usr/bin/vpn-script/script/wg-cron.sh > /dev/null 2>&1" >> /tmp/cron_wg
crontab /tmp/cron_wg
rm -f /tmp/cron_wg

echo -e "\n[9/12] Mengunduh dan Menjalankan Installer L2TP..."
wget -qO /tmp/install-l2tp https://github.com/hokagelegendshop-script/vpn-script/raw/refs/heads/main/install-l2tp
chmod +x /tmp/install-l2tp
bash /tmp/install-l2tp

echo -e "\n[10/12] Mengunduh dan Menjalankan Installer PPTP..."
wget -qO /tmp/pptp-vpn https://github.com/hokagelegendshop-script/vpn-script/raw/refs/heads/main/pptp-vpn
chmod +x /tmp/pptp-vpn
bash /tmp/pptp-vpn

echo -e "\n[11/12] Menginstal Library Telegram Bot..."
pip3 install pyTelegramBotAPI --break-system-packages 2>/dev/null || pip3 install pyTelegramBotAPI

echo -e "\n[12/12] Menanamkan Arsitektur Bot Hokage Legend..."
mkdir -p /usr/bin/vpn-script/bot-telegram/core

# Membuat config.py
cat <<EOF > /usr/bin/vpn-script/bot-telegram/config.py
BOT_TOKEN = "$bot_token"
ADMIN_ID = "$admin_id"
EOF

# Membuat core/vpn_handler.py
cat << 'EOF' > /usr/bin/vpn-script/bot-telegram/core/vpn_handler.py
import subprocess
def run_bash_script(command):
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr
EOF
# Membuat core/wg_manager.py (Logika Final Anti-Error)
cat << 'EOF' > /usr/bin/vpn-script/bot-telegram/core/wg_manager.py
import os
import subprocess

def create_wg_account(username, exp_days=30, limit_ip=0, limit_quota=0):
    username = username.strip().replace(" ", "_")
    check_cmd = f"grep -qw '^### Client {username}' /etc/wireguard/wg0.conf"
    if subprocess.run(check_cmd, shell=True).returncode == 0:
        return False, f"❌ Gagal! Username '{username}' sudah terdaftar.", None

    bash_script = f"""#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SERVER_PUB_IP=\$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
SERVER_PUB_KEY=\$(cat /etc/wireguard/server_public_key)

LAST_IP=\$(grep -oP 'AllowedIPs = 10\\.66\\.66\\.\\K[0-9]+' /etc/wireguard/wg0.conf | sort -n | tail -1)
if [ -z "\$LAST_IP" ]; then
    CLIENT_IP="10.66.66.3"
else
    CLIENT_IP="10.66.66.\$((LAST_IP+1))"
fi

CLIENT_PRIV_KEY=\$(wg genkey)
CLIENT_PUB_KEY=\$(echo "\$CLIENT_PRIV_KEY" | wg pubkey)
exp_date=\$(date -d "+{exp_days} days" +"%Y-%m-%d")

cat <<INNER_EOF >> /etc/wireguard/wg0.conf
### Client {username} \$exp_date {limit_ip} {limit_quota}
[Peer]
PublicKey = \$CLIENT_PUB_KEY
AllowedIPs = \$CLIENT_IP/32
INNER_EOF

wg set wg0 peer "\$CLIENT_PUB_KEY" allowed-ips "\$CLIENT_IP/32"

mkdir -p /usr/bin/vpn-script/dashboard-user/config-wg
CLIENT_CONF="/usr/bin/vpn-script/dashboard-user/config-wg/{username}.conf"

cat <<INNER_EOF > "\$CLIENT_CONF"
[Interface]
PrivateKey = \$CLIENT_PRIV_KEY
Address = \$CLIENT_IP/24
DNS = 8.8.8.8, 8.8.4.4
MTU = 1280

[Peer]
PublicKey = \$SERVER_PUB_KEY
Endpoint = \$SERVER_PUB_IP:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
INNER_EOF

echo "\$CLIENT_IP|\$exp_date|\$CLIENT_CONF"
"""
    script_path = f"/tmp/wg_build_{username}.sh"
    with open(script_path, "w") as f:
        f.write(bash_script)
    os.chmod(script_path, 0o755)
    
    try:
        result = subprocess.check_output(['/bin/bash', script_path], text=True).strip()
        if os.path.exists(script_path): os.remove(script_path)
        if "|" not in result: return False, "❌ Gagal mengonfigurasi WireGuard.", None
        client_ip, exp_date, conf_path = result.split("|")
        
        formatted_quota = "Unlimited" if limit_quota == 0 else f"{limit_quota:,} MB"
        success_msg = (
            f"✅ *AKUN WIREGUARD BERHASIL DIBUAT* ✅\n"
            f"━━━━━━━━━━━━━━━━━━\n"
            f"👤 *Username* : `{username}`\n"
            f"🌐 *IP Client* : `{client_ip}`\n"
            f"⏳ *Expired*  : `{exp_date}` ({exp_days} Hari)\n"
            f"📊 *Limit Kuota* : `{formatted_quota}`\n"
            f"━━━━━━━━━━━━━━━━━━\n"
            f"👇 _File konfigurasi siap di-import:_"
        )
        return True, success_msg, conf_path
    except Exception as e:
        if os.path.exists(script_path): os.remove(script_path)
        return False, f"❌ Terjadi kesalahan: {e}", None
EOF
# Membuat bot.py (Versi Final dengan Logika Menu & Role Lengkap)
cat << 'EOF' > /usr/bin/vpn-script/bot-telegram/bot.py
import telebot
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
import config
from core import vpn_handler

bot = telebot.TeleBot(config.BOT_TOKEN)
user_view_mode = {}

def get_role(chat_id):
    if str(chat_id) == config.ADMIN_ID:
        return user_view_mode.get(chat_id, 'admin')
    return 'user'

def replace_with_text(bot, call, text, markup):
    try:
        if call.message.content_type == 'photo':
            bot.delete_message(call.message.chat.id, call.message.message_id)
            bot.send_message(call.message.chat.id, text, reply_markup=markup, parse_mode='Markdown')
        else:
            bot.edit_message_text(chat_id=call.message.chat.id, message_id=call.message.message_id, text=text, reply_markup=markup, parse_mode='Markdown')
    except Exception as e:
        pass

def replace_with_photo(bot, call, photo_id, text, markup):
    try:
        if call.message.content_type == 'text':
            bot.delete_message(call.message.chat.id, call.message.message_id)
            bot.send_photo(call.message.chat.id, photo_id, caption=text, reply_markup=markup, parse_mode='Markdown')
        else:
            bot.edit_message_caption(chat_id=call.message.chat.id, message_id=call.message.message_id, caption=text, reply_markup=markup, parse_mode='Markdown')
    except Exception as e:
        pass

def get_vpn_info_text(vpn_name):
    return (
        f"⚡ *PREMIUM {vpn_name} SERVER* ⚡\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"Nikmati koneksi tingkat tinggi dengan privasi maksimal. Cocok untuk *Browsing, Streaming, & Gaming* tanpa hambatan!\n\n"
        f"💳 *Tarif Layanan* : Rp 20.000 / Bulan\n"
        f"📱 *Limit Device*  : Max 3 IP Bersamaan\n"
        f"📊 *Limit Kuota*   : 200 GB (Kecepatan Penuh)\n\n"
        f"⚠️ _Syarat & Ketentuan:_\n"
        f"_Untuk melakukan pembuatan akun {vpn_name} baru, pastikan saldo di dompet Anda minimal tersedia *Rp 20.000*._\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"🛠 *Silakan pilih tindakan operasional di bawah ini:*"
    )

def get_start_markup(chat_id):
    markup = InlineKeyboardMarkup()
    if str(chat_id) == config.ADMIN_ID:
        markup.row(
            InlineKeyboardButton("👑 Admin", callback_data="role_admin"),
            InlineKeyboardButton("💼 Reseller", callback_data="role_reseller"),
            InlineKeyboardButton("👤 User", callback_data="role_user")
        )
    markup.add(InlineKeyboardButton("📋 Tampilkan Menu", callback_data="show_menu"))
    return markup

def get_admin_menu():
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("🌐 WireGuard", callback_data="menu_wg"),
        InlineKeyboardButton("🔒 SSTP", callback_data="menu_sstp"),
        InlineKeyboardButton("🔑 PPTP", callback_data="menu_pptp"),
        InlineKeyboardButton("🛡️ L2TP", callback_data="menu_l2tp")
    )
    markup.row(InlineKeyboardButton("❌ Tutup Menu", callback_data="close_menu"))
    return markup

def get_reseller_menu():
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("➕ Buat Akun Klien", callback_data="res_create"),
        InlineKeyboardButton("⏳ Perpanjang Klien", callback_data="res_extend"),
        InlineKeyboardButton("💰 Cek Saldo", callback_data="res_balance")
    )
    markup.row(InlineKeyboardButton("❌ Tutup Menu", callback_data="close_menu"))
    return markup

def get_user_menu():
    markup = InlineKeyboardMarkup()
    markup.row_width = 1
    markup.add(
        InlineKeyboardButton("🔍 Cek Status Akunku", callback_data="usr_check"),
        InlineKeyboardButton("🛒 Beli VPN Baru", callback_data="usr_buy_vpn"),
        InlineKeyboardButton("🎧 Hubungi Bantuan", callback_data="usr_cs")
    )
    markup.row(InlineKeyboardButton("❌ Tutup Menu", callback_data="close_menu"))
    return markup

def get_user_buy_menu():
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("🌐 WireGuard", callback_data="buy_wg"),
        InlineKeyboardButton("🔒 SSTP", callback_data="buy_sstp"),
        InlineKeyboardButton("🔑 PPTP", callback_data="buy_pptp"),
        InlineKeyboardButton("🛡️ L2TP", callback_data="buy_l2tp")
    )
    markup.row(InlineKeyboardButton("🔙 Kembali ke Profil", callback_data="show_menu"))
    return markup

def get_submenu_markup(proto, role):
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("➕ Buat Akun", callback_data=f"{proto}_create"),
        InlineKeyboardButton("⏳ Perpanjang", callback_data=f"{proto}_extend"),
        InlineKeyboardButton("🔍 Cek Akun", callback_data=f"{proto}_check"),
        InlineKeyboardButton("🗑️ Hapus Akun", callback_data=f"{proto}_delete")
    )
    if role == 'user':
        markup.row(InlineKeyboardButton("🔙 Kembali ke Katalog", callback_data="usr_buy_vpn"))
    else:
        markup.row(InlineKeyboardButton("🔙 Kembali ke Menu Utama", callback_data="show_menu"))
    return markup

@bot.message_handler(commands=['start'])
def send_welcome(message):
    chat_id = message.chat.id
    mode = get_role(chat_id).capitalize()
    if str(chat_id) == config.ADMIN_ID:
        welcome_text = (f"🤖 *Selamat Datang di Hokage Legend VPN Bot* 🤖\n\nStatus Anda: *Administrator*\nMode Tampilan Saat Ini: *{mode}*\n\nGunakan tombol di bawah untuk berpindah mode tampilan (Role Switch) sebelum masuk ke dalam menu dasbor.")
    else:
        welcome_text = ("🤖 *Selamat Datang di Hokage Legend VPN Bot* 🤖\n\nSaya adalah asisten otomatis untuk manajemen layanan VPN Anda.\nSilakan klik tombol di bawah ini untuk melihat daftar layanan kami.")
    bot.reply_to(message, welcome_text, parse_mode='Markdown', reply_markup=get_start_markup(chat_id))

@bot.callback_query_handler(func=lambda call: True)
def callback_handler(call):
    chat_id = call.message.chat.id
    if call.data.startswith("role_"):
        mode = call.data.split("_")[1]
        user_view_mode[chat_id] = mode
        bot.answer_callback_query(call.id, f"✅ Beralih ke UI {mode.capitalize()}")
        welcome_text = (f"🤖 *Selamat Datang di Hokage Legend VPN Bot* 🤖\n\nStatus Anda: *Administrator*\nMode Tampilan Saat Ini: *{mode.capitalize()}*\n\nGunakan tombol di bawah untuk berpindah mode tampilan (Role Switch) sebelum masuk ke dalam menu dasbor.")
        replace_with_text(bot, call, welcome_text, get_start_markup(chat_id))
        
    elif call.data == "show_menu":
        mode = get_role(chat_id)
        if mode == 'admin':
            text = "🛠 *Menu Utama (Mode Admin)*\nAkses Penuh (Folder: dashboard-admin)\nSilakan pilih layanan VPN:"
            replace_with_text(bot, call, text, get_admin_menu())
        elif mode == 'reseller':
            text = "💼 *Menu Utama (Mode Reseller)*\nAkses Reseller (Folder: dashboard-reseller)\nKelola klien dan saldo Anda:"
            replace_with_text(bot, call, text, get_reseller_menu())
        else:
            first_name = call.from_user.first_name
            last_name = call.from_user.last_name if call.from_user.last_name else ""
            full_name = f"{first_name} {last_name}".strip()
            saldo = "Rp 0" 
            text = (f"👤 *PROFIL PENGGUNA*\n━━━━━━━━━━━━━━━━━━\nNama : *{full_name}*\nID Telegram : `{chat_id}`\nSaldo : *{saldo}*\n━━━━━━━━━━━━━━━━━━\n\n🛠 *Menu Layanan Hokage Legend*\nSilakan pilih operasional di bawah ini:")
            markup = get_user_menu()
            photos = bot.get_user_profile_photos(chat_id)
            if photos.total_count > 0:
                replace_with_photo(bot, call, photos.photos[0][-1].file_id, text, markup)
            else:
                replace_with_text(bot, call, text, markup)
                
    elif call.data == "close_menu":
        mode = get_role(chat_id).capitalize()
        if str(chat_id) == config.ADMIN_ID:
            text = f"🤖 *Menu ditutup.*\nMode Tampilan: *{mode}*\nSilakan klik tombol di bawah jika ingin membuka menu kembali."
        else:
            text = "🤖 *Menu ditutup.*\nSilakan klik tombol di bawah jika ingin membuka menu kembali."
        replace_with_text(bot, call, text, get_start_markup(chat_id))

    elif call.data == "usr_buy_vpn":
        bot.answer_callback_query(call.id, "Silakan lihat daftar VPN kami.")
        text = "🛒 *Pilih Protokol VPN*\nSilakan pilih layanan VPN yang ingin Anda beli:\n*(Harga akan ditarik dari saldo Anda)*"
        photos = bot.get_user_profile_photos(chat_id)
        if photos.total_count > 0:
            replace_with_photo(bot, call, photos.photos[0][-1].file_id, text, get_user_buy_menu())
        else:
            replace_with_text(bot, call, text, get_user_buy_menu())

    elif call.data in ["buy_wg", "menu_wg", "buy_sstp", "menu_sstp", "buy_pptp", "menu_pptp", "buy_l2tp", "menu_l2tp"]:
        proto = call.data.split("_")[1]
        nama_vpn = proto.upper()
        bot.answer_callback_query(call.id, f"Membuka Menu {nama_vpn}...")
        text = get_vpn_info_text(nama_vpn)
        mode = get_role(chat_id)
        if mode == 'user':
            photos = bot.get_user_profile_photos(chat_id)
            if photos.total_count > 0:
                replace_with_photo(bot, call, photos.photos[0][-1].file_id, text, get_submenu_markup(proto, mode))
            else:
                replace_with_text(bot, call, text, get_submenu_markup(proto, mode))
        else:
            replace_with_text(bot, call, text, get_submenu_markup(proto, mode))

    elif call.data in ["wg_create", "sstp_create", "pptp_create", "l2tp_create"]:
        mode = get_role(chat_id)
        proto = call.data.split("_")[0].upper()
        if mode == 'user':
            current_saldo = 0 
            harga_vpn = 20000 
            if current_saldo < harga_vpn:
                pesan_gagal = f"❌ Saldo Anda tidak cukup!\nSaldo saat ini: Rp {current_saldo}\nSyarat Minimal: Rp {harga_vpn}\nSilakan top-up terlebih dahulu."
                bot.answer_callback_query(call.id, text=pesan_gagal, show_alert=True)
            else:
                bot.answer_callback_query(call.id, "✅ Saldo mencukupi, memproses...")
                bot.send_message(chat_id, f"Masukkan username untuk VPN {proto} Anda:")
        else:
            bot.answer_callback_query(call.id, "Memproses pembuatan akun...")
            bot.send_message(chat_id, f"Mode {mode.capitalize()}: Masukkan username untuk VPN {proto} Anda:")

if __name__ == "__main__":
    bot.infinity_polling(timeout=10, long_polling_timeout=5)
EOF

# Membuat Service Bot Systemd
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
systemctl start hokage-bot

clear
echo "====================================================="
echo "    INSTALASI SELESAI & BOT TELEGRAM TELAH AKTIF     "
echo "====================================================="
echo "WireGuard Config Windows Admin:"
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
echo "Silakan buka Telegram Anda dan ketik /start ke Bot!"
