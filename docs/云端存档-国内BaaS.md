# 云端存档 · 国内可用方案（推荐阿里云轻量）

`CloudSync` 已内置三种后端，主菜单 →「云端存档」→ 点「存储后端」切换：

| 后端 | 状态 | 说明 |
|---|---|---|
| **通用 HTTP（阿里云自建，推荐）** | ✅ | 轻量服务器几十元/年，IP+8788 端口免备案、不用梯子，数据完全自己掌控 |
| Bmob | ✅ 可注册 | 国内 BaaS，有免费额度但有限制，注册即用、不用买服务器 |
| LeanCloud | ⚠️ 仅存量 | **2026-01-12 起停止新注册**；2027-01-12 正式停服（[公告](https://docs.leancloud.cn/sdk/announcements/sunset-announcement)）。存量账号可用到停服前 |

> 只同步「段位 + 对战纪录」JSON，不含录像；朋友小圈子足够。

---

## 方案 A：阿里云轻量应用服务器（推荐）

完整步骤见 [`cloudflare/cloud-save/deploy/README.md`](../cloudflare/cloud-save/deploy/README.md)，摘要：

1. 阿里云买轻量应用服务器：**Ubuntu 22.04/24.04**，2C2G（活动价几十元/年）
2. 轻量控制台 → 防火墙 → 放行 **TCP 8788**
3. 本地 PowerShell 上传：

   ```powershell
   scp -r "C:\Users\18749\Documents\honor-king\cloudflare\cloud-save" root@服务器公网IP:/root/
   ```
4. 服务器 SSH 一键安装：

   ```bash
   ssh root@服务器公网IP
   cd /root/cloud-save
   CLOUD_TOKEN='换成长随机口令' bash deploy/install.sh
   ```
5. 游戏内：后端选 **通用 HTTP（阿里云自建，推荐）**，地址 `http://公网IP:8788`，令牌填 `CLOUD_TOKEN`

脚本会自动装 Node、写 systemd、开机自启，并打印游戏内要填的地址；数据在
`/opt/honorking-cloud-save/.data/saves.json`，配一条 cron 每天备份即可。

> IP + 8788 这种非 80/443 端口访问**不需要域名备案**；想上 HTTPS 再买备案域名加 Caddy。

---

## 方案 B：Bmob（不想买服务器时）

1. 注册 <https://www.bmob.cn> → 创建应用
2. 应用 → 设置 → 应用密钥，记下 `Application ID` / `REST API Key`
3. 数据表 → 新建表 **`CloudSave`**：`pid`(String)、`ts`(Number)、`data`(Object)，权限「所有用户可读写」
4. 游戏内：后端选 `Bmob（国内 BaaS）`，服务器地址**留空**，AppID/AppKey 填上面两个 key

> Bmob 免费档有请求/存储额度限制，以官网当期政策为准。

---

## 方案 C：其他云（需自己写一层适配）

- 腾讯云开发 CloudBase、阿里云 EMAS Serverless / 函数计算 + 表格存储：实现
  `POST /upload`、`GET /download?pid=` 两个 HTTP 路由即可，游戏内仍选「通用 HTTP」
- Cloudflare Workers：本仓库 `cloudflare/cloud-save` 已带模板，但控制台在国内需代理

---

## 通用说明

- **换机恢复**：靠 `pid` 找行；重装/换机后 `pid` 会变，把老设备 `player_prefs.json` 的
  `cloud.pid` 抄到新设备即可（朋友规模手动）
- **凭证安全**：口令/AppKey 存在客户端本地，只发朋友私有包
- **录像**：10MB 级 `.rep` 目前不同步，需要的话再叠加对象存储
- **本地联调**：后端选「通用 HTTP」+ 仓库内 `dev-server.mjs`（默认 127.0.0.1:8788）即可离线跑通

