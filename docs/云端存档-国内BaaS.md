# 云端存档 · 国内可用方案（不用梯子）

`CloudSync` 已内置三种后端，主菜单 →「云端存档」→ 点「存储后端」切换：

| 后端 | 状态 | 说明 |
|---|---|---|
| **Bmob**（推荐） | ✅ 可注册 | 国内 BaaS，官网 `bmob.cn` / `bmobapp.com`，控制台直接访问 |
| 通用 HTTP | ✅ 任意 | 自建/Serverless/轻量服务器，填 `POST {url}/upload` 兼容服务 |
| LeanCloud | ⚠️ 仅存量 | **2026-01-12 起停止新用户注册、停止创建应用**；2027-01-12 正式停服（[官方公告](https://docs.leancloud.cn/sdk/announcements/sunset-announcement)）。只有在 2026-01-12 前已注册的账号可用到停服前 |

> 只同步「段位 + 对战纪录」JSON，不含录像；朋友小圈子用免费档足够。

---

## 推荐：Bmob

1. **注册**：<https://www.bmob.cn>（或 <https://www.bmobapp.com>）→ 创建应用。
2. **拿凭证**：应用 → 设置 → 应用密钥，记下 `Application ID` 和 `REST API Key`。
3. **建表**：数据表 → 新建表 **`CloudSave`**，字段：

   | 字段名 | 类型 |
   |---|---|
   | `pid` | String |
   | `ts` | Number |
   | `data` | Object |

   （`data` 里是 `{pid,ts,rank,history}` 整包，不用拆字段；表权限设为「所有用户可读写」。）
4. **游戏内填**：
   - 存储后端 → `Bmob（国内 BaaS）`
   - 服务器地址 → **留空**（默认 `https://api.bmob.cn/1`；换自定义域名才填）
   - AppID → Application ID
   - AppKey → REST API Key
   - 点「↑ 上传到云端」测试

> Bmob 免费开发档有请求/存储额度限制，以官网当期政策为准；朋友规模不够用再升档或换自建。

---

## 备选 1：轻量服务器自建（最稳、几十元/年）

买阿里云/华为云/京东云 2C2G 活动机，把仓库里现成的 Node 服务跑起来即可：

```bash
cd cloudflare/cloud-save
CLOUD_TOKEN=你的口令 node dev-server.mjs
# 想长期跑：pm2 start dev-server.mjs 或 systemd
```

游戏内后端选「通用 HTTP」，服务器地址填 `http://公网IP:8788`，口令填 `CLOUD_TOKEN`。
IP+非 80 端口访问无需备案，无梯子，数据在境内。

## 备选 2：其他 BaaS / Serverless

- **腾讯云开发 CloudBase**：云函数 + 文档型数据库，有免费额度；需要写一个 HTTP 触发器适配
  （`/upload`、`/download` 两个路由），客户端仍选「通用 HTTP」。
- **阿里云 EMAS Serverless / 函数计算 + 表格存储**：同上，需要做一层 HTTP 适配。
- **Supabase / Cloudflare Workers**：功能可用，但控制台在国内可能需要代理，不建议作为首选。

---

## 通用说明

- **换机恢复**：同一份存档靠 `pid` 找行。重装/换机后 `pid` 会变，需要把老设备
  `player_prefs.json` 里的 `cloud.pid` 抄到新设备（朋友规模手动即可）。
- **凭证安全**：AppID/AppKey 会存在客户端本地（`player_prefs.json`），只发朋友私有包没问题，
  不要公开分发带凭证的安装包。
- **录像/大数据**：当前只同步段位+对战纪录（几十~几百 KB）；10MB 级录像建议后续接对象存储。
- **本地联调**：后端选「通用 HTTP」+ 仓库内 `cloudflare/cloud-save/dev-server.mjs` 即可离线跑通。
