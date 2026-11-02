-- HonorKing 云端存档 D1 表结构
-- 用法：npx wrangler d1 execute honorking-saves --remote --file=./schema.sql

CREATE TABLE IF NOT EXISTS saves (
  pid        TEXT PRIMARY KEY,          -- 客户端 CloudSync.player_id()（每台设备一个）
  ts         INTEGER NOT NULL DEFAULT 0,-- 客户端上传时间戳（秒）
  data       TEXT NOT NULL,             -- 完整 JSON：{pid,ts,rank,history}
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
