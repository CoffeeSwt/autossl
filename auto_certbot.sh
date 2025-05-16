#!/bin/bash

# ========== 可配置区域 ==========
EMAIL="897884964@qq.com"
DOMAINS_FILE="./domains.txt"
CERT_DIR="./certbot_certs"       # 你可以保留这个变量但暂时不用它存证书，证书用默认路径
WWW_DIR="./www"
LOG_FILE="./certbot.log"
NGINX_CONF_DIR="/etc/nginx/conf.d"
# ================================

# ========= 颜色 ==========
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========= 把相对路径转成绝对路径 ==========
ABS_WWW_DIR=$(realpath "$WWW_DIR")

# ========= 检测 80 端口 ==========
check_port_80() {
    echo -e "${YELLOW}[INFO] 检查 80 端口是否被占用...${NC}"
    local listen_info
    listen_info=$(sudo ss -tulpn | grep ':80 .*LISTEN' | grep -v $$)
    if [ -n "$listen_info" ]; then
        echo -e "${RED}[ERROR] 80 端口已被监听，详情：${NC}"
        echo "$listen_info"
        exit 1
    fi
    echo -e "${GREEN}[OK] 80 端口可用${NC}"
}

# ========= 安装 Certbot ==========
install_certbot() {
    if ! command -v certbot &>/dev/null; then
        echo -e "${YELLOW}[INFO] 安装 Certbot...${NC}"
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y certbot
        elif command -v yum &>/dev/null; then
            sudo yum install -y certbot
        else
            echo -e "${RED}[ERROR] 无法识别的包管理器${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[OK] Certbot 已安装${NC}"
    fi
}

# ========= 读取域名 ==========
load_domains() {
    if [ ! -f "$DOMAINS_FILE" ]; then
        echo -e "${RED}[ERROR] 域名文件 $DOMAINS_FILE 不存在${NC}"
        exit 1
    fi
    mapfile -t DOMAINS < <(grep -v '^\s*#' "$DOMAINS_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
    echo -e "${GREEN}[OK] 已加载 ${#DOMAINS[@]} 个域名${NC}"
}

# ========= 自动创建网站目录 ==========
create_www_dirs() {
    echo -e "${YELLOW}[INFO] 创建网站根目录...${NC}"
    for domain in "${DOMAINS[@]}"; do
        local dir="$ABS_WWW_DIR/$domain"
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo -e "${GREEN}[OK] 已创建目录 $dir${NC}"
            echo "<h1>Welcome to $domain</h1>" > "$dir/index.html"
        else
            echo -e "${YELLOW}[INFO] 目录已存在 $dir${NC}"
        fi
    done
}

# ========= 申请/更新证书 ==========
obtain_certificates() {
    echo -e "${YELLOW}[INFO] 开始申请/更新证书...${NC}"
    for domain in "${DOMAINS[@]}"; do
        echo -e "${YELLOW}[INFO] 申请 $domain…${NC}"
        sudo certbot certonly --agree-tos --non-interactive --email "$EMAIL" \
            --preferred-challenges http --standalone \
            -d "$domain"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[SUCCESS] $domain 证书就绪${NC}"
        else
            echo -e "${RED}[ERROR] $domain 证书申请失败${NC}"
        fi
    done
}

# ========= 自动续期 ==========
setup_auto_renew() {
    echo -e "${YELLOW}[INFO] 配置自动续期任务…${NC}"
    local renew_script="/usr/local/bin/certbot_renew.sh"
    sudo bash -c "cat > $renew_script" <<EOF
#!/bin/bash
echo "\$(date) - 检查证书续期" >> $LOG_FILE
certbot renew --quiet
if [ \$? -eq 0 ]; then
    echo "\$(date) - 续期成功，重载 Nginx" >> $LOG_FILE
    systemctl reload nginx
else
    echo "\$(date) - 续期失败" >> $LOG_FILE
fi
EOF
    sudo chmod +x "$renew_script"
    (crontab -l 2>/dev/null; echo "0 0 * * * $renew_script") | crontab -
    echo -e "${GREEN}[OK] 自动续期已设置（每天 00:00）${NC}"
}

# ========= 生成并部署 Nginx 配置 ==========
deploy_nginx_config() {
    echo -e "${YELLOW}[INFO] 生成并部署 Nginx 配置到 $NGINX_CONF_DIR …${NC}"
    for domain in "${DOMAINS[@]}"; do
        local tmp_conf="./nginx_${domain}.conf"
        cat > "$tmp_conf" <<EOF
# HTTP -> HTTPS 重定向 & ACME 验证
server {
    listen 80;
    server_name $domain;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate     /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root $ABS_WWW_DIR/$domain;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        sudo cp "$tmp_conf" "$NGINX_CONF_DIR/$domain.conf"
        echo -e "${GREEN}[OK] 已部署 $domain.conf${NC}"
    done

    echo -e "${YELLOW}[INFO] 测试 Nginx 配置…${NC}"
    sudo nginx -t && echo -e "${GREEN}[OK] 配置语法正确${NC}" || { echo -e "${RED}[ERROR] 配置语法错误，请检查${NC}"; exit 1; }

    echo -e "${YELLOW}[INFO] 重新加载 Nginx…${NC}"
    sudo systemctl reload nginx
    echo -e "${GREEN}[OK] Nginx 已重载${NC}"
}

# ========= 主流程 ==========
main() {
    echo -e "${GREEN}=== Certbot & Nginx 自动化管理脚本 ===${NC}"
    check_port_80
    install_certbot
    load_domains
    create_www_dirs
    obtain_certificates
    setup_auto_renew
    deploy_nginx_config
    echo -e "${GREEN}=== 全部任务完成 ===${NC}"
}

main
