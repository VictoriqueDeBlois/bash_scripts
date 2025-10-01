#!/usr/bin/env python3
"""
脚本：为系统用户在 /backup 中创建对应文件夹
功能：检查 /data 目录下的文件夹，如果对应用户存在于 passwd 中，则在 /backup 创建用户文件夹
作者：系统管理员
"""

import os
import sys
import pwd
import grp
import stat
from pathlib import Path
from typing import List, Dict, Tuple

# 颜色定义
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def log_info(message: str) -> None:
    """输出信息日志"""
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {message}")

def log_success(message: str) -> None:
    """输出成功日志"""
    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")

def log_warning(message: str) -> None:
    """输出警告日志"""
    print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {message}")

def log_error(message: str) -> None:
    """输出错误日志"""
    print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")

def check_directories() -> bool:
    """检查必要的目录是否存在"""
    data_dir = Path("/data")
    backup_dir = Path("/backup")
    
    if not data_dir.exists():
        log_error("/data 目录不存在！")
        return False
    
    if not backup_dir.exists():
        log_error("/backup 目录不存在！")
        return False
    
    if not data_dir.is_dir():
        log_error("/data 不是一个目录！")
        return False
        
    if not backup_dir.is_dir():
        log_error("/backup 不是一个目录！")
        return False
    
    log_info("目录检查完成")
    return True

def get_system_users() -> Dict[str, Tuple[int, int]]:
    """获取系统中所有用户的信息"""
    users = {}
    try:
        # 读取所有用户信息
        for user in pwd.getpwall():
            # 过滤系统用户，只保留 UID >= 1000 的用户（普通用户）
            if user.pw_uid >= 1000:
                users[user.pw_name] = (user.pw_uid, user.pw_gid)
        
        log_info(f"从 passwd 中找到 {len(users)} 个普通用户")
        return users
    
    except Exception as e:
        log_error(f"读取用户信息失败: {e}")
        return {}

def get_data_directories() -> List[str]:
    """获取 /data 目录下的所有子目录"""
    data_path = Path("/data")
    directories = []
    
    try:
        for item in data_path.iterdir():
            if item.is_dir():
                # 过滤一些明显的系统目录
                system_dirs = {
                    'lost+found', 'tmp', 'temp', 'backup', 'logs', 
                    'shared', 'public', 'cache', '.snapshots'
                }
                
                if item.name not in system_dirs:
                    directories.append(item.name)
                else:
                    log_warning(f"跳过系统目录: {item.name}")
        
        log_info(f"在 /data 中找到 {len(directories)} 个用户目录")
        return directories
    
    except Exception as e:
        log_error(f"读取 /data 目录失败: {e}")
        return []

def validate_users(data_dirs: List[str], system_users: Dict[str, Tuple[int, int]]) -> List[str]:
    """验证哪些目录对应真实的系统用户"""
    valid_users = []
    invalid_dirs = []
    
    for dir_name in data_dirs:
        if dir_name in system_users:
            valid_users.append(dir_name)
            log_success(f"验证用户: {dir_name} (UID: {system_users[dir_name][0]})")
        else:
            invalid_dirs.append(dir_name)
            log_warning(f"目录 {dir_name} 不对应系统用户")
    
    if invalid_dirs:
        log_info("以下目录不对应系统用户，将被跳过:")
        for dir_name in invalid_dirs:
            print(f"  - {dir_name}")
    
    return valid_users

def get_directory_permissions(path: str) -> Tuple[int, int, int]:
    """获取目录的所有者、组和权限"""
    try:
        stat_info = os.stat(path)
        uid = stat_info.st_uid
        gid = stat_info.st_gid
        mode = stat.S_IMODE(stat_info.st_mode)
        return uid, gid, mode
    except Exception as e:
        log_warning(f"获取 {path} 权限信息失败: {e}")
        return -1, -1, 0o755  # 默认权限

def create_backup_folders(valid_users: List[str], system_users: Dict[str, Tuple[int, int]]) -> Dict[str, int]:
    """为验证的用户创建备份目录"""
    results = {'created': 0, 'existed': 0, 'failed': 0}
    
    log_info("开始为用户创建备份目录...")
    
    for username in valid_users:
        backup_path = Path(f"/backup/{username}")
        data_path = Path(f"/data/{username}")
        
        try:
            if backup_path.exists():
                log_warning(f"目录已存在: {backup_path}")
                results['existed'] += 1
            else:
                # 创建目录
                backup_path.mkdir(parents=True, exist_ok=True)
                log_success(f"已创建目录: {backup_path}")
                
                # 获取原目录的权限信息
                if data_path.exists():
                    original_uid, original_gid, original_mode = get_directory_permissions(str(data_path))
                else:
                    # 使用系统用户信息作为默认值
                    original_uid, original_gid = system_users[username]
                    original_mode = 0o755
                
                # 设置所有者和权限
                try:
                    os.chown(str(backup_path), original_uid, original_gid)
                    os.chmod(str(backup_path), original_mode)
                    
                    # 获取用户名和组名用于显示
                    try:
                        user_name = pwd.getpwuid(original_uid).pw_name
                        group_name = grp.getgrgid(original_gid).gr_name
                        log_info(f"已设置权限: {backup_path} -> {user_name}:{group_name} ({oct(original_mode)})")
                    except:
                        log_info(f"已设置权限: {backup_path} -> {original_uid}:{original_gid} ({oct(original_mode)})")
                        
                except Exception as e:
                    log_warning(f"设置权限失败 {backup_path}: {e}")
                
                results['created'] += 1
                
        except Exception as e:
            log_error(f"创建目录失败 {backup_path}: {e}")
            results['failed'] += 1
    
    return results

def show_statistics(results: Dict[str, int]) -> None:
    """显示操作统计信息"""
    print("\n" + "="*50)
    log_info("操作完成统计")
    print("="*50)
    log_success(f"成功创建: {results['created']} 个目录")
    log_warning(f"已存在: {results['existed']} 个目录")
    if results['failed'] > 0:
        log_error(f"创建失败: {results['failed']} 个目录")

def show_backup_structure() -> None:
    """显示备份目录结构"""
    backup_path = Path("/backup")
    
    print("\n" + "="*50)
    log_info("当前 /backup 目录结构")
    print("="*50)
    
    try:
        # 获取目录列表并排序
        dirs = [d for d in backup_path.iterdir() if d.is_dir()]
        dirs.sort()
        
        if not dirs:
            log_warning("备份目录为空")
            return
        
        print(f"{'用户名':<20} {'所有者':<15} {'权限':<10} {'大小'}")
        print("-" * 60)
        
        for dir_path in dirs:
            try:
                stat_info = dir_path.stat()
                uid, gid = stat_info.st_uid, stat_info.st_gid
                mode = oct(stat.S_IMODE(stat_info.st_mode))
                
                try:
                    owner = pwd.getpwuid(uid).pw_name
                    group = grp.getgrgid(gid).gr_name
                    owner_info = f"{owner}:{group}"
                except:
                    owner_info = f"{uid}:{gid}"
                
                # 计算目录大小
                total_size = sum(f.stat().st_size for f in dir_path.rglob('*') if f.is_file())
                size_str = format_size(total_size)
                
                print(f"{dir_path.name:<20} {owner_info:<15} {mode:<10} {size_str}")
                
            except Exception as e:
                print(f"{dir_path.name:<20} {'ERROR':<15} {'ERROR':<10} {str(e)}")
    
    except Exception as e:
        log_error(f"读取备份目录失败: {e}")

def format_size(bytes_size: int) -> str:
    """格式化文件大小"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.1f}{unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.1f}PB"

def show_disk_usage() -> None:
    """显示磁盘使用情况"""
    print("\n" + "="*50)
    log_info("存储空间使用情况")
    print("="*50)
    
    try:
        import shutil
        total, used, free = shutil.disk_usage("/backup")
        
        print(f"总空间: {format_size(total)}")
        print(f"已使用: {format_size(used)} ({used/total*100:.1f}%)")
        print(f"可用空间: {format_size(free)} ({free/total*100:.1f}%)")
        
    except Exception as e:
        log_error(f"获取磁盘使用情况失败: {e}")

def main():
    """主函数"""
    print("=" * 60)
    log_info("开始执行用户备份目录创建脚本")
    print("=" * 60)
    
    # 检查是否以 root 权限运行
    if os.geteuid() != 0:
        log_warning("建议以 root 权限运行此脚本以确保权限设置正确")
        print("使用命令: sudo python3 create_user_backup_folders.py\n")
    
    # 步骤1: 检查目录
    if not check_directories():
        sys.exit(1)
    
    # 步骤2: 获取系统用户
    system_users = get_system_users()
    if not system_users:
        log_error("无法获取系统用户信息")
        sys.exit(1)
    
    # 步骤3: 获取 /data 下的目录
    data_dirs = get_data_directories()
    if not data_dirs:
        log_warning("在 /data 目录下没有找到用户目录")
        sys.exit(0)
    
    # 步骤4: 验证用户
    valid_users = validate_users(data_dirs, system_users)
    if not valid_users:
        log_warning("没有找到对应系统用户的目录")
        sys.exit(0)
    
    # 显示将要创建的用户目录
    print(f"\n{Colors.CYAN}将为以下 {len(valid_users)} 个用户创建备份目录:{Colors.NC}")
    for i, user in enumerate(valid_users, 1):
        uid, gid = system_users[user]
        print(f"  {i:2d}. {user} (UID: {uid})")
    
    # 询问用户确认
    print()
    try:
        confirm = input("是否继续为这些用户创建备份目录？[y/N]: ").strip().lower()
        if confirm not in ['y', 'yes']:
            log_info("操作已取消")
            sys.exit(0)
    except KeyboardInterrupt:
        print("\n操作已取消")
        sys.exit(0)
    
    # 步骤5: 创建备份目录
    results = create_backup_folders(valid_users, system_users)
    
    # 步骤6: 显示结果
    show_statistics(results)
    show_backup_structure()
    show_disk_usage()
    
    print()
    log_success("脚本执行完成！")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}操作被用户中断{Colors.NC}")
        sys.exit(1)
    except Exception as e:
        log_error(f"脚本执行出错: {e}")
        sys.exit(1)
