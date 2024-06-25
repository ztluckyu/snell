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

# Step 4: Ask if tcp-brutal should be enabled and handle the input
read -p "Do you want to enable tcp-brutal? (yes/no): " ENABLE_TCP_BRUTAL
if [[ "$ENABLE_TCP_BRUTAL" == "yes" ]]; then
  read -p "Enter the bandwidth (1-1000 Mbps): " BANDWIDTH
  if ! [[ "$BANDWIDTH" =~ ^[0-9]+$ ]] || [ "$BANDWIDTH" -lt 1 ] || [ "$BANDWIDTH" -gt 1000 ]; then
    echo "Invalid bandwidth value. Please enter a number between 1 and 1000."
    exit 1
  fi

  # Install the additional package
  bash <(curl -fsSL https://tcp.hy2.sh/)

  CONFIG_TEMPLATE=$(cat <<EOF
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": $PORT,
      "sniff": true,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$PASSWORD",
      "multiplex": {
        "enabled": true,
        "padding": true,
        "brutal": {
          "enabled": true,
          "up_mbps": $BANDWIDTH,
          "down_mbps": $BANDWIDTH
        }
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
)
else
  CONFIG_TEMPLATE=$(cat <<EOF
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": $PORT,
      "sniff": true,
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
)
fi

# Step 5: Edit the config.json file in /etc/sing-box directory
sudo mkdir -p /etc/sing-box
echo "$CONFIG_TEMPLATE" | sudo tee /etc/sing-box/config.json > /dev/null

# Step 6: Start Sing-box
sudo systemctl start sing-box

# Step 7: Output the configuration template and save to /root/ss2022.txt
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [[ "$ENABLE_TCP_BRUTAL" == "yes" ]]; then
  OUTPUT_CONFIG=$(cat <<EOF
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
    "protocol": "h2mux",
    "padding": true,
    "brutal": {
      "enabled": true,
      "up_mbps": $BANDWIDTH,
      "down_mbps": $BANDWIDTH
    }
  }
}
EOF
  )
else
  OUTPUT_CONFIG=$(cat <<EOF
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
    "protocol": "h2mux",
    "padding": true
  }
}
EOF
  )
fi

echo "$OUTPUT_CONFIG" | sudo tee /root/ss2022.txt > /dev/null
echo "配置模版已存放在 /root/ss2022.txt"

# Also output the configuration to the terminal
echo "$OUTPUT_CONFIG"
