#!/bin/bash

# 检测系统架构
export ARCH=$(case "$(uname -m)" in
    'x86_64') echo 'amd64';;
    'x86' | 'i686' | 'i386') echo '386';;
    'aarch64' | 'arm64') echo 'arm64';;
    'armv7l') echo 'armv7';;
    's390x') echo 's390x';;
    *) echo '不支持的服务器架构';;
esac)

echo -e "\n当前服务器架构是：$ARCH"

# 如果架构不支持则退出
if [ "$ARCH" = "不支持的服务器架构" ]; then
    echo "不支持的服务器架构，退出安装"
    exit 1
fi

# 获取最新的mihomo版本号
LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep -o '"tag_name": ".*"' | sed 's/"tag_name": "//;s/"//g')

# 如果无法获取版本号，则退出
if [ -z "$LATEST_VERSION" ]; then
    echo "无法获取最新版本号，请检查网络连接"
    exit 1
fi

echo "最新的mihomo版本是：$LATEST_VERSION"

# 根据链接格式调整版本号格式（移除可能的'v'前缀）
VERSION_NUM=${LATEST_VERSION#v}

# 根据架构下载对应的压缩包
DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/mihomo-linux-${ARCH}-${LATEST_VERSION}.gz"
echo "下载地址：$DOWNLOAD_URL"

# 创建临时目录并进入
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || exit 1

# 下载mihomo
echo "正在下载mihomo..."
wget -q "$DOWNLOAD_URL" -O mihomo.gz

# 检查下载是否成功
if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络连接或版本信息"
    exit 1
fi

# 解压文件
echo "正在解压文件..."
gunzip mihomo.gz

# 确保文件存在且有执行权限
if [ ! -f "mihomo" ]; then
    echo "解压后未找到可执行文件"
    exit 1
fi

chmod +x mihomo

# 移动可执行文件到/usr/local/bin目录
echo "正在安装mihomo到系统..."
sudo mv mihomo /usr/local/bin/
sudo chmod +x /usr/local/bin/mihomo

# 创建配置目录
echo "创建配置目录..."
sudo mkdir -p /etc/mihomo

# 创建基本配置文件
echo "创建基本配置文件..."
# 生成随机端口和密码
SS_PORT_BASE=$((10000 + RANDOM % 55000))
SS_PORT_MUX=$((SS_PORT_BASE + 1))
SS_PORT_NONE=$((SS_PORT_BASE + 2))
SS_PORT_128=$((SS_PORT_BASE + 3))
ANYTLS_PORT=$((10000 + RANDOM % 55000))

# 确保AnyTLS端口与SS端口不冲突
while [ "$ANYTLS_PORT" -ge "$SS_PORT_BASE" ] && [ "$ANYTLS_PORT" -le "$((SS_PORT_BASE + 3))" ]; do
  ANYTLS_PORT=$((10000 + RANDOM % 55000))
done

# 生成随机密码和用户名
SS_PASSWORD=$(openssl rand -base64 16)
ANYTLS_USERNAME=$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)
ANYTLS_PASSWORD=$(openssl rand -base64 16)

# 生成证书和密钥
echo "生成SSL证书和密钥..."
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout ca.key -out ca.cer \
  -subj "/CN=mihomo.local" \
  -addext "subjectAltName=DNS:mihomo.local,IP:127.0.0.1"

sudo mv ca.key ca.cer /etc/mihomo/

# 创建配置文件
cat > config.yaml << EOF
allow-lan: true
bind-address: '0.0.0.0'
mode: rule
log-level: info
ipv6: true
inbound-tfo: true
inbound-mptcp: true


listeners:
  - name: in-ss-mux
    type: shadowsocks
    port: $SS_PORT_MUX
    listen: 0.0.0.0
    password: $SS_PASSWORD
    cipher: 2022-blake3-aes-128-gcm
    mux-option: { padding: true }
  - name: in-ss-none
    type: shadowsocks
    port: $SS_PORT_NONE
    listen: 0.0.0.0
    password: $SS_PASSWORD
    cipher: none
  - name: in-ss-128
    type: shadowsocks
    port: $SS_PORT_128
    listen: 0.0.0.0
    password: $SS_PASSWORD
    cipher: aes-128-gcm
    mux-option: { padding: true }
  - name: in-anytls
    type: anytls
    port: $ANYTLS_PORT
    listen: 0.0.0.0
    users: { $ANYTLS_USERNAME: $ANYTLS_PASSWORD }
    certificate: /etc/mihomo/ca.cer
    private-key: /etc/mihomo/ca.key
rules:
  - DOMAIN-SUFFIX,ad.com,REJECT
  - MATCH,DIRECT
EOF

# 将配置文件复制到配置目录
sudo mv config.yaml /etc/mihomo/config.yaml

# 创建systemd服务配置文件
echo "创建systemd服务配置文件..."
cat > mihomo.service << 'EOF'
[Unit]
Description=mihomo Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -f /etc/mihomo/config.yaml
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# 安装systemd服务文件
sudo mv mihomo.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mihomo.service

# 清理临时文件
cd
rm -rf "$TMP_DIR"

echo "mihomo安装完成！"
echo "可执行文件位置：/usr/local/bin/mihomo"
echo "配置文件位置：/etc/mihomo/config.yaml"
echo "服务文件位置：/etc/systemd/system/mihomo.service"
echo "证书文件位置：/etc/mihomo/ca.cer"
echo "密钥文件位置：/etc/mihomo/ca.key"
echo ""
echo "Shadowsocks 配置信息："
echo "  端口1 (mux): $SS_PORT_MUX  - 加密方式: 2022-blake3-aes-128-gcm"
echo "  端口2 (none): $SS_PORT_NONE  - 加密方式: none"
echo "  端口3 (128): $SS_PORT_128  - 加密方式: aes-128-gcm"
echo "  密码: $SS_PASSWORD"
echo ""
echo "AnyTLS 配置信息："
echo "  端口: $ANYTLS_PORT"
echo "  用户名: $ANYTLS_USERNAME"
echo "  密码: $ANYTLS_PASSWORD"
echo ""
echo "您可以使用以下命令管理mihomo服务："
echo "启动服务: sudo systemctl start mihomo"
echo "停止服务: sudo systemctl stop mihomo"
echo "查看状态: sudo systemctl status mihomo"
echo "查看日志: sudo journalctl -u mihomo"
