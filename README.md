<div align="center">

# 🎬 Emby + Cloudflare Tunnel

**无公网 IP / CGNAT 环境下的家庭影音服务器公网访问方案**

![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![Emby](https://img.shields.io/badge/Emby%20Server-4.10.x-52b043)
![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-f6821f)
![pm2](https://img.shields.io/badge/process%20guard-pm2-2b037a)
![License](https://img.shields.io/badge/license-MIT-green)
![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen)

**免公网 IP · 免 IPv6 · 免端口映射 · 免费 HTTPS · 大内网(CGNAT)直接用**

[快速开始](#快速开始一键脚本) · [手动部署](#手动部署步骤) · [踩坑记录](#踩坑记录重要) · [安全建议](#安全建议)

</div>

---

## 架构

```
                    ┌─────────────────────────────┐
   用户设备          │      Cloudflare 边缘网络      │
 手机/PC/电视  ───▶ │  https://your-domain.com     │
                    │  (免费HTTPS + 免DDoS防护)     │
                    └──────────────┬──────────────┘
                                   │ Tunnel 加密隧道（出站连接，无需开放入站端口）
                    ┌──────────────▼──────────────┐
                    │     家庭服务器 (Windows)      │
                    │                             │
                    │  cloudflared (pm2 守护)      │
                    │    └──▶ http://127.0.0.1:8096│
                    │           └──▶ Emby Server   │
                    │                (pm2 守护)     │
                    └─────────────────────────────┘
```

**工作原理**：cloudflared 从家里主动向 Cloudflare 边缘建立 4 条出站 QUIC 连接，用户访问域名时，Cloudflare 通过这些隧道把请求转发回 Emby。因为连接是出站的，CGNAT 完全不影响。

## 项目文件

| 文件 | 说明 |
|---|---|
| `README.md` | 本文档 |
| `install.ps1` | Windows 一键部署脚本 |
| `config.yml.template` | cloudflared 隧道配置模板 |
| `ecosystem.config.js` | pm2 进程守护配置 |

## 前置要求

- Windows 10/11（Linux/macOS 同理，路径自行替换）
- 一个已托管到 Cloudflare 的域名（免费计划即可）
- Cloudflare 账号
- Node.js + pm2（用于进程守护和开机自启；没有的话先 `npm i -g pm2`）

## 快速开始（一键脚本）

```powershell
# 以管理员身份运行 PowerShell
cd emby-cloudflared-deploy
.\install.ps1 -Domain "media.example.com" -EmbyDir "D:\EmbyServer"
```

脚本会自动完成：下载 Emby/7zr/cloudflared → 解压安装 → 创建隧道 → 绑定 DNS → 注册 pm2 → 启动。

> 首次运行会弹出浏览器要求登录 Cloudflare 并选择域名授权，这是唯一需要人工操作的步骤。

## 手动部署步骤

### 1. 安装 Emby Server（Windows portable）

```powershell
# 下载最新版（示例 4.10.2.0，去 https://github.com/MediaBrowser/Emby.Releases/releases 取最新tag）
curl -L -o emby.7z "https://github.com/MediaBrowser/Emby.Releases/releases/download/4.10.2.0/embyserver-win-x64-4.10.2.0.7z"

# 下载 7z 独立解压器并解压（系统自带 tar 不支持 LZMA）
curl -L -o 7zr.exe "https://www.7-zip.org/a/7zr.exe"
.\7zr.exe x emby.7z -oD:\EmbyServer
```

- 程序目录：`D:\EmbyServer`
- 数据目录（数据库/日志/配置）：`C:\programdata`（备份重装系统时记得带上它）

### 2. 安装 cloudflared 并登录授权

```powershell
curl -L -o C:\ProgramData\cloudflared\cloudflared.exe "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
C:\ProgramData\cloudflared\cloudflared.exe tunnel login
```

浏览器会打开授权页 → **先完整登录 Cloudflare 账号 → 再选择域名 → 点 Authorize**。

> ⚠️ 授权页要求浏览器已登录 Cloudflare。如果出现反复要求登录的循环，先在单独标签页完成 dash.cloudflare.com 登录再回来授权。
> ⚠️ 授权链接和发起 `tunnel login` 的进程一一绑定，**必须用当前存活进程输出的链接**，旧链接点了也不会生效（页面显示成功但证书不会写入）。

### 3. 创建隧道并绑定域名

```powershell
cd C:\ProgramData\cloudflared
.\cloudflared.exe tunnel create emby
# 输出 Tunnel credentials written to C:\Users\<你>\.cloudflared\<TUNNEL-ID>.json

.\cloudflared.exe tunnel route dns emby media.example.com
```

### 4. 写隧道配置

创建 `C:\ProgramData\cloudflared\config.yml`（参考 `config.yml.template`）：

```yaml
tunnel: <TUNNEL-ID>
credentials-file: C:\Users\<你>\.cloudflared\<TUNNEL-ID>.json

ingress:
  - hostname: media.example.com
    service: http://127.0.0.1:8096
  - service: http_status:404
```

### 5. 用 pm2 守护进程（开机自启）

```powershell
pm2 start D:\EmbyServer\EmbyServer.exe --name emby-server --cwd D:\EmbyServer
pm2 start C:\ProgramData\cloudflared\cloudflared.exe --name emby-tunnel -- --config C:\ProgramData\cloudflared\config.yml --protocol http2 tunnel run emby
pm2 save
```

或直接使用 `ecosystem.config.js`：

```powershell
pm2 start ecosystem.config.js
pm2 save
```

> 为什么用 pm2 而不是 Windows 服务？cloudflared 服务以 LocalSystem 运行时读不到用户目录下的凭据文件，容易踩 502 坑；pm2 方式与你现有运维体系统一，日志也好查（`pm2 logs`）。

### 6. 验证

```powershell
curl -I https://media.example.com/web/
# 期望：HTTP/1.1 200 OK（或 302 跳转），SSL 验证通过
```

浏览器打开 `https://media.example.com`，进入 Emby 初始化向导：设置管理员账号 → 添加媒体库（指向本地视频文件夹）→ 完成。

## 日常使用

| 操作 | 命令/路径 |
|---|---|
| 查看运行状态 | `pm2 ls` |
| 重启 Emby | `pm2 restart emby-server` |
| 重启隧道 | `pm2 restart emby-tunnel` |
| 查日志 | `pm2 logs emby-tunnel --lines 100` |
| Emby 后台 | `https://media.example.com/web/` → 右上角扳手 |

- 登录主页自动展示所有用户卡片，点头像 + 密码/PIN 进入，各用户进度独立
- 手机装 Emby 官方 App，服务器地址填 `https://media.example.com`，体验远好于浏览器
- 添加媒体：把文件放进媒体库文件夹即可，实时监控自动入库；命名规范（`名字 (年份).mp4`、剧集 `S01E01`）刮削更准

## 踩坑记录（重要）

1. **pm2 里千万别把 `cloudflared tunnel login` 注册成应用**。login 进程退出后 pm2 会无限重启它（实测重启 268 次），每次都拉起浏览器授权页。login 只能手动跑一次，授权成功即退出。
2. **授权回调链接必须来自存活进程**。每个 `tunnel login` 进程生成专属回调链接；进程被杀后再点旧链接，页面显示成功但证书永远不会写入。授权不生效时先确认发起进程还活着。
3. **cloudflared Windows 服务（LocalSystem）读不到用户目录配置**。`cloudflared service install` 以 SYSTEM 身份运行，默认配置路径是 `C:\Windows\System32\config\systemprofile\.cloudflared\`，导致隧道 502。要么把 config+credentials 复制到该路径，要么改用 pm2 方案（推荐）。
4. **Windows 自带 tar 不支持 7z 的 LZMA 压缩**，解压 Emby portable 包要用 7zr.exe。
5. **公网 502 排查顺序**：`pm2 ls` 看进程 → `curl http://127.0.0.1:8096/web/` 验证本机 Emby → `cloudflared tunnel info emby` 看隧道连接数 → 检查 config.yml 的 hostname/service。
6. **错误 DNS 记录清理**：`tunnel route dns` 在证书 zone 不匹配时会把子域名拼到旧域名下（如 `emby.a.com.b.com`），需到 Cloudflare 后台 DNS 页手动删除。
7. **CGNAT 下隧道抖动/超时**：默认 QUIC 协议走 UDP，家宽 CGNAT 环境容易被限流导致连接不稳。启动参数加 `--protocol http2`（TCP）可显著提升稳定性——这是实测踩坑后从 typecho 隧道稳定运行中总结出的。
8. **重启后隧道 530**：如果 pm2 resurrect 后隧道应用没起来，Cloudflare 会返回 530（源站不可达）。检查 `pm2 ls` 是否包含 emby-server/emby-tunnel，缺失就重新 `pm2 start` 并 `pm2 save`（dump 里必须包含这两个应用才会随开机自启恢复）。

## 安全建议

- 管理员账号用强密码；家人账号用 4 位 PIN 即可
- 不要把 Emby 后台端口 8096 直接暴露公网（本方案全程走隧道，无需开放任何入站端口）
- 可选：在 Cloudflare Zero Trust 里给域名加 Access 策略（邮箱验证码二次保护）
- 定期备份 `C:\programdata`（数据库+配置全在里面）

## License

MIT
