#!/bin/bash

# 第一步
sudo apt install wget curl sudo vim git lsof mtr iperf3 unzip -y

# 第二步
wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip

# 第三步
sudo unzip snell-server-v4.0.1-linux-amd64.zip -d /usr/local/bin

# 第四步
sudo chmod +x /usr/local/bin/snell-server

# 第五步
sudo snell-server --wizard -c /etc/snell-server.conf <<< "y"

# 第六步
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

# 重载服务
sudo systemctl daemon-reload

# 开机运行 Snell
sudo systemctl start snell

# 开启 Snell
sudo systemctl enable snell

sysctl -w net.core.rmem_max=26214400

sysctl -w net.core.rmem_default=26214400

