#!/bin/bash

# Docker SSH 代理管理脚本
# 用法: ./docker-proxy.sh start user@server
#       ./docker-proxy.sh stop
#       ./docker-proxy.sh status

PROXY_CONFIG_DIR="/etc/systemd/system/docker.service.d"
PROXY_CONFIG_FILE="$PROXY_CONFIG_DIR/http-proxy.conf"
PID_FILE="/tmp/docker-ssh-proxy.pid"
PORT_FILE="/tmp/docker-ssh-proxy.port"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 查找空闲端口
find_free_port() {
    local port
    for port in {8080..9000}; do
        if ! netstat -tuln 2>/dev/null | grep -q ":$port " && \
           ! ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo $port
            return 0
        fi
    done
    # 如果上述范围都被占用，使用随机端口
    echo $((10000 + RANDOM % 10000))
}

# 启动 SSH 代理
start_proxy() {
    local server=$1

    if [ -z "$server" ]; then
        print_error "请提供服务器地址，格式: username@server-ip"
        echo "用法: $0 start username@server-ip"
        exit 1
    fi

    # 检查是否已经运行
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            print_warning "SSH 代理已在运行 (PID: $old_pid)"
            local old_port=$(cat "$PORT_FILE" 2>/dev/null || echo "未知")
            print_info "当前使用端口: $old_port"
            read -p "是否重启代理? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
            stop_proxy
        fi
    fi

    # 查找空闲端口
    local port=$(find_free_port)
    print_info "找到空闲端口: $port"

    # 查找 SSH 私钥
    local ssh_key=""
    local possible_keys=(
        "$HOME/.ssh/id_rsa"
        "$HOME/.ssh/id_ed25519"
        "$HOME/.ssh/id_ecdsa"
        "$HOME/.ssh/id_dsa"
    )

    for key in "${possible_keys[@]}"; do
        if [ -f "$key" ]; then
            ssh_key="$key"
            print_info "找到 SSH 私钥: $key"
            break
        fi
    done

    # 构建 SSH 命令参数
    local ssh_opts="-o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes"
    if [ -n "$ssh_key" ]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi

    # 测试 SSH 连接
    print_info "测试 SSH 连接到 $server ..."
    if [ -n "$ssh_key" ]; then
        if ! ssh -i "$ssh_key" -o BatchMode=yes -o ConnectTimeout=5 "$server" exit 2>/dev/null; then
            print_warning "使用密钥 $ssh_key 连接失败，将需要输入密码"
        else
            print_info "SSH 密钥认证成功"
        fi
    else
        print_warning "未找到 SSH 私钥，将需要输入密码"
    fi

    # 启动 SSH 隧道
    print_info "启动 SSH 隧道..."
    if [ -n "$ssh_key" ]; then
        ssh -f -N -D "$port" -i "$ssh_key" $ssh_opts "$server"
    else
        ssh -f -N -D "$port" $ssh_opts "$server"
    fi

    if [ $? -ne 0 ]; then
        print_error "SSH 隧道启动失败"
        exit 1
    fi

    # 获取 SSH 进程 PID
    sleep 2
    local pid=$(pgrep -f "ssh.*-D $port.*$server" | head -n 1)

    if [ -z "$pid" ]; then
        print_error "无法找到 SSH 进程"
        exit 1
    fi

    # 保存 PID 和端口
    echo $pid > "$PID_FILE"
    echo $port > "$PORT_FILE"

    print_info "SSH 隧道已启动 (PID: $pid, Port: $port)"

    # 配置 Docker 代理
    print_info "配置 Docker 代理..."

    sudo mkdir -p "$PROXY_CONFIG_DIR"

    sudo tee "$PROXY_CONFIG_FILE" > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=socks5://127.0.0.1:$port"
Environment="HTTPS_PROXY=socks5://127.0.0.1:$port"
Environment="NO_PROXY=localhost,127.0.0.1,docker.io"
EOF

    # 重启 Docker
    print_info "重启 Docker 服务..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    if [ $? -eq 0 ]; then
        print_info "Docker 代理配置成功！"
        print_info "代理地址: socks5://127.0.0.1:$port"
        echo ""
        print_info "测试代理: curl -x socks5://127.0.0.1:$port https://www.google.com"
        print_info "测试 Docker: docker pull hello-world"
    else
        print_error "Docker 重启失败"
        exit 1
    fi
}

# 停止 SSH 代理
stop_proxy() {
    print_info "停止 SSH 代理..."

    if [ ! -f "$PID_FILE" ]; then
        print_warning "未找到运行中的代理"
    else
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
            print_info "已停止 SSH 隧道 (PID: $pid)"
        else
            print_warning "SSH 进程不存在 (PID: $pid)"
        fi
        rm -f "$PID_FILE" "$PORT_FILE"
    fi

    # 移除 Docker 代理配置
    print_info "移除 Docker 代理配置..."

    if [ -f "$PROXY_CONFIG_FILE" ]; then
        sudo rm -f "$PROXY_CONFIG_FILE"
        print_info "已删除代理配置文件"
    fi

    # 重启 Docker
    print_info "重启 Docker 服务..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    if [ $? -eq 0 ]; then
        print_info "Docker 代理已移除！"
    else
        print_error "Docker 重启失败"
        exit 1
    fi
}

# 查看状态
show_status() {
    echo "========== Docker SSH 代理状态 =========="
    echo ""

    # SSH 隧道状态
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        local port=$(cat "$PORT_FILE" 2>/dev/null || echo "未知")

        if ps -p "$pid" > /dev/null 2>&1; then
            print_info "SSH 隧道: ${GREEN}运行中${NC}"
            echo "  PID: $pid"
            echo "  端口: $port"
            echo "  进程: $(ps -p $pid -o args= 2>/dev/null)"
        else
            print_warning "SSH 隧道: ${YELLOW}已停止${NC} (PID 文件存在但进程不存在)"
        fi
    else
        print_info "SSH 隧道: ${RED}未运行${NC}"
    fi

    echo ""

    # Docker 代理状态
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        print_info "Docker 代理配置: ${GREEN}已启用${NC}"
        echo "配置内容:"
        sudo cat "$PROXY_CONFIG_FILE" | grep Environment | sed 's/^/  /'
    else
        print_info "Docker 代理配置: ${RED}未启用${NC}"
    fi

    echo ""

    # Docker 实际代理设置
    print_info "Docker 当前环境变量:"
    sudo systemctl show --property=Environment docker 2>/dev/null | sed 's/^/  /'

    echo ""
    echo "========================================"
}

# 测试代理
test_proxy() {
    if [ ! -f "$PORT_FILE" ]; then
        print_error "代理未运行"
        exit 1
    fi

    local port=$(cat "$PORT_FILE")

    print_info "测试 SOCKS5 代理连接..."
    if curl -m 10 -x socks5://127.0.0.1:$port https://www.google.com > /dev/null 2>&1; then
        print_info "代理连接: ${GREEN}正常${NC}"
    else
        print_error "代理连接: ${RED}失败${NC}"
    fi

    print_info "测试 Docker 拉取镜像..."
    if timeout 30 docker pull hello-world > /dev/null 2>&1; then
        print_info "Docker 拉取: ${GREEN}成功${NC}"
    else
        print_warning "Docker 拉取: ${YELLOW}失败或超时${NC}"
    fi
}

# 主函数
main() {
    case "$1" in
        start)
            start_proxy "$2"
            ;;
        stop)
            stop_proxy
            ;;
        status)
            show_status
            ;;
        test)
            test_proxy
            ;;
        restart)
            stop_proxy
            sleep 2
            start_proxy "$2"
            ;;
        *)
            echo "Docker SSH 代理管理工具"
            echo ""
            echo "用法: $0 {start|stop|status|test|restart} [username@server]"
            echo ""
            echo "命令:"
            echo "  start <user@server>  - 启动 SSH 代理并配置 Docker"
            echo "  stop                 - 停止 SSH 代理并移除 Docker 配置"
            echo "  status               - 查看当前状态"
            echo "  test                 - 测试代理连接"
            echo "  restart <user@server> - 重启代理"
            echo ""
            echo "示例:"
            echo "  $0 start root@1.2.3.4"
            echo "  $0 stop"
            echo "  $0 status"
            exit 1
            ;;
    esac
}

# 检查是否有 sudo 权限
if [ "$EUID" -ne 0 ] && [ "$1" != "status" ] && [ "$1" != "test" ]; then
    if ! sudo -n true 2>/dev/null; then
        print_warning "此脚本需要 sudo 权限来配置 Docker"
    fi
fi

main "$@"