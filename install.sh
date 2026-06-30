#!/usr/bin/env bash
# Oasisic Downloader — 安装脚本
# 平台: Debian/Ubuntu | 用法: sudo ./install.sh
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' N='\033[0m'
ok()   { echo -e "  ${G}✔${N}  $*"; }
fail() { echo -e "  ${R}✘${N}  $*" >&2; exit 1; }
info() { echo -e "  ${C}·${N}  $*"; }
head() { echo -e "\n  ${B}■${N}  ${B}$*${N}"; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="$DIR/server/.env"
YT="/usr/local/bin/yt-dlp"
START=$(date +%s)

# ─── 参数 ────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "  ${B}■${N}  ${B}Oasisic Downloader${N}  — 安装"
echo ""

P="3000"
[ -f "$ENV" ] && P=$(grep -E '^PORT=' "$ENV" | tail -1 | cut -d= -f2 | tr -d ' ')
read -r -p "  · 端口 [${P}]: " _P; P="${_P:-$P}"

S1=""; S2=""
[ -f "$ENV" ] && S1=$(grep -E '^SPOTIFY_CLIENT_ID=' "$ENV" | tail -1 | cut -d= -f2 | tr -d ' ')
[ -f "$ENV" ] && S2=$(grep -E '^SPOTIFY_CLIENT_SECRET=' "$ENV" | tail -1 | cut -d= -f2 | tr -d ' ')
if [ -z "$S1" ]; then
  echo ""
  read -r -p "  · Spotify Client ID (回车跳过): " S1
  read -r -p "  · Spotify Secret   (回车跳过): " S2
fi

echo ""
read -r -p "  · 开始安装？[Y/n] " _G
[[ "${_G,,}" == "n" ]] && exit 0

# ─── 系统依赖 ────────────────────────────────────────────────────
head "1/4  系统依赖"
apt-get update -qq 2>/dev/null
for p in curl ffmpeg aria2 python3 python3-pip; do
  dpkg -s "$p" &>/dev/null && info "$p" || { apt-get install -y -qq "$p" && ok "$p"; }
done
python3 -c "import mutagen" &>/dev/null && info "mutagen" \
  || { pip3 install -q --break-system-packages mutagen 2>/dev/null && ok "mutagen"; }

# ─── 工具链 ──────────────────────────────────────────────────────
head "2/4  工具链"
if command -v node &>/dev/null && [ "$(node --version | tr -d v | cut -d. -f1)" -ge 18 ]; then
  info "Node.js $(node --version)"
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &>/dev/null
  apt-get install -y -qq nodejs && ok "Node.js $(node --version)"
fi

if [ -x "$YT" ]; then
  info "yt-dlp $("$YT" --version)"
else
  curl -fsSL --connect-timeout 15 --max-time 60 \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$YT" \
    && chmod +x "$YT" && ok "yt-dlp $("$YT" --version)" || fail "yt-dlp 下载失败"
fi

command -v pm2 &>/dev/null && info "PM2" || { npm install -g pm2 -q && ok "PM2"; }

# ─── 项目依赖 ────────────────────────────────────────────────────
head "3/4  项目依赖"
[ -d node_modules ] && info "npm 依赖" \
  || { npm install --production --no-audit --no-fund && ok "npm 依赖"; }

CD="$DIR/client"
if [ -d "$CD/dist" ] && [ -f "$CD/dist/index.html" ] && [ "$CD/dist/index.html" -nt "$CD/src/App.jsx" ]; then
  info "前端构建"
else
  (cd "$CD" && npm install --no-audit --no-fund &>/dev/null && npm run build &>/dev/null) && ok "前端构建"
fi

# ─── 部署 ────────────────────────────────────────────────────────
head "4/4  部署"
mkdir -p downloads tmp logs
cat > "$ENV" << EOF
PORT=${P}
NODE_ENV=production
SPOTIFY_CLIENT_ID=${S1}
SPOTIFY_CLIENT_SECRET=${S2}
EOF
ok ".env 已配置 (端口 ${P})"

for n in ytdl-server oasisic-downloader; do
  pm2 list 2>/dev/null | grep -qw "$n" || continue
  pm2 stop "$n" --silent 2>/dev/null || true
  pm2 delete "$n" --silent 2>/dev/null || true
done
pm2 start ecosystem.config.js &>/dev/null
pm2 save &>/dev/null
ok "服务已启动 (端口 ${P})"

sed "s|@@INSTALL_DIR@@|$DIR|g; s|@@ENV_FILE@@|$ENV|g" scripts/oasisic.sh > /usr/local/bin/oasisic
chmod +x /usr/local/bin/oasisic && ok "oasisic 管理命令"

crontab -l 2>/dev/null | grep -qF "$YT -U" \
  || (crontab -l 2>/dev/null; echo "0 3 * * * $YT -U >> /var/log/ytdlp-update.log 2>&1") | crontab -

# ─── 完成 ────────────────────────────────────────────────────────
IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo localhost)"
echo ""
echo "  ──────────────────────────────────────"
echo -e "  ${G}✔${N}  安装完成  ($(( $(date +%s) - START )) 秒)"
echo ""
echo -e "  ${C}http://${IP}:${P}${N}"
echo "  oasisic"