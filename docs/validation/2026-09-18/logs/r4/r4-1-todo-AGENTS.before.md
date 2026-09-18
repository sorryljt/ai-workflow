<!-- fe-ai-workflow-start -->
## fe-ai-workflow（viktor）

本项目使用 viktor AI 开发工作流。技能：viktor-flow（自动流水线 / 续接），以及可单独调用的 viktor-init、viktor-plan、viktor-code、viktor-review、viktor-check、viktor-ship。

### 开始任何开发任务前：先判断档位，只输出一行声明（`▶ M 档  plan（等你确认）→ code → …`，不写理由；用户可以改）

| 档位 | 判据 | 流程 |
|------|------|------|
| S | 没有需要人拍板的口径或取舍，改动集中 | code → review → check → ship（全自动） |
| M | 有口径或取舍需要确认，单个模块 | plan（人确认）→ code → review → check → ship |
| L | 新增或修改数据模型 / 持久化结构（给已有表加可空列、放宽或收紧请求校验边界不算，这两类按 M；只有影响已有数据可读性、需要迁移或改主键 / 唯一约束的才算 L） / 对外接口契约，或跨两个以上模块 | plan（含任务清单，人确认）→ code → review → check → ship |

判档首先看"有没有需要人拍板的取舍"，有就至少 M；再看兼容性、数据影响、恢复成本；文件数和验收数只作参考。

给出完整需求时优先用 viktor-flow 跑完整流程；用户说“继续”“接着上次的”时用 viktor-flow 续接。做到一半发现范围超出档位：停下来说明，建议升档。流程停下时只输出待确认卡或需要处理卡，卡片之外不写段落，卡里不写续接命令。

调用方式：Claude Code、Cursor 输入 `/viktor-flow` 等；Codex 输入 `$viktor-flow`；或用自然语言描述意图。首次接入先运行 viktor-init。

### 约定

- 需求产物放在 `docs/changes/YYYY-MM-DD--<slug>/`（slug 用英文 kebab-case）：plan.md、review.md、check.md、report.md。plan.md frontmatter 的 `status` / `stage` / `stage_result` 是需求状态的唯一来源；每个节点只从磁盘取输入，人随时可以停、插话、手工修改，之后用 viktor-flow 续接。
- Agent 能直接读代码，所以不维护组件清单、接口清单；`docs/knowledge/` 只放代码里读不出来的知识（decisions / pitfalls / glossary，一条一个文件）。取知识只用 `bash .workflow/fe-ai-workflow/scripts/knowledge.sh lookup <路径或关键词>`，不要整目录读。
- M/L 档：plan 经用户确认之前，不写实现代码。
- review 和 check 在独立进程中执行（`scripts/viktor-spawn.sh`），避免自己审自己。
- 所有“已完成”“已通过”的说法，都要有本轮真实运行命令的输出作为依据。
- 检查命令记录在下方 `viktor-checks` 块中。Claude Code 中 Stop hook 会自动运行 typecheck / lint / test；其他工具中，结束前手动运行。
- 除非用户要求，不自动 commit。
<!-- fe-ai-workflow-end -->

## 项目信息（viktor-init）

- 技术栈：Vite 8 + React 19 + TypeScript 6（`tsc -b` 项目引用模式）/ 无状态管理库，状态在 `src/useTodos.ts` 自写 hook 里 / Vitest + React Testing Library + jsdom
- 包管理器：npm（仓库里只有 package-lock.json）
- 主干分支：main

```viktor-checks
typecheck: npm run typecheck
lint: npm run lint
test: npm test
dev: npm run dev
```

### 约定（只写不明显的）

- **typecheck 用 `tsc -b` 而不是 `tsc --noEmit`**：根 tsconfig.json 是 `files: []` 的 solution 文件，只有 references，`tsc --noEmit` 什么都不会检查。真正的配置在 `tsconfig.app.json`（src/）和 `tsconfig.node.json`（vite.config.ts）。
- **lint 是 oxlint，不是 ESLint**：配置在 `.oxlintrc.json`，`// eslint-disable-*` 注释在这里不生效，要用 `// oxlint-disable-next-line <rule>`。
- 测试配置写在 `vite.config.ts` 的 `test` 字段里（没有单独的 vitest.config.ts）；`src/test/setup.ts` 每个用例后自动 `cleanup()` 并清空 localStorage，测试里不用自己清。
- Vitest 开了 `globals: true`，`describe / it / expect` 无需 import；类型靠 tsconfig.app.json 的 `types: ["vitest/globals", "@testing-library/jest-dom"]` 提供。
- 测试文件与被测文件同级放置：`src/useTodos.ts` ↔ `src/useTodos.test.ts`。
- `tsconfig.app.json` 开了 `noUnusedLocals` / `noUnusedParameters` / `erasableSyntaxOnly`：写了没用到的变量会直接让 typecheck 失败；不能用 enum、参数属性等需要 TS 运行时转译的语法。
- localStorage 的 key 是 `'todolist-demo'`（`src/useTodos.ts`），改动它等于丢掉用户已有数据。
- 提交信息用 Conventional Commits（`feat:` / `fix:` / `chore:` / `docs:` / `test:` / `refactor:`）。
- 仓库目前没有任何 commit，`git log` 为空属正常。
- 数据存 localStorage，新增字段必须兼容旧数据（缺字段给默认值，不丢数据）
- 不引入 UI 组件库；拖拽可用轻量库
- jsdom 难测的交互（拖拽等）写明手动验证步骤

### 禁区

- `.workflow/`：fe-ai-workflow 的 git submodule，由 `install.sh` / `upgrade.sh` 管理，不手工改。
- `.claude/`、`.agents/`：工作流安装出来的技能与 hook 定义，同样由安装脚本维护。需要调整流程时改上游仓库再 upgrade。
