# 服务器迁移手册

本文档说明如何将御书房从一台服务器完整迁移到另一台服务器。

---

## 迁移前准备

### 新服务器环境要求

| 组件 | 版本要求 | 说明 |
|------|---------|------|
| Node.js | >= 22.16.0 | 推荐使用 nvm 安装 |
| npm | 随 Node.js 附送 | - |
| Docker | Latest | 可选，用于 Docker 部署 |
| jq / curl / git | 最新版 | 辅助工具 |

### 工具准备

```bash
# 确认新服务器已安装必要工具
node --version   # >= 22.16.0
npm --version
git --version
jq --version     # JSON 处理
curl --version
```

---

## 第一步：原服务器 — 停止服务

### Docker 部署

```bash
cd ~/yushufang          # 进入项目目录
docker compose down      # 停止并移除容器（保留数据卷）
docker compose down -v   # 加上 -v 同时删除数据卷（谨慎！）
```

### 非 Docker 部署

```bash
openclaw gateway stop    # 停止 Gateway
```

> **重要**：务必在停止服务后再进行数据备份，否则内存中的未持久化数据可能丢失。

---

## 第二步：原服务器 — 备份数据

### 完整备份清单

以下是需要迁移的所有数据，请按顺序打包：

#### 1. OpenClaw 主配置文件（必选）

```bash
cp ~/.openclaw/openclaw.json ~/backup/openclaw.json
```

该文件包含：
- 所有 LLM API Key
- 所有 Discord Bot Token
- 所有 Agent 定义和人设
- Cron 任务配置

> **安全提示**：该文件包含敏感凭据，建议加密传输或通过安全渠道迁移。

#### 2. 记忆数据库（建议迁移）

```bash
# 记忆数据库（SQLite）
cp ~/.openclaw/memory/*.sqlite ~/backup/

# 项目工作记忆
cp -r ~/clawd/memory ~/backup/clawd-memory
```

#### 3. 工作目录（按需迁移）

```bash
# 各 Agent 工作区（如有重要数据）
cp -r ~/clawd ~/backup/clawd

# 户部数据（包含 token 用量记录）
cp -r ~/clawd-hubu ~/backup/clawd-hubu
```

#### 4. 自定义 Skills（按需迁移）

```bash
# 自定义 skills（如有）
cp -r ~/clawd/skills ~/backup/clawd-skills
```

#### 5. .env 文件

```bash
cp ~/.env ~/backup/.env 2>/dev/null || true
```

#### 6. Cron 任务记录（手动记录）

```bash
# 记录当前 cron 任务配置
openclaw cron list > ~/backup/cron-list.txt
crontab -l > ~/backup/crontab.txt 2>/dev/null || true
```

### 一键打包（推荐）

```bash
# 在 ~/ 创建备份目录
mkdir -p ~/yushufang-backup

# 复制所有数据
cp ~/.openclaw/openclaw.json ~/yushufang-backup/
cp -r ~/.openclaw/memory ~/yushufang-backup/memory
cp -r ~/clawd ~/yushufang-backup/clawd
[ -d ~/clawd-hubu ] && cp -r ~/clawd-hubu ~/yushufang-backup/
cp -r ~/clawd/skills ~/yushufang-backup/skills 2>/dev/null || true
cp ~/.env ~/yushufang-backup/.env 2>/dev/null || true

# 记录 cron 配置
openclaw cron list > ~/yushufang-backup/cron-list.txt

# 打包
cd ~
tar -czvf yushufang-backup-$(date +%Y%m%d).tar.gz yushufang-backup/

echo "备份完成：~/yushufang-backup-$(date +%Y%m%d).tar.gz"
```

---

## 第三步：传输数据到新服务器

### 安全传输（推荐）

```bash
# 方式一：scp（通过密钥认证）
scp -i ~/.ssh/id_rsa \
  ~/yushufang-backup-YYYYMMDD.tar.gz \
  user@newserver:~/

# 方式二：rsync（增量同步）
rsync -avz --progress \
  -e "ssh -i ~/.ssh/id_rsa" \
  ~/yushufang-backup/ \
  user@newserver:~/yushufang-backup/
```

> **安全提示**：不要通过不安全渠道（如邮件、公开网盘）传输包含 Token 的备份文件。

### 到达新服务器后解压

```bash
# SSH 登录新服务器
ssh user@newserver

# 解压备份
cd ~
tar -xzvf yushufang-backup-YYYYMMDD.tar.gz
```

---

## 第四步：新服务器 — 安装御书房

### 安装 OpenClaw

```bash
# Node.js >= 22.16.0（如未安装）
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# 安装 OpenClaw
npm install -g openclaw
```

### 安装御书房（推荐方式）

```bash
# 完整安装脚本（会自动引导）
bash <(curl -fsSL https://raw.githubusercontent.com/1012Lonin/Yushufang/main/scripts/full-install.sh)

# 或克隆仓库后本地安装
git clone https://github.com/1012Lonin/Yushufang.git ~/yushufang
cd ~/yushufang
bash scripts/full-install.sh
```

> **注意**：安装脚本会生成新的默认配置，请**跳过**配置步骤，直接在第五步恢复备份的配置。

### Docker 部署方式

```bash
# 克隆项目
git clone https://github.com/1012Lonin/Yushufang.git ~/yushufang
cd ~/yushufang

# 复制 .env（包含所有 Token）
cp ~/yushufang-backup/.env .env

# 启动
docker compose up -d
```

---

## 第五步：新服务器 — 恢复配置

### 恢复主配置文件

```bash
# 备份安装脚本生成的新配置
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.new

# 恢复备份配置
cp ~/yushufang-backup/openclaw.json ~/.openclaw/openclaw.json

# 验证配置格式
jq empty ~/.openclaw/openclaw.json && echo "配置格式正确"
```

### 恢复记忆数据库

```bash
# 确保目录存在
mkdir -p ~/.openclaw/memory

# 恢复记忆
cp ~/yushufang-backup/memory/*.sqlite ~/.openclaw/memory/ 2>/dev/null || true

# 验证
ls -la ~/.openclaw/memory/
```

### 恢复工作目录

```bash
# 恢复主工作目录
mkdir -p ~/clawd
cp -r ~/yushufang-backup/clawd/* ~/clawd/ 2>/dev/null || true

# 恢复户部数据
mkdir -p ~/clawd-hubu
cp -r ~/yushufang-backup/clawd-hubu/* ~/clawd-hubu/ 2>/dev/null || true

# 恢复自定义 skills
mkdir -p ~/clawd/skills
cp -r ~/yushufang-backup/skills/* ~/clawd/skills/ 2>/dev/null || true
```

---

## 第六步：重新配置 Cron 任务

查看原服务器的 cron 记录：

```bash
cat ~/yushufang-backup/cron-list.txt
```

根据记录，重新添加 cron 任务：

```bash
# 示例：国子监每日计划推送
openclaw cron add "0 8 * * *" "guozijian-daily-plan"

# 示例：户部日报
openclaw cron add "0 23 * * *" "hubu-daily-report"

# 示例：户部周报
openclaw cron add "0 9 * * 1" "hubu-weekly-report"

# 示例：工部健康检查
openclaw cron add "0 */2 * * *" "gongbu-health-check"
```

> **注意**：cron 任务依赖 OpenClaw Gateway 运行。确保 Gateway 启动后再添加 cron 任务。

---

## 第七步：验证

### 启动服务

```bash
# 非 Docker 部署
openclaw gateway start
openclaw status

# Docker 部署
docker compose up -d
docker compose ps
```

### 运行健康检查

```bash
# 在项目目录执行
bash scripts/health-check.sh
```

### 验证各 Agent

在 Discord 中 @mention 各 Agent，确认响应正常。

### 验证 Cron 任务

```bash
openclaw cron list
# 确认所有预期任务都在列表中
```

---

## 常见问题

### Q1：迁移后 Agent 不响应

检查：
1. Discord Bot Token 是否正确（检查 ~/.openclaw/openclaw.json 中的 tokens）
2. Bot 是否已加入正确的服务器和频道
3. Gateway 是否正常运行：`openclaw status`

### Q2：Cron 任务不执行

1. Gateway 必须处于运行状态才能执行 cron 任务
2. 检查 cron 任务是否正确添加：`openclaw cron list`
3. 检查日志：`openclaw logs`

### Q3：记忆丢失

确保恢复了 `~/.openclaw/memory/*.sqlite` 文件。记忆数据库是 SQLite 文件，丢失后无法恢复。

### Q4：户部数据用量统计错乱

户部数据存放在 `~/clawd-hubu/`。恢复该目录后，阈值计算会从备份位置继续。
如需重置：`rm -rf ~/clawd-hubu/data/*`（会清空历史数据，重新开始计数）

---

## 回滚方案

如迁移失败，返回原服务器：

```bash
# 原服务器重新启动（非 Docker）
openclaw gateway start

# 原服务器重新启动（Docker）
cd ~/yushufang
docker compose up -d
```

> **建议**：在确认新服务器完全正常之前，**不要**关闭原服务器。
