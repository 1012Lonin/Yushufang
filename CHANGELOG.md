# 📜 Changelog

All notable changes to **Yushufang** will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/).

> 本文件的其余部分为上游 [danghuangshang](https://github.com/wanikua/danghuangshang) 的变更日志。

---

## [Unreleased]

### Fixed

- **scripts/pre-update-check.sh**: `date -d` 改为跨平台兼容实现（支持 macOS BSD + Linux GNU）
- **scripts/pre-update-check.sh**: `--install-hook` 改为检测已有 hook，保留备份而非直接覆盖
- **scripts/safe-update.sh**: `--rollback` 同时支持 safe-update 自身备份格式和 backup-all 时间戳文件格式

### Enhanced

- **scripts/pre-update-check.sh**: 完整重写为 8 项安全检查（+ allowBots/@everyone/@here 安全配置）
- **docs/UPDATE.md**: 新增自动定时备份、Git Hook 保护、版本管理、检查清单分层
- **scripts/safe-update.sh**: 新增 `--install-hook` 参数，委托 pre-update-check.sh 安装 Git Hook

### Added

- **Git Hook 保护**：pre-commit 钩子自动拦截真实 API Key / Token / .env 敏感文件

---

## [1.2.0] — 2026-04-06

### Added

- **scripts/uninstall.sh**: 完整卸载脚本，支持 Docker/non-Docker 全部清理项（npm 包 / 配置目录 / 工作目录 / Docker 容器镜像 / crontab）
- **docs/migration.md**: 服务器迁移完整操作手册（备份清单 → 传输 → 配置恢复 → Cron 重配 → 验证步骤）

### Changed

- **安装脚本精简**：保留 `scripts/full-install.sh` / `install-mac.sh` / `Dockerfile`，删除 `install-lite.sh` / `install.ps1` / `scripts/full-install.ps1`
- **上游引用清理**：所有保留脚本和 Dockerfile 的 danghuangshang 引用更新为 Yushufang（`wanikua/danghuangshang` → `1012Lonin/Yushufang`）
- **README.md**：新增运维相关入口（迁移指南 + 卸载脚本链接）

### Fixed

- `install-lite.sh`: 硬编码错误路径 `$HOME/clawd/danghuangshang/`（文件已删除）
- `Dockerfile`: OCI 标签更新（maintainer / version / repo URL）

---

## [1.1.1] — 2026-04-06

### Fixed

- **hubu-data-collect.sh**: 修复 JSON 注入风险，所有 Python heredoc 中的 shell 变量改为环境变量传参（api-usage.json / tick / rolling / daily-snapshots / weekly-snapshots）
- **scripts/health-check.sh**: 修复飞书/Discord 告警中 JavaScript 三元运算符语法错误（`${level = 'critical' ? ...}` 在 bash 中不生效），改为 if-then-else 变量
- **scripts/cleanup-repo.sh**: 添加缺失的 `CYAN` 颜色变量定义
- **scripts/test-all-installs.sh**: `set -uo pipefail` 修正为 `set -euo pipefail`（缺少 `-e`）
- **scripts/full-install.sh**: 修复步骤编号跳号（[2.5/7] → [2/7]，[4/7] → [3/7]，[5/7] → [4/7]）
- **.env.example**: 移除重复的 `DISCORD_DIANBOSI_TOKEN` 字段

---

## [1.1.0] — 2026-04-06

### Added

- **户部阈值系统重构**：重写 `scripts/hubu_data_collect.py`，替代旧 Shell 脚本
  - 5 小时滚动窗口配额（Soft: 80,000 / Hard: 120,000）
  - 周配额（Soft: 800,000 / Hard: 1,000,000）
  - 多层级告警：Soft → 记录日志；Hard → 发 Discord @司礼监；月额 90% → @司礼监 + @皇帝
  - 告警冷却机制：同类告警 4 小时内不重复发送
  - 时间序列数据：`ticks/`、`daily-snapshots/`、`weekly-snapshots/`、`rolling/` 四类文件
  - 向后兼容 `api-usage.json`，现有 LLM prompt 无需改动
- **`scripts/hubu-data-collect.sh`** 重写为纯 bash 薄封装，直接调用 Python 模块
- **`.env.example`** 新增户部阈值环境变量说明（HUBU_ROLLING_*/HUBU_WEEKLY_*/HUBU_DAILY_* 等）
- **README SVG 图表**：`images/dispatch-flow.svg`（核心调度链路）、`images/org-structure.svg`（组织架构图）

### Changed

- **版本号统一为 1.1.0**：`package.json`、`README.md` badge 同步更新
- **户部 cron prompt**（`configs/ming-neige/openclaw.json`）：日报/周报/月报均改为指向新的结构化数据文件路径
- **户部 persona**（`configs/ming-neige/agents/hubu.md`）：补充新数据文件说明、阈值表、含 5h 窗口的日报/周报/月报模板
- **README.md**：
  - 修正 ASCII 架构图竖线对齐问题
  - 补充跨频道通信说明（Discord @mention 只在同频道内有效，跨频道用 `sessions_spawn`/`sessions_send`）
  - 户部数据管道章节更新为 v1.1.0 重构说明，含阈值表和自定义方式
  - 底部新增 CHANGELOG 跳转链接

### Removed

- **清理上游遗留文件**：移除飞书配置（`configs/feishu*/`）、维权证据（`evidence/`）、上游审查报告（`BUG-REPORT.md`）、原创声明文档（`docs/originality.md`）、菠萝王朝介绍（`docs/pineapple-dynasty.md`）、英文版 README（`README_EN.md`）
- **删除未使用的飞书脚本/文档**：7 个飞书相关脚本和文档
- **`skills/ai-court-skill/`** 中飞书 agent 配置及引用文档

### Fixed

- README SVG 图表路径修正（中文文件名改为英文）

---

## [1.0.1] — 2026-04-05

### Added

- **国子监多计划管理**：支持同时管理多个学习计划（`workspace/plans/` 目录）
- GitHub CI 工作流修复，移除上游 CI 依赖

---

## [1.0.0] — 2026-04-05

### Added

- **御书房 1.0.0 正式发布**，基于 danghuangshang 改造的学术开发者定制版
- 完整 20 Agent 配置（明朝内阁制）
- 7 项 Cron 任务（含国子监每日计划推送）
- 多 Provider 支持（Anthropic / OpenAI / DeepSeek）
- 三级记忆收集机制
- 翰林院 5 角色创作流水线
- Docker / 非 Docker 两种部署方式

---

## [v3.5.3] — 2026-03-19

> 以下为上游 danghuangshang 的变更日志

### 新功能
- **多制度支持** — 安装时可选择三种制度
  - **唐朝三省制**：中书→门下→尚书，制衡审核（14 Agent）
  - **明朝内阁制**：司礼监 + 内阁，快速迭代（18 Agent）
  - **现代企业制**：CEO/CTO/CFO，国际化（14 Agent）
- **配置模板分离** — `configs/{tang-sansheng,modern-ceo,ming-neige}/`
- **独立审查机制** — 御史台通过 GitHub webhook 触发代码审查

### 配置修复
- **openclaw.example.json** — 所有 18 个 Discord accounts 补充 `applicationId` 字段
- **install.sh** — Discord 配置模板同步补充 `applicationId`
- **install-lite.sh** — Discord 配置模板同步补充 `applicationId`
- **install-mac.sh** — Discord 配置模板同步补充 `applicationId`

### 文档更新
- **docs/regimes.md** — 新增制度选择指南（详细对比 + 工作流程）
- **configs/tang-sansheng/** — 唐朝三省制配置 + SOUL.md
- **configs/modern-ceo/** — 现代企业制配置 + SOUL.md
- **README.md** — 新增 Windows PowerShell 安装命令，版本号更新为 v3.5.3
- **README_EN.md** — 版本号更新为 v3.5.3
- **docs/faq.md** — Windows 支持说明更新（原生 vs WSL2 对比表）
- **docs/windows-wsl.md** — 重构为两种安装方式指南
- **install.ps1** — 修复 WSL2 安装命令说明（`wsl bash -c` 替代直接运行）

### Bug 修复
- 修复 Windows 用户找不到安装指南的问题 (closes #99)
- 修复 Discord 配置缺少 `applicationId` 导致新手配置失败的问题

---

## [v3.5.2] — 2026-03-13

### Bug 修复
- **H-01** `install.sh` — nvm/volta/fnm 环境下不再使用 sudo 安装全局 npm 包
- **H-05** `gui/server/index.js` — `/api/health` 中 wss/sseClients/metricsBuffer 引用改为 optional chaining
- **H-06** `openclaw.example.json` — `$HOME/clawd` 替换为 `/home/YOUR_USERNAME/clawd` 占位符
- **H-07** `install.sh` — heredoc 中 `$HOME` 增加空值保护
- **H-09** `gui/server/index.js` — `countSessionFile` 改为异步流，不再阻塞 Node 事件循环

---

## [v3.5.1] — 2026-03-12

### 优化
- **README 重构** — 精简为 ~400 行引导页，详细教程拆分到 `docs/` 目录
- 修复飞书权限数量描述（8→9 个）
- 飞书排查权限表补全 `contact:user.employee_id:readonly`
- 修复 Sandbox 锚点链接
- `clawdhub install` 命令更新为 `openclaw skill install`
- 基础篇/进阶篇 txt 转 markdown 格式

---

## [v3.5] — 2026-03-12

### 新功能
- **预装 7 个 Skill** — weather / github / notion / hacker-news / browser-use / quadrants / openviking
- **飞书配置全面优化**
- **GUI 品牌可配置** — 通过 `VITE_BRAND_NAME` 环境变量自定义
- **install.sh 安装后自动运行 doctor.sh** 健康检查
- **新增 CONTRIBUTING.md**

### Bug 修复
- README 飞书配置示例缺 groupPolicy
- openclaw.example.json 缺少翰林院的 Discord account 和 binding
- Dockerfile `COPY skills/` 路径硬编码

---

## [v3.4] — 2026-03-11

### 新功能
- **飞书配置指南** — 完整的飞书接入文档
- **doctor.sh 飞书诊断** — 自动检测飞书 appId/appSecret/权限
- **GUI 多框架支持**
- **Docker 部署** — Dockerfile + docker-compose + entrypoint

---

## [v3.0] — 2026-03-10

### 新功能
- **一键安装脚本三合一** — install.sh / install-lite.sh / install-mac.sh
- **多部署模式** — Discord 多Bot / 飞书多Bot / 纯 WebUI
- **Web GUI** — React + TypeScript Dashboard
- **OpenViking Skill** — 向量知识库集成

---

## [v2.0] — 2026-02-22

### 首次发布
- 三省六部制 × OpenClaw 多 Agent 架构
- 10 Agent 模板
- Discord 多 Bot 模式
