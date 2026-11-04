# 网页版（Web/HTML5）导出与部署

## 1. 导出

```powershell
# 一键导出（自动临时切渲染后端 → 导出 → 还原 project.godot）
pwsh -NoProfile -File scripts\dev\export_web.ps1
```

脚本做的事：
1. 把 `rendering/renderer/rendering_method` 临时改成 `gl_compatibility`（Web 只有 GL/WebGL2 后端），导出结束自动改回 `mobile`；
2. 调 `godot --headless --export-release Web build/web/index.html`（Godot 4.7.2 + 官方 web 模板）；
3. 自检 `index.pck` 里的渲染后端确实是 `gl_compatibility`。

产物在 `build/web/`：`index.html` + `index.js` + `index.wasm`(≈39.5 MB) + `index.pck`(≈8.4 MB) + 图标。
首次加载约 48 MB，之后走浏览器缓存。

## 2. 本地预览

```powershell
pwsh -NoProfile -File scripts\dev\serve_web.ps1 -Port 8080
# 浏览器打开 http://127.0.0.1:8080/
```

注意：必须用 `http://`（或 https）打开，直接双击 `file://` 跑不了 WebGL/WASM。

## 3. 部署

任意静态文件服务器，指向 `build/web/` 即可（Nginx / Apache / GitHub Pages / Netlify / Cloudflare Pages）。

- 当前 Web 导出用的是**单线程模板**（`variant/thread_support=false`），**不需要** `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` 头，普通静态托管即可。
- 若以后改成多线程模板，则站点必须返回：
  `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: require-corp`。
- 建议开启 gzip/brotli（`.wasm`、`.pck` 压缩后约 1/3），并给 `.wasm` 配 `application/wasm`。

## 4. 已做的网页适配

| 项 | 处理 |
|---|---|
| 渲染后端 | Web 导出用 `gl_compatibility`(WebGL2)：由 `export_web.ps1` 在导出期间临时改写、导出后还原，桌面端继续用 `mobile` |
| 导出过滤 | Web 预设 `exclude_filter` 排除 `screenshots/ android/ build/ export/ artifacts/ docs/` 等，pck 从 100+MB 降到 8.4MB |
| 纹理压缩 | 关闭 `vram_texture_compression/for_desktop|for_mobile`（WebGL2 普遍不支持 S3TC） |
| 画布 | `canvas_resize_policy=2`（跟随浏览器窗口自适应缩放） |
| 触屏 HUD | `Config.on_mobile()`：原生移动端 **或** 移动浏览器（`web_android`/`web_ios`）都走触屏 HUD |
| 联机 | 浏览器只能当**客户端**：`NetSession` 在 web 下改用 `WebSocketMultiplayerPeer` 连 `ws://<host>:<port>`；页面可用 `?host=ip:port` 覆盖地址。网页版大厅的「创建房间」置灰（浏览器无法监听端口） |
| 存档 | `user://`（IndexedDB）可用；`res://` 只读，相关回退分支在 web 下会失败但不影响运行 |

## 5. 已知限制

- 网页版不能当联机主机（需要桌面端开房）。
- 移动浏览器性能有限，建议关闭/降低特效档位（项目内 `Vfx.quality`）。
- 首次进入是静音状态，点一下画布后音频才启动（浏览器自动播放策略）。
