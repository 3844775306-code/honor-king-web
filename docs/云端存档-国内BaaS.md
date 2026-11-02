# 云端存档 · 国内可用方案（推荐 Supabase 免费档）

`CloudSync` 已内置四种后端，主菜单 →「云端存档」→ 点「存储后端」切换：

| 后端 | 费用 | 说明 |
|---|---|---|
| **Supabase（免费档，推荐）** | 0 元 | 不用买服务器、控制台一般可直连；500MB 数据库朋友局够用。**连续 7 天无活动会自动暂停**，去面板点一下恢复即可 |
| 通用 HTTP（阿里云自建） | 轻量服务器几十元/年 | 最稳、数据自己掌控，IP+8788 免备案；见 `cloudflare/cloud-save/deploy/README.md` |
| Bmob | 有免费额度 | 国内 BaaS；注册/额度以官网为准 |
| LeanCloud | 仅存量 | 2026-01-12 起停止新注册，2027-01-12 停服 |

> 只同步「段位 + 对战纪录」JSON，不含录像。

---

## 推荐：Supabase 免费档（约 5 分钟）

### 1. 注册 / 建项目

<https://supabase.com> → 注册 → **New project**：

- 数据库密码随便设（用不到）
- **Region 选 Singapore / Tokyo**（离国内近，延迟低）

### 2. 建表 + 权限（SQL Editor 里整段执行）

```sql
create table if not exists public.cloud_saves (
  pid text primary key,
  ts bigint not null default 0,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.cloud_saves enable row level security;

-- 朋友私有局：anon key 可读写（客户端里本来就会带 anon key）
create policy cloud_saves_read   on public.cloud_saves for select using (true);
create policy cloud_saves_insert on public.cloud_saves for insert with check (true);
create policy cloud_saves_update on public.cloud_saves for update using (true) with check (true);
```

### 3. 拿地址和 key

Project Settings → **API**：

- `Project URL`（形如 `https://xxxx.supabase.co`）
- `anon public` key

### 4. 游戏内填

主菜单 → 云端存档：

| 字段 | 值 |
|---|---|
| 存储后端 | **Supabase（免费档）** |
| 服务器地址 | `https://xxxx.supabase.co` |
| AppKey | `anon public` key |
| 赛后自动上传 | 可选开启 |

点「↑ 上传到云端」，成功后再点「↓ 从云端恢复」验证。

### 5. 免费档注意事项

- **7 天没有任何访问会被自动暂停**：进 Supabase 面板点 Restore 即可恢复（数据不丢）
- 想避免暂停：每周自己打开一次游戏同步，或用免费定时服务（如 cron-job.org）每 3 天访问一次
  `https://xxxx.supabase.co/rest/v1/cloud_saves?select=pid&limit=1`（带 `apikey` 头）
- anon key 会随客户端本地保存：只发朋友私有包没问题；要更严需改 Edge Function + service key
- 换机恢复靠 `pid`：把老设备 `player_prefs.json` 里的 `cloud.pid` 抄到新设备

### 6. 国内访问

- `supabase.com` 控制台和 `*.supabase.co` API 国内一般能直连，偶尔慢；打不开可换手机热点/公共 DNS 再试
- 实在访问不稳定，就退回下面的「阿里云轻量自建」

---

## 备选：阿里云轻量自建

完整步骤见 [`cloudflare/cloud-save/deploy/README.md`](../cloudflare/cloud-save/deploy/README.md)：

1. 阿里云轻量（Ubuntu 22.04/24.04）→ 防火墙放行 **8788**
2. `scp -r cloud-save root@IP:/root/` → 服务器上 `CLOUD_TOKEN='长口令' bash deploy/install.sh`
3. 游戏内后端选「通用 HTTP」，地址 `http://公网IP:8788`，令牌填 `CLOUD_TOKEN`

---

## 本地联调

后端选「通用 HTTP」+ 仓库内 `cloudflare/cloud-save/dev-server.mjs`：

```bash
cd cloudflare/cloud-save
CLOUD_TOKEN=dev-token node dev-server.mjs
# 游戏内地址 http://127.0.0.1:8788，口令 dev-token
```
