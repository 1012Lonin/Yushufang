# 安全更新指南

> 保护数据不丢失的标准流程

---

## 快速更新（推荐）

```bash
cd ~/Yushufang

# 1. 自动备份（配置 → ~/.openclaw/backups/）
bash scripts/backup-all.sh

# 2. 更新前检查
bash scripts/pre-update-check.sh

# 3. 拉取最新代码
git pull

# 4. 重新注入人设（configs/*/agents/*.md → ~/.openclaw/openclaw.json）
bash scripts/init-personas.sh

# 5. 重启 Gateway
openclaw gateway restart

# 6. 验证状态
openclaw status
```

> 使用 `bash scripts/safe-update.sh` 可一键执行以上完整流程（备份 → 检查 → 拉取 → 注入 → 重启）。

---

## 备份说明

### 备份位置

所有备份存放在 `~/.openclaw/backups/`（配置目录内，随配置一起迁移）：

```
~/.openclaw/backups/
├── configs/          # openclaw.json 时间戳备份
├── memory/           # 记忆数据库 (.sqlite) 时间戳打包
├── agents/           # Agent 工作空间（--full 模式）
└── backup-manifest.*.json  # 备份清单
```

### 备份内容

| 内容 | 路径 | 敏感度 |
|------|------|--------|
| 主配置 | `~/.openclaw/openclaw.json` | 🔴 含所有 API Key / Token |
| 记忆数据库 | `~/.openclaw/memory/*.sqlite` | 🟡 重要数据 |
| Agent 工作空间 | `~/clawd/` | 🟡 按需 |
| 户部用量数据 | `~/clawd-hubu/` | 🟢 非敏感 |

### 定时自动备份

```bash
# 每天凌晨 3 点备份
crontab -e
# 添加：
0 3 * * * bash $HOME/Yushufang/scripts/backup-all.sh >> $HOME/.openclaw/backups/backup.log 2>&1
```

---

## 回滚

```bash
# 查看可用备份
ls ~/.openclaw/backups/configs/

# 恢复配置（以最新的为准）
cp ~/.openclaw/backups/configs/openclaw.json.YYYYMMDD_HHMMSS ~/.openclaw/openclaw.json

# 重启
openclaw gateway restart
```

或使用交互式回滚：

```bash
bash scripts/safe-update.sh --rollback
```

---

## 禁止操作

```bash
# ❌ 禁止直接覆盖运行时配置（会丢失 API Key）
cp configs/ming-neige/openclaw.json ~/.openclaw/

# ❌ 禁止 git pull 后不检查直接重启
git pull && openclaw gateway restart

# ❌ 禁止删除 ~/.openclaw/backups/ 目录
```

---

## 更新检查清单

### 更新前

- [ ] `bash scripts/backup-all.sh` — 确认备份成功
- [ ] `bash scripts/pre-update-check.sh` — 确认无严重警告
- [ ] 记录当前版本：`git rev-parse HEAD | cut -c1-7`

### 更新后

- [ ] `bash scripts/init-personas.sh` — 确认人设注入成功
- [ ] `openclaw status` — Gateway 运行正常
- [ ] Discord @mention 任一 Agent — 确认响应
- [ ] `tail ~/.openclaw/logs/*.log` — 无报错

---

**最后更新**: 2026-04-06
**参考**: [docs/migration.md](./migration.md)（服务器迁移场景）
