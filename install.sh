#!/usr/bin/env bash
# =============================================================================
# Oasisic Downloader — 安装脚本
# 平台: Debian 12/13 · Ubuntu 22.04/24.04
# 用法: sudo ./install.sh
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── 颜色与样式 ──────────────────────────────────────────────────────────────
R='\033[0;31m'    G='\033[0;32m'    Y='\033[1;33m'    C='\033[0;36m'
B='\033[1m'       N='\033[0m'       D='\033[2m'       W='\033[1;37m'

ok()   { echo -e " ${G}✅${N}  $*"; }
fail() { echo -e " ${R}❌  $*${N}" >&2; exit 1; }
warn() { echo -e " ${Y}⚠️  $*${N}"; }
info() { echo -e " ${C}ℹ️  $*${N}"; }
step() { echo -e "\n${B}${W}━━━  $*  ━━━${N}"; }
skip() { echo -e " ${D}⏭️  $*${N}"; }

run_q() {
  local label="$1"; shift
  printf "  %-40s" "${label}..."
  if "$@" >/dev/null 2>&1; then echo -e " ${G}✓${N}"
  else echo -e " ${R}✗${N}"; return 1; fi
}
ver_gte() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

# ── 基础变量 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
ENV_FILE="$SCRIPT_DIR/server/.env"
YTDLP_BIN="/usr/local/bin/yt-dlp"
PM2_PROC="oasisic-downloader"
OASISIC_CMD="/usr/local/bin/oasisic"
APT_DONE=0
START_TIME=$(date +%s)

apt_once() {
  [ "$APT_DONE" -eq 1 ] && return
  run_q "apt-get update" apt-get update; APT_DONE=1
}
pkg_install() {
  dpkg -s "$1" >/dev/null 2>&1 && { skip "$1 已安装"; return; }
  apt_once
  run_q "安装 $1" apt-get install -y "$1" && ok "$1 安装完成"
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  开场                                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════╝
clear 2>/dev/null || true
echo ""
echo -e "  ${B}${C}╔══════════════════════════════════════════════╗${N}"
echo -e "  ${B}${C}║${N}  ${W}🧲  Oasisic Downloader  安装向导${N}           ${B}${C}║${N}"
echo -e "  ${B}${C}║${N}  ${D}YouTube 高品质音视频下载系统${N}               ${B}${C}║${N}"
echo -e "  ${B}${C}╚══════════════════════════════════════════════╝${N}"
echo ""
echo -e "  📁 ${B}安装目录:${N} ${C}${SCRIPT_DIR}${N}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
step "⚙️  配置参数"
# ══════════════════════════════════════════════════════════════════════════

# ── 端口 ──
EXIST_PORT=""
[ -f "$ENV_FILE" ] && EXIST_PORT="$(grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ' || true)"
DEF_PORT="${EXIST_PORT:-3000}"

echo -e "  ${B}🔌 服务端口${N}  (默认 ${C}${DEF_PORT}${N})"
read -r -p "  → 端口号: " _IN_PORT
CHOSEN_PORT="${_IN_PORT:-$DEF_PORT}"
[[ "$CHOSEN_PORT" =~ ^[0-9]+$ ]] && [ "$CHOSEN_PORT" -ge 1 ] && [ "$CHOSEN_PORT" -le 65535 ] \
  || fail "端口号无效: $CHOSEN_PORT"
ok "端口: ${C}${CHOSEN_PORT}${N}"

# 端口占用检测
CON_PID=""
command -v ss &>/dev/null && CON_PID="$(ss -tlnp "sport = :${CHOSEN_PORT}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1 || true)"
if [ -n "$CON_PID" ]; then
  CON_CMD="$(ps -p "$CON_PID" -o comm= 2>/dev/null || echo '未知')"
  warn "端口 ${CHOSEN_PORT} 已被 ${CON_CMD} (PID: ${CON_PID}) 占用"
  read -r -p "  → 强制终止占用的进程？[y/N]: " _K
  if [[ "${_K,,}" == "y" ]]; then
    kill -TERM "$CON_PID" 2>/dev/null || true; sleep 2
    kill -0 "$CON_PID" 2>/dev/null && { kill -KILL "$CON_PID" 2>/dev/null || true; sleep 1; }
    ok "占用的进程已终止"
  else
    fail "请先释放端口 ${CHOSEN_PORT} 后重新安装"
  fi
fi

# ── Spotify（可选）─────────────────────────────────────────────────────────
EXIST_SPOT_ID=""; EXIST_SPOT_SEC=""
[ -f "$ENV_FILE" ] && EXIST_SPOT_ID="$(grep -E '^SPOTIFY_CLIENT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)"
[ -f "$ENV_FILE" ] && EXIST_SPOT_SEC="$(grep -E '^SPOTIFY_CLIENT_SECRET=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)"

if [ -n "$EXIST_SPOT_ID" ]; then
  SPOT_ID="$EXIST_SPOT_ID"; SPOT_SEC="$EXIST_SPOT_SEC"
  ok "Spotify 凭证已存在（可通过 ${C}oasisic${N} 管理命令修改）"
else
  echo ""
  echo -e "  ${B}🎵 Spotify API（可选）${N}"
  echo -e "  ${D}  用途: 辅助歌词搜索匹配曲目${N}"
  echo -e "  ${D}  获取: https://developer.spotify.com/dashboard → Create App${N}"
  echo -e "  ${D}  提示: 不填写不影响下载功能${N}"
  read -r -p "  → Client ID     (回车跳过): " SPOT_ID
  read -r -p "  → Client Secret (回车跳过): " SPOT_SEC
  [ -n "$SPOT_ID" ] && ok "Spotify 已配置" || info "Spotify 跳过"
fi

SPOT_STATUS="$([ -n "$SPOT_ID" ] && echo '✓ 已配置' || echo '− 跳过')"

# ── 确认 ──
echo ""
echo -e "  ${B}┌─ 配置摘要 ───────────────────────────┐${N}"
echo -e "  ${B}│${N}  ${C}🔌 端口${N}        ${CHOSEN_PORT}"
echo -e "  ${B}│${N}  ${C}🎵 Spotify${N}      ${SPOT_STATUS}"
echo -e "  ${B}└────────────────────────────────────────┘${N}"
echo ""
read -r -p "  → 确认以上配置，开始安装？[Y/n]: " _GO
[[ "${_GO,,}" == "n" ]] && { echo -e "\n  安装已取消"; exit 0; }

# ══════════════════════════════════════════════════════════════════════════
step "1/7 · 系统依赖"
# ══════════════════════════════════════════════════════════════════════════
echo ""
for pkg in curl ffmpeg aria2 python3 python3-pip; do pkg_install "$pkg"; done

# mutagen
echo ""
printf "  %-40s" "python3 mutagen..."
python3 -c "import mutagen" 2>/dev/null && echo -e " ${G}✓${N}" || {
  pip3 install --quiet --break-system-packages mutagen 2>/dev/null \
    || pip3 install --quiet mutagen 2>/dev/null \
    || true
  python3 -c "import mutagen" 2>/dev/null && echo -e " ${G}✓${N}" \
    || echo -e " ${Y}⚠ 安装失败（可手动: pip3 install mutagen）${N}"
}

# ══════════════════════════════════════════════════════════════════════════
step "2/7 · Node.js"
# ══════════════════════════════════════════════════════════════════════════
echo ""
NODE_OK=0
if command -v node &>/dev/null; then
  NODE_VER="$(node --version | tr -d 'v')"
  if ver_gte "$NODE_VER" "18.0.0"; then
    ok "Node.js ${NODE_VER} ✓"
    NODE_OK=1
  else
    warn "Node.js ${NODE_VER} 版本过低，升级中..."
  fi
fi
if [ "$NODE_OK" -eq 0 ]; then
  run_q "添加 NodeSource 源" bash -c 'curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1'
  run_q "安装 nodejs"        apt-get install -y nodejs
  ok "Node.js $(node --version) 安装完成"
fi

# ══════════════════════════════════════════════════════════════════════════
step "3/7 · yt-dlp"
# ══════════════════════════════════════════════════════════════════════════
echo ""
YTDLP_BEFORE="$([ -x "$YTDLP_BIN" ] && "$YTDLP_BIN" --version 2>/dev/null || echo '未安装')"

if [ -x "$YTDLP_BIN" ] && "$YTDLP_BIN" --version &>/dev/null; then
  ok "yt-dlp ${YTDLP_BEFORE} 已存在，跳过安装"
else
  YTDLP_OK=0
  printf "  %-40s" "从 GitHub 下载..."
  _ytdlp_curl() {
    if [ "$(id -u)" -eq 0 ]; then
      curl -fsSL --connect-timeout 15 --max-time 120 \
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$YTDLP_BIN"
    else
      local _tmp; _tmp="$(mktemp)"
      curl -fsSL --connect-timeout 15 --max-time 120 \
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$_tmp" \
        && sudo mv "$_tmp" "$YTDLP_BIN" || { rm -f "$_tmp"; return 1; }
    fi
  }
  if _ytdlp_curl 2>/dev/null && [ -s "$YTDLP_BIN" ]; then
    [ "$(id -u)" -eq 0 ] && chmod +x "$YTDLP_BIN" || sudo chmod +x "$YTDLP_BIN"
    "$YTDLP_BIN" --version &>/dev/null && YTDLP_OK=1
  fi
  [ "$YTDLP_OK" -eq 1 ] && echo -e " ${G}✓${N}" || echo -e " ${Y}跳过${N}"

  if [ "$YTDLP_OK" -eq 0 ]; then
    printf "  %-40s" "备用: pip3 安装..."
    pip3 install --quiet --break-system-packages yt-dlp 2>/dev/null || true
    if python3 -m yt_dlp --version &>/dev/null; then
      echo '#!/bin/sh' > "$YTDLP_BIN"
      echo 'exec python3 -m yt_dlp "$@"' >> "$YTDLP_BIN"
      chmod +x "$YTDLP_BIN"
      "$YTDLP_BIN" --version &>/dev/null && YTDLP_OK=1
    fi
    [ "$YTDLP_OK" -eq 1 ] && echo -e " ${G}✓${N}" || echo -e " ${Y}跳过${N}"
  fi

  [ "$YTDLP_OK" -eq 0 ] && fail "yt-dlp 安装失败，请检查网络连接后重试"

  YTDLP_AFTER="$("$YTDLP_BIN" --version 2>/dev/null || echo '?')"
  [ "$YTDLP_BEFORE" = "$YTDLP_AFTER" ] \
    && ok "yt-dlp ${YTDLP_AFTER} ✓" \
    || ok "yt-dlp: ${YTDLP_BEFORE} → ${YTDLP_AFTER}"
fi

# ══════════════════════════════════════════════════════════════════════════
step "4/7 · PM2 进程管理器"
# ══════════════════════════════════════════════════════════════════════════
echo ""
if command -v pm2 &>/dev/null; then
  ok "PM2 $(pm2 --version) ✓"
else
  run_q "安装 PM2" npm install -g pm2
  ok "PM2 $(pm2 --version) 安装完成"
fi

# ══════════════════════════════════════════════════════════════════════════
step "5/7 · 后端依赖 (npm)"
# ══════════════════════════════════════════════════════════════════════════
echo ""
[ -f "package.json" ] || fail "未找到 package.json"

# 检测是否已安装
if [ -d "node_modules" ] && [ -f "node_modules/.package-lock.json" ]; then
  skip "node_modules 已存在，跳过安装"
else
  # 低内存环境处理
  TOTAL_MEM="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 2097152)"
  if [ "$TOTAL_MEM" -lt 1048576 ] 2>/dev/null; then
    warn "内存不足 1GB（${TOTAL_MEM} KB）"
    echo -e "  ${B}💡 推荐使用 Docker:${N}"
    echo -e "  ${C}  docker compose -f docker-compose.pull.yml up -d${N}"
    read -r -p "  → 继续本地安装？[y/N]: " _CONT
    [[ "${_CONT,,}" != "y" ]] && { echo "安装已取消"; exit 0; }
    if [ "$(id -u)" -eq 0 ] && ! swapon --show 2>/dev/null | grep -q .; then
      info "创建 1GB swap..."
      fallocate -l 1G /swapfile 2>/dev/null && chmod 600 /swapfile \
        && mkswap /swapfile 2>/dev/null && swapon /swapfile 2>/dev/null \
        && ok "Swap 已启用" || warn "创建 swap 失败"
    fi
  fi

  info "安装后端依赖（首次约 1-3 分钟）..."
  npm install --production --no-audit --no-fund
  ok "后端依赖安装完成"
fi

# ══════════════════════════════════════════════════════════════════════════
step "6/7 · 前端构建 (React + Vite)"
# ══════════════════════════════════════════════════════════════════════════
echo ""
CLIENT_DIR="$SCRIPT_DIR/client"
DIST_DIR="$CLIENT_DIR/dist"

# 检测前端是否已是最新
BUILD_NEEDED=1
if [ -d "$DIST_DIR" ] && [ -f "$DIST_DIR/index.html" ]; then
  NEWER="$(find "$CLIENT_DIR/src" -newer "$DIST_DIR/index.html" 2>/dev/null | wc -l)"
  [ "$NEWER" -eq 0 ] && skip "前端已是最新，跳过构建" && BUILD_NEEDED=0
fi

if [ "$BUILD_NEEDED" -eq 1 ]; then
  info "安装前端依赖..."
  ( cd "$CLIENT_DIR" && npm install --no-audit --no-fund )
  ok "前端依赖完成"

  info "Vite 构建中..."
  BUILD_LOG="$(cd "$CLIENT_DIR" && npm run build 2>&1)"
  if echo "$BUILD_LOG" | grep -q "built in\|vite v" || [ -f "$DIST_DIR/index.html" ]; then
    ok "构建完成 → client/dist/"
  else
    echo ""
    echo -e "${R}  ❌ 构建失败:${N}"
    echo "$BUILD_LOG" | tail -20 | sed 's/^/    /'
    fail "前端构建失败"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════
step "7/7 · 部署"
# ══════════════════════════════════════════════════════════════════════════
echo ""

# 工作目录
for dir in downloads tmp logs; do mkdir -p "$SCRIPT_DIR/$dir"; done
RUN_USER="${SUDO_USER:-root}"
chown -R "$RUN_USER":"$RUN_USER" "$SCRIPT_DIR/downloads" "$SCRIPT_DIR/tmp" "$SCRIPT_DIR/logs" 2>/dev/null || true
ok "downloads/ tmp/ logs/ 就绪"

# .env
mkdir -p "$(dirname "$ENV_FILE")"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" << _EV
# Oasisic Downloader — 服务器环境变量
PORT=${CHOSEN_PORT}
NODE_ENV=production
SPOTIFY_CLIENT_ID=${SPOT_ID}
SPOTIFY_CLIENT_SECRET=${SPOT_SEC}
# Apple Music（可选）: developer.apple.com → MusicKit Key
# APPLE_MUSIC_TOKEN=
_EV
  ok ".env 创建完成"
else
  _CHG=0
  if grep -qE '^PORT=' "$ENV_FILE"; then
    OLD_P="$(grep -E '^PORT=' "$ENV_FILE" | head -1 | cut -d= -f2 | tr -d ' ')"
    if [ "$OLD_P" != "$CHOSEN_PORT" ]; then
      sed -i "s/^PORT=.*/PORT=${CHOSEN_PORT}/" "$ENV_FILE"
      ok "端口更新: ${OLD_P} → ${CHOSEN_PORT}"; _CHG=1
    else
      ok "端口无变化 (${CHOSEN_PORT})"
    fi
  else
    sed -i "1s/^/PORT=${CHOSEN_PORT}\n/" "$ENV_FILE"; _CHG=1
  fi
  if [ -n "$SPOT_ID" ] && [ "$SPOT_ID" != "$EXIST_SPOT_ID" ]; then
    grep -qE '^SPOTIFY_CLIENT_ID='     "$ENV_FILE" \
      && sed -i "s/^SPOTIFY_CLIENT_ID=.*/SPOTIFY_CLIENT_ID=${SPOT_ID}/"         "$ENV_FILE" \
      || echo "SPOTIFY_CLIENT_ID=${SPOT_ID}"     >> "$ENV_FILE"
    grep -qE '^SPOTIFY_CLIENT_SECRET=' "$ENV_FILE" \
      && sed -i "s/^SPOTIFY_CLIENT_SECRET=.*/SPOTIFY_CLIENT_SECRET=${SPOT_SEC}/" "$ENV_FILE" \
      || echo "SPOTIFY_CLIENT_SECRET=${SPOT_SEC}" >> "$ENV_FILE"
    ok "Spotify 凭证更新"; _CHG=1
  fi
  [ "$_CHG" -eq 0 ] && info ".env 无需变更"
fi

# PM2 服务启动
for _old_proc in ytdl-server oasisic-downloader; do
  pm2 list 2>/dev/null | grep -qw "$_old_proc" || continue
  pm2 stop "$_old_proc" --silent 2>/dev/null || true
  pm2 delete "$_old_proc" --silent 2>/dev/null || true
done

run_q "启动服务"   pm2 start "$SCRIPT_DIR/ecosystem.config.js"
run_q "保存 PM2"   pm2 save
ok "服务已启动 (端口 ${C}${CHOSEN_PORT}${N})"

# 开机自启
_STARTUP="$(pm2 startup 2>&1 | grep '^sudo' | head -1 || true)"
[ -n "$_STARTUP" ] && { eval "$_STARTUP" >/dev/null 2>&1 && ok "开机自启 ✓" || warn "开机自启设置失败"; } || ok "开机自启 ✓"

# Cron 自动更新 yt-dlp
CRON_JOB="0 3 * * * ${YTDLP_BIN} -U >> /var/log/ytdlp-update.log 2>&1"
crontab -l 2>/dev/null | grep -qF "${YTDLP_BIN} -U" \
  && skip "yt-dlp 自动更新 cron 已存在" \
  || { ( crontab -l 2>/dev/null; echo "$CRON_JOB" ) | crontab -; ok "每日 03:00 自动更新 yt-dlp"; }

# 注册 oasisic 管理命令
info "注册 oasisic 管理命令..."
OASISIC_TMP="$(mktemp /tmp/oasisic.XXXXXX)"

# ── 生成管理脚本（from heredoc template）──────────────
# 注意: __TPL__ 使用单引号防止 bash 展开变量
cat > "$OASISIC_TMP" << '__TPL__'
#!/usr/bin/env bash
# oasisic — Oasisic Downloader 管理工具
INSTALL_DIR="@@INSTALL_DIR@@"
YTDLP_BIN="@@YTDLP_BIN@@"
ENV_FILE="@@ENV_FILE@@"
PM2_PROC="@@PM2_PROC@@"

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' B='\033[1m' N='\033[0m' D='\033[2m'
ok()   { echo -e " ${G}✅${N}  $*"; }
warn() { echo -e " ${Y}⚠️  $*${N}"; }
info() { echo -e " ${C}ℹ️  $*${N}"; }
err()  { echo -e " ${R}❌  $*${N}"; }

get_port() { grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ' || echo 3000; }
pm2_restart() {
  pm2 stop   "$PM2_PROC" --silent 2>/dev/null || true
  pm2 delete "$PM2_PROC" --silent 2>/dev/null || true
  pm2 start  "$INSTALL_DIR/ecosystem.config.js" >/dev/null 2>&1
  pm2 save   >/dev/null 2>&1
}

print_box() {
  local txt="$1"
  echo -e "${B}${C}┌─────────────────────────────────────────────┐${N}"
  echo -e "${B}${C}│${N}  ${W}🧲  Oasisic Downloader${N}  ${D}管理工具${N}           ${B}${C}│${N}"
  echo -e "${B}${C}├─────────────────────────────────────────────┤${N}"
  echo -e "${B}${C}│${N}  🛜  进程: ${C}${PM2_PROC}${N}       🔌 端口: ${C}$(get_port)${N}   ${B}${C}│${N}"
  echo -e "${B}${C}└─────────────────────────────────────────────┘${N}"
}
show_menu() {
  local PORT; PORT="$(get_port)"
  clear 2>/dev/null || printf '\033[2J\033[H'
  print_box
  echo ""
  echo -e " ${B}── 日常 ──────────────────────────────────${N}"
  echo "   1)  🔄  更新 yt-dlp"
  echo "   2)  🔌  修改端口             (当前: ${PORT})"
  echo "   3)  🎵  Spotify 凭证"
  echo "   4)  ↺   重启服务"
  echo "   5)  📊  服务状态"
  echo "   6)  📋  日志"
  echo ""
  echo -e " ${B}── 维护 ──────────────────────────────────${N}"
  echo "   7)  🔨  重建前端"
  echo "   8)  📦  更新系统依赖"
  echo "   9)  🗑   卸载"
  echo ""
  echo -e " ${B}── Docker ────────────────────────────────${N}"
  echo "   10) 🐳  Docker 完整更新"
  echo ""
  echo "   0)  退出"
  echo ""
  read -r -p "  → 请选择 [0-10]: " CHOICE
  case "$CHOICE" in
    1) do_update    ;; 2) do_port      ;; 3) do_spotify ;;
    4) do_restart   ;; 5) do_status    ;; 6) do_logs    ;;
    7) do_rebuild   ;; 8) do_sysupdate ;; 9) do_uninstall ;;
    10) do_docker_update ;;
    0) exit 0       ;; *) show_menu    ;;
  esac
}

do_docker_update() {
  echo ""; info "Docker 完整更新..."
  info "① git pull..." && git -C "$INSTALL_DIR" pull 2>/dev/null || { err "git pull 失败"; read -r -p "" _; show_menu; return; }
  if command -v docker &>/dev/null; then
    info "② 重建 Docker..." && docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d --build 2>/dev/null \
      || docker-compose -f "$INSTALL_DIR/docker-compose.yml" up -d --build 2>/dev/null \
      || docker build -t oasisic-downloader "$INSTALL_DIR" 2>/dev/null
  else
    (cd "$INSTALL_DIR" && npm install --production 2>/dev/null)
    (cd "$INSTALL_DIR/client" && npm install 2>/dev/null && npm run build 2>/dev/null)
    pm2_restart
  fi
  "$YTDLP_BIN" -U 2>/dev/null; ok "更新完成"; read -r -p "" _; show_menu
}
do_update() {
  echo ""; info "更新 yt-dlp..."
  curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$YTDLP_BIN" 2>/dev/null \
    && chmod +x "$YTDLP_BIN" && ok "yt-dlp $("$YTDLP_BIN" --version) ✓" \
    || { sudo "$YTDLP_BIN" -U 2>/dev/null && ok "更新完成" || err "更新失败"; }
  read -r -p "" _; show_menu
}
kill_port() {
  local PORT="$1" PIDS=""
  local HEX; HEX=$(printf '%04X' "$PORT")
  local INODES; INODES=$(awk -v p=":$HEX" '$2~p||$3~p{print$10}' /proc/net/tcp /proc/net/tcp6 2>/dev/null | sort -u)
  for inode in $INODES; do PIDS="$PIDS $(grep -rl "socket:\[$inode\]" /proc/*/fd 2>/dev/null | head -1 | grep -oP '/proc/\K[0-9]+')"; done
  local SS_PIDS; SS_PIDS=$(ss -tnlp 2>/dev/null | awk -v port=":$PORT" '$4~port{print$NF}' | grep -oP 'pid=\K[0-9]+' | tr '\n' ' ')
  PIDS="$(echo "$PIDS $SS_PIDS" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  [ -z "$(echo $PIDS | tr -d ' ')" ] && return 0
  for PID in $PIDS; do kill -15 "$PID" 2>/dev/null || true; done; sleep 1
  for PID in $PIDS; do kill -9 "$PID" 2>/dev/null || true; done; sleep 1
}
do_port() {
  local CUR; CUR="$(get_port)"; echo ""
  echo -e "  当前: ${C}${CUR}${N}"; read -r -p "  → 新端口: " NP
  [[ "$NP" =~ ^[0-9]+$ ]] && [ "$NP" -ge 1 ] && [ "$NP" -le 65535 ] || { err "无效"; read -r -p "" _; show_menu; return; }
  pm2 stop "$PM2_PROC" --silent 2>/dev/null || true; pm2 delete "$PM2_PROC" --silent 2>/dev/null || true
  kill_port "$CUR"
  grep -qE '^PORT=' "$ENV_FILE" && sed -i "s/^PORT=.*/PORT=${NP}/" "$ENV_FILE" || echo "PORT=${NP}" >> "$ENV_FILE"
  pm2 start "$INSTALL_DIR/ecosystem.config.js" >/dev/null 2>&1; pm2 save >/dev/null 2>&1
  sleep 2; ss -tlnp 2>/dev/null | grep -q ":${NP}" && ok "端口: ${CUR}→${NP} ✓" || warn "端口已改，等待监听..."
  read -r -p "" _; show_menu
}
do_spotify() {
  echo ""; local CID; CID="$(grep -E '^SPOTIFY_CLIENT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)"
  [ -n "$CID" ] && echo -e "  当前 ID: ${C}${CID}${N}" || echo -e "  当前: ${Y}未配置${N}"
  read -r -p "  Client ID     (回车不修改): " SID; read -r -p "  Client Secret (回车不修改): " SSEC
  local CHG=0; [ -n "$SID" ] && { grep -qE '^SPOTIFY_CLIENT_ID=' "$ENV_FILE" && sed -i "s/^SPOTIFY_CLIENT_ID=.*/SPOTIFY_CLIENT_ID=${SID}/" "$ENV_FILE" || echo "SPOTIFY_CLIENT_ID=${SID}" >> "$ENV_FILE"; CHG=1; }
  [ -n "$SSEC" ] && { grep -qE '^SPOTIFY_CLIENT_SECRET=' "$ENV_FILE" && sed -i "s/^SPOTIFY_CLIENT_SECRET=.*/SPOTIFY_CLIENT_SECRET=${SSEC}/" "$ENV_FILE" || echo "SPOTIFY_CLIENT_SECRET=${SSEC}" >> "$ENV_FILE"; CHG=1; }
  [ "$CHG" -eq 1 ] && { pm2_restart; ok "已更新，服务重启"; } || info "无修改"; read -r -p "" _; show_menu
}
do_restart() { echo ""; pm2_restart; ok "已重启"; read -r -p "" _; show_menu; }
do_status() {
  local PORT; PORT="$(get_port)"; local IP; IP="$(hostname -I 2>/dev/null | awk '{print$1}' || echo localhost)"
  echo ""; echo -e " ${B}── PM2 ──────────────────────────────────${N}"; pm2 list 2>/dev/null
  echo ""; echo -e " ${B}── 信息 ──────────────────────────────────${N}"
  echo -e "  🌐  ${C}http://${IP}:${PORT}${N}"; echo -e "  🎵  yt-dlp $("$YTDLP_BIN" --version 2>/dev/null || echo '?')"
  read -r -p "" _; show_menu
}
do_logs() { echo ""; echo -e "  ${Y}Ctrl+C 退出${N}"; pm2 logs "$PM2_PROC" --lines 30 --nostream 2>/dev/null || true; pm2 logs "$PM2_PROC" 2>/dev/null || true; show_menu; }
do_rebuild() { echo ""; (cd "$INSTALL_DIR/client" && npm install --quiet 2>/dev/null && npm run build >/dev/null 2>&1) && { pm2_restart; ok "重建完成"; } || err "失败"; read -r -p "" _; show_menu; }
do_sysupdate() {
  echo ""; echo -e " ${B}📦 系统依赖检查${N}"
  curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$YTDLP_BIN" 2>/dev/null && chmod +x "$YTDLP_BIN" && ok "yt-dlp ✓" || warn "yt-dlp 更新失败"
  command -v ffmpeg &>/dev/null && ok "ffmpeg $(ffmpeg -version 2>/dev/null|head -1|grep -oP 'version \K[^ ]+')" || warn "ffmpeg 未安装"
  command -v aria2c &>/dev/null && ok "aria2c ✓" || warn "aria2c 未安装"
  [ "$(id -u)" -eq 0 ] && npm install -g pm2 --silent >/dev/null 2>&1 || sudo npm install -g pm2 --silent >/dev/null 2>&1; ok "PM2 $(pm2 --version)"
  read -r -p "" _; show_menu
}
do_uninstall() {
  echo ""; warn "这将卸载 Oasisic Downloader 并删除所有相关进程"
  read -r -p "  → 确认卸载？[y/N]: " _YN; [[ "${_YN,,}" != "y" ]] && { info "已取消"; read -r -p "" _; show_menu; return; }
  pm2 stop "$PM2_PROC" --silent 2>/dev/null || true; pm2 delete "$PM2_PROC" --silent 2>/dev/null || true; pm2 save --force >/dev/null 2>&1
  rm -f "/usr/local/bin/oasisic" 2>/dev/null
  echo -e "\n  ${Y}⚠️  项目目录 ${INSTALL_DIR} 未被删除${N}"
  echo -e "  ${D}   手动删除: rm -rf ${INSTALL_DIR}${N}"
  read -r -p "" _; exit 0
}
show_menu
__TPL__

# 替换占位符
sed -i "s|@@INSTALL_DIR@@|$SCRIPT_DIR|g; s|@@YTDLP_BIN@@|$YTDLP_BIN|g; s|@@ENV_FILE@@|$ENV_FILE|g; s|@@PM2_PROC@@|$PM2_PROC|g" "$OASISIC_TMP"
install -m 755 "$OASISIC_TMP" "$OASISIC_CMD" 2>/dev/null || sudo install -m 755 "$OASISIC_TMP" "$OASISIC_CMD" 2>/dev/null
rm -f "$OASISIC_TMP"
ok "oasisic 管理命令 → ${C}${OASISIC_CMD}${N}"

# ══════════════════════════════════════════════════════════════════════════
#  完成
# ══════════════════════════════════════════════════════════════════════════
DURATION=$(( $(date +%s) - START_TIME ))
IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')"
echo ""
echo -e "  ${B}${G}╔══════════════════════════════════════════════╗${N}"
echo -e "  ${B}${G}║${N}  ✅  安装完成！ (${DURATION}秒)              ${B}${G}║${N}"
echo -e "  ${B}${G}╚══════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${C}🌐  http://${IP}:${CHOSEN_PORT}${N}"
echo -e "  ${C}🛠  oasisic${N}   — 管理命令"
echo -e "  ${C}📋  pm2 logs ${PM2_PROC}${N} — 查看日志"
echo ""