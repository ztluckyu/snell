#!/bin/bash

# 第一步
sudo apt-get update
sudo apt-get install -y wget curl sudo vim git lsof mtr iperf3 unzip

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

# 第七步
sudo systemctl daemon-reload
sudo systemctl start snell
sudo systemctl enable snell
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
cat /etc/snell-server.conf



