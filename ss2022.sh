#!/bin/bash

# Step 1: Check if the system is Debian
if [ -f /etc/debian_version ]; then
  echo "This is a Debian-based system."
else
  echo "This is not a Debian-based system. Exiting."
  exit 1
fi

# Step 2: Update software sources
sudo apt update && sudo apt upgrade -y

# Step 3: Install Sing-box
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

# Step 4: Generate a random port and password
PORT=$((RANDOM % 65535 + 1024))
PASSWORD=$(sing-box generate rand 16 --base64)

# Step 5: Edit the config.json file in /etc/sing-box directory
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

# Step 6: Start Sing-box
sudo systemctl start sing-box

# Step 7: Output the configuration template
LOCAL_IP=$(hostname -I | awk '{print $1}')
cat <<EOF
{
  "type": "shadowsocks",
  "tag": "BWG",
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
