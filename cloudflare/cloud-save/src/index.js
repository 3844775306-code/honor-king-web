// HonorKing 云端存档 · Cloudflare Worker
// 协议与客户端 scripts/core/CloudSync.gd 完全对齐：
//   POST /upload              Authorization: Bearer <CLOUD_TOKEN>
//        body {"pid","ts","rank","history"}  -> 2xx 成功
//   GET  /download?pid=<pid>  Authorization: Bearer <CLOUD_TOKEN>
//        -> 与上传相同的 JSON（{pid,ts,rank,history}）
//   GET  /health              健康检查
//
// 绑定：D1 数据库（变量名 DB），口令用 secret：CLOUD_TOKEN

const MAX_BYTES = 2 * 1024 * 1024; // 段位+对战纪录不会太大；2MB 防滥用

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = corsHeaders(env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    try {
      if (url.pathname === "/health") {
        return json({ ok: true, ts: nowSec() }, 200, cors);
      }

      if (url.pathname === "/upload") {
        if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, cors);
        if (!authorized(request, env)) return json({ error: "unauthorized" }, 401, cors);

        const text = await request.text();
        if (text.length > MAX_BYTES) return json({ error: "payload_too_large" }, 413, cors);

        let body;
        try {
          body = JSON.parse(text);
        } catch {
          return json({ error: "bad_json" }, 400, cors);
        }
        if (!body || typeof body !== "object") return json({ error: "bad_body" }, 400, cors);

        const pid = String(body.pid || "").trim();
        if (!pid || pid.length > 128) return json({ error: "bad_pid" }, 400, cors);

        const ts = Number(body.ts) || nowSec();
        const data = JSON.stringify({
          pid,
          ts,
          rank: body.rank ?? {},
          history: Array.isArray(body.history) ? body.history : [],
        });

        await env.DB.prepare(
          `INSERT INTO saves (pid, ts, data, updated_at)
           VALUES (?1, ?2, ?3, datetime('now'))
           ON CONFLICT(pid) DO UPDATE SET
             ts = excluded.ts,
             data = excluded.data,
             updated_at = datetime('now')`
        )
          .bind(pid, ts, data)
          .run();

        return json({ ok: true, ts }, 200, cors);
      }

      if (url.pathname === "/download") {
        if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405, cors);
        if (!authorized(request, env)) return json({ error: "unauthorized" }, 401, cors);

        const pid = String(url.searchParams.get("pid") || "").trim();
        if (!pid) return json({ error: "bad_pid" }, 400, cors);

        const row = await env.DB.prepare("SELECT data FROM saves WHERE pid = ?1").bind(pid).first();
        if (!row) return json({ error: "not_found" }, 404, cors);

        return new Response(row.data, {
          status: 200,
          headers: { ...cors, "content-type": "application/json; charset=utf-8" },
        });
      }

      return json({ error: "not_found" }, 404, cors);
    } catch (e) {
      return json({ error: String((e && e.message) || e) }, 500, cors);
    }
  },
};

function nowSec() {
  return Math.floor(Date.now() / 1000);
}

function corsHeaders(env) {
  const origin = (env && env.ALLOWED_ORIGIN) || "*";
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "Authorization, Content-Type",
    "access-control-max-age": "86400",
  };
}

function authorized(request, env) {
  const expected = String((env && env.CLOUD_TOKEN) || "").trim();
  if (!expected) return false; // 没配口令一律拒绝，避免裸奔
  const h = request.headers.get("authorization") || "";
  const token = h.toLowerCase().startsWith("bearer ") ? h.slice(7).trim() : h.trim();
  return token.length > 0 && constantTimeEqual(token, expected);
}

// 简单定长比较，避免明显的时序侧信道（朋友局够用）
function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(obj, status, headers) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...headers, "content-type": "application/json; charset=utf-8" },
  });
}
