# Wall 后端方案：Cloudflare Worker + D1

状态：规划中。前端已合入 master（commit `82ce1bb`），`/wall` 路由可用但导航/footer 入口已 CSS 隐藏；数据层 `website/app/services/wall.ts` 跑本地种子。本方案把它切到真实后端。

**进度（2026-06-06，分支 `feat/wall-backend`）**：后端 `website/server/` 脚手架已建并 `tsc` 通过；本地 `wrangler dev` + curl 全绿（健康、GET/POST/OPTIONS、归属 `mine` 不泄 owner、限流 429、Turnstile siteverify、CORS 预检）。前端数据层/交互改造与 13 语言 i18n 进行中。决策 D1–D5 已拍板（见第 13 节）。

读者：执行本方案的下一个会话与后续维护者。

## 1. 目标

留言持久化、跨用户可见、"只拖自己的便签"在刷新后仍生效。后端用 Cloudflare Worker + D1，静态站点（GitHub Pages，`output: export`）运行时 `fetch` 调用。本方案覆盖：数据模型、API 契约、归属机制、反滥用、前端切换、i18n、部署。

## 2. 架构

```
flowchart LR
  Browser --> Site[GitHub Pages static site]
  Site --> Worker[Cloudflare Worker]
  Worker --> D1[(D1 SQLite)]
  Worker --> TS[Turnstile siteverify]
```

静态站不动；运行时向 Worker 拉取与提交。Worker 负责路由、Turnstile 校验、限流、内容过滤、读写 D1。

## 3. 数据模型（D1 / SQLite）

只记录 文本 / 颜色 / 位置（中心点百分比，适配任意屏）。不记录旋转角度（客户端按 id 派生，见第 7 节）。

```sql
-- migrations/0001_init.sql
CREATE TABLE IF NOT EXISTS notes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  body        TEXT    NOT NULL,
  color       TEXT    NOT NULL,            -- 调色板键: amber|rose|sky|mint|lilac|blush
  x           REAL    NOT NULL,            -- 中心点归一化 0..1
  y           REAL    NOT NULL,            -- 中心点归一化 0..1
  name        TEXT,                        -- 可选署名 (见决策 D1)
  owner       TEXT    NOT NULL,            -- 客户端不透明 token, 用于归属
  created_at  INTEGER NOT NULL,            -- epoch ms
  hidden      INTEGER NOT NULL DEFAULT 0,  -- 审核软删
  ip_hash     TEXT                         -- 限流/审核, 不可逆 hash
);
CREATE INDEX IF NOT EXISTS idx_notes_visible   ON notes (hidden, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_ratelimit ON notes (ip_hash, created_at);
```

`id` 用自增整数即可；前端按字符串处理（`String(id)`）。

## 4. 归属机制（owner token）

目标："只拖自己的"跨刷新生效，且不泄露他人身份。

- 客户端首次进入 `/wall` 生成 `crypto.randomUUID()`，存 `localStorage["wall_owner"]`。
- `POST` 带 `owner` 字段，写入 `notes.owner`。
- `GET` 带请求头 `x-wall-owner: <token>`；服务端逐条计算 `mine = (note.owner === token)` 返回布尔，**绝不返回他人的 owner 原值**（否则可被冒充）。
- `PATCH`（重定位）只有 `owner === notes.owner` 才放行。

## 5. API 契约

统一返回 JSON，带 CORS（`Access-Control-Allow-Origin: <站点域名>`，允许 `content-type, x-wall-owner`，方法 `GET, POST, PATCH, OPTIONS`）。

### GET /wall/messages
- 请求头：`x-wall-owner`（可选）。
- 行为：取 `hidden = 0`，按 `created_at` 倒序，上限一次 800 条（后续可加 `?before=<id>` 分页）。
- 200：
  ```json
  { "notes": [ { "id": "12", "body": "…", "color": "sky",
      "x": 0.42, "y": 0.31, "name": "Lin", "createdAt": 1717000000000, "mine": true } ] }
  ```

### POST /wall/messages
- 请求体：`{ body, color, x, y, name?, owner, turnstileToken }`。
- 校验：`body` 1..180；`color` ∈ 调色板；`x,y` ∈ [0,1]；`name` ≤ 24；`owner` 非空；`turnstileToken` 非空。
- Turnstile：向 `https://challenges.cloudflare.com/turnstile/v0/siteverify` POST `secret + token + remoteip`，失败 → 403。
- 限流：按 `ip_hash` 查最近计数（如 1/分钟、20/小时），超限 → 429。
- 过滤：服务端复核长度；可选敏感词/链接过滤，命中 → 拒绝或 `hidden = 1`。
- 入库后返回：`{ "note": { …同 GET 单条…, "mine": true } }`。

### PATCH /wall/messages/:id
- 请求体：`{ x, y, owner }`。
- 校验 `notes.owner === owner`，否则 403；更新 `x, y`；返回 `{ "ok": true }`。
- 用途：拖拽重定位的持久化（当前前端只改本地）。

`ip_hash`：`sha256(cf-connecting-ip + SALT)` 取前若干位；`SALT` 用 Worker secret，避免反查 IP。

## 6. 反滥用

- Turnstile：前端在 compose 确认步骤挂 widget 取 token；后端 siteverify。site key 公开（`NEXT_PUBLIC_TURNSTILE_SITE_KEY`），secret 走 `wrangler secret put TURNSTILE_SECRET`。
- 限流：见 POST。阈值见决策 D2。
- 审核：`hidden` 列。手动 `wrangler d1 execute mos-server --command "UPDATE wall_notes SET hidden=1 WHERE id=?"`；如需页面化，加一个受 `ADMIN_TOKEN` 保护的 `POST /api/admin/hide`。

## 7. 旋转派生（不入库）

便签的小角度倾斜不存储，由 id 确定性派生，保证刷新后角度稳定、不每次随机跳：

```ts
export function rotFromId(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
  return Math.round(((Math.abs(h) % 81) / 10 - 4) * 10) / 10; // [-4, 4]
}
```

已知取舍：从托盘拖出时草稿用"释放瞬间惯性角"（连贯落定）；`confirm` 入库后展示角切到 `rotFromId(id)`，会有一次很小的角度切换。可接受；若要消除，需把 rot 也入库（与"不记录旋转"冲突），不做。

## 8. 前端切换

`website/app/services/wall.ts`：
- `WallNote` 去掉持久化里的 `rot`，改为 map 时 `rot = rotFromId(id)`；新增 `mine` 字段来自服务端；新增 `name`。
- owner token：`getOwner()` 读/写 `localStorage["wall_owner"]`。
- `fetchNotes()`：带 `x-wall-owner` 头；map 服务端返回。
- `postNote(input)`：带 `owner + turnstileToken`；不再发 `rot`。
- 新增 `repositionNote(id, x, y)` → `PATCH`。

`website/app/wall/wall-client.tsx`：
- `myIds` 改为依据服务端 `note.mine`（删掉本会话 Set）。
- `reposition` 调 `repositionNote` 持久化（失败回滚或提示）。
- compose 确认：挂 Turnstile widget，拿到 token 才允许 `Stick it`；token 传给 `postNote`。

环境变量（静态导出，build 时注入；在 GitHub Pages 构建工作流里设置）：
- `NEXT_PUBLIC_SERVER_URL`：Worker 地址。
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY`：Turnstile site key。

未设 `NEXT_PUBLIC_SERVER_URL` 时保留现有本地种子回退（便于本地开发）。

## 9. i18n

墙的文案目前是英文硬编码，需接站点 13 语言（`website/app/i18n/*.ts`，`Translations = typeof en` 约束所有 locale 同构）。新增 `t.wall.*`：tray 标签、compose 占位/计数/按钮、header 标题、空态、错误提示。英文+简繁中文亲写，其余给合理翻译。可复用既有注入脚本模式（见 donation 阶段的 `inject` 脚本思路）。

## 10. Worker 工程结构

放在 `website/server/`（与站点同目录）。两道隔离避免它被站点构建吞并：① `website/tsconfig.json` 的 `exclude` 加 `server`，把 Worker 代码挡在 Next 编译之外；② server 自带 `pnpm-workspace.yaml` 成为独立 pnpm 根，`install`/`dev`/`deploy` 锁在自己的 node_modules（否则父 workspace 会把安装劫持到站点根）。

```
website/server/                 # 通用后端，多功能；wall 只是第一个 feature
  wrangler.toml         # name=mos-server, main, [[d1_databases]] 绑定, [vars] ALLOWED_ORIGIN
  pnpm-workspace.yaml   # 独立 pnpm 根 + 批准 workerd/esbuild 构建脚本
  package.json
  migrations/0001_wall.sql       # 表 wall_notes
  src/
    index.ts            # 顶层路由：按路径前缀分发到各 feature（健康 / + /wall/*）
    lib/                # 跨 feature 共享：env / http(cors+json) / turnstile / hash
    features/wall.ts    # wall 的端点 + 逻辑（GET/POST /wall/messages，无 PATCH 见 D3）
```

原生 `fetch` handler 手写路由，无需框架。共享件在 `src/lib/`，每个 feature 一个 `src/features/<name>.ts`，在 `src/index.ts` 注册路由；新功能照此添加。

## 11. 部署步骤

```
cd website/server
wrangler d1 create mos-server                     # 记录 database_id 填进 wrangler.toml
wrangler d1 migrations apply mos-server            # 建表
wrangler secret put TURNSTILE_SECRET             # 输入 Turnstile secret
wrangler secret put IP_SALT                      # 限流 hash 盐
wrangler deploy                                  # 得到 Worker 地址/路由
```
- 站点构建注入 `NEXT_PUBLIC_SERVER_URL`（Worker 地址）与 `NEXT_PUBLIC_TURNSTILE_SITE_KEY`。
- 去掉 `website/app/home-client.tsx` 里两处 `hidden`（导航 + footer 的 Wall 入口），放出墙。

## 12. 下一会话任务清单（建议顺序）

1. 建 `server/`：wrangler.toml + migrations + `src/index.ts`（GET/POST/PATCH + CORS + Turnstile + 限流 + 过滤）。
2. 本地 `wrangler dev` 跑通，curl 验证三个端点。
3. 改 `services/wall.ts`：owner token、`mine`、`rotFromId`、`name`、`repositionNote`、Turnstile token 透传。
4. 改 `wall-client.tsx`：`mine` 用服务端、reposition 持久化、compose 挂 Turnstile。
5. 接 13 语言 i18n。
6. 部署 Worker + D1；配置站点 env；去掉入口 `hidden`。
7. 真机验证：跨浏览器/会话可见、只拖自己的、限流、Turnstile 拦机器人。

## 13. 决策（已拍板 2026-06-06）

- **D1 署名 `name`：保留**为可选字段（属于 note 内容）。migration 含 `name` 列，前端 compose 维持可选署名输入。
- **D2 限流：1/分钟、20/小时/IP**（已在 `website/server/src/index.ts` 实现，本地 curl 验证 429）。
- **D3 重定位：落点持久化，但"保存即锁"** —— note 一旦贴上即不可再编辑/拖动。**因此不做 PATCH**：第 5 节 `PATCH /wall/messages/:id`、第 8 节 `repositionNote`、任务清单中"reposition 持久化"均作废；位置在 POST 时定稿、之后只读。公开 API 仅 `GET` / `POST` / `OPTIONS`。
- **D4 部署：自定义路由 `mos-api.caldis.me`**（DNS 已在 Cloudflare）。`wrangler.toml` 用 `routes = [{ pattern = "mos-api.caldis.me", custom_domain = true }]`；CORS `ALLOWED_ORIGIN = https://mos.caldis.me`。
- **D5 拉取上限：最近 800 条，无分页**（已实现；将来需要再加 `?before`）。
