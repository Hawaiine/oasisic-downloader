#!/usr/bin/env bash
set -euo pipefail

G='\033[0;32m' C='\033[0;36m' N='\033[0m'
ok()   { echo -e "   ${G}✔${N}  $*"; }
head() { echo -e "\n  ${G}==>${N}  ${G}$*${N}"; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="$DIR/server/.env"
YT="/usr/local/bin/yt-dlp"
START=$(date +%s)

# ─── 参数 ────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "  ${G}==>${N}  Oasisic Downloader  — 安装"
echo ""

P="3000"
[ -f "$ENV" ] && P=$(grep -E '^PORT=' "$ENV" | tail -1 | cut -d= -f2 | tr -d ' ')
read -r -p "  Port [${P}]: " _P; P="${_P:-$P}"

S1=""; S2=""
[ -f "$ENV" ] && S1=$(grep -E '^SPOTIFY_CLIENT_ID=' "$ENV" | tail -1 | cut -d= -f2 | tr -d ' ')
[ -f "$ENV" ] && S2=$(grep -E '^SPOTIFY_CLIENT_SECRET=' "$ENV" | tail -1 | cut -d= -f2 | tr -d ' ')
if [ -z "$S1" ]; then
  read -r -p "  Spotify Client ID (skip=Enter): " S1
  read -r -p "  Spotify Secret   (skip=Enter): " S2
fi

read -r -p "  Proceed? [Y/n] " _G
[[ "${_G,,}" == "n" ]] && exit 0

# ─── System ──────────────────────────────────────────────────────
head "1/4  System Dependencies"
apt-get update -qq 2>/dev/null
for p in curl ffmpeg aria2 python3 python3-pip; do
  dpkg -s "$p" &>/dev/null || apt-get install -y -qq "$p"
  ok "$p"
done
python3 -c "import mutagen" &>/dev/null && ok "mutagen (python)" \
  || { pip3 install -q --break-system-packages mutagen 2>/dev/null && ok "mutagen (python)"; }

# ─── Tools ───────────────────────────────────────────────────────
head "2/4  Tools"
if command -v node &>/dev/null && [ "$(node --version | tr -d v | cut -d. -f1)" -ge 18 ]; then
  ok "Node.js $(node --version)"
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &>/dev/null
  apt-get install -y -qq nodejs && ok "Node.js $(node --version)"
fi

if [ -x "$YT" ] && "$YT" --version &>/dev/null; then
  ok "yt-dlp $("$YT" --version)"
else
  curl -fsSL --connect-timeout 15 --max-time 60 \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$YT" \
    && chmod +x "$YT" && ok "yt-dlp $("$YT" --version)" || echo "  ✘ yt-dlp download failed"
fi

command -v pm2 &>/dev/null && ok "PM2 $(pm2 --version)" \
  || { npm install -g pm2 -q && ok "PM2 $(pm2 --version)"; }

# ─── Project ─────────────────────────────────────────────────────
head "3/4  Project Dependencies"
[ ! -d node_modules ] && npm install --production --no-audit --no-fund
ok "npm packages"

CD="$DIR/web"
if [ ! -f "$CD/dist/index.html" ] || [ "$CD/src/App.jsx" -nt "$CD/dist/index.html" ]; then
  (cd "$CD" && npm install --no-audit --no-fund &>/dev/null && npm run build &>/dev/null)
fi
ok "frontend build"

# ─── Deploy ──────────────────────────────────────────────────────
head "4/4  Deploy"
mkdir -p downloads tmp logs

cat > "$ENV" << EOF
PORT=${P}
NODE_ENV=production
SPOTIFY_CLIENT_ID=${S1}
SPOTIFY_CLIENT_SECRET=${S2}
# AUTH_TOKEN=your-secret-token    # 可选：启用 Bearer 鉴权（注释掉则不开启）
EOF
ok "config written (port ${P})"

for n in ytdl-server oasisic-downloader; do
  pm2 list 2>/dev/null | grep -qw "$n" || continue
  pm2 stop "$n" --silent 2>/dev/null || true
  pm2 delete "$n" --silent 2>/dev/null || true
done
pm2 start ecosystem.config.js &>/dev/null
pm2 save &>/dev/null
ok "service started (port ${P})"

# 管理命令（替换路径占位符）
sed "s|@@INSTALL_DIR@@|$DIR|g; s|@@ENV_FILE@@|$ENV|g" "$DIR/scripts/oasisic.sh" > /usr/local/bin/oasisic
chmod +x /usr/local/bin/oasisic && ok "oasisic command installed"

crontab -l 2>/dev/null | grep -qF "$YT -U" \
  || (crontab -l 2>/dev/null; echo "0 3 * * * $YT -U >> /var/log/ytdlp-update.log 2>&1") | crontab -

# ─── Done ────────────────────────────────────────────────────────
IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo localhost)"
echo ""
echo -e "  ${G}==>${N}  ${G}Done${N}  ($(( $(date +%s) - START ))s)"
echo ""
echo -e "  ${C}http://${IP}:${P}${N}"
echo "  Run: oasisic"