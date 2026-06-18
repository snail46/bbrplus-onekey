#!/bin/bash

echo "正在开始执行 VPS 极限低延迟调优（完全体，无 BBR 版）..."

# 1. 自动安装并启用 irqbalance（网卡中断平衡，降低多核 CPU 下的网络延迟）
echo "正在配置 CPU 网络中断平衡..."
if [ -f /etc/debian_version ]; then
    sudo apt-get update -y && sudo apt-get install -y irqbalance
elif [ -f /etc/redhat-release ]; then
    sudo yum install -y irqbalance
fi
sudo systemctl enable irqbalance --now 2>/dev/null || true

# 2. 写入 sysctl 内核参数（含内存优化、连接跟踪表及基础网络扩展）
echo "正在写入系统内核优化参数..."
sudo tee -a /etc/sysctl.conf << 'EOF'

# ================= 1. 内存与抖动优化 =================
# 极大地减少 Swap 空间的使用，强迫系统使用物理内存，消除瞬时延迟抖动
vm.swappiness = 10

# ================= 2. 系统文件与全局队列优化 =================
fs.file-max = 65535000
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535

# ================= 3. TCP/UDP 内存缓冲区优化 =================
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# ================= 4. 连接复用与超时优化 =================
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_fin_timeout = 15

# ================= 5. 握手与抗延迟优化 =================
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0

# ================= 6. 防火墙连接跟踪表（Conntrack）优化 =================
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
EOF

# 使内核参数生效
sudo sysctl -p 2>/dev/null || true

# 3. 写入系统文件限制
echo "正在提升系统文件句柄限制..."
sudo tee -a /etc/security/limits.conf << 'EOF'
* soft nofile 655350
* hard nofile 655350
root soft nofile 655350
root hard nofile 655350
EOF

# 4. 写入 Systemd 限制
sudo sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/g' /etc/systemd/system.conf
sudo sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/g' /etc/systemd/user.conf 2>/dev/null || sudo sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/g' /etc/systemd/user.conf
sudo grep -q "DefaultLimitNOFILE=655350" /etc/systemd/system.conf || echo "DefaultLimitNOFILE=655350" | sudo tee -a /etc/systemd/system.conf
sudo grep -q "DefaultLimitNOFILE=655350" /etc/systemd/user.conf || echo "DefaultLimitNOFILE=655350" | sudo tee -a /etc/systemd/user.conf
sudo systemctl daemon-reexec

# 5. 修改 DNS 提升解析响应速度
echo "正在优化公网 DNS 解析..."
sudo tee /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

echo "系统底层调优完全体配置成功！"
echo "VPS 即将自动重启以全面应用所有硬限制和硬件中断更改..."
sleep 2
sudo reboot
