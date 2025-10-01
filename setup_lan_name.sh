#!/bin/bash
# Ubuntu 局域网广播配置脚本
# 适用版本：Ubuntu 20.04+（Debian 系也可参考）

set -e

# 1. 需要 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "请用 sudo 运行此脚本"
    exit 1
fi

# 2. 用户输入 NetBIOS 名称
read -p "请输入要广播的 NetBIOS 名称（建议全大写，无空格）: " NETBIOS_NAME
read -p "请输入 Windows 工作组名（默认 WORKGROUP）: " WORKGROUP
WORKGROUP=${WORKGROUP:-WORKGROUP}

echo ">>> 安装 Samba 和 Avahi..."
apt update
apt install -y samba avahi-daemon

echo ">>> 配置 Samba..."
# 备份原配置
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%F_%T)

# 修改 smb.conf
grep -q "netbios name" /etc/samba/smb.conf && \
    sed -i "s/^.*netbios name.*/   netbios name = $NETBIOS_NAME/" /etc/samba/smb.conf || \
    sed -i "/^\[global\]/a\   netbios name = $NETBIOS_NAME" /etc/samba/smb.conf

grep -q "workgroup" /etc/samba/smb.conf && \
    sed -i "s/^.*workgroup.*/   workgroup = $WORKGROUP/" /etc/samba/smb.conf || \
    sed -i "/^\[global\]/a\   workgroup = $WORKGROUP" /etc/samba/smb.conf

echo ">>> 启动并设置开机自启..."
systemctl enable --now smbd nmbd avahi-daemon

echo ">>> 配置完成！"
HOSTNAME_NOW=$(hostname)
IP_ADDR=$(hostname -I | awk '{print $1}')

echo "--------------------------------------"
echo "当前主机名: $HOSTNAME_NOW"
echo "NetBIOS 名称: $NETBIOS_NAME"
echo "工作组: $WORKGROUP"
echo "IP 地址: $IP_ADDR"
echo
echo "Windows 可用: \\\\$NETBIOS_NAME 或 \\\\$IP_ADDR"
echo "Linux/macOS 可用: ping ${HOSTNAME_NOW}.local"
echo "--------------------------------------"
