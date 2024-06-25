#!/bin/bash

# Step 0: Prompt for a name
read -p "Enter a name: " NAME

# Step 1: Update software sources
sudo apt update && sudo apt upgrade -y

# Step 2: Install Sing-box
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

# Step 3: Generate a random port and password
PORT=$((RANDOM % 64512 + 1024))
PASSWORD=$(sing-box generate rand 16 --base64)

# Step 4: Edit the config.json file in /etc/sing-box directory
sudo mkdir -p /etc/sing-box
sudo bash -c "cat > /etc/sing-box/config.json" <<EOF
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": $PORT,
      "sniff": true,
      "sniff_override_destination": true,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$PASSWORD",
      "multiplex": {
        "enabled": true,
        "padding": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# Step 5: Start Sing-box
sudo systemctl start sing-box

# Step 6: Output the configuration template
LOCAL_IP=$(hostname -I | awk '{print $1}')
cat <<EOF
{
  "type": "shadowsocks",
  "tag": "$NAME",
  "server": "$LOCAL_IP",
  "server_port": $PORT,
  "method": "2022-blake3-aes-128-gcm",
  "password": "$PASSWORD",
  "udp_over_tcp": false,
  "multiplex": {
    "enabled": true,
    "padding": true
  }
}
EOF
