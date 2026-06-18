#!/usr/bin/env bash

# ==============================================================================
# 脚本名称: bbrplus_optimize.sh
# 脚本功能: 
#   1. 一键安装并启用 BBRplus 高速 TCP 拥塞控制协议（支持 Debian/Ubuntu/CentOS）
#   2. 永久修改系统最大文件打开数 (limits.conf) 到 65535
#   3. 深度优化系统 UDP/TCP 发送与接收缓冲区大小（拉大最大缓冲区至 8MB）
#   4. 提升系统网络队列最大排队数据包数 (backlog) 至 10000
# 适用系统: Debian 9+, Ubuntu 16.04+, CentOS 7 (x86_64/amd64 架构)
# ==============================================================================

# 颜色控制字符定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 日志输出前缀
INFO="[${GREEN}信息${PLAIN}]"
WARNING="[${YELLOW}警告${PLAIN}]"
ERROR="[${RED}错误${PLAIN}]"

# ==========================================
# 1. 基础权限与环境检查
# ==========================================

# 确保脚本以 root 权限运行
check_root() {
    # 结合 EUID 与 id -u 进行双重安全校验，防止因环境变量丢失导致判断失效
    if [[ $EUID -ne 0 ]] && [[ $(id -u) -ne 0 ]]; then
        echo -e "${ERROR} 必须以 root 权限运行此脚本，请使用 'sudo -i' 或 'su' 切换到 root 账户！"
        exit 1
    fi
}

# 自动检测系统类型与架构
detect_system() {
    # 架构检查
    ARCH=$(uname -m)
    if [[ "${ARCH}" != "x86_64" ]]; then
        echo -e "${ERROR} 目前 BBRplus 预编译内核仅支持 x86_64 (amd64) 架构，当前系统为: ${ARCH}"
        exit 1
    fi

    # 检测系统发行版
    if [[ -f /etc/redhat-release ]]; then
        OS="CentOS"
        if grep -q -i "release 7" /etc/redhat-release; then
            OS_VER="7"
        elif grep -q -i "release 8" /etc/redhat-release; then
            OS_VER="8"
        else
            OS_VER="unknown"
        fi
    elif grep -q -i "debian" /etc/issue || [[ -f /etc/debian_version ]]; then
        OS="Debian"
        OS_VER=$(cat /etc/debian_version | cut -d'.' -f1)
    elif grep -q -i "ubuntu" /etc/issue || [[ -f /etc/lsb-release ]]; then
        OS="Ubuntu"
        OS_VER=$(lsb_release -rs | cut -d'.' -f1)
    else
        echo -e "${ERROR} 未检测到受支持的 Linux 系统（仅支持 CentOS, Debian, Ubuntu）！"
        exit 1
    fi
    echo -e "${INFO} 系统检测成功: ${GREEN}${OS} ${OS_VER} (${ARCH})${PLAIN}"
}

# 安装必要依赖
install_dependencies() {
    echo -e "${INFO} 正在检查并安装脚本所需基础依赖..."
    if [[ "${OS}" == "CentOS" ]]; then
        yum install -y wget curl ca-certificates sed awk >/dev/null 2>&1
    else
        apt-get update -y >/dev/null 2>&1
        apt-get install -y wget curl ca-certificates sed awk >/dev/null 2>&1
    fi
}

# ==========================================
# 2. 系统参数优化 (文件限制 & UDP/TCP 缓冲区)
# ==========================================

# 优化系统文件描述符最大数限制
optimize_limits() {
    echo -e "${INFO} 正在修改系统文件打开数限制 (永久修改为 65535)..."
    
    # 1. 备份原安全限制配置文件
    if [[ ! -f /etc/security/limits.conf.bak ]]; then
        cp /etc/security/limits.conf /etc/security/limits.conf.bak
    fi

    # 清除旧的配置（避免重复添加）
    sed -i '/soft nofile/d' /etc/security/limits.conf
    sed -i '/hard nofile/d' /etc/security/limits.conf
    sed -i '/soft nproc/d' /etc/security/limits.conf
    sed -i '/hard nproc/d' /etc/security/limits.conf

    # 写入新限制
    cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
EOF

    # 2. 针对 Systemd 管理的服务也配置对应文件打开数
    if [[ -d /etc/systemd ]]; then
        # 修改 system.conf
        if [[ -f /etc/systemd/system.conf ]]; then
            sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/g' /etc/systemd/system.conf
            sed -i 's/^DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/g' /etc/systemd/system.conf
        fi
        # 修改 user.conf
        if [[ -f /etc/systemd/user.conf ]]; then
            sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/g' /etc/systemd/user.conf
            sed -i 's/^DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/g' /etc/systemd/user.conf
        fi
    fi

    echo -e "${GREEN}[成功] 文件限制优化完成！已设置软硬限制为 65535。${PLAIN}"
}

# 优化网络参数 (UDP/TCP 缓冲区 & 队列)
optimize_sysctl() {
    echo -e "${INFO} 正在优化系统网络栈参数 (包含 UDP 8MB 缓存、队列等)..."

    # 备份现有的 sysctl.conf
    if [[ ! -f /etc/sysctl.conf.bak ]]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak
    fi

    # 准备写入优化的参数
    SYSCTL_CONF="/etc/sysctl.d/99-network-optimize.conf"
    
    cat > ${SYSCTL_CONF} <<EOF
# ==========================================
# 系统网络深度优化设置 - BBR一键脚本自动生成
# ==========================================

# 1. 提升系统最大文件描述符
fs.file-max = 65535

# 2. UDP & TCP 网络缓冲区大小优化 (拉大最大接收与发送缓冲区至 8MB)
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608

# 设置默认/标准缓冲区大小为 262144 字节
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# 针对 TCP 的缓冲区范围优化 (最小 默认 最大字节数)
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608

# 3. 提高网络设备队列的最大排队数据包数到 10000
net.core.netdev_max_backlog = 10000

# 提高系统网络最大并发连接数
net.core.somaxconn = 4096

# 允许重用处于 TIME-WAIT 状态的 TCP 连接
net.ipv4.tcp_tw_reuse = 1
EOF

    # 应用 sysctl 参数变更
    sysctl -p ${SYSCTL_CONF} >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1

    echo -e "${GREEN}[成功] 系统网络参数优化应用完成！${PLAIN}"
}

# ==========================================
# 3. BBR / BBRplus 内核检查与部署
# ==========================================

# 检测当前已启用的 TCP 拥塞控制算法
check_bbr_status() {
    local active_algo=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    local loaded_algos=$(sysctl net.ipv4.tcp_available_congestion_control | awk -F '=' '{print $2}')
    
    echo -e "${CYAN}---------------- 当前内核网络加速状态 ----------------${PLAIN}"
    echo -e "当前运行的内核版本: ${GREEN}$(uname -r)${PLAIN}"
    echo -e "正在使用的拥塞控制算法: ${GREEN}${active_algo}${PLAIN}"
    echo -e "系统中可用的拥塞控制算法:${YELLOW}${loaded_algos}${PLAIN}"
    echo -e "${CYAN}------------------------------------------------------${PLAIN}"
}

# 安装 BBRplus 内核 (基于 4.14.129 经典稳定版)
install_bbrplus_kernel() {
    echo -e "${INFO} 开始获取稳定版 BBRplus 内核组件 (基于 4.14.129 版本)..."
    
    # 建立临时下载工作目录
    local tmp_dir="/tmp/bbrplus_install"
    rm -rf "${tmp_dir}" && mkdir -p "${tmp_dir}" && cd "${tmp_dir}" || exit 1

    local k_url=""
    local h_url=""
    
    if [[ "${OS}" == "CentOS" ]]; then
        if [[ "${OS_VER}" == "7" ]]; then
            h_url="https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/centos/7/kernel-headers-4.14.129-bbrplus.rpm"
            k_url="https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/centos/7/kernel-4.14.129-bbrplus.rpm"
            
            echo -e "${INFO} 正在下载 CentOS 7 BBRplus 内核文件..."
            wget --no-check-certificate -q --show-progress -O "kernel-headers.rpm" "${h_url}"
            wget --no-check-certificate -q --show-progress -O "kernel.rpm" "${k_url}"
            
            echo -e "${INFO} 正在通过 YUM 本地安装内核包，请稍候..."
            yum localinstall -y kernel-headers.rpm kernel.rpm
            
            # 锁定并配置 CentOS grub2 默认启动内核
            echo -e "${INFO} 正在动态分析并更新 Grub2 启动配置项..."
            if [ -f /boot/grub2/grub.cfg ]; then
                grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
                local bbrplus_entry=$(awk -F\' '/menuentry / {print $2}' /boot/grub2/grub.cfg | grep "bbrplus" | head -n 1)
                if [ -z "$bbrplus_entry" ]; then
                    bbrplus_entry=$(awk -F\" '/menuentry / {print $2}' /boot/grub2/grub.cfg | grep "bbrplus" | head -n 1)
                fi
                if [ -n "$bbrplus_entry" ]; then
                    grub2-set-default "$bbrplus_entry"
                else
                    grub2-set-default "CentOS Linux (4.14.129-bbrplus) 7 (Core)"
                fi
            fi
        else
            echo -e "${ERROR} CentOS ${OS_VER} 的 BBRplus 自动安装支持受限，请考虑手动升级或更换为 Debian/Ubuntu！"
            return 1
        fi
    elif [[ "${OS}" == "Debian" || "${OS}" == "Ubuntu" ]]; then
        h_url="https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/debian-ubuntu/x64/linux-headers-4.14.129-bbrplus.deb"
        k_url="https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/debian-ubuntu/x64/linux-image-4.14.129-bbrplus.deb"
        
        echo -e "${INFO} 正在下载 Debian/Ubuntu BBRplus 内核包..."
        wget --no-check-certificate -q --show-progress -O "linux-headers.deb" "${h_url}"
        wget --no-check-certificate -q --show-progress -O "linux-image.deb" "${k_url}"
        
        echo -e "${INFO} 正在通过 DPKG 部署 BBRplus 内核，请稍候..."
        dpkg -i linux-headers.deb linux-image.deb
        
        # 核心修复：动态锁定并锁定 Debian/Ubuntu 的 GRUB 默认引导项为 BBRplus，防止新内核抢占引导
        echo -e "${INFO} 正在动态解析并锁定 BBRplus 内核引导顺序..."
        if [ -f /boot/grub/grub.cfg ]; then
            if [ -f /etc/default/grub ]; then
                # 备份默认设置
                cp /etc/default/grub /etc/default/grub.bak
                
                # 获取 GRUB 菜单中的子菜单标识（Submenu ID/Title）
                local submenu_raw=$(grep -i "submenu" /boot/grub/grub.cfg | head -n 1)
                local submenu_val=""
                if [[ "$submenu_raw" =~ --id ]]; then
                    submenu_val=$(echo "$submenu_raw" | sed -n 's/.*--id \([^ ]*\).*/\1/p' | tr -d "'\"")
                fi
                if [ -z "$submenu_val" ]; then
                    submenu_val=$(echo "$submenu_raw" | cut -d"'" -f2)
                fi
                if [ -z "$submenu_val" ]; then
                    submenu_val=$(echo "$submenu_raw" | cut -d'"' -f2)
                fi

                # 获取 BBRplus 内核的启动项标识（Menuentry ID/Title）
                local entry_raw=$(grep -i "menuentry" /boot/grub/grub.cfg | grep "bbrplus" | head -n 1)
                local entry_val=""
                if [[ "$entry_raw" =~ --id ]]; then
                    entry_val=$(echo "$entry_raw" | sed -n 's/.*--id \([^ ]*\).*/\1/p' | tr -d "'\"")
                fi
                if [ -z "$entry_val" ]; then
                    entry_val=$(echo "$entry_raw" | cut -d"'" -f2)
                fi
                if [ -z "$entry_val" ]; then
                    entry_val=$(echo "$entry_raw" | cut -d'"' -f2)
                fi

                # 完美写入 GRUB
                if [ -n "$entry_val" ]; then
                    if [ -n "$submenu_val" ]; then
                        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="'"$submenu_val"'>'"$entry_val"'"/g' /etc/default/grub
                    else
                        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="'"$entry_val"'"/g' /etc/default/grub
                    fi
                fi
            fi
        fi
        
        # 更新 Debian/Ubuntu 引导程序
        echo -e "${INFO} 正在更新 GRUB 引导记录..."
        update-grub
    fi

    # 清理安装残留包
    cd /tmp && rm -rf "${tmp_dir}"
    echo -e "${GREEN}[成功] BBRplus 内核安装包部署并已被锁定为默认引导！${PLAIN}"
    echo -e "${WARNING} 注意: 必须 ${RED}重启系统${YELLOW} 引导进新内核后才能彻底生效运行。${PLAIN}"
}

# 彻底开启 BBRplus / BBR 网络加速配置
enable_bbr_acceleration() {
    local current_kernel=$(uname -r)
    
    echo -e "${INFO} 正在对系统全局网络进行加速参数配置..."
    
    # 尝试加载内核模块，防止部分轻量版系统在开启时抛出未加载异常
    modprobe tcp_bbr >/dev/null 2>&1
    modprobe tcp_bbrplus >/dev/null 2>&1
    
    # 检查当前内核环境是否支持 BBRplus
    if [[ "${current_kernel}" == *"bbrplus"* ]]; then
        echo -e "${INFO} 系统当前正是 BBRplus 内核，正在执行一键开启..."
        
        # 写入配置
        cat > /etc/sysctl.d/90-bbr-tune.conf <<EOF
# BBRplus 启动拥塞算法配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbrplus
EOF
        sysctl -p /etc/sysctl.d/90-bbr-tune.conf >/dev/null 2>&1
        echo -e "${GREEN}[成功] BBRplus TCP 拥塞控制已被成功激活并锁定运行！${PLAIN}"
    else
        echo -e "${WARNING} 系统当前运行的内核版本为 [${current_kernel}]，没有启用 BBRplus 特性。"
        
        # 动态提取并判定主次内核版本号，看是否支持免重启原生 BBR 激活 (>= 4.9)
        local main_ver=$(echo "${current_kernel}" | cut -d'.' -f1)
        local sub_ver=$(echo "${current_kernel}" | cut -d'.' -f2)
        
        if [ "${main_ver}" -gt 4 ] || { [ "${main_ver}" -eq 4 ] && [ "${sub_ver}" -ge 9 ]; }; then
            echo -e "${INFO} 检测到当前内核版本支持原生 BBR。正在为您【免重启直接激活】标准 BBR 加速..."
            
            cat > /etc/sysctl.d/90-bbr-tune.conf <<EOF
# 标准 BBR 启动配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
            sysctl -p /etc/sysctl.d/90-bbr-tune.conf >/dev/null 2>&1
            echo -e "${GREEN}[成功] 原生 BBR 算法开启成功，且已立即生效（无需重启）！${PLAIN}"
            echo -e "${INFO} 温馨提示: 如果您后期想使用更激进的 BBRplus，请在主菜单选择 [2] 部署 BBRplus 内核并重启。"
        else
            echo -e "${ERROR} 抱歉，当前系统原版内核版本过低（低于 4.9），不支持任何 BBR 拥塞控制。"
            echo -e "${INFO} 强烈建议您选择菜单中的选项 [2] 安装 BBRplus 内核并重启！"
        fi
    fi
}

# ==========================================
# 4. 主控菜单界面
# ==========================================

show_menu() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "       ${GREEN}Linux 一键系统调优与 BBRplus 内核自动开启脚本${PLAIN}"
    echo -e "   适用系统: Debian/Ubuntu/CentOS  内核版本: BBRplus 4.14.129"
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e " ${GREEN}1.${PLAIN} 执行系统深度调优 (一键优化系统 limits + 8MB UDP 缓存 + 队列)"
    echo -e " ${GREEN}2.${PLAIN} 一键安装 BBRplus 专用加速内核并设置为默认引导"
    echo -e " ${GREEN}3.${PLAIN} 自动开启网络拥塞算法 (原生 BBR 免重启 / BBRplus 加速机制)"
    echo -e " ${GREEN}4.${PLAIN} 运行一键式组合包 [ 选项 1 + 2 + 3 ] 彻底极速调优"
    echo -e " ${GREEN}5.${PLAIN} 查看当前系统详细的内核加速状态"
    echo -e " ${RED}6. 退出脚本${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
}

main() {
    check_root
    detect_system
    install_dependencies
    
    while true; do
        show_menu
        read -p "请输入要执行的选项 [1-6]: " choice
        case "${choice}" in
            1)
                echo -e "\n${BLUE}>>> 正在启动系统深度调优方案...${PLAIN}"
                optimize_limits
                optimize_sysctl
                echo -e "${GREEN}系统参数调优已全部注入成功。输入任意键返回主菜单...${PLAIN}"
                read -n 1
                ;;
            2)
                echo -e "\n${BLUE}>>> 正在部署 BBRplus 高速内核...${PLAIN}"
                install_bbrplus_kernel
                echo -e "${GREEN}内核安装流程完成，输入任意键返回主菜单...${PLAIN}"
                read -n 1
                ;;
            3)
                echo -e "\n${BLUE}>>> 正在配置拥塞算法控制中心...${PLAIN}"
                enable_bbr_acceleration
                echo -e "${GREEN}算法配置完成，输入任意键返回主菜单...${PLAIN}"
                read -n 1
                ;;
            4)
                echo -e "\n${BLUE}>>> 正在为您执行一键自动化综合极限调优...${PLAIN}"
                optimize_limits
                optimize_sysctl
                install_bbrplus_kernel
                enable_bbr_acceleration
                echo -e "\n${GREEN}======================================================${PLAIN}"
                echo -e "${GREEN} 恭喜！一键自动化网络加速与系统限制已经配置部署完成。${PLAIN}"
                echo -e "${YELLOW} 【重要提醒】为了让刚安装的 BBRplus 内核生效，请执行：${RED}reboot${YELLOW} 重启系统。${PLAIN}"
                echo -e "${YELLOW} 重启完成后，再次运行本脚本选择 【5】 即可看到 BBRplus 已完美运行！${PLAIN}"
                echo -e "${GREEN}======================================================${PLAIN}"
                echo -e "按任意键回到主菜单..."
                read -n 1
                ;;
            5)
                echo -e "\n"
                check_bbr_status
                echo -e "\n按任意键返回主菜单..."
                read -n 1
                ;;
            6)
                echo -e "\n${GREEN}感谢使用调优脚本，祝您网络飞速，再见！${PLAIN}\n"
                exit 0
                ;;
            *)
                echo -e "\n${ERROR} 输入无效，请输入有效数字 [1-6]"
                sleep 1.5
                ;;
        esac
    done
}

# 启动运行主入口
main
