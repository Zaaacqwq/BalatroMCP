# 如何把 Agent 接入 Balatro

## 前置条件
1. 打开 Balatro（游戏内置 MCP 服务器会在 `127.0.0.1:12346` 自动启动）
2. 确认 mod 已加载（游戏启动后终端里能看到 `[balatro-mcp-mod]` 字样）

---

## Claude Desktop

1. 打开配置文件：`%APPDATA%\Claude\claude_desktop_config.json`
2. 把下面这段合并进去：

```json
{
  "mcpServers": {
    "balatro": {
      "command": "C:\\Users\\ZacPC\\AppData\\Local\\Programs\\Python\\Python310\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

3. 重启 Claude Desktop → 对话里出现锤子图标 → 工具栏里能看到 `balatro` → 可以开始对话

**示例 prompt：**
> "帮我玩 Balatro，先看看当前游戏状态，然后帮我打完这一轮。"

---

## Cursor

在项目根目录创建 `.cursor/mcp.json`（或合并到 `~/.cursor/mcp.json`）：

```json
{
  "mcpServers": {
    "balatro": {
      "command": "C:\\Users\\ZacPC\\AppData\\Local\\Programs\\Python\\Python310\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

重启 Cursor → Settings → MCP → 看到 balatro 为绿色即可。

---

## VS Code + GitHub Copilot (>=1.99)

在项目创建 `.vscode/mcp.json`：

```json
{
  "servers": {
    "balatro": {
      "type": "stdio",
      "command": "C:\\Users\\ZacPC\\AppData\\Local\\Programs\\Python\\Python310\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

或者在用户 `settings.json` 里加：
```json
"mcp.servers": {
  "balatro": {
    "type": "stdio",
    "command": "C:\\Users\\ZacPC\\AppData\\Local\\Programs\\Python\\Python310\\python.exe",
    "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
  }
}
```

---

## OpenAI Codex CLI

在 `~/.codex/config.json` 里加：

```json
{
  "mcpServers": {
    "balatro": {
      "type": "stdio",
      "command": "C:\\Users\\ZacPC\\AppData\\Local\\Programs\\Python\\Python310\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

---

## 可用工具（所有客户端通用）

| 工具 | 功能 |
|------|------|
| `get_game_state` | 获取当前完整游戏状态（阶段、手牌、商店、金钱、分数） |
| `list_legal_actions` | 列出当前可执行的所有合法操作 |
| `execute_action` | 执行一个游戏操作（会等动画结束再返回） |
| `get_action_history` | 查看最近的操作历史（调试用） |
| `get_run_summary` | 获取本局的简要摘要 |

---

## 游戏阶段 & 对应操作速查

| 阶段 | 可用操作 |
|------|---------|
| `menu` | `continue` |
| `blind_select` | `choose_option` (small/big/boss), `skip` |
| `in_round` | `select_card`, `deselect_card`, `play_hand`, `discard_selected` |
| `round_eval` | `continue` |
| `shop` | `buy_item`, `reroll_shop`, `end_turn`, `continue` |
| `game_over` | `continue` |

---

## Copilot 推荐用法（显式工具版）

为了让 Copilot 更稳定地调用 Balatro，优先使用显式 MCP 工具，不要默认依赖通用 `execute_action`：

- `continue_run`
- `choose_blind`
- `skip_choice`
- `select_card`
- `deselect_card`
- `play_hand`
- `discard_selected`
- `end_turn`
- `buy_item`
- `reroll_shop`
- `sell_joker`
- `use_consumable`

推荐固定流程：

1. 先读 `E:\BalatroLLM\strategy`
2. 再调 `get_game_state`
3. 再调 `list_legal_actions`
4. 最后用上面最具体的工具执行一个合法动作
