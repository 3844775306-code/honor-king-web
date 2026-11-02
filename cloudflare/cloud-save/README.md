# HonorKing 云端存档 · Cloudflare Workers

给朋友小圈子用的免费云存档后端，零运维、免费额度足够。协议与游戏内
`scripts/core/CloudSync.gd` 完全一致（**玩家段位 + 对战纪录**，不含录像）：

```
POST /upload              Authorization: Bearer <口令>
     {"pid","ts","rank","history"}     → 2xx
GET  /download?pid=<pid>  Authorization: Bearer <口令>
     → 与上传相同的 JSON
GET  /health
```

## 一、部署（5 分钟，只需一次）

```bash
cd cloudflare/cloud-save
npx wrangler login                                   # 浏览器授权 Cloudflare 账号（免费）
npx wrangler d1 create honorking-saves               # 输出里复制 database_id
#   把 database_id 填进 wrangler.toml 的 REPLACE_WITH_YOUR_D1_ID
npx wrangler d1 execute honorking-saves --remote --file=./schema.sql
npx wrangler secret put CLOUD_TOKEN                  # 输入朋友共用的口令，例如 honorking-friends
npx wrangler deploy
```

部署成功会得到一个地址，例如：

```
https://honorking-saves.<你的子域>.workers.dev
```

## 二、游戏内配置

主菜单 → **云端存档** 页：

| 字段 | 填什么 |
|---|---|
| 服务器地址 | `https://honorking-saves.<你的子域>.workers.dev` |
| 口令 | 上一步 `CLOUD_TOKEN` 里输入的那串 |
| 赛后自动上传 | 打开（可选） |

然后点「上传」「下载」即可。每台设备会生成自己的 `pid`（`CloudSync.player_id()`），
换设备/重装后 pid 会变，需要手动同步迁移时可以把老设备的 `pid` 抄到新设备的
`player_prefs.json` 的 `cloud.pid` 里（朋友规模手动处理即可）。

## 三、本地调试（不花一分钱先试）

```bash
cd cloudflare/cloud-save
CLOUD_TOKEN=dev-token node dev-server.mjs
# 游戏内地址填 http://127.0.0.1:8788，口令 dev-token
```

数据落在 `./.data/saves.json`（已在 .gitignore 中忽略）。

## 四、常用维护

```bash
# 备份全部云存档
npx wrangler d1 execute honorking-saves --remote --command "SELECT pid,data FROM saves" > saves-backup.json

# 看某个玩家
npx wrangler d1 execute honorking-saves --remote --command "SELECT pid,ts,updated_at FROM saves"
```

## 五、说明

- 免费额度：D1 5GB 存储 / 每天 500 万行读，朋友规模永远用不完
- 口令是**全朋友共用一个**的简单鉴权，别公开贴到网上；要更严可后续加设备级 token
- 只同步段位和对战纪录；10MB 级录像 `.rep` 没有上传（需要的话另加 R2/KV 方案）
- 数据在 Cloudflare D1（海外节点）；国内访问延迟约 100–300ms，存档 KB 级基本无感
