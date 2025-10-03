#!/bin/bash

# Nginx 反向代理配置自动生成脚本（支持路径代理）
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
read -p "请输入路径 (例如: /api 或直接回车表示根路径 /): " PROXY_PATH
read -p "请输入后端服务端口 (例如: 3000): " PROXY_PORT

# 处理路径输入
if [ -z "$PROXY_PATH" ]; then
    PROXY_PATH="/"
else
    # 确保路径以 / 开头
    if [[ ! "$PROXY_PATH" =~ ^/ ]]; then
        PROXY_PATH="/$PROXY_PATH"
    fi
    # 移除末尾的 /
    PROXY_PATH="${PROXY_PATH%/}"
    # 如果处理后为空，设为 /
    if [ -z "$PROXY_PATH" ]; then
        PROXY_PATH="/"
    fi
fi

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
CONF_FILE="${SITES_AVAILABLE}/${CONF_NAME}.conf"

# 确保目录存在
mkdir -p "$SITES_AVAILABLE"
mkdir -p "$SITES_ENABLED"

echo -e "\n${GREEN}配置信息:${NC}"
echo -e "域名: ${SERVER_NAME}"
echo -e "路径: ${PROXY_PATH}"
echo -e "代理端口: ${PROXY_PORT}"
echo -e "配置文件: ${CONF_FILE}"
echo ""

# 生成 location 块
generate_location_block() {
    local path="$1"
    local port="$2"

    cat << EOF
    location ${path} {
        proxy_pass http://127.0.0.1:${port};
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
EOF
}

# 检查配置文件是否已存在
if [ -f "$CONF_FILE" ]; then
    echo -e "${YELLOW}配置文件 ${CONF_NAME}.conf 已存在${NC}"

    # 检查是否已经有相同路径的配置
    if grep -q "location ${PROXY_PATH}" "$CONF_FILE"; then
        echo -e "${YELLOW}路径 ${PROXY_PATH} 已存在于配置中${NC}"
        read -p "是否覆盖此路径的配置? (y/n): " OVERWRITE_PATH
        if [ "$OVERWRITE_PATH" != "y" ] && [ "$OVERWRITE_PATH" != "Y" ]; then
            echo -e "${YELLOW}操作已取消${NC}"
            exit 0
        fi

        # 删除旧的 location 块
        echo -e "${GREEN}删除旧的 location ${PROXY_PATH} 配置...${NC}"
        # 使用 sed 删除匹配的 location 块
        sed -i "/location ${PROXY_PATH//\//\\/}/,/^    }/d" "$CONF_FILE"
    fi

    # 在最后一个 } 之前插入新的 location 块
    echo -e "${GREEN}添加新的路径配置到现有文件...${NC}"

    # 创建临时文件
    TEMP_FILE=$(mktemp)

    # 生成新的 location 块
    NEW_LOCATION=$(generate_location_block "$PROXY_PATH" "$PROXY_PORT")

    # 在最后一个 } 前插入
    awk -v location="$NEW_LOCATION" '
        /^}$/ && !found {
            print location
            found=1
        }
        {print}
    ' "$CONF_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$CONF_FILE"
    echo -e "${GREEN}✓ 已添加路径 ${PROXY_PATH} 到配置文件${NC}"

else
    # 创建新的配置文件
    echo -e "${GREEN}创建新配置文件...${NC}"

    cat > "$CONF_FILE" << EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVER_NAME};

    # 访问日志
    access_log /var/log/nginx/${CONF_NAME}_access.log;
    error_log /var/log/nginx/${CONF_NAME}_error.log;

    # 反向代理配置
$(generate_location_block "$PROXY_PATH" "$PROXY_PORT")
}
EOF

    echo -e "${GREEN}✓ 配置文件已生成: ${CONF_FILE}${NC}"

    # 创建软链接
    if [ -L "${SITES_ENABLED}/${CONF_NAME}.conf" ]; then
        rm "${SITES_ENABLED}/${CONF_NAME}.conf"
    fi

    ln -s "$CONF_FILE" "${SITES_ENABLED}/${CONF_NAME}.conf"
    echo -e "${GREEN}✓ 软链接已创建: ${SITES_ENABLED}/${CONF_NAME}.conf${NC}"
fi

# 显示当前配置内容
echo -e "\n${YELLOW}当前配置文件内容:${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"
cat "$CONF_FILE"
echo -e "${YELLOW}----------------------------------------${NC}\n"

# 测试 Nginx 配置
echo -e "${YELLOW}测试 Nginx 配置...${NC}"
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

# 检查是否需要配置 SSL
NEED_SSL=false
if [ -f "$CONF_FILE" ]; then
    # 检查是否已经有 SSL 配置
    if ! grep -q "listen 443 ssl" "$CONF_FILE"; then
        NEED_SSL=true
    fi
fi

# 使用 Certbot 生成 SSL 证书
if [ "$NEED_SSL" = true ]; then
    echo -e "\n${YELLOW}检测到需要配置 SSL 证书...${NC}"
    echo -e "${YELLOW}注意: 请确保域名已正确解析到本服务器${NC}\n"

    read -p "是否现在配置 SSL 证书? (y/n): " CONFIGURE_SSL

    if [ "$CONFIGURE_SSL" = "y" ] || [ "$CONFIGURE_SSL" = "Y" ]; then
        if certbot --nginx -d "$SERVER_NAME" --non-interactive --agree-tos --redirect --register-unsafely-without-email 2>/dev/null || \
           certbot --nginx -d "$SERVER_NAME"; then
            echo -e "\n${GREEN}✓ SSL 证书配置成功${NC}"
        else
            echo -e "\n${YELLOW}⚠ SSL 证书配置失败，但 HTTP 配置已生效${NC}"
            echo -e "${YELLOW}你可以稍后手动运行: certbot --nginx -d ${SERVER_NAME}${NC}"
        fi

        # 最终测试并重载
        nginx -t && systemctl reload nginx
    else
        echo -e "${YELLOW}跳过 SSL 配置，稍后可手动运行: certbot --nginx -d ${SERVER_NAME}${NC}"
    fi
else
    echo -e "\n${GREEN}✓ SSL 证书已配置，无需重复申请${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}配置完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "域名: ${SERVER_NAME}"
echo -e "路径: ${PROXY_PATH}"
echo -e "代理端口: ${PROXY_PORT}"
echo -e "配置文件: ${CONF_FILE}"
echo -e "\n访问地址: http://${SERVER_NAME}${PROXY_PATH}"
if [ "$NEED_SSL" = false ] || [ "$CONFIGURE_SSL" = "y" ] || [ "$CONFIGURE_SSL" = "Y" ]; then
    echo -e "HTTPS访问: https://${SERVER_NAME}${PROXY_PATH}"
fi
echo -e "${GREEN}========================================${NC}"