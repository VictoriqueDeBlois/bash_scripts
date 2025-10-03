#!/bin/bash

# Nginx 反向代理配置自动生成脚本
# 用法: ./generate_nginx_proxy.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

# 检查并自动安装必要的软件包
check_and_install() {
    local packages_to_install=()

    # 检查 nginx
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}未找到 nginx，将自动安装${NC}"
        packages_to_install+=("nginx")
    fi

    # 检查 certbot
    if ! command -v certbot &> /dev/null; then
        echo -e "${YELLOW}未找到 certbot，将自动安装${NC}"
        packages_to_install+=("certbot" "python3-certbot-nginx")
    fi

    # 如果有需要安装的包
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo -e "\n${GREEN}开始安装依赖包...${NC}"
        echo -e "将安装: ${packages_to_install[*]}\n"

        # 更新包列表
        apt update || {
            echo -e "${RED}错误: apt update 失败${NC}"
            exit 1
        }

        # 安装包
        apt install -y "${packages_to_install[@]}" || {
            echo -e "${RED}错误: 安装失败${NC}"
            exit 1
        }

        echo -e "${GREEN}✓ 依赖包安装完成${NC}\n"

        # 如果安装了 nginx，确保服务已启动
        if [[ " ${packages_to_install[*]} " =~ " nginx " ]]; then
            systemctl enable nginx
            systemctl start nginx
            echo -e "${GREEN}✓ Nginx 服务已启动${NC}\n"
        fi
    else
        echo -e "${GREEN}✓ 所有依赖已满足${NC}\n"
    fi
}

# 执行检查和安装
check_and_install

# 获取用户输入
echo -e "${GREEN}=== Nginx 反向代理配置生成工具 ===${NC}\n"

read -p "请输入域名 (例如: api.example.com): " SERVER_NAME
read -p "请输入后端服务端口 (例如: 3000): " PROXY_PORT

# 验证输入
if [ -z "$SERVER_NAME" ]; then
    echo -e "${RED}错误: 域名不能为空${NC}"
    exit 1
fi

if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ]; then
    echo -e "${RED}错误: 端口必须是 1-65535 之间的数字${NC}"
    exit 1
fi

# 提取子域名作为配置文件名
SUBDOMAIN=$(echo $SERVER_NAME | cut -d'.' -f1)
CONF_NAME="${SUBDOMAIN}"
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
CONF_FILE="${SITES_AVAILABLE}/${CONF_NAME}"

# 确保目录存在
mkdir -p "$SITES_AVAILABLE"
mkdir -p "$SITES_ENABLED"

# 检查配置文件是否已存在
if [ -f "$CONF_FILE" ]; then
    read -p "配置文件 ${CONF_NAME} 已存在，是否覆盖? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
fi

echo -e "\n${GREEN}开始生成配置...${NC}"

# 生成 Nginx 配置文件
cat > "$CONF_FILE" << EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVER_NAME};

    # 访问日志
    access_log /var/log/nginx/${CONF_NAME}_access.log;
    error_log /var/log/nginx/${CONF_NAME}_error.log;

    # 反向代理配置
    location / {
        proxy_pass http://127.0.0.1:${PROXY_PORT};
        proxy_http_version 1.1;

        # 请求头设置
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket 支持
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

echo -e "${GREEN}✓ 配置文件已生成: ${CONF_FILE}${NC}"

# 创建软链接
if [ -L "${SITES_ENABLED}/${CONF_NAME}" ]; then
    rm "${SITES_ENABLED}/${CONF_NAME}"
fi

ln -s "$CONF_FILE" "${SITES_ENABLED}/${CONF_NAME}"
echo -e "${GREEN}✓ 软链接已创建: ${SITES_ENABLED}/${CONF_NAME}${NC}"

# 测试 Nginx 配置
echo -e "\n${YELLOW}测试 Nginx 配置...${NC}"
if nginx -t; then
    echo -e "${GREEN}✓ Nginx 配置测试通过${NC}"
else
    echo -e "${RED}✗ Nginx 配置测试失败，请检查配置${NC}"
    exit 1
fi

# 重载 Nginx
echo -e "\n${YELLOW}重载 Nginx...${NC}"
systemctl reload nginx
echo -e "${GREEN}✓ Nginx 已重载${NC}"

# 使用 Certbot 生成 SSL 证书
echo -e "\n${YELLOW}开始生成 SSL 证书...${NC}"
echo -e "${YELLOW}注意: 请确保域名已正确解析到本服务器${NC}\n"

if certbot --nginx -d "$SERVER_NAME" --non-interactive --agree-tos --redirect --register-unsafely-without-email || \
   certbot --nginx -d "$SERVER_NAME"; then
    echo -e "\n${GREEN}✓ SSL 证书配置成功${NC}"
else
    echo -e "\n${YELLOW}⚠ SSL 证书配置失败，但 HTTP 配置已生效${NC}"
    echo -e "${YELLOW}你可以稍后手动运行: certbot --nginx -d ${SERVER_NAME}${NC}"
fi

# 最终测试并重载
nginx -t && systemctl reload nginx

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}配置完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "域名: ${SERVER_NAME}"
echo -e "代理端口: ${PROXY_PORT}"
echo -e "配置文件: ${CONF_FILE}"
echo -e "\n访问地址: https://${SERVER_NAME}"
echo -e "${GREEN}========================================${NC}"