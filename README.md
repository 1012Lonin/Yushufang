# 📚 御书房 Yushufang

> 基于 [danghuangshang](https://github.com/wanikua/danghuangshang) 上游项目定制的个人学术开发者 AI 多 Agent 协作系统。
> 一台服务器 + OpenClaw = 一个 7×24 在线的私人学术工作室。

## 项目定位

御书房是 danghuangshang 的个人定制版本，针对**研究生/个人学术+代码开发者**场景做了全面改造：
- 6 个部门 + 翰林院 + 典簿司 + 起居注官 + 生活辅助（18+ Agent）
- 多 LLM Provider 支持（Anthropic / OpenAI / DeepSeek / 自定义）
- 自动日报/周报/月报 + 记忆管理 + 计划推送

## 快速开始

```bash
git clone https://github.com/1012Lonin/Yushufang.git
cd Yushufang
bash scripts/full-install.sh
```

## 🔧 模型配置指南

### 当前 Provider 配置

项目已预置三个 LLM Provider 架构，均在 `configs/ming-neige/openclaw.json` 的 `models.providers` 中：

| Provider | 用途建议 | 预置模型 |
|---|---|---|
| `anthropic` | 强推理（内阁/兵部/吏部/翰林院/都察院） | claude-sonnet-4-6, claude-haiku-4-5 |
| `openai` | 轻量任务（司礼监/工部/刑部） | gpt-4o-mini, gpt-4o |
| `deepseek` | 低成本任务（户部/礼部/典簿司/起居注官） | deepseek-chat |

### 如何更换模型 / 添加新 Provider

**1. 添加新 Provider（如 Google Gemini）**

在 `configs/ming-neige/openclaw.json` 的 `models.providers` 中添加：

```json
{
  "google": {
    "baseUrl": "https://generativelanguage.googleapis.com/v1beta/openai",
    "apiKey": "YOUR_GOOGLE_API_KEY",
    "api": "openai-completions",
    "models": [
      { "id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash", "input": ["text"], "contextWindow": 1000000, "maxTokens": 8192 }
    ]
  }
}
```

`api` 字段值取决于 API 协议类型：
- OpenAI 兼容 API：`"openai-completions"`
- Anthropic Messages API：`"anthropic-messages"`

**2. 修改 Agent 使用的模型**

在 `agents.list` 中找到对应的 agent，修改 `model.primary` 字段：

```json
{
  "id": "silijian",
  "name": "司礼监",
  "model": {
    "primary": "openai/gpt-4o-mini"
  },
  ...
}
```

格式：`"provider名/模型id"`，其中 `provider名` 必须与 `models.providers` 中的 key 一致。

**3. 添加新模型到已有 Provider**

在对应 Provider 的 `models` 数组中添加新条目：

```json
"models": [
  { "id": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6", "input": ["text", "image"], "contextWindow": 200000, "maxTokens": 32768 },
  { "id": "claude-opus-4-6", "name": "Claude Opus 4.6", "input": ["text", "image"], "contextWindow": 200000, "maxTokens": 32768 }
]
```

**4. 切换现有 Agent 到省钱模型**

例如把内阁从 Sonnet 切换到 GPT-4o：

```json
{
  "id": "neige",
  "model": { "primary": "openai/gpt-4o" }
}
```

### 费用优化建议

| 场景 | 推荐模型 | 原因 |
|---|---|---|
| 司礼监（纯调度） | gpt-4o-mini / deepseek-chat | 简单路由判断 |
| 内阁/兵部/都察院 | claude-sonnet-4-6 | 强推理+代码能力 |
| 学术文案 | deepseek-chat | 便宜且速度快 |
| 论文写作 | claude-sonnet-4-6 | 深度推理+长文本 |
| 日常辅助 | gpt-4o-mini | 成本低 |

### 完整 Agent-模型映射表（默认）

| Agent | 默认模型 | 如何改 |
|---|---|---|
| 司礼监 | `your-provider/fast-model` | 编辑 `openclaw.json` → `silijian.model.primary` |
| 内阁 | `your-provider/strong-model` | 编辑 `openclaw.json` → `neige.model.primary` |
| 兵部 | `your-provider/strong-model` | 编辑 `openclaw.json` → `bingbu.model.primary` |
| ... | ... | 同理，每个 `agent.model.primary` 都可独立指定 |

> 所有 Agent 的 `model.primary` 字段默认使用占位符 `your-provider/fast-model` 或 `your-provider/strong-model`，这是为了让你可以自由替换为任意 Provider 和模型。

---

以下保留上游原始文档，供参考。

---
