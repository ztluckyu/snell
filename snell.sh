#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}    Snell 5.0.0 安装/升级脚本${NC}"
echo -e "${BLUE}================================${NC}"
echo

# 处理配置文件
handle_config_file() {
    if [ -f "/etc/snell-server.conf" ]; then
        echo -e "${GREEN}使用现有配置文件${NC}"
    else
        echo "生成新的配置文件..."
        sudo snell-server --wizard -c /etc/snell-server.conf <<< "y"
    fi
}

# 检测现有安装
check_existing_installation() {
    if [ -f "/usr/local/bin/snell-server" ]; then
        echo -e "${YELLOW}检测到现有的 Snell 安装${NC}"
        version_output=$(/usr/local/bin/snell-server --version 2>/dev/null || echo "未知版本")
        echo -e "当前版本: ${version_output}"
        
        if systemctl is-active --quiet snell; then
            echo -e "服务状态: ${GREEN}运行中${NC}"
        else
            echo -e "服务状态: ${RED}未运行${NC}"
        fi
        
        if [ -f "/etc/snell-server.conf" ]; then
            echo -e "配置文件: ${GREEN}存在${NC}"
        else
            echo -e "配置文件: ${RED}不存在${NC}"
        fi
        
        echo
        return 0
    else
        echo -e "${GREEN}未检测到现有的 Snell 安装${NC}"
        echo
        return 1
    fi
}

# 卸载现有版本
uninstall_existing() {
    echo -e "${YELLOW}开始卸载现有的 Snell...${NC}"
    
    # 停止并禁用服务
    if systemctl is-active --quiet snell; then
        echo "停止 Snell 服务..."
        sudo systemctl stop snell
    fi
    
    if systemctl is-enabled --quiet snell; then
        echo "禁用 Snell 服务..."
        sudo systemctl disable snell
    fi
    
    # 备份配置文件
    if [ -f "/etc/snell-server.conf" ]; then
        echo "备份配置文件..."
        sudo cp /etc/snell-server.conf /etc/snell-server.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 删除文件
    echo "删除旧文件..."
    sudo rm -f /usr/local/bin/snell-server
    sudo rm -f /lib/systemd/system/snell.service
    
    # 重新加载 systemd
    sudo systemctl daemon-reload
    
    echo -e "${GREEN}卸载完成${NC}"
    echo
}

# 安装新版本
install_new_version() {
    echo -e "${YELLOW}开始安装 Snell 5.0.0...${NC}"
    
    # 安装依赖
    echo "安装依赖包..."
    sudo apt-get update
    sudo apt-get install -y wget curl sudo vim git lsof mtr iperf3 unzip
    
    # 下载新版本
    echo "下载 Snell 5.0.0..."
    wget https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-amd64.zip
    
    # 解压
    echo "解压文件..."
    sudo unzip snell-server-v5.0.0-linux-amd64.zip -d /usr/local/bin
    
    # 设置权限
    echo "设置执行权限..."
    sudo chmod +x /usr/local/bin/snell-server
    
    # 处理配置文件
    handle_config_file
    
    # 创建 systemd 服务文件
    echo "创建 systemd 服务文件..."
    sudo cat > /lib/systemd/system/snell.service << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell-server.conf
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd
    echo "重新加载 systemd 守护进程..."
    sudo systemctl daemon-reload
    
    # 启动并启用服务
    echo "启动并启用 Snell 服务..."
    sudo systemctl start snell
    sudo systemctl enable snell
    
    # 设置网络参数
    echo "设置网络参数..."
    sudo sysctl -w net.core.rmem_max=26214400
    sudo sysctl -w net.core.rmem_default=26214400
    
    # 清理下载文件
    echo "清理下载文件..."
    rm -f snell-server-v5.0.0-linux-amd64.zip
    
    echo -e "${GREEN}安装完成！${NC}"
    echo
}

# 显示安装结果
show_status() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}        安装结果${NC}"
    echo -e "${BLUE}================================${NC}"
    
    # 检查服务状态
    if systemctl is-active --quiet snell; then
        echo -e "服务状态: ${GREEN}运行中${NC}"
    else
        echo -e "服务状态: ${RED}未运行${NC}"
    fi
    
    # 显示版本信息
    if [ -f "/usr/local/bin/snell-server" ]; then
        version_output=$(/usr/local/bin/snell-server --version 2>/dev/null || echo "未知版本")
        echo -e "版本信息: ${version_output}"
    fi
    
    # 显示配置文件
    if [ -f "/etc/snell-server.conf" ]; then
        echo -e "${YELLOW}配置文件内容:${NC}"
        sudo cat /etc/snell-server.conf
    fi
    
    echo
    echo -e "${GREEN}如需重新配置，请运行:${NC}"
    echo "sudo snell-server --wizard -c /etc/snell-server.conf"
}

# 主菜单
main_menu() {
    echo "请选择操作:"
    echo "1) 直接安装 Snell 5.0.0 (覆盖现有安装，保留配置)"
    echo "2) 检测并卸载旧版本，然后安装 Snell 5.0.0"
    echo "3) 仅检测现有安装"
    echo "4) 退出"
    echo
    read -p "请输入选项 [1-4]: " choice
    
    case $choice in
        1)
            echo -e "${YELLOW}选择: 直接安装 Snell 5.0.0${NC}"
            echo
            echo -e "${BLUE}提示: 这将覆盖现有安装，但会保留配置文件${NC}"
            install_new_version
            show_status
            ;;
        2)
            echo -e "${YELLOW}选择: 检测并卸载旧版本，然后安装新版本${NC}"
            echo
            if check_existing_installation; then
                read -p "是否继续卸载现有版本? [y/N]: " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    uninstall_existing
                    install_new_version
                    show_status
                else
                    echo "操作已取消"
                fi
            else
                echo "没有检测到现有安装，直接安装新版本..."
                install_new_version
                show_status
            fi
            ;;
        3)
            echo -e "${YELLOW}选择: 仅检测现有安装${NC}"
            echo
            check_existing_installation
            ;;
        4)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${NC}"
            echo
            main_menu
            ;;
    esac
}

# 检查是否为 root 用户
#if [ "$EUID" -eq 0 ]; then
#    echo -e "${RED}请不要使用 root 用户运行此脚本${NC}"
#    echo "请使用普通用户运行，脚本会在需要时使用 sudo"
#    exit 1
#fi

# 检查 sudo 权限
if ! sudo -n true 2>/dev/null; then
    echo "此脚本需要 sudo 权限，请确保你的用户在 sudoers 中"
    sudo -v
fi

# 运行主菜单
main_menu
