# 云端存档 · 国内 BaaS 方案（不用梯子）

Cloudflare 控制台在国内要代理，这里改用**国内可直接访问**的 BaaS。游戏端已内置两种适配，
主菜单 →「云端存档」→ 点「存储后端」切换即可，协议/字段都不用改。

> 只同步「段位 + 对战纪录」JSON，不含录像；朋友小圈子用免费档足够。

---

## 方案 A：LeanCloud（推荐，建表免配置）

1. **注册**：<https://www.leancloud.cn> → 控制台 → 创建应用（开发版即可）。
2. **拿凭证**：应用 → 设置 → 应用凭证，记下：
   - `AppID`
   - `AppKey`
   - `服务器地址`（形如 `https://xxxx.lc-cn-n1-shared.com`，国内节点）
3. **建表**：数据存储 → 创建 Class，名字 **`CloudSave`**，添加 3 个字段：

   | 字段名 | 类型 |
   |---|---|
   | `pid` | String |
   | `ts` | Number |
   | `data` | Object |

   （`data` 里就是 `{pid,ts,rank,history}` 整包，不用拆字段。）
4. **权限**：Class 权限设为「**所有用户可读写**」（朋友私有应用；否则未登录客户端只能新建、不能更新自己的行）。
5. **游戏内填**：
   - 存储后端 → `LeanCloud（国内 BaaS）`
   - 服务器地址 → 上一步的服务器地址
   - AppID / AppKey → 对应凭证
   - 点「↑ 上传到云端」测试

> 免费开发版有请求/存储限额，朋友规模够用；数据量增长后可清理历史或升档。

---

## 方案 B：Bmob

1. **注册**：<https://www.bmob.cn> → 创建应用。
2. **拿凭证**：应用 → 设置 → 应用密钥，记下 `Application ID` 和 `REST API Key`。
3. **建表**：数据表 → 新建表 **`CloudSave`**，字段同方案 A：`pid`(String)、`ts`(Number)、`data`(Object)。
   - 权限设为「所有用户可读写」（或按控制台实际选项开放读写）。
4. **游戏内填**：
   - 存储后端 → `Bmob（国内 BaaS）`
   - 服务器地址 → **留空**（默认 `https://api.bmob.cn/1`；换自定义域名才填）
   - AppID → Application ID
   - AppKey → REST API Key

---

## 通用说明

- **换机恢复**：同一份存档靠 `pid` 找行。重装/换机后 `pid` 会变，需要把老设备
  `player_prefs.json` 里的 `cloud.pid` 抄到新设备（朋友规模手动即可）。
- **凭证安全**：AppID/AppKey 会存在客户端本地（`player_prefs.json`），只发朋友私有包没问题，
  不要公开分发带凭证的安装包。
- **想加录像/更大数据**：当前只同步段位+对战纪录（几十~几百 KB）；录像 10MB 级建议后续接对象存储。
- **电脑上联调**：可把「服务器地址」填 `http://127.0.0.1:8788` 配合仓库里
  `cloudflare/cloud-save/dev-server.mjs`（通用 HTTP 后端）先验证流程。
