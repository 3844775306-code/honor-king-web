# 云端存档 · 国内可用方案（推荐 Supabase 免费档）

`CloudSync` 已内置四种后端，主菜单 →「云端存档」→ 点「存储后端」切换：

| 后端 | 费用 | 说明 |
|---|---|---|
| **Supabase（免费档，推荐）** | 0 元 | 不用买服务器、控制台一般可直连；500MB 数据库朋友局够用。**连续 7 天无活动会自动暂停**，去面板点一下恢复即可 |
| 通用 HTTP（阿里云自建） | 轻量服务器几十元/年 | 最稳、数据自己掌控，IP+8788 免备案；见 `cloudflare/cloud-save/deploy/README.md` |
| Bmob | 有免费额度 | 国内 BaaS；注册/额度以官网为准 |
| LeanCloud | 仅存量 | 2026-01-12 起停止新注册，2027-01-12 停服 |

> 默认自动同步：账号（本地账号文件）、昵称、段位、灵宝、操作设置、出装方案等所有本地存档；录像不自动同步，点「上传最近录像」手动传。

---

## 推荐：Supabase 免费档（约 5 分钟）

### 1. 注册 / 建项目

<https://supabase.com> → 注册 → **New project**：

- 数据库密码随便设（用不到）
- **Region 选 Singapore / Tokyo**（离国内近，延迟低）

### 2. 建表 + 权限（SQL Editor 里整段执行；含录像桶）

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

-- 云端账号（换设备/重装后可按用户名+密码找回存档）
create table if not exists public.hk_accounts (
  username text primary key,
  salt text not null,
  hash text not null,
  pid text not null,
  updated_at bigint not null default 0
);
alter table public.hk_accounts enable row level security;
create policy hk_accounts_read   on public.hk_accounts for select using (true);
create policy hk_accounts_insert on public.hk_accounts for insert with check (true);
create policy hk_accounts_update on public.hk_accounts for update using (true) with check (true);

-- 云端录像元数据（所有玩家共享的录像列表）
create table if not exists public.hk_replay_meta (
  id text primary key,
  object text not null,
  pid text not null,
  name text not null,
  uploader text default '',
  hero text default '',
  nick text default '',
  mode text default '',
  duration double precision default 0,
  winner int default -1,
  player_team int default 0,
  partial int default 0,
  time text default '',
  size bigint default 0,
  created bigint default 0
);
alter table public.hk_replay_meta enable row level security;
create policy hk_replay_meta_read   on public.hk_replay_meta for select using (true);
create policy hk_replay_meta_insert on public.hk_replay_meta for insert with check (true);
create policy hk_replay_meta_update on public.hk_replay_meta for update using (true) with check (true);

-- 段位排行榜（自动上传段位/昵称）
create table if not exists public.hk_profiles (
  pid text primary key,
  nickname text default '',
  tier int default 0,
  sub int default 0,
  stars int default 0,
  points int default 0,
  wins int default 0,
  losses int default 0,
  updated bigint default 0
);
alter table public.hk_profiles enable row level security;
create policy hk_profiles_read   on public.hk_profiles for select using (true);
create policy hk_profiles_insert on public.hk_profiles for insert with check (true);
create policy hk_profiles_update on public.hk_profiles for update using (true) with check (true);

-- 录像手动上传用的存储桶（10MB 级 .rep）
insert into storage.buckets (id, name, public)
values ('hk_replays', 'hk_replays', false)
on conflict (id) do nothing;

create policy hk_replays_insert on storage.objects for insert with check (bucket_id = 'hk_replays');
create policy hk_replays_read   on storage.objects for select using (bucket_id = 'hk_replays');
```

### 3. 拿地址和 key

Project Settings → **API**：

- `Project URL`（形如 `https://xxxx.supabase.co`）
- `anon public` key

### 4. 游戏内

地址和 anon key 已经**内置在客户端**，玩家不用填：

- 启动游戏会自动拉取云端最新存档（云端比本地新时覆盖）
- 账号/昵称/段位/灵宝/设置/出装等存档一有变化，2 秒内自动上传
- 云端存档页可手动「立即同步」「从云端恢复」「上传最近录像」
- 换机/重装：用原用户名+密码登录，会自动从云端找回账号与全部存档\n- 自动同步防抖：存档变化后 2 秒内自动上传，按玩家 ID 分档、新设备按用户名找回

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





