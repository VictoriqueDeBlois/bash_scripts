#!/bin/bash

# ZeroTier Moon 服务器自动安装配置脚本
# 使用方法: sudo bash zerotier_moon_setup.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo_error "此脚本必须以 root 权限运行 (使用 sudo)"
   exit 1
fi

# 获取公网IP
echo_info "正在获取公网 IP 地址..."
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip)

if [ -z "$PUBLIC_IP" ]; then
    echo_error "无法自动获取公网 IP，请手动输入:"
    read -p "请输入服务器公网 IP: " PUBLIC_IP
fi

echo_info "检测到公网 IP: $PUBLIC_IP"

# 设置 ZeroTier 端口
ZEROTIER_PORT=9993
read -p "ZeroTier 端口 (默认 9993): " INPUT_PORT
if [ ! -z "$INPUT_PORT" ]; then
    ZEROTIER_PORT=$INPUT_PORT
fi

echo_info "使用端口: $ZEROTIER_PORT"

# 检查当前目录是否有 planet 文件
BASH_DIR="$(pwd)"
CUSTOM_PLANET=""
if [ -f "planet" ]; then
    echo_info "检测到当前目录存在 planet 文件"
    read -p "是否使用此 planet 文件替换默认配置? (y/n): " USE_PLANET
    if [[ "$USE_PLANET" =~ ^[Yy]$ ]]; then
        CUSTOM_PLANET="$(pwd)/planet"
        echo_info "将使用自定义 planet 文件: $CUSTOM_PLANET"
    fi
elif ls planet.* &>/dev/null 2>&1; then
    PLANET_FILE=$(ls planet.* | head -1)
    echo_info "检测到当前目录存在 planet 文件: $PLANET_FILE"
    read -p "是否使用此 planet 文件替换默认配置? (y/n): " USE_PLANET
    if [[ "$USE_PLANET" =~ ^[Yy]$ ]]; then
        CUSTOM_PLANET="$(pwd)/$PLANET_FILE"
        echo_info "将使用自定义 planet 文件: $CUSTOM_PLANET"
    fi
else
    echo_info "未检测到自定义 planet 文件,将使用默认配置"
fi

# 安装 ZeroTier
echo_info "开始安装 ZeroTier..."
if command -v zerotier-cli &> /dev/null; then
    echo_warn "ZeroTier 已安装，跳过安装步骤"
else
    curl -s https://install.zerotier.com | bash
    echo_info "ZeroTier 安装完成"
fi

# 等待 ZeroTier 服务启动
sleep 3

# 替换 planet 文件(如果有自定义 planet)
if [ ! -z "$CUSTOM_PLANET" ]; then
    echo_info "替换 planet 文件..."
    ZEROTIER_DIR="/var/lib/zerotier-one"
    
    # 备份原始 planet 文件
    if [ -f "$ZEROTIER_DIR/planet" ]; then
        echo_info "备份原始 planet 文件..."
        cp $ZEROTIER_DIR/planet $ZEROTIER_DIR/planet.bak.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 复制自定义 planet 文件
    cp $CUSTOM_PLANET $ZEROTIER_DIR/planet
    echo_info "已替换为自定义 planet 文件"
    
    # 重启服务使 planet 生效
    echo_info "重启 ZeroTier 服务以应用新的 planet 配置..."
    systemctl restart zerotier-one
    sleep 3
    
    if systemctl is-active --quiet zerotier-one; then
        echo_info "ZeroTier 服务重启成功,自定义 planet 已生效"
    else
        echo_error "ZeroTier 服务重启失败"
        systemctl status zerotier-one
        exit 1
    fi
fi

# 进入 ZeroTier 目录
ZEROTIER_DIR="/var/lib/zerotier-one"
cd $ZEROTIER_DIR

# 生成 moon 配置文件
echo_info "生成 Moon 配置文件..."
zerotier-idtool initmoon identity.public > moon.json

# 备份原始配置
cp moon.json moon.json.bak

# 修改配置文件中的 IP 地址
echo_info "配置 Moon 服务器地址..."
python3 - <<EOF
import json

with open('moon.json', 'r') as f:
    config = json.load(f)

# 修改 stableEndpoints
config['roots'][0]['stableEndpoints'] = ["$PUBLIC_IP/$ZEROTIER_PORT"]

with open('moon.json', 'w') as f:
    json.dump(config, f, indent=2)

print("配置文件已更新")
EOF

# 如果 Python 不可用，使用 sed 替代
if [ $? -ne 0 ]; then
    echo_warn "Python3 不可用，使用 sed 修改配置..."
    sed -i "s|\"stableEndpoints\": \[\]|\"stableEndpoints\": [\"$PUBLIC_IP/$ZEROTIER_PORT\"]|g" moon.json
fi

echo_info "Moon 配置内容:"
cat moon.json

# 生成 moon 文件
echo_info "生成 Moon 文件..."
zerotier-idtool genmoon moon.json

# 获取生成的 moon 文件名
MOON_FILE=$(ls -t 000000*.moon 2>/dev/null | head -1)

if [ -z "$MOON_FILE" ]; then
    echo_error "Moon 文件生成失败"
    exit 1
fi

echo_info "生成的 Moon 文件: $MOON_FILE"

# 提取 World ID
WORLD_ID=$(echo $MOON_FILE | sed 's/.moon//')
echo_info "World ID: $WORLD_ID"

# 创建 moons.d 目录并移动文件
echo_info "配置 Moon 服务..."
mkdir -p moons.d
mv $MOON_FILE moons.d/

# 重启 ZeroTier 服务
echo_info "重启 ZeroTier 服务..."
systemctl restart zerotier-one
sleep 3

# 检查服务状态
if systemctl is-active --quiet zerotier-one; then
    echo_info "ZeroTier 服务运行正常"
else
    echo_error "ZeroTier 服务启动失败"
    systemctl status zerotier-one
    exit 1
fi

# 显示防火墙配置提示
echo ""
echo_info "=========================================="
echo_info "Moon 服务器配置完成!"
echo_info "=========================================="
echo ""
echo_info "World ID: $WORLD_ID"
echo_info "Moon 文件位置: $ZEROTIER_DIR/moons.d/$MOON_FILE"
if [ ! -z "$CUSTOM_PLANET" ]; then
    echo_info "已使用自定义 Planet: $CUSTOM_PLANET"
    echo_info "原始 Planet 已备份到: $ZEROTIER_DIR/planet.bak.*"
fi
echo ""
echo_warn "重要提示:"
echo "1. 请确保防火墙开放 UDP 端口 $ZEROTIER_PORT"
echo ""
echo "   UFW 防火墙:"
echo "   sudo ufw allow $ZEROTIER_PORT/udp"
echo ""
echo "   Firewalld 防火墙:"
echo "   sudo firewall-cmd --permanent --add-port=$ZEROTIER_PORT/udp"
echo "   sudo firewall-cmd --reload"
echo ""
echo "   云服务器安全组:"
echo "   请在控制台添加入站规则: UDP $ZEROTIER_PORT"
echo ""
echo "2. 客户端配置 Moon 服务器:"
echo "   - 将文件 $ZEROTIER_DIR/moons.d/$MOON_FILE 复制到客户端"
echo "   - Linux: 放到 /var/lib/zerotier-one/moons.d/"
echo "   - Windows: 放到 C:\\ProgramData\\ZeroTier\\One\\moons.d\\"
echo "   - macOS: 放到 /Library/Application Support/ZeroTier/One/moons.d/"
echo "   - 重启客户端 ZeroTier 服务"
echo ""
echo "3. 客户端验证连接:"
echo "   zerotier-cli orbit $WORLD_ID $WORLD_ID"
echo "   zerotier-cli listpeers"
echo ""
echo_info "=========================================="

# 保存 Moon 文件到用户目录
cp $ZEROTIER_DIR/moons.d/$MOON_FILE $BASH_DIR/

echo_info "Moon 文件已备份到: $BASH_DIR"
echo ""

exit 0
