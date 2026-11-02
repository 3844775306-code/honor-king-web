#!/usr/bin/env bash
# HonorKing 云端存档 · 阿里云轻量应用服务器一键安装（Ubuntu / Debian，root 执行）
#
# 用法（在解压后的 cloud-save 目录里）：
#   CLOUD_TOKEN='换成你自己的长口令' bash deploy/install.sh
#
# 作用：装 Node 20（缺才装）→ 拷服务到 /opt/honorking-cloud-save → 写 systemd → 启动
set -euo pipefail

APP_DIR="/opt/honorking-cloud-save"
PORT="${PORT:-8788}"
TOKEN="${CLOUD_TOKEN:-}"
NODE_VER="${NODE_VER:-v20.19.0}"

if [[ -z "$TOKEN" || ${#TOKEN} -lt 8 ]]; then
  echo "请设置 CLOUD_TOKEN（至少 8 位）：CLOUD_TOKEN='你的长口令' bash deploy/install.sh"
  exit 1
fi

cd "$(dirname "$0")/.."   # 进入 cloud-save 目录（dev-server.mjs 所在）

# 1) Node：优先用国内镜像安装，避免 nodesource 拉取慢
if ! command -v node >/dev/null 2>&1; then
  echo "[install] 安装 Node ${NODE_VER} …"
  case "$(uname -m)" in
    x86_64) ARCH="linux-x64" ;;
    aarch64) ARCH="linux-arm64" ;;
    *) echo "不支持的架构：$(uname -m)"; exit 1 ;;
  esac
  TMP="$(mktemp -d)"
  curl -fsSL "https://npmmirror.com/mirrors/node/${NODE_VER}/node-${NODE_VER}-${ARCH}.tar.xz" -o "$TMP/node.tar.xz"
  tar -xf "$TMP/node.tar.xz" -C "$TMP"
  cp -rf "$TMP/node-${NODE_VER}-${ARCH}/bin/"* /usr/local/bin/
  cp -rf "$TMP/node-${NODE_VER}-${ARCH}/lib/"* /usr/local/lib/ 2>/dev/null || true
  rm -rf "$TMP"
fi
NODE_BIN="$(command -v node)"

# 2) 拷贝服务文件
mkdir -p "$APP_DIR"
cp -f dev-server.mjs "$APP_DIR/dev-server.mjs"
mkdir -p "$APP_DIR/.data"

# 3) systemd 常驻
cat > /etc/systemd/system/honorking-save.service <<EOF
[Unit]
Description=HonorKing cloud save server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=HOST=0.0.0.0
Environment=PORT=$PORT
Environment=CLOUD_TOKEN=$TOKEN
ExecStart=$NODE_BIN $APP_DIR/dev-server.mjs
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now honorking-save

sleep 1
echo
echo "[install] 已启动。本机自检："
curl -fsS "http://127.0.0.1:${PORT}/health" && echo
IP="$(curl -fsS --max-time 5 https://ipinfo.io/ip 2>/dev/null || true)"
echo
echo "游戏内配置："
echo "  存储后端：通用 HTTP"
echo "  服务器地址：http://${IP:-<服务器公网IP>}:${PORT}"
echo "  访问令牌：$TOKEN"
echo
echo "记得在阿里云轻量控制台「防火墙」放行 TCP ${PORT}。"
echo "数据目录：${APP_DIR}/.data （备份：cp ${APP_DIR}/.data/saves.json /root/saves-$(date +%F).json）"
