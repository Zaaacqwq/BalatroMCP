# Balatro MCP

Balatro MCP is a bridge between Balatro, a local game mod, and MCP-compatible AI clients. It combines a Lua mod that exposes the game state and accepts actions with a Python MCP server that turns those game capabilities into tools for Copilot, Cursor, Claude, Codex, and similar clients.

## What's In The Repo

- A Balatro mod scaffold under `mod/` that runs inside the game and exposes a local HTTP bridge.
- A Python stdio MCP bridge in `balatro_mcp_stdio.py` for AI clients.
- A FastAPI proxy server in `balatro_mcp.mcp_server.server` for local HTTP access and debugging.
- A strategy pack in `strategy/` for keeping decision policy outside the model prompt.
- Example MCP configuration files in `mcp_configs/` for common clients.
- Tests and utility scripts for bridge, server, and strategy validation.

## How It Works

The runtime flow is:

1. Balatro loads the Lua mod from `mod/`.
2. The mod exposes its HTTP bridge on `127.0.0.1:12346`.
3. The Python MCP bridge connects to that mod bridge.
4. MCP clients call tools like `get_game_state`, `list_legal_actions`, and `play_hand`.
5. The bridge forwards the request to the mod, which applies the action in game.

The stdio bridge is the main integration path for AI clients. The FastAPI app is optional and useful for local inspection or when you want an HTTP service around the same mod bridge.

## Available Tools

The stdio bridge exposes these MCP tools:

- `get_game_state`
- `list_legal_actions`
- `continue_run`
- `choose_option`
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
- `get_action_history`
- `get_run_summary`

## Requirements

- Windows is the primary target in this workspace.
- Python 3.10 or newer.
- Balatro installed locally.
- A working Balatro mod deployment.

## Quick Start

### 1. Install Python dependencies

From the repository root:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -U pip
python -m pip install -e .[dev]
```

### 2. Deploy the Balatro mod

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy_mod.ps1
```

This copies the contents of `mod/` into the Balatro mods directory under `%APPDATA%\Balatro\Mods\balatro_mcp`.

### 3. Start Balatro

Launch the game first so the mod-side bridge is available at `http://127.0.0.1:12346`.

### 4. Start or configure your MCP client

Point the client at the stdio entrypoint:

```powershell
E:\BalatroLLM\.venv\Scripts\python.exe E:\BalatroLLM\balatro_mcp_stdio.py
```

You can also use the installed console script after installation:

```powershell
balatro-mcp
```

## MCP Client Examples

The `mcp_configs/` directory contains example configurations for:

- VS Code
- Cursor
- Claude Desktop
- OpenAI Codex CLI

Adjust the Python executable and repository path to match your machine before using them.

## Optional HTTP Server

If you want an HTTP layer around the mod bridge, run the FastAPI app:

```powershell
uvicorn balatro_mcp.mcp_server.server:app --reload
```

The server exposes:

- `GET /health`
- `GET /mcp/tools`
- `POST /mcp/call`

It proxies requests to the mod bridge at `127.0.0.1:12346`.

## Strategy Pack

The `strategy/` directory holds a portable strategy layer for Balatro-focused agents.

Use it to keep decision policy outside the prompt. The main files are:

- `strategy/BALATRO_STRATEGY_SPEC.md`
- `strategy/llm_decision_template.md`
- `strategy/deck_profiles.yaml`
- `strategy/stake_adjustments.yaml`
- `strategy/shop_policy.yaml`

The intended flow is:

1. Load the strategy spec.
2. Call `get_game_state`.
3. Call `list_legal_actions`.
4. Inject only the relevant strategy fragments for the current deck, stake, blind, and shop context.
5. Choose exactly one legal action.

## Repository Layout

- `balatro_mcp/`: Python package for the MCP server.
- `balatro_mcp_stdio.py`: stdio MCP entrypoint.
- `mod/`: Balatro Lua mod scaffold and web assets.
- `strategy/`: strategy prompts, policy, and tuning data.
- `mcp_configs/`: sample client configs.
- `schemas/`: JSON schemas for game state and protocol payloads.
- `tests/`: automated tests for the Python bridge and strategy loader.
- `tools/`: deployment, probing, and replay utilities.

## Development

Run tests with:

```powershell
pytest
```

Common local checks:

```powershell
python -m pip install -e .[dev]
uvicorn balatro_mcp.mcp_server.server:app --reload
```

## Troubleshooting

- If MCP tools do not appear, verify the client config points to the correct Python executable and `balatro_mcp_stdio.py` path.
- If the bridge reports `mod_unreachable`, make sure Balatro is running and the mod has loaded.
- If the mod files are missing, rerun `tools/deploy_mod.ps1`.
- If you are moving the repo to another machine, update the absolute paths in the example configs.

## Related Docs

- `HOW_TO_CONNECT.md`
- `README_INSTALL_NEW_PC.md`
- `docs/mod-integration.md`
