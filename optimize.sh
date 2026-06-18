#!/bin/bash

echo "正在开始优化网络代理节点..."

# 1. 写入 sysctl 内核参数
sudo tee -a /etc/sysctl.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 65535000
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF
sudo sysctl -p

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
