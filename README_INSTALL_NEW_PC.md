# Balatro MCP 在另一台电脑上的安装指南（Windows）

这份文档用于从零安装：
- Balatro 端 Mod（游戏内桥接）
- Python MCP Server（给 AI 客户端调用）
- VS Code / Cursor / Claude / Codex 的 MCP 配置

适用仓库目录示例：`E:\BalatroLLM`

---

## 1. 先决条件

1. 已安装并可正常启动 Balatro。
2. 已安装 Python 3.10+（推荐 3.10 或 3.11）。
3. 可在 PowerShell 执行脚本（默认可用）。
4. 已把本仓库拷贝到本机，例如：`E:\BalatroLLM`。

---

## 2. 安装游戏 Mod（必须）

在仓库根目录打开 PowerShell，执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy_mod.ps1
```

该脚本会把 `mod/` 下内容部署到：

`%APPDATA%\Balatro\Mods\balatro_mcp`

你可以用下面命令检查：

```powershell
Get-ChildItem "$env:APPDATA\Balatro\Mods\balatro_mcp"
```

至少应看到：`entry.lua`、`mod.json`、多个 `*.lua` 文件和 `web/` 目录。

---

## 3. 安装 Python 依赖（必须）

仍在仓库根目录执行：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -U pip
python -m pip install -e .[dev]
```

安装完成后，MCP Server 启动入口是：

`E:\BalatroLLM\balatro_mcp_stdio.py`

---

## 4. 配置你的 AI 客户端（必须，四选一或多选）

注意：下面所有配置里的路径都要改成你本机真实路径。

### A) VS Code + GitHub Copilot

在项目根目录创建：`.vscode/mcp.json`

```json
{
  "servers": {
    "balatro": {
      "type": "stdio",
      "command": "E:\\BalatroLLM\\.venv\\Scripts\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

### B) Cursor

创建项目文件：`.cursor/mcp.json`（或全局 `~/.cursor/mcp.json`）

```json
{
  "mcpServers": {
    "balatro": {
      "command": "E:\\BalatroLLM\\.venv\\Scripts\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

### C) Claude Desktop

编辑：`%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "balatro": {
      "command": "E:\\BalatroLLM\\.venv\\Scripts\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

### D) OpenAI Codex CLI

编辑：`~/.codex/config.json`

```json
{
  "mcpServers": {
    "balatro": {
      "type": "stdio",
      "command": "E:\\BalatroLLM\\.venv\\Scripts\\python.exe",
      "args": ["E:\\BalatroLLM\\balatro_mcp_stdio.py"]
    }
  }
}
```

---

## 5. 运行顺序（很重要）

1. 先启动 Balatro（让游戏内桥接服务在 `127.0.0.1:12346` 起来）。
2. 再打开/重启你的 AI 客户端（VS Code/Cursor/Claude/Codex）。
3. 在对话里调用工具（例如先 `get_game_state`）。

---

## 6. 快速自检

### 检查游戏桥接是否在线

开着游戏时，在 PowerShell 执行：

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:12346/health | Select-Object -ExpandProperty Content
```

能返回 JSON 说明 mod 侧正常。

### 检查 Python 入口是否存在

```powershell
Test-Path E:\BalatroLLM\.venv\Scripts\python.exe
Test-Path E:\BalatroLLM\balatro_mcp_stdio.py
```

两条都应返回 `True`。

---

## 7. 常见问题

1. 工具看不到 `balatro`
- 通常是客户端配置文件没放对位置，或 JSON 格式错误。
- 处理：检查配置路径，校验 JSON，然后重启客户端。

2. 报 `mod_unreachable` / 连不上 `127.0.0.1:12346`
- 通常是 Balatro 没启动，或者 mod 没加载。
- 处理：先启动游戏，再确认 `%APPDATA%\Balatro\Mods\balatro_mcp` 文件完整。

3. 另一台电脑路径不同
- 例如仓库放在 `D:\Projects\BalatroLLM`。
- 处理：把所有配置里的 `command` 和 `args` 改成新路径。

---

## 8. 最小可用结论

在新电脑上，最少需要做三件事：

1. 部署 mod（`tools/deploy_mod.ps1`）
2. 安装 Python 依赖（`pip install -e .[dev]`）
3. 给 AI 客户端写 MCP 配置（`mcp.json`/`config.json`）

完成后即可让 Agent 直接通过工具控制 Balatro。
