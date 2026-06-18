#!/bin/bash

echo "正在开始优化网络代理节点（完全体，无 BBR 版）..."

# 1. 写入 sysctl 内核参数
sudo tee -a /etc/sysctl.conf << 'EOF'

# ================= 系统文件与全局队列优化 =================
fs.file-max = 65535000
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535

# ================= TCP/UDP 内存缓冲区优化 =================
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# ================= 连接复用与超时优化 =================
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_fin_timeout = 15

# ================= 握手与抗延迟优化 =================
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0

# ================= 防火墙连接跟踪表（Conntrack）优化 =================
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
EOF

# 使内核参数生效（容错处理）
sudo sysctl -p 2>/dev/null || true

# 2. 写入系统文件限制
sudo tee -a /etc/security/limits.conf << 'EOF'
* soft nofile 655350
* hard nofile 655350
root soft nofile 655350
root hard nofile 655350
EOF

# 3. 写入 Systemd 限制
sudo sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/g' /etc/systemd/system.conf
sudo sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/g' /etc/systemd/user.conf 2>/dev/null || sudo sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/g' /etc/systemd/user.conf
sudo grep -q "DefaultLimitNOFILE=655350" /etc/systemd/system.conf || echo "DefaultLimitNOFILE=655350" | sudo tee -a /etc/systemd/system.conf
sudo grep -q "DefaultLimitNOFILE=655350" /etc/systemd/user.conf || echo "DefaultLimitNOFILE=655350" | sudo tee -a /etc/systemd/user.conf
sudo systemctl daemon-reexec

# 4. 修改 DNS
sudo tee /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

echo "系统底层调优完成！VPS 即将自动重启以完全应用所有更改..."
sleep 2
sudo reboot
