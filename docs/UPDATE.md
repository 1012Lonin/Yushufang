# 安全更新指南

> 保护数据不丢失的标准流程

---

## 快速更新（推荐）

```bash
cd ~/Yushufang

# 一键完整流程（备份 → 检查 → 拉取 → 注入 → 重启）
bash scripts/safe-update.sh

# 或分步执行
bash scripts/backup-all.sh
bash scripts/pre-update-check.sh
git pull
bash scripts/init-personas.sh
openclaw gateway restart
openclaw status
```

---

## 脚本说明

| 脚本 | 用途 |
|------|------|
| `scripts/safe-update.sh` | 一键更新，支持 `--backup` / `--check` / `--rollback` |
| `scripts/pre-update-check.sh` | 更新前安全检查（8 项），支持 `--install-hook` 安装 Git Hook |
| `scripts/backup-all.sh` | 备份到 `~/.openclaw/backups/`，支持 `--full` |
| `scripts/init-personas.sh` | 将 `configs/*/agents/*.md` 注入运行时配置 |

---

## 备份机制

### 备份位置

所有备份统一存放于 `~/.openclaw/backups/`：

```
~/.openclaw/backups/
├── configs/
│   └── openclaw.json.YYYYMMDD_HHMMSS      # 配置快照（自动保留 30 天）
├── memory.YYYYMMDD_HHMMSS.tar.gz           # 记忆数据库打包（自动保留 7 天）
├── agents.YYYYMMDD_HHMMSS.tar.gz           # Agent 工作区（--full 模式）
├── backup.log                                # 定时备份日志
└── backup-manifest.YYYYMMDD_HHMMSS.json   # 备份清单
```

### 备份内容

| 内容 | 路径 | 敏感度 |
|------|------|--------|
| 主配置 | `~/.openclaw/openclaw.json` | 🔴 含所有 API Key / Token |
| 记忆数据库 | `~/.openclaw/memory/*.sqlite` | 🟡 重要工作数据 |
| Agent 工作区 | `~/clawd/` | 🟡 按需备份 |
| 户部用量记录 | `~/clawd-hubu/` | 🟢 非敏感 |

### 自动定时备份（推荐）

```bash
crontab -e
# 添加以下两行：
0 3 * * *  bash $HOME/Yushufang/scripts/backup-all.sh >> $HOME/.openclaw/backups/backup.log 2>&1
0 3 * * 0  bash $HOME/Yushufang/scripts/backup-all.sh --full >> $HOME/.openclaw/backups/backup.log 2>&1

# 说明：
# 每天凌晨 3 点：标准备份（配置 + 记忆）
# 每周日凌晨 3 点：完整备份（+ Agent 工作区）
```

> 查看备份日志：`tail -20 ~/.openclaw/backups/backup.log`

### 备份保留策略

| 类型 | 自动保留 | 手动清理 |
|------|---------|---------|
| 配置快照 | 30 天 | `find ~/.openclaw/backups/configs/ -mtime +30 -delete` |
| 完整打包 | 7 天 | `find ~/.openclaw/backups/ -name "*.tar.gz" -mtime +7 -delete` |
| 清单文件 | 30 天 | 同配置快照 |

---

## Git Hook 保护（推荐安装）

提交代码时自动拦截真实敏感信息，防止意外泄露。

### 安装

```bash
bash scripts/pre-update-check.sh --install-hook
```

或：

```bash
bash scripts/safe-update.sh --install-hook
```

### 保护范围

| 检查项 | 拦截模式 | 正确做法 |
|--------|---------|---------|
| Anthropic API Key | `sk-ant-...` | 使用占位符 |
| OpenAI API Key | `sk-...`（20+字符） | 使用占位符 |
| Discord Token | `MNT...` / `Bot...`（50+字符） | 使用占位符 |
| .env 敏感文件 | 包含 `api_key/token/password` 的 .env | 使用 `.env.example` |

### 验证安装

```bash
# 已安装：有输出
grep "御书房" .git/hooks/pre-commit

# 未安装：无输出
grep "御书房" .git/hooks/pre-commit || echo "未安装"
```

---

## 回滚

### 方式一：交互式回滚

```bash
bash scripts/safe-update.sh --rollback
```

### 方式二：手动恢复

```bash
# 查看可用备份（按时间倒序）
ls -lt ~/.openclaw/backups/configs/

# 恢复配置
cp ~/.openclaw/backups/configs/openclaw.json.YYYYMMDD_HHMMSS ~/.openclaw/openclaw.json

# 验证格式
jq empty ~/.openclaw/openclaw.json && echo "OK"

# 重启
openclaw gateway restart
```

---

## 禁止操作

```bash
# ❌ 禁止直接覆盖运行时配置（会丢失 API Key / Token）
cp configs/ming-neige/openclaw.json ~/.openclaw/

# ❌ 禁止 git pull 后不检查直接重启
git pull && openclaw gateway restart

# ❌ 禁止在未备份的情况下执行重大更新

# ❌ 禁止删除 ~/.openclaw/backups/ 目录
```

---

## 更新检查清单

### 更新前（必须）

- [ ] `bash scripts/backup-all.sh` — 确认备份成功，无 ERROR
- [ ] `bash scripts/pre-update-check.sh` — 确认 0 个严重问题（issues=0）
- [ ] 记录当前版本：`git rev-parse HEAD | cut -c1-7`
- [ ] 确认无未提交的本地变更：`git status --short`

### 更新后（必须）

- [ ] `bash scripts/init-personas.sh` — 确认人设注入无报错
- [ ] `openclaw gateway restart` — 重启生效
- [ ] `openclaw status` — Gateway 显示 running
- [ ] Discord @mention 任一 Agent — 确认正常响应
- [ ] `tail -50 ~/.openclaw/logs/*.log` — 检查 ERROR 日志

### 可选（推荐）

- [ ] `bash scripts/pre-update-check.sh --install-hook` — 安装 Git Hook
- [ ] 配置定时自动备份（crontab）
- [ ] `git log --oneline -3` — 确认更新内容符合预期

---

## 版本管理

### 查看版本历史

```bash
git log --oneline -10
cat CHANGELOG.md | head -30
```

### 查看可用远程标签

```bash
git fetch --tags
git tag -l
```

### 切到特定版本

```bash
# 查看当前版本
git describe --tags

# 切到某个 tag
git checkout 1.2.0
```

> 注意：回退版本后，建议运行 `bash scripts/init-personas.sh` 确认配置兼容。

---

**最后更新**: 2026-04-06
**参考**:
- [迁移指南](./migration.md) — 服务器迁移场景
- [CHANGELOG.md](../CHANGELOG.md) — 版本变更记录
