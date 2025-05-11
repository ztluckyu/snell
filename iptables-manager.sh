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

# 检查并安装必要的工具
check_dependencies() {
    local missing_deps=()
    
    # 检查 tc 工具
    if ! command -v tc &> /dev/null; then
        missing_deps+=("iproute2")
    fi
    
    # 检查 bc 工具
    if ! command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi
    
    # 如果有缺失的依赖项，安装它们
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在安装必要的依赖项: ${missing_deps[*]}${NC}"
        if [ -f /etc/debian_version ]; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}"
        elif [ -f /etc/redhat-release ]; then
            # CentOS/RHEL
            sudo yum install -y "${missing_deps[@]}"
        else
            echo -e "${RED}无法确定您的系统类型，请手动安装以下依赖项: ${missing_deps[*]}${NC}"
            press_enter_to_continue
        fi
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
    echo -e "${BLUE}iptables 端口转发与限速管理脚本${NC}"
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
    echo "  -r, --rate     为已有端口转发添加限速"
    echo "  -i, --info     显示当前的限速信息"
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

# 列出当前的限速规则
list_tc_rules() {
    echo -e "${BLUE}当前的流量限速规则:${NC}"
    echo "-------------------------------------------------------------------------"
    
    # 查找所有网络接口
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | cut -d '@' -f1 | grep -v "lo")
    
    # 遍历每个接口，检查是否有限速规则
    found_rules=0
    for iface in $interfaces; do
        tc_rules=$(tc -s qdisc show dev $iface 2>/dev/null)
        if [[ "$tc_rules" == *htb* ]]; then
            echo -e "${YELLOW}接口: $iface${NC}"
            tc -s qdisc show dev $iface
            tc -s class show dev $iface
            tc -s filter show dev $iface
            
            # 解析并显示每个 IP 的限速配置
            echo -e "${BLUE}当前限速配置:${NC}"
            tc filter show dev $iface | grep -A4 "fh.*:" | while read -r line; do
                if [[ $line == *"match"* ]]; then
                    # 提取 IP 地址和 flowid
                    ip_hex=$(echo $line | awk '{print $2}' | cut -d'/' -f1)
                    flowid=$(echo "$line" | grep -oE "flowid [0-9:]+")
                    
                    if [ -n "$flowid" ]; then
                        # 从上一行或当前行中提取 flowid
                        if [[ $flowid != *"flowid"* ]]; then
                            flowid=$(tc filter show dev $iface | grep -B2 "$ip_hex" | grep "flowid" | awk '{print $6}')
                        else
                            flowid=$(echo $flowid | awk '{print $2}')
                        fi
                        
                        # 查找对应的 class 并获取限速信息
                        rate_info=$(tc class show dev $iface | grep "classid $flowid" | awk '{print $6}')
                        
                        # 正确的字节顺序转换（大端字节序）
                        ip_addr=$(printf "%d.%d.%d.%d" 0x${ip_hex:0:2} 0x${ip_hex:2:2} 0x${ip_hex:4:2} 0x${ip_hex:6:2})
                        echo -e "  IP: $ip_addr → 限速: $rate_info"
                    fi
                fi
            done
            found_rules=1
        fi
    done
    
    if [ "$found_rules" -eq "0" ]; then
        echo -e "${YELLOW}未找到任何限速规则.${NC}"
    fi
    
    echo "-------------------------------------------------------------------------"
}

# 初始化 HTB 系统（如果尚未初始化）
init_htb_system() {
    local main_interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    
    if [ -z "$main_interface" ]; then
        echo -e "${RED}错误: 无法确定主网络接口${NC}"
        return 1
    fi
    
    # 检查是否已经初始化了 HTB 系统
    tc_rules=$(tc qdisc show dev $main_interface 2>/dev/null)
    if [[ "$tc_rules" != *htb* ]]; then
        echo -e "${YELLOW}正在初始化 HTB 流量控制系统...${NC}"
        
        # 清除可能存在的旧规则
        tc qdisc del dev $main_interface root 2>/dev/null
        
        # 创建 HTB qdisc
        tc qdisc add dev $main_interface root handle 1: htb default 999
        
        # 创建主类（设置一个大一点的带宽，支持多个子类）
        tc class add dev $main_interface parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
        
        # 创建默认类（用于未被限速的流量）
        tc class add dev $main_interface parent 1:1 classid 1:999 htb rate 1000mbit ceil 1000mbit
        
        echo -e "${GREEN}HTB 流量控制系统初始化完成${NC}"
    fi
    
    echo $main_interface
}

# 为目标 IP 添加限速规则
add_rate_limit() {
    local target_ip=$1
    local limit_rate=$2
    
    # 检查参数
    if [ -z "$target_ip" ] || [ -z "$limit_rate" ]; then
        echo -e "${RED}错误: 目标 IP 和限速值不能为空.${NC}"
        return 1
    fi
    
    # 设置突发流量限制为基本速率的 1.125 倍
    local burst_rate=$(echo "$limit_rate * 1.125" | bc | cut -d'.' -f1)
    
    # 初始化 HTB 系统并获取主网络接口
    local main_interface=$(init_htb_system)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo -e "${BLUE}为目标 IP: $target_ip 添加限速规则${NC}"
    echo -e "${YELLOW}限速: $limit_rate Mbps (突发: $burst_rate Mbps)${NC}"
    echo -e "${YELLOW}网络接口: $main_interface${NC}"
    
    # 找到下一个可用的 class ID（从 10 开始递增）
    local next_class_id=$(tc class show dev $main_interface | grep -oE "classid 1:[0-9]+" | cut -d':' -f2 | sort -n | tail -n1)
    if [ -z "$next_class_id" ] || [ "$next_class_id" -lt "10" ]; then
        next_class_id=10
    else
        next_class_id=$((next_class_id + 1))
    fi
    
    # 将 IP 转换为十六进制格式
    IFS='.' read -ra ADDR <<< "$target_ip"
    # 修正：使用大端字节序（网络字节序）
    target_ip_hex=$(printf "%02x%02x%02x%02x" "${ADDR[0]}" "${ADDR[1]}" "${ADDR[2]}" "${ADDR[3]}")
    
    if echo "$ip_filter" | grep -q "$target_ip_hex"; then
        echo -e "${YELLOW}警告: IP $target_ip 已存在限速规则，是否要覆盖？(y/n)${NC}"
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "操作已取消."
            return 0
        fi
        
        # 删除现有规则（需要找到对应的 filter 和 class）
        local existing_filter=$(tc filter show dev $main_interface | grep -B3 "$target_ip_hex" | head -1 | awk '{print $5}' | cut -d':' -f2)
        if [ -n "$existing_filter" ]; then
            tc filter del dev $main_interface parent 1: pref 1 handle "$existing_filter"
            tc class del dev $main_interface classid "1:$existing_filter"
            echo -e "${YELLOW}已删除现有的限速规则${NC}"
        fi
    fi
    
    # 创建新的子类
    tc class add dev $main_interface parent 1:1 classid "1:$next_class_id" htb rate "${limit_rate}mbit" ceil "${burst_rate}mbit"
    
    # 添加过滤器
    tc filter add dev $main_interface parent 1: protocol ip prio 1 u32 match ip dst "$target_ip" flowid "1:$next_class_id"
    
    echo -e "${GREEN}限速规则添加成功！${NC}"
    echo -e "${BLUE}新规则详情：${NC}"
    echo -e "  目标 IP: $target_ip"
    echo -e "  限速: $limit_rate Mbps"
    echo -e "  突发: $burst_rate Mbps"
    echo -e "  Class ID: 1:$next_class_id"
    
    return 0
}

# 删除特定 IP 的限速规则
delete_single_rate_limit() {
    echo -e "${BLUE}删除特定 IP 的限速规则${NC}"
    
    # 列出当前限速规则
    list_tc_rules
    
    # 查找主网络接口
    local main_interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    
    if [ -z "$main_interface" ]; then
        echo -e "${RED}错误: 无法确定主网络接口${NC}"
        return 1
    fi
    
    # 显示所有现有的限速 IP 列表
    echo -e "${BLUE}当前限速的 IP 地址列表:${NC}"
    tc filter show dev $main_interface | grep -E "fh.* (flowid|match)" | while read -r line; do
        if [[ $line == *"match"* ]]; then
            # 提取 IP 地址
            ip_hex=$(echo $line | awk '{print $2}' | cut -d'/' -f1)
            # 修正：使用大端字节序解析
            ip_addr=$(printf "%d.%d.%d.%d" 0x${ip_hex:0:2} 0x${ip_hex:2:2} 0x${ip_hex:4:2} 0x${ip_hex:6:2})
            echo -e "  - $ip_addr"
        fi
    done
    echo ""
    
    # 获取要删除的 IP
    read -p "输入要删除限速的 IP 地址: " target_ip
    
    # 检查输入的 IP 格式
    if [[ ! $target_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}错误: 无效的 IP 地址格式${NC}"
        return 1
    fi
    
    # 将 IP 转换为十六进制格式（使用正确的字节顺序）
    IFS='.' read -ra ADDR <<< "$target_ip"
    # 修正：使用大端字节序（网络字节序）
    local target_ip_hex=$(printf "%02x%02x%02x%02x" "${ADDR[0]}" "${ADDR[1]}" "${ADDR[2]}" "${ADDR[3]}")
    
    # 调试信息
    echo -e "${YELLOW}查找 IP 的十六进制: $target_ip_hex${NC}"
    
    # 解析 filter 信息
    local filter_full_output=$(tc filter show dev $main_interface)
    local found_filter=false
    local filter_line=""
    local filter_handle=""
    local filter_flowid=""
    
    # 逐行处理 filter 输出
    while IFS= read -r line; do
        if [[ $line == *"fh 800::"* ]] && [[ $line == *"flowid"* ]]; then
            # 这是包含 handle 和 flowid 的行
            filter_line="$line"
        elif [[ $line == *"match"* ]] && [[ $line == *"$target_ip_hex"* ]]; then
            # 找到匹配的 IP
            if [ -n "$filter_line" ]; then
                # 提取 handle
                filter_handle=$(echo "$filter_line" | grep -oE "fh [0-9]+::[0-9]+" | awk '{print $2}')
                # 提取 flowid
                filter_flowid=$(echo "$filter_line" | grep -oE "flowid [0-9:]*" | awk '{print $2}')
                found_filter=true
                break
            fi
        fi
    done <<< "$filter_full_output"
    
    if [ "$found_filter" = false ] || [ -z "$filter_handle" ] || [ -z "$filter_flowid" ]; then
        echo -e "${RED}错误: 未找到 IP $target_ip 的限速规则${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}准备删除:${NC}"
    echo -e "  Filter handle: $filter_handle"
    echo -e "  Flowid: $filter_flowid"
    
    # 删除 filter（需要使用完整的 handle）
    tc filter del dev $main_interface parent 1: protocol ip pref 1 handle "$filter_handle" u32
    
    # 删除 class（先检查是否还有其他 filter 使用这个 class）
    local remaining_filters=$(tc filter show dev $main_interface | grep -c "$filter_flowid")
    if [ "$remaining_filters" -eq 0 ]; then
        tc class del dev $main_interface classid "$filter_flowid"
        echo -e "${GREEN}已成功删除 IP $target_ip 的限速规则和相关 class${NC}"
    else
        echo -e "${GREEN}已成功删除 IP $target_ip 的限速规则${NC}"
        echo -e "${YELLOW}注意: class $filter_flowid 还有其他 filter 使用，未删除${NC}"
    fi
}

# 管理多个 IP 的限速规则
manage_multiple_rate_limits() {
    echo -e "${BLUE}管理多个 IP 的限速规则${NC}"
    echo "当前选项:"
    echo "1) 查看所有限速规则"
    echo "2) 添加新的 IP 限速规则"
    echo "3) 删除特定 IP 的限速规则"
    echo "4) 返回主菜单"
    echo ""
    read -p "请选择 (1-4): " choice
    
    case $choice in
        1) list_tc_rules ;;
        2) 
            read -p "输入目标 IP 地址: " target_ip
            read -p "设置限速值 (Mbps): " rate_limit
            if [ -n "$target_ip" ] && [ -n "$rate_limit" ] && [ "$rate_limit" -eq "$rate_limit" ] 2>/dev/null; then
                add_rate_limit "$target_ip" "$rate_limit"
            else
                echo -e "${RED}无效的输入.${NC}"
            fi
            ;;
        3) delete_single_rate_limit ;;
        4) return ;;
        *) echo -e "${RED}无效的选择.${NC}" ;;
    esac
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
    
    # 询问是否添加限速规则
    read -p "是否为此转发添加限速? (y/n): " add_rate_limit
    if [ "$add_rate_limit" = "y" ] || [ "$add_rate_limit" = "Y" ]; then
        read -p "设置限速值 (Mbps): " rate_limit
        if [ -n "$rate_limit" ] && [ "$rate_limit" -eq "$rate_limit" ] 2>/dev/null; then
            add_rate_limit "$target_ip" "$rate_limit"
        else
            echo -e "${RED}无效的限速值，跳过限速设置.${NC}"
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
    
    echo -e "${YELLOW}注意: tc 限速规则无法通过 iptables-save 保存.${NC}"
    echo -e "${YELLOW}您需要将 tc 命令添加到系统启动脚本中以保持限速设置.${NC}"
}

# 清除所有 NAT 规则
clear_rules() {
    echo -e "${YELLOW}警告: 这将清除所有 NAT 表中的规则.${NC}"
    read -p "确定要继续吗? (y/n): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sudo iptables -t nat -F PREROUTING
        sudo iptables -t nat -F POSTROUTING
        echo -e "${GREEN}所有 NAT 规则已清除.${NC}"
        
        # 询问是否也清除限速规则
        read -p "是否也清除所有限速规则? (y/n): " clear_tc
        if [ "$clear_tc" = "y" ] || [ "$clear_tc" = "Y" ]; then
            # 查找主网络接口（假设是有公网 IP 的接口）
            local main_interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
            if [ -n "$main_interface" ]; then
                tc qdisc del dev $main_interface root 2>/dev/null
                echo -e "${GREEN}所有限速规则已清除.${NC}"
            fi
        fi
        
        # 询问是否保存规则
        read -p "是否保存当前规则状态? (y/n): " save_rules
        if [ "$save_rules" = "y" ] || [ "$save_rules" = "Y" ]; then
            save_iptables_rules
        fi
    else
        echo "操作已取消."
    fi
}

# 按 Enter 键继续
press_enter_to_continue() {
    echo ""
    read -p "按 Enter 键继续..."
}

# 主菜单
main_menu() {
    clear
    echo -e "${BLUE}===== iptables 端口转发与限速管理脚本 =====${NC}"
    echo "1) 列出当前端口转发规则"
    echo "2) 添加新的端口转发规则"
    echo "3) 删除端口转发规则"
    echo "4) 保存 iptables 规则"
    echo "5) 清除所有 NAT 规则"
    echo "6) 检查/启用 IP 转发"
    echo "7) 管理多个 IP 的限速规则"
    echo "h) 帮助信息"
    echo "0) 退出"
    echo ""
    read -p "请选择 (0-7, h): " choice
    
    case $choice in
        1) list_rules; press_enter_to_continue ;;
        2) add_rule; press_enter_to_continue ;;
        3) delete_rule; press_enter_to_continue ;;
        4) save_iptables_rules; press_enter_to_continue ;;
        5) clear_rules; press_enter_to_continue ;;
        6) enable_ip_forwarding; press_enter_to_continue ;;
        7) manage_multiple_rate_limits; press_enter_to_continue ;;
        h) show_help; press_enter_to_continue ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择.${NC}"; press_enter_to_continue ;;
    esac
}

# 主程序
check_root
check_dependencies

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
        -r|--rate) manage_multiple_rate_limits ;;
        -i|--info) list_tc_rules ;;
        *) echo -e "${RED}未知参数: $1${NC}"; show_help ;;
    esac
    exit 0
fi

# 无参数运行时显示交互式菜单
while true; do
    main_menu
done
