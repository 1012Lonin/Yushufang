# 安装脚本问题诊断与修复方案

> **历史文档 · 2026-03-25**  
> 以下问题已在后续版本中修复。当前御书房仓库使用 `scripts/full-install.sh` 和 `scripts/simple-install.sh`，参考 [README.md](../README.md) 中的安装说明。

## 🐛 用户反馈的问题

1. **没有人设** - 安装后 agent 没有 identity.theme
2. **安装脚本很乱** - 多个脚本功能重复，逻辑复杂

## 🔍 问题根源

### 问题 1: 人设丢失

**原因**：
- `install-lite.sh` 只下载 `openclaw.json` 模板
- 模板中的 identity.theme 是占位符文本
- 没有从 `configs/ming-neige/agents/*.md` 注入真实人设

**对比**：
```bash
# full-install.sh ✅
# 1. 克隆仓库到临时目录
# 2. 遍历 agents/*.md 文件
# 3. 将人设内容注入到 JSON 的 identity.theme
# 4. 自动检测 ~/.openclaw 或 ~/.clawdbot

# simple-install.sh ✅（已修复人设注入）
# 1. 直接下载 openclaw.json 模板
# 2. 注入人设
# 3. 自动检测 ~/.openclaw 或 ~/.clawdbot
```

### 问题 2: 脚本混乱

**现状**：
| 脚本 | 行数 | 功能 | 问题 |
|------|------|------|------|
| `full-install.sh` | ~330 | 完整安装 | 功能最全（推荐） |
| `simple-install.sh` | ~130 | 精简安装 | 快速上手 |
| `install-mac.sh` | ~500 | macOS 专用 | 平台限定 |

**总计**：1628 行，大量重复代码

---

## ✅ 修复方案

### 方案 A: 快速修复（推荐）

1. **修复 `install-lite.sh`** - 添加人设注入逻辑
2. **统一脚本** - 删除重复的 `install.sh`
3. **创建文档** - 明确各脚本用途

### 方案 B: 彻底重构

1. **创建核心安装库** - `scripts/install-core.sh`
2. **简化各脚本** - 只保留差异部分
3. **统一配置处理** - 共用配置注入逻辑

---

## 🔧 立即执行：方案 A

### 步骤 1: 修复 install-lite.sh

添加人设注入步骤：
```bash
# 在生成配置后添加
inject_personas() {
  local config_file="$1"
  local agents_dir="$2"
  
  if [ ! -d "$agents_dir" ]; then
    echo "⚠ 人设目录不存在"
    return
  fi
  
  echo "正在注入人设..."
  agent_count=$(jq '.agents.list | length' "$config_file")
  
  for ((i=0; i<agent_count; i++)); do
    agent_id=$(jq -r ".agents.list[$i].id" "$config_file")
    persona_file="$agents_dir/${agent_id}.md"
    
    if [ -f "$persona_file" ]; then
      persona=$(tail -n +3 "$persona_file")
      persona_escaped=$(echo "$persona" | jq -Rs '.')
      
      jq --argjson idx "$i" --argjson persona "$persona_escaped" \
        ".agents.list[$idx].identity.theme = \$persona" \
        "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
      
      echo "  ✓ $agent_id"
    fi
  done
}
```

### 步骤 2: 更新文档

已在 README.md 中明确各脚本用途，详见安装章节。

### 步骤 3: 更新 README

明确脚本用途：
```markdown
## 安装方式

### 方式一：完整安装（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/1012Lonin/Yushufang/main/scripts/full-install.sh)
# ✅ 包含：环境检查 + 人设注入 + 配置生成

### 方式二：精简安装（已有 OpenClaw）
bash <(curl -fsSL https://raw.githubusercontent.com/1012Lonin/Yushufang/main/scripts/simple-install.sh)
# ✅ 包含：配置生成 + 人设注入
```

---

## 📋 待办事项

> 以下问题已在 2026-03-25 修复后的版本中解决，保留此处作为历史记录。

- [x] 修复人设注入（已集成到 `full-install.sh` 和 `simple-install.sh`）
- [x] 统一脚本（`install.sh` 已废弃，使用 `full-install.sh`）
- [x] 更新 README 文档
- [x] 测试所有安装流程
