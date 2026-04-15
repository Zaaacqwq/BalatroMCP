"""
Balatro MCP stdio server.

Bridges the Balatro mod HTTP API (127.0.0.1:12346) to the standard MCP
stdio transport so that Claude Desktop, Cursor, Copilot, Codex, and any
other MCP-compatible client can control the game.

Usage (the clients call this script automatically):
    python balatro_mcp_stdio.py

The script connects to the mod server that is already running inside
Balatro. Start the game before pointing a client at this bridge.
"""

from __future__ import annotations

import asyncio
import json
import urllib.error
import urllib.request
from typing import Any

import mcp.server.stdio
import mcp.types as types
from mcp.server import Server

MOD_URL = "http://127.0.0.1:12346"
HTTP_TIMEOUT = 25  # seconds; play_hand can take ~15 s to settle


def _post(path: str, payload: dict) -> Any:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{MOD_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as response:
            return json.loads(response.read().decode())
    except urllib.error.URLError as exc:
        return {"error": f"mod_unreachable: {exc}"}


def _mcp(name: str, arguments: dict | None = None) -> Any:
    return _post("/mcp/call", {"name": name, "arguments": arguments or {}})


def _execute_action(action_type: str, **params: Any) -> Any:
    return _mcp("execute_action", {"action_type": action_type, "params": params})


def _tool(name: str, description: str, properties: dict[str, Any] | None = None, required: list[str] | None = None) -> types.Tool:
    return types.Tool(
        name=name,
        description=description,
        inputSchema={
            "type": "object",
            "properties": properties or {},
            "required": required or [],
            "additionalProperties": False,
        },
    )


TOOLS: list[types.Tool] = [
    _tool(
        "get_game_state",
        "Return the current Balatro game state: phase, hand, shop items, money, score, blinds, etc. Call this first to understand the situation.",
    ),
    _tool(
        "list_legal_actions",
        "List every action that is currently legal given the game state. Always call this before executing an action.",
    ),
    _tool(
        "continue_run",
        "Advance through menu, round-eval, shop, or game-over screens when continue is legal.",
    ),
    _tool(
        "choose_option",
        "Choose an option during blind selection or pack choice screens using option_id from get_game_state or list_legal_actions.",
        properties={
            "option_id": {
                "type": "string",
                "description": "Option id from the game state or legal action list, such as 'small', 'big', 'boss', or a pack option id.",
            }
        },
        required=["option_id"],
    ),
    _tool(
        "choose_blind",
        "Alias for choose_option during blind selection. Prefer choose_option for general option-based flows.",
        properties={
            "option_id": {
                "type": "string",
                "description": "Option id from the game state or legal action list, such as 'small', 'big', or 'boss'.",
            }
        },
        required=["option_id"],
    ),
    _tool(
        "skip_choice",
        "Skip the current blind or pack choice when skip is legal.",
    ),
    _tool(
        "select_card",
        "Highlight one card in hand by card_id during in-round play.",
        properties={
            "card_id": {
                "type": "string",
                "description": "Card id from get_game_state.hand.cards[].id.",
            }
        },
        required=["card_id"],
    ),
    _tool(
        "deselect_card",
        "Remove highlight from one selected hand card by card_id.",
        properties={
            "card_id": {
                "type": "string",
                "description": "Card id from get_game_state.hand.cards[].id.",
            }
        },
        required=["card_id"],
    ),
    _tool(
        "play_hand",
        "Play a scored poker hand using the provided card_ids. Only pass cards that form the intended hand.",
        properties={
            "card_ids": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Ordered list of hand card ids to play.",
            }
        },
        required=["card_ids"],
    ),
    _tool(
        "discard_selected",
        "Discard the currently highlighted hand cards.",
    ),
    _tool(
        "end_turn",
        "Leave the shop or end the current step when end_turn is legal.",
    ),
    _tool(
        "buy_item",
        "Buy a shop item by item_id.",
        properties={
            "item_id": {
                "type": "string",
                "description": "Shop item id from get_game_state.shop.",
            }
        },
        required=["item_id"],
    ),
    _tool(
        "reroll_shop",
        "Spend money to reroll the shop when reroll is legal.",
    ),
    _tool(
        "sell_joker",
        "Sell a joker in the shop by joker_id when legal.",
        properties={
            "joker_id": {
                "type": "string",
                "description": "Joker id from get_game_state.jokers[].id.",
            }
        },
        required=["joker_id"],
    ),
    _tool(
        "use_consumable",
        "Use a consumable in the shop by consumable_id when legal.",
        properties={
            "consumable_id": {
                "type": "string",
                "description": "Consumable id from get_game_state.consumables[].id.",
            }
        },
        required=["consumable_id"],
    ),
    _tool(
        "get_action_history",
        "Return recent game actions and events for debugging.",
        properties={
            "limit": {
                "type": "integer",
                "description": "Number of history entries to return (default 20, max 200).",
                "minimum": 1,
                "maximum": 200,
            }
        },
    ),
    _tool(
        "get_run_summary",
        "Return a short summary of the current run (money, score, hands left, etc.).",
    ),
]

server = Server("balatro-mcp")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return TOOLS


async def _run_sync(callable_obj):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, callable_obj)


def _json_text(result: Any) -> list[types.TextContent]:
    return [types.TextContent(type="text", text=json.dumps(result, ensure_ascii=False, indent=2))]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    arguments = arguments or {}

    if name == "get_game_state":
        result = await _run_sync(lambda: _mcp("get_game_state"))
    elif name == "list_legal_actions":
        result = await _run_sync(lambda: _mcp("list_legal_actions"))
    elif name == "continue_run":
        result = await _run_sync(lambda: _execute_action("continue"))
    elif name == "choose_option":
        result = await _run_sync(lambda: _execute_action("choose_option", option_id=arguments["option_id"]))
    elif name == "choose_blind":
        result = await _run_sync(lambda: _execute_action("choose_option", option_id=arguments["option_id"]))
    elif name == "skip_choice":
        result = await _run_sync(lambda: _execute_action("skip"))
    elif name == "select_card":
        result = await _run_sync(lambda: _execute_action("select_card", card_id=arguments["card_id"]))
    elif name == "deselect_card":
        result = await _run_sync(lambda: _execute_action("deselect_card", card_id=arguments["card_id"]))
    elif name == "play_hand":
        result = await _run_sync(lambda: _execute_action("play_hand", card_ids=arguments["card_ids"]))
    elif name == "discard_selected":
        result = await _run_sync(lambda: _execute_action("discard_selected"))
    elif name == "end_turn":
        result = await _run_sync(lambda: _execute_action("end_turn"))
    elif name == "buy_item":
        result = await _run_sync(lambda: _execute_action("buy_item", item_id=arguments["item_id"]))
    elif name == "reroll_shop":
        result = await _run_sync(lambda: _execute_action("reroll_shop"))
    elif name == "sell_joker":
        result = await _run_sync(lambda: _execute_action("sell_joker", joker_id=arguments["joker_id"]))
    elif name == "use_consumable":
        result = await _run_sync(
            lambda: _execute_action("use_consumable", consumable_id=arguments["consumable_id"])
        )
    elif name == "get_action_history":
        limit = arguments.get("limit", 20)
        result = await _run_sync(lambda: _mcp("get_action_history", {"limit": limit}))
    elif name == "get_run_summary":
        result = await _run_sync(lambda: _mcp("get_run_summary"))
    else:
        result = {"error": f"unknown_tool: {name}"}

    return _json_text(result)


async def main() -> None:
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())
