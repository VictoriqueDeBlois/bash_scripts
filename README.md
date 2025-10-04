# Bash Scripts Collection

本项目包含一组常用的 Bash/Python 脚本，适用于服务器日常管理和自动化运维。

## 脚本说明

### 1. create_user_backup_folders.py
为系统用户在 `/backup` 目录中创建对应的备份文件夹。会检查 `/data` 目录下的文件夹名是否为有效用户，并在 `/backup` 下为其创建同名文件夹。
- 适用场景：批量为所有有效用户准备备份空间。
- 用法：`python3 create_user_backup_folders.py`

### 2. install_docker.sh
自动安装 Docker，包括官方 GPG 密钥、软件源配置和 Docker 相关组件的安装。
- 适用场景：一键部署 Docker 环境。
- 用法：`bash install_docker.sh`

### 3. kill_toolbox.sh
强制杀死服务器上 JetBrains Toolbox 及 PyCharm 相关进程，解决卡死或无法连接的问题。
- 适用场景：JetBrains 工具出现假死或无法关闭时。
- 用法：`bash kill_toolbox.sh`

### 4. restore_permissions.sh
恢复指定目录及其下所有文件和文件夹的默认权限（文件夹 755，文件 644）。
- 适用场景：目录权限混乱时快速恢复。
- 用法：`bash restore_permissions.sh <目录路径>`

### 5. setup_lan_name.sh
配置 Ubuntu 局域网广播名（NetBIOS 名称），自动安装并配置 Samba 和 Avahi，适用于 Ubuntu 20.04+。
- 适用场景：让 Linux 主机在局域网内以指定名称被发现。
- 用法：`sudo bash setup_lan_name.sh`

### 6. zerotier_moon_setup.sh
自动安装和配置 ZeroTier Moon 服务器，支持自动获取公网 IP。
- 适用场景：需要搭建 ZeroTier Moon 网络节点时。
- 用法：`sudo bash zerotier_moon_setup.sh`

### 7. generate_nginx_proxy.sh
Nginx 反向代理与 HTTPS 自动化配置脚本。支持自定义域名、路径和后端端口，自动生成 Nginx 配置并可一键申请 Let's Encrypt SSL 证书。
- 适用场景：快速为 Web 服务配置反向代理和 HTTPS，适合多服务、多路径场景。
- 主要功能：
  - 检查并自动安装 nginx、certbot 等依赖
  - 交互式输入域名、路径、后端端口，自动生成/更新 Nginx 配置
  - 支持多路径代理，自动处理配置文件合并与去重
  - 自动测试并重载 Nginx 配置
  - 可选一键申请并配置 SSL 证书，实现 HTTP 自动跳转到 HTTPS
- 用法：`sudo bash generate_nginx_proxy.sh`
- 注意事项：需 root 权限运行，域名需已正确解析到本机

### 8. docker-proxy.sh
Docker SSH 代理管理脚本。用于通过 SSH 动态端口转发（SOCKS5 代理）为 Docker 配置网络代理，适合在受限网络环境下加速 Docker 镜像拉取或访问外部服务。
- 适用场景：需要为 Docker 配置代理，或通过 SSH 隧道安全访问外部网络时。
- 用法示例：
  - 启动代理：`bash docker-proxy.sh start user@server`
  - 停止代理：`bash docker-proxy.sh stop`
  - 查看状态：`bash docker-proxy.sh status`
  - 测试代理：`bash docker-proxy.sh test`
  - 重启代理：`bash docker-proxy.sh restart user@server`
- 主要功能：
  - 自动查找本地空闲端口并建立 SSH 动态代理
  - 自动配置/移除 Docker 的 HTTP/HTTPS 代理环境变量
  - 支持状态查询与代理连通性测试
  - 需具备 sudo 权限以修改 Docker 配置

---

如需详细用法和参数说明，请参考各脚本内注释。
