#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 这个脚本需要以 root 权限运行.${NC}"
        echo "请使用 sudo 重新运行脚本."
        exit 1
    fi
}

# 启用 IP 转发
enable_ip_forwarding() {
    # 检查当前 IP 转发状态
    ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
    
    if [ "$ip_forward" -eq "1" ]; then
        echo -e "${GREEN}IP 转发已经启用.${NC}"
    else
        echo -e "${YELLOW}正在启用 IP 转发...${NC}"
        # 临时启用
        echo 1 > /proc/sys/net/ipv4/ip_forward
        
        # 永久启用
        if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
            # 如果条目存在，确保它被设置为 1
            sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
        else
            # 如果条目不存在，添加它
            echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        fi
        
        # 应用 sysctl 设置
        sysctl -p
        
        echo -e "${GREEN}IP 转发已启用并设置为永久生效.${NC}"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}iptables 端口转发管理脚本${NC}"
    echo -e "${YELLOW}用法:${NC}"
    echo "  $0 [选项]"
    echo -e "${YELLOW}选项:${NC}"
    echo "  -h, --help     显示帮助信息"
    echo "  -a, --add      添加新的端口转发规则"
    echo "  -l, --list     列出当前的端口转发规则"
    echo "  -d, --delete   删除已存在的端口转发规则"
    echo "  -s, --save     保存当前的 iptables 规则"
    echo "  -c, --clear    清除所有端口转发规则"
    echo "  -f, --forward  检查并启用 IP 转发"
}

# 列出当前的 NAT 规则
list_rules() {
    echo -e "${BLUE}当前的 NAT 端口转发规则:${NC}"
    echo "-------------------------------------------------------------------------"
    sudo iptables -t nat -L PREROUTING -n -v --line-numbers
    echo "-------------------------------------------------------------------------"
    echo -e "${BLUE}当前的 MASQUERADE 规则:${NC}"
    echo "-------------------------------------------------------------------------"
    sudo iptables -t nat -L POSTROUTING -n -v --line-numbers
    echo "-------------------------------------------------------------------------"
}

# 添加新的端口转发规则
add_rule() {
    echo -e "${BLUE}添加新的端口转发规则${NC}"
    
    # 确保 IP 转发已启用
    enable_ip_forwarding
    
    # 获取用户输入
    read -p "本地端口号: " local_port
    read -p "目标 IP 地址: " target_ip
    read -p "目标端口号 (默认与本地端口相同): " target_port
    
    # 如果目标端口为空，则使用本地端口
    if [ -z "$target_port" ]; then
        target_port=$local_port
    fi
    
    # 询问协议类型
    echo "选择协议类型:"
    echo "1) TCP"
    echo "2) UDP"
    echo "3) 两者都添加"
    read -p "请选择 (1-3): " protocol_choice
    
    # 根据选择添加规则
    case $protocol_choice in
        1)
            sudo iptables -t nat -A PREROUTING -p tcp --dport $local_port -j DNAT --to-destination $target_ip:$target_port
            echo -e "${GREEN}已添加 TCP 端口 $local_port 转发到 $target_ip:$target_port${NC}"
            ;;
        2)
            sudo iptables -t nat -A PREROUTING -p udp --dport $local_port -j DNAT --to-destination $target_ip:$target_port
            echo -e "${GREEN}已添加 UDP 端口 $local_port 转发到 $target_ip:$target_port${NC}"
            ;;
        3)
            sudo iptables -t nat -A PREROUTING -p tcp --dport $local_port -j DNAT --to-destination $target_ip:$target_port
            sudo iptables -t nat -A PREROUTING -p udp --dport $local_port -j DNAT --to-destination $target_ip:$target_port
            echo -e "${GREEN}已添加 TCP 和 UDP 端口 $local_port 转发到 $target_ip:$target_port${NC}"
            ;;
        *)
            echo -e "${RED}无效的选择，未添加任何规则.${NC}"
            return
            ;;
    esac
    
    # 询问是否添加 MASQUERADE 规则
    read -p "是否添加 MASQUERADE 规则? (y/n): " add_masq
    if [ "$add_masq" = "y" ] || [ "$add_masq" = "Y" ]; then
        # 检查是否已存在相同的 MASQUERADE 规则
        existing_masq=$(sudo iptables -t nat -L POSTROUTING -n | grep $target_ip | grep MASQUERADE | wc -l)
        if [ $existing_masq -eq 0 ]; then
            sudo iptables -t nat -A POSTROUTING -d $target_ip -j MASQUERADE
            echo -e "${GREEN}已添加 MASQUERADE 规则用于 $target_ip${NC}"
        else
            echo -e "${YELLOW}MASQUERADE 规则已存在，跳过添加.${NC}"
        fi
    fi
    
    # 询问是否保存规则
    read -p "是否保存当前规则? (y/n): " save_rules
    if [ "$save_rules" = "y" ] || [ "$save_rules" = "Y" ]; then
        save_iptables_rules
    fi
}

# 删除端口转发规则
delete_rule() {
    echo -e "${BLUE}删除端口转发规则${NC}"
    
    # 列出当前规则
    list_rules
    
    echo "选择要删除的规则类型:"
    echo "1) PREROUTING 规则 (端口转发)"
    echo "2) POSTROUTING 规则 (MASQUERADE)"
    read -p "请选择 (1-2): " rule_type
    
    case $rule_type in
        1)
            read -p "输入要删除的 PREROUTING 规则编号: " rule_number
            if [ -n "$rule_number" ] && [ "$rule_number" -eq "$rule_number" ] 2>/dev/null; then
                sudo iptables -t nat -D PREROUTING $rule_number
                echo -e "${GREEN}PREROUTING 规则 #$rule_number 已删除${NC}"
            else
                echo -e "${RED}无效的规则编号${NC}"
            fi
            ;;
        2)
            read -p "输入要删除的 POSTROUTING 规则编号: " rule_number
            if [ -n "$rule_number" ] && [ "$rule_number" -eq "$rule_number" ] 2>/dev/null; then
                sudo iptables -t nat -D POSTROUTING $rule_number
                echo -e "${GREEN}POSTROUTING 规则 #$rule_number 已删除${NC}"
            else
                echo -e "${RED}无效的规则编号${NC}"
            fi
            ;;
        *)
            echo -e "${RED}无效的选择.${NC}"
            ;;
    esac
    
    # 询问是否保存规则
    read -p "是否保存当前规则? (y/n): " save_rules
    if [ "$save_rules" = "y" ] || [ "$save_rules" = "Y" ]; then
        save_iptables_rules
    fi
}

# 保存 iptables 规则
save_iptables_rules() {
    # 检测操作系统类型
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        if command -v netfilter-persistent &> /dev/null; then
            sudo netfilter-persistent save
            echo -e "${GREEN}规则已保存 (使用 netfilter-persistent)${NC}"
        else
            echo -e "${YELLOW}未找到 netfilter-persistent, 尝试安装...${NC}"
            sudo apt-get update
            sudo apt-get install -y iptables-persistent
            sudo netfilter-persistent save
            echo -e "${GREEN}规则已保存 (使用 netfilter-persistent)${NC}"
        fi
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        sudo service iptables save
        echo -e "${GREEN}规则已保存 (使用 service iptables save)${NC}"
    else
        # 其他系统，尝试手动保存
        sudo sh -c "iptables-save > /etc/iptables.rules"
        # 添加启动时加载规则
        if [ ! -f /etc/network/if-pre-up.d/iptables ]; then
            echo '#!/bin/sh' | sudo tee /etc/network/if-pre-up.d/iptables
            echo 'iptables-restore < /etc/iptables.rules' | sudo tee -a /etc/network/if-pre-up.d/iptables
            sudo chmod +x /etc/network/if-pre-up.d/iptables
        fi
        echo -e "${GREEN}规则已手动保存到 /etc/iptables.rules${NC}"
    fi
}

# 清除所有 NAT 规则
clear_rules() {
    echo -e "${YELLOW}警告: 这将清除所有 NAT 表中的规则.${NC}"
    read -p "确定要继续吗? (y/n): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sudo iptables -t nat -F PREROUTING
        sudo iptables -t nat -F POSTROUTING
        echo -e "${GREEN}所有 NAT 规则已清除.${NC}"
        
        # 询问是否保存规则
        read -p "是否保存当前规则状态? (y/n): " save_rules
        if [ "$save_rules" = "y" ] || [ "$save_rules" = "Y" ]; then
            save_iptables_rules
        fi
    else
        echo "操作已取消."
    fi
}

# 主菜单
main_menu() {
    clear
    echo -e "${BLUE}===== iptables 端口转发管理脚本 =====${NC}"
    echo "1) 列出当前规则"
    echo "2) 添加新的端口转发规则"
    echo "3) 删除端口转发规则"
    echo "4) 保存 iptables 规则"
    echo "5) 清除所有 NAT 规则"
    echo "6) 检查/启用 IP 转发"
    echo "7) 帮助信息"
    echo "0) 退出"
    echo ""
    read -p "请选择 (0-7): " choice
    
    case $choice in
        1) list_rules; press_enter_to_continue ;;
        2) add_rule; press_enter_to_continue ;;
        3) delete_rule; press_enter_to_continue ;;
        4) save_iptables_rules; press_enter_to_continue ;;
        5) clear_rules; press_enter_to_continue ;;
        6) enable_ip_forwarding; press_enter_to_continue ;;
        7) show_help; press_enter_to_continue ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择.${NC}"; press_enter_to_continue ;;
    esac
}

# 按 Enter 键继续
press_enter_to_continue() {
    echo ""
    read -p "按 Enter 键继续..."
}

# 主程序
check_root

# 检查 IP 转发状态
ip_forward_status=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$ip_forward_status" -eq "0" ]; then
    echo -e "${YELLOW}警告: IP 转发当前未启用，NAT 转发将无法正常工作.${NC}"
    echo -e "您可以在菜单中选择 '检查/启用 IP 转发' 选项启用它."
    press_enter_to_continue
fi

# 处理命令行参数
if [ $# -gt 0 ]; then
    case $1 in
        -h|--help) show_help ;;
        -a|--add) add_rule ;;
        -l|--list) list_rules ;;
        -d|--delete) delete_rule ;;
        -s|--save) save_iptables_rules ;;
        -c|--clear) clear_rules ;;
        -f|--forward) enable_ip_forwarding ;;
        *) echo -e "${RED}未知参数: $1${NC}"; show_help ;;
    esac
    exit 0
fi

# 无参数运行时显示交互式菜单
while true; do
    main_menu
done
