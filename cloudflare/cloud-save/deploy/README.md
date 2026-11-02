# 阿里云轻量应用服务器部署（云存档 · 通用 HTTP 后端）

适合：只给朋友玩、要国内低延迟、不想用需要梯子的海外平台。
代码沿用 `dev-server.mjs`（零依赖 Node 服务，协议与游戏内 `CloudSync` 对齐）。

## 1. 买机器

阿里云 → 轻量应用服务器（Lightweight Application Server）：

- 镜像：**Ubuntu 22.04 / 24.04**
- 规格：2 核 2G 足够（朋友规模 1 核 1G 也行）
- 地域：国内（离你和朋友近的）
- 新用户/活动价通常几十元一年

## 2. 放行端口

轻量控制台 → 服务器详情 → **防火墙** → 添加规则：

- 应用类型：自定义
- 协议：TCP
- 端口：**8788**（或你自定义的 PORT）

> 用 IP + 非 80/443 端口访问，**不需要域名备案**。

## 3. 本地把服务传上去

Windows PowerShell 里（路径按你实际位置改）：

```powershell
scp -r "C:\Users\18749\Documents\honor-king\cloudflare\cloud-save" root@你的服务器公网IP:/root/
```

## 4. 服务器上一键安装

SSH 登录：

```bash
ssh root@你的服务器公网IP
cd /root/cloud-save
CLOUD_TOKEN='换成长随机口令' bash deploy/install.sh
```

脚本会：装 Node 20（走 npmmirror 国内镜像）→ 拷贝到 `/opt/honorking-cloud-save` →
写 systemd 服务并启动 → 打印游戏内要填的地址和口令。

## 5. 游戏内配置

主菜单 → 云端存档：

| 字段 | 值 |
|---|---|
| 存储后端 | **通用 HTTP（阿里云自建）** |
| 服务器地址 | `http://你的服务器公网IP:8788` |
| 访问令牌（HTTP） | `CLOUD_TOKEN` 那个口令 |
| 赛后自动上传 | 可选开启 |

先在本机验证服务：

```powershell
curl http://你的服务器公网IP:8788/health
```

## 6. 运维

```bash
systemctl status honorking-save      # 状态
journalctl -u honorking-save -f      # 日志
systemctl restart honorking-save     # 重启

# 备份存档（建议加个 cron）
cp /opt/honorking-cloud-save/.data/saves.json /root/saves-$(date +%F).json
```

`crontab -e` 加一行每天备份：

```
30 4 * * * cp /opt/honorking-cloud-save/.data/saves.json /root/saves-$(date +\%F).json
```

## 7. 安全建议

- `CLOUD_TOKEN` 用长随机串（≥16 位），只发给朋友
- 防火墙只放行 **8788** 和 SSH（22），不要全开
- 数据是明文 JSON + HTTP：朋友局够用；若要 HTTPS，可买备案域名后加 Caddy 反代自动证书
- 换机恢复：`pid` 存在本地 `player_prefs.json` 的 `cloud.pid`，换机时把它抄到新设备即可

## 8. 常见问题

- **连不上**：先 `curl http://127.0.0.1:8788/health` 确认服务在跑，再查轻量控制台防火墙是否放行 8788
- **上传 401**：游戏内令牌和服务器 `CLOUD_TOKEN` 不一致
- **上传没反应/超时**：检查服务器安全组/防火墙；确认地址是 `http://IP:8788`（不要漏端口）
