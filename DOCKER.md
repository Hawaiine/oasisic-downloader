# 🐳 Oasisic Downloader — Docker 部署指南

## 镜像

| 镜像 | 大小 | 说明 |
|------|------|------|
| `barryallen26/oasisic-downloader:latest` | ~320 MB | 最新稳定版 |
| `barryallen26/oasisic-downloader:YYYYMMDD` | ~320 MB | 按日期标记的版本 |
| `barryallen26/oasisic-downloader:sha-xxxxxx` | ~320 MB | 按 commit 标记 |

镜像包含：Node.js 22 + ffmpeg + aria2 + yt-dlp + mutagen，解压即用。

---

## 两种部署方式

### 方式 A：从 Docker Hub 拉取（推荐）

```bash
# 首次部署
mkdir oasisic && cd oasisic
wget https://raw.githubusercontent.com/Hawaiine/oasisic-downloader/main/docker-compose.pull.yml
docker compose -f docker-compose.pull.yml up -d

# 日常更新
docker compose -f docker-compose.pull.yml pull
docker compose -f docker-compose.pull.yml up -d
```

### 方式 B：本地构建

```bash
git clone https://github.com/Hawaiine/oasisic-downloader.git
cd oasisic-downloader
docker compose up -d --build
```

---

## 配置

### 端口

服务默认运行在 `3000` 端口。修改 `docker-compose.yml`：

```yaml
ports:
  - "8888:3000"    # 宿主机 8888 → 容器 3000
```

### Spotify（可选）

```yaml
environment:
  - SPOTIFY_CLIENT_ID=your_client_id
  - SPOTIFY_CLIENT_SECRET=your_client_secret
```

获取：https://developer.spotify.com/dashboard → Create App

### Apple Music（可选）

```yaml
environment:
  - APPLE_MUSIC_TOKEN=your_token
```

需要付费 Apple Developer 账号 ($99/年)，获取：developer.apple.com → MusicKit Key

### 浏览器 Cookie（防机器人检测）

YouTube 可能要求验证身份。解决方案：

1. 浏览器安装 [Get cookies.txt](https://chrome.google.com/webstore/detail/get-cookiestxt) 扩展
2. 登录 youtube.com，导出 cookies
3. 挂载到容器：

```yaml
volumes:
  - ./cookies.txt:/app/server/cookies.txt:ro
```

### 代理

```yaml
environment:
  - HTTP_PROXY=http://proxy:port
  - HTTPS_PROXY=http://proxy:port
```

---

## 持久化数据

| 路径 | 说明 | 建议 |
|------|------|------|
| `./downloads` | 已下载的文件 | 按需保留 |
| `./tmp` | 临时工作目录 | 可清除 |
| `./logs` | 运行日志 | 排查问题时保留 |

---

## 健康检查

```bash
curl http://localhost:3000/api/health
# → {"status":"ok","port":3000,"uptime":123}
```

---

## 资源限制

默认限制内存 512M / 保留 128M。可调整：

```yaml
deploy:
  resources:
    limits:
      memory: 1G
    reservations:
      memory: 256M
```

---

## 从零开始的一键部署

```bash
# 1. 安装 Docker
curl -fsSL https://get.docker.com | sh

# 2. 启动
mkdir ~/oasisic && cd ~/oasisic
wget https://raw.githubusercontent.com/Hawaiine/oasisic-downloader/main/docker-compose.pull.yml
docker compose -f docker-compose.pull.yml up -d

# 3. 查看
docker compose -f docker-compose.pull.yml logs -f
```

---

## 常见问题

**Q: 下载很慢？**
A: 默认 aria2c 16 并发。可添加代理环境变量。

**Q: 提示 "Sign in to confirm"？**
A: 需要 cookies.txt，见上方说明。

**Q: 如何更新？**
A: `docker compose -f docker-compose.pull.yml pull && docker compose -f docker-compose.pull.yml up -d`

**Q: 镜像太大？**
A: ~320MB 已是最小化（含 ffmpeg + yt-dlp + aria2 + Node.js）。apt 安装同样内容需要更大空间。