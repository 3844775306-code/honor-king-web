#!/usr/bin/env node
// 本地调试用：模拟 Cloudflare Worker 的 /upload /download /health（无依赖，单文件）
// 用法：
//   CLOUD_TOKEN=dev-token node dev-server.mjs          # 监听 8788
//   游戏内 云端存档 页填：地址 http://127.0.0.1:8788  口令 dev-token
// 数据落盘：./.data/saves.json（记得别提交）

import http from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const PORT = Number(process.env.PORT || 8788);
const TOKEN = String(process.env.CLOUD_TOKEN || "dev-token");
const DATA_DIR = path.resolve(process.cwd(), ".data");
const DATA_FILE = path.join(DATA_DIR, "saves.json");
const MAX_BYTES = 2 * 1024 * 1024;

let store = {};
try {
  store = JSON.parse(await readFile(DATA_FILE, "utf8")) || {};
} catch {
  store = {};
}
async function persist() {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(DATA_FILE, JSON.stringify(store, null, 2), "utf8");
}

function cors(res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
  res.setHeader("access-control-allow-headers", "Authorization, Content-Type");
}

function send(res, status, obj) {
  const body = typeof obj === "string" ? obj : JSON.stringify(obj);
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(body);
}

function readable(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BYTES) {
        reject(new Error("too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function authorized(req) {
  const h = String(req.headers.authorization || "");
  const token = h.toLowerCase().startsWith("bearer ") ? h.slice(7).trim() : h.trim();
  return token === TOKEN;
}

const server = http.createServer(async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  try {
    if (url.pathname === "/health") return send(res, 200, { ok: true, ts: Math.floor(Date.now() / 1000) });
    if (url.pathname === "/upload") {
      if (req.method !== "POST") return send(res, 405, { error: "method_not_allowed" });
      if (!authorized(req)) return send(res, 401, { error: "unauthorized" });
      let body;
      try {
        body = JSON.parse(await readable(req));
      } catch {
        return send(res, 400, { error: "bad_json" });
      }
      const pid = String(body?.pid || "").trim();
      if (!pid || pid.length > 128) return send(res, 400, { error: "bad_pid" });
      const ts = Number(body.ts) || Math.floor(Date.now() / 1000);
      store[pid] = JSON.stringify({
        pid,
        ts,
        rank: body.rank ?? {},
        history: Array.isArray(body.history) ? body.history : [],
      });
      await persist();
      return send(res, 200, { ok: true, ts });
    }
    if (url.pathname === "/download") {
      if (req.method !== "GET") return send(res, 405, { error: "method_not_allowed" });
      if (!authorized(req)) return send(res, 401, { error: "unauthorized" });
      const pid = String(url.searchParams.get("pid") || "").trim();
      if (!pid) return send(res, 400, { error: "bad_pid" });
      if (!store[pid]) return send(res, 404, { error: "not_found" });
      return send(res, 200, store[pid]);
    }
    return send(res, 404, { error: "not_found" });
  } catch (e) {
    return send(res, 500, { error: String(e?.message || e) });
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[cloud-save] http://127.0.0.1:${PORT}  token=${TOKEN}`);
});
