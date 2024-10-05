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
UUID=$(sing-box generate uuid)
SS_PASSWORD=$(sing-box generate rand 16 --base64)
SS_PORT=$((RANDOM % 64512 + 1024))

# Step 4: Ask for the configuration option
echo "Choose a configuration option:"
echo "(1) ss2022"
echo "(2) ss2022 + TCP Brutal"
echo "(3) ss2022 + shadowtls"
echo "(4) ss128 + shadowtls"
read -p "Enter option (1/2/3/4): " OPTION

case "$OPTION" in
  1)
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
    ;;
  2)
    read -p "Enter the bandwidth (1-1000 Mbps): " BANDWIDTH
    if ! [[ "$BANDWIDTH" =~ ^[0-9]+$ ]] || [ "$BANDWIDTH" -lt 1 ] || [ "$BANDWIDTH" -gt 1000 ]; then
      echo "Invalid bandwidth value. Please enter a number between 1 and 1000."
      exit 1
    fi
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
    ;;
  3)
    CONFIG_TEMPLATE=$(cat <<EOF
{
  "inbounds": [
    {
      "type": "shadowtls",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "sniff_override_destination": true,
      "detour": "shadowsocks-in",
      "version": 3,
      "users": [
        {
          "password": "$UUID"
        }
      ],
      "handshake": {
        "server": "addons.mozilla.org",
        "server_port": 443
      },
      "strict_mode": true
    },
    {
      "type": "shadowsocks",
      "tag": "shadowsocks-in",
      "listen": "::",
      "listen_port": $SS_PORT,
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
    ;;
  4)
    CONFIG_TEMPLATE=$(cat <<EOF
{
  "inbounds": [
    {
      "type": "shadowtls",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "sniff_override_destination": true,
      "detour": "shadowsocks-in",
      "version": 3,
      "users": [
        {
          "password": "$UUID"
        }
      ],
      "handshake": {
        "server": "addons.mozilla.org",
        "server_port": 443
      },
      "strict_mode": true
    },
    {
      "type": "shadowsocks",
      "tag": "shadowsocks-in",
      "listen": "::",
      "listen_port": $SS_PORT,
      "method": "aes-128-gcm",
      "password": "$SS_PASSWORD",
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
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
esac

# Step 5: Edit the config.json file in /etc/sing-box directory
sudo mkdir -p /etc/sing-box
echo "$CONFIG_TEMPLATE" | sudo tee /etc/sing-box/config.json > /dev/null

# Step 6: Start Sing-box
sudo systemctl start sing-box

# Step 7: Output the configuration to /root/ss2022.txt
LOCAL_IP=$(hostname -I | awk '{print $1}')
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
EOF
)

echo "$OUTPUT_CONFIG" | sudo tee /root/ss2022.txt > /dev/null
echo "配置模版已存放在 /root/ss2022.txt"
