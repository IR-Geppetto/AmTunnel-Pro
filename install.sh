#!/bin/bash

# ==========================================
# AmneziaWG Smart Auto-Installer Pro (V2.0)
# ==========================================

# --- تنظیمات رنگ‌ها ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_DIR="/etc/amnezia/awg"
INTERFACE="awg0"

# ==========================================
# بررسی‌های اولیه (دسترسی و سیستم‌عامل)
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ خطا: این اسکریپت باید با دسترسی Root اجرا شود! (sudo su)${NC}"
  exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        echo -e "${RED}❌ خطا: این اسکریپت فقط برای سیستم‌عامل‌های Ubuntu و Debian طراحی شده است.${NC}"
        exit 1
    fi
fi

# ==========================================
# توابع پایه
# ==========================================
install_dependencies() {
    echo -e "${CYAN}🔄 در حال آپدیت سیستم و نصب پیش‌نیازها...${NC}"
    apt update -y > /dev/null 2>&1
    apt install -y curl jq wget iptables iptables-persistent wireguard-tools > /dev/null 2>&1
}

check_and_install_awg() {
    echo -e "${YELLOW}⚙️ در حال نصب هسته AmneziaWG-Go...${NC}"
    wget -q -O /usr/bin/amneziawg-go https://github.com/amnezia-vpn/amneziawg-go/releases/latest/download/amneziawg-go_linux_amd64
    chmod +x /usr/bin/amneziawg-go
    mkdir -p $CONFIG_DIR
}

generate_smart_params() {
    H1=$(shuf -i 1000000-2147483647 -n 1)
    H2=$(shuf -i 1000000-2147483647 -n 1)
    H3=$(shuf -i 1000000-2147483647 -n 1)
    H4=$(shuf -i 1000000-2147483647 -n 1)
    JC=$(shuf -i 4-8 -n 1)
    JMIN=$(shuf -i 40-60 -n 1)
    JMAX=$(shuf -i 400-1200 -n 1)
    S1=$(shuf -i 15-100 -n 1)
    S2=$(shuf -i 15-100 -n 1)
    if [ $((S1 + 56)) -eq $S2 ]; then S2=$((S2 + 1)); fi
}

# ==========================================
# قابلیت‌های ویژه (BBR و فایروال ایمن)
# ==========================================
enable_bbr() {
    clear
    echo -e "${GREEN}=== 🚀 فعال‌سازی الگوریتم شتاب‌دهنده BBR ===${NC}"
    echo -e "این الگوریتم (ساخت گوگل) سرعت انتقال داده را در نت‌های خراب ایران به شدت افزایش می‌دهد."
    read -p "آیا مایل به فعال‌سازی BBR هستید؟ (y/n): " OPT
    if [[ "$OPT" =~ ^[Yy]$ ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
        echo -e "${GREEN}✅ شتاب‌دهنده BBR با موفقیت فعال شد!${NC}"
    else
        echo -e "${YELLOW}عملیات لغو شد.${NC}"
    fi
    sleep 2
}

safe_remove_iptables() {
    echo -e "${CYAN}🧹 در حال پاکسازی ایمن قوانین فایروال مرتبط با تانل...${NC}"
    # پاک کردن رول‌های فورواردینگ بدون آسیب زدن به داکر و سایر برنامه‌ها
    iptables-save -t nat | grep -e "10.0.0.1" -e "awg0" | sed 's/^-A /-D /' | while read rule; do
        iptables -t nat $rule 2>/dev/null
    done
    netfilter-persistent save > /dev/null 2>&1
}

# ==========================================
# وضعیت تانل (Status Check)
# ==========================================
check_status() {
    clear
    echo -e "${CYAN}=== 📊 بررسی وضعیت تانل ===${NC}"
    
    if systemctl is-active --quiet wg-quick@$INTERFACE; then
        echo -e "وضعیت سرویس: ${GREEN}روشن و فعال (RUNNING) ✅${NC}"
        
        # تشخیص اینکه این سرور ایران است یا خارج
        LOCAL_IP=$(ip -4 addr show $INTERFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        
        if [ "$LOCAL_IP" == "10.0.0.1" ]; then
            TARGET="10.0.0.2"
            echo -e "نقش سرور: ${YELLOW}خارج (Master)${NC}"
        elif [ "$LOCAL_IP" == "10.0.0.2" ]; then
            TARGET="10.0.0.1"
            echo -e "نقش سرور: ${YELLOW}ایران (Slave)${NC}"
        else
            echo -e "${RED}آی‌پی مجازی یافت نشد!${NC}"
            read -p "برای بازگشت Enter بزنید..."
            return
        fi

        echo -e "\n${CYAN}در حال پینگ گرفتن از سمت مقابل ($TARGET)...${NC}"
        ping -c 3 -W 2 $TARGET | grep -E 'time=|packets'
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo -e "\n${GREEN}🎉 ارتباط دوطرفه برقرار است و تانل بدون مشکل کار می‌کند!${NC}"
        else
            echo -e "\n${RED}⚠️ پینگ تایم‌آوت شد! ارتباط برقرار نیست. (احتمالاً فایروال پورت را بسته یا توکن اشتباه بوده)${NC}"
        fi
    else
        echo -e "وضعیت سرویس: ${RED}خاموش (STOPPED) ❌${NC}"
    fi
    echo -e "\n-------------------------------------"
    read -p "برای بازگشت به منو Enter بزنید..."
}

# ==========================================
# نصب سرور اصلی (Master)
# ==========================================
setup_master_server() {
    clear
    echo -e "${GREEN}=== 🚀 راه‌اندازی سرور اصلی (Master) ===${NC}"
    install_dependencies
    check_and_install_awg
    
    echo -e "\n${CYAN}--- تنظیمات هوشمند تانل ---${NC}"
    echo -e "1) ${YELLOW}استاندارد${NC} (سرور دوم متصل می‌شود - پیشنهاد برای سرور خارج)"
    echo -e "2) ${YELLOW}معکوس${NC} (این سرور به سرور دوم متصل می‌شود - ضد DPI قدرتمند)"
    read -p "انتخاب شما (پیش‌فرض 1): " TUNNEL_DIR
    TUNNEL_DIR=${TUNNEL_DIR:-1}
    
    read -p "یک پورت برای اتصال وارد کنید (پیش‌فرض 443): " AWG_PORT
    AWG_PORT=${AWG_PORT:-443}
    
    MASTER_PRIV=$(wg genkey)
    MASTER_PUB=$(echo "$MASTER_PRIV" | wg pubkey)
    SLAVE_PRIV=$(wg genkey)
    SLAVE_PUB=$(echo "$SLAVE_PRIV" | wg pubkey)
    
    generate_smart_params
    MASTER_IP=$(curl -s ifconfig.me)
    
    TOKEN_STRING="${TUNNEL_DIR}|${AWG_PORT}|${MASTER_IP}|${MASTER_PUB}|${SLAVE_PRIV}|${JC}|${JMIN}|${JMAX}|${S1}|${S2}|${H1}|${H2}|${H3}|${H4}"
    ENCODED_TOKEN=$(echo -n "$TOKEN_STRING" | base64 -w 0)
    
    cat > $CONFIG_DIR/$INTERFACE.conf <<EOF
[Interface]
PrivateKey = $MASTER_PRIV
Address = 10.0.0.1/24
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
EOF

    if [ "$TUNNEL_DIR" == "1" ]; then
        echo "ListenPort = $AWG_PORT" >> $CONFIG_DIR/$INTERFACE.conf
        echo -e "\n[Peer]\nPublicKey = $SLAVE_PUB\nAllowedIPs = 10.0.0.2/32" >> $CONFIG_DIR/$INTERFACE.conf
        iptables -A INPUT -p udp --dport $AWG_PORT -j ACCEPT
        netfilter-persistent save > /dev/null 2>&1
    else
        read -p "لطفا آی‌پی سرور دوم (مثلاً ایران) را وارد کنید: " SLAVE_IP
        echo -e "\n[Peer]\nPublicKey = $SLAVE_PUB\nEndpoint = $SLAVE_IP:$AWG_PORT\nAllowedIPs = 10.0.0.2/32\nPersistentKeepalive = 25" >> $CONFIG_DIR/$INTERFACE.conf
        TOKEN_STRING="${TUNNEL_DIR}|${AWG_PORT}|${MASTER_IP}|${MASTER_PUB}|${SLAVE_PRIV}|${JC}|${JMIN}|${JMAX}|${S1}|${S2}|${H1}|${H2}|${H3}|${H4}|${SLAVE_IP}"
        ENCODED_TOKEN=$(echo -n "$TOKEN_STRING" | base64 -w 0)
    fi

    wg-quick up $CONFIG_DIR/$INTERFACE.conf > /dev/null 2>&1
    systemctl enable wg-quick@$INTERFACE > /dev/null 2>&1
    
    clear
    echo -e "${GREEN}✅ سرور اصلی با موفقیت تنظیم شد!${NC}"
    echo -e "\n${YELLOW}=== توکن اتصال (این را کپی کنید) ===${NC}"
    echo -e "\n${CYAN}$ENCODED_TOKEN${NC}\n"
    echo -e "${YELLOW}=====================================${NC}"
    read -p "برای بازگشت به منو Enter بزنید..."
}

# ==========================================
# اتصال سرور دوم (Slave)
# ==========================================
setup_slave_server() {
    clear
    echo -e "${GREEN}=== 🔗 اتصال سرور دوم (Slave) ===${NC}"
    read -p "توکن دریافتی از سرور اصلی را پیست (Paste) کنید: " INPUT_TOKEN
    
    DECODED=$(echo "$INPUT_TOKEN" | base64 -d)
    IFS='|' read -r DIR PORT MIP MPUB SPRIV JC JMIN JMAX S1 S2 H1 H2 H3 H4 SIP <<< "$DECODED"
    
    if [ -z "$SPRIV" ]; then
        echo -e "${RED}❌ خطا: توکن نامعتبر است!${NC}"
        sleep 2
        return
    fi
    
    install_dependencies
    check_and_install_awg
    
    cat > $CONFIG_DIR/$INTERFACE.conf <<EOF
[Interface]
PrivateKey = $SPRIV
Address = 10.0.0.2/24
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
EOF

    if [ "$DIR" == "1" ]; then
        echo -e "\n[Peer]\nPublicKey = $MPUB\nEndpoint = $MIP:$PORT\nAllowedIPs = 10.0.0.1/32\nPersistentKeepalive = 25" >> $CONFIG_DIR/$INTERFACE.conf
    else
        echo "ListenPort = $PORT" >> $CONFIG_DIR/$INTERFACE.conf
        echo -e "\n[Peer]\nPublicKey = $MPUB\nAllowedIPs = 10.0.0.1/32" >> $CONFIG_DIR/$INTERFACE.conf
        iptables -A INPUT -p udp --dport $PORT -j ACCEPT
        netfilter-persistent save > /dev/null 2>&1
    fi

    wg-quick up $CONFIG_DIR/$INTERFACE.conf > /dev/null 2>&1
    systemctl enable wg-quick@$INTERFACE > /dev/null 2>&1
    
    echo -e "${GREEN}✅ سرور دوم با موفقیت به تانل متصل شد!${NC}"
    read -p "برای تست اتصال، از منوی اصلی گزینه بررسی وضعیت (5) را انتخاب کنید. Enter بزنید..."
}

# ==========================================
# تنظیم پورت فورواردینگ (X-UI)
# ==========================================
setup_port_forward() {
    clear
    echo -e "${GREEN}=== 🔀 تنظیم پورت فورواردینگ (X-UI و...) ===${NC}"
    read -p "پورت کانفیگ V2ray/X-UI شما در سرور خارج چند است؟ (مثلاً 8080): " XUI_PORT
    
    if [ -z "$XUI_PORT" ]; then echo -e "${RED}پورت نامعتبر!${NC}"; sleep 2; return; fi
    
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    
    iptables -t nat -A PREROUTING -p tcp --dport $XUI_PORT -j DNAT --to-destination 10.0.0.1:$XUI_PORT
    iptables -t nat -A PREROUTING -p udp --dport $XUI_PORT -j DNAT --to-destination 10.0.0.1:$XUI_PORT
    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
    iptables -A INPUT -p tcp --dport $XUI_PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $XUI_PORT -j ACCEPT
    
    netfilter-persistent save > /dev/null 2>&1
    echo -e "${GREEN}✅ پورت $XUI_PORT با موفقیت به داخل تانل هدایت شد!${NC}"
    read -p "Enter بزنید..."
}

# ==========================================
# حذف کامل
# ==========================================
uninstall_awg() {
    clear
    read -p "آیا از حذف کامل تانل و تنظیمات شبکه مطمئن هستید؟ (y/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        wg-quick down $CONFIG_DIR/$INTERFACE.conf 2>/dev/null
        systemctl disable wg-quick@$INTERFACE 2>/dev/null
        rm -rf $CONFIG_DIR
        rm -f /usr/bin/amneziawg-go
        
        safe_remove_iptables
        
        echo -e "${GREEN}✅ تانل AmneziaWG و رول‌های آن با موفقیت پاک شد! (سایر رول‌های سرور شما دست‌نخورده باقی ماند)${NC}"
    else
        echo -e "${YELLOW}عملیات لغو شد.${NC}"
    fi
    read -p "Enter بزنید..."
}

# ==========================================
# منوی اصلی
# ==========================================
while true; do
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "   🛡️ AmneziaWG Smart Auto-Installer Pro 🛡️"
    echo -e "         ${YELLOW}By: Your Name / GitHub${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo -e " 1) 🚀 نصب سرور اصلی (Master - تولید توکن)"
    echo -e " 2) 🔗 اتصال سرور دوم (Slave - با توکن)"
    echo -e " 3) 🔀 تنظیم پورت فورواردینگ (برای پنل X-UI)"
    echo -e " 4) ⚡ فعال‌سازی شتاب‌دهنده BBR (پیشنهادی)"
    echo -e " 5) 📊 بررسی وضعیت تانل (پینگ‌تست هوشمند)"
    echo -e " 6) 🗑️ حذف ایمن تانل و تنظیمات"
    echo -e " 0) ❌ خروج"
    echo -e "${CYAN}==================================================${NC}"
    read -p "لطفاً یک گزینه انتخاب کنید: " OPTION
    
    case $OPTION in
        1) setup_master_server ;;
        2) setup_slave_server ;;
        3) setup_port_forward ;;
        4) enable_bbr ;;
        5) check_status ;;
        6) uninstall_awg ;;
        0) clear; echo -e "${GREEN}خداحافظ!${NC}"; exit 0 ;;
        *) echo -e "${RED}گزینه نامعتبر!${NC}"; sleep 1 ;;
    esac
done
