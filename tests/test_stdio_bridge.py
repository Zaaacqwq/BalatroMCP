from __future__ import annotations

import asyncio
import json

from balatro_mcp_stdio import TOOLS, call_tool


def _tool_names() -> set[str]:
    return {tool.name for tool in TOOLS}


def _parse_text(result):
    assert len(result) == 1
    return json.loads(result[0].text)


def test_explicit_tools_are_exposed():
    names = _tool_names()
    assert "get_game_state" in names
    assert "list_legal_actions" in names
    assert "choose_option" in names
    assert "choose_blind" in names
    assert "play_hand" in names
    assert "buy_item" in names
    assert "sell_joker" in names
    assert "use_consumable" in names
    assert "execute_action" not in names


def test_choose_option_routes_to_execute_action(monkeypatch):
    called = {}

    def fake_execute_action(action_type: str, **params):
        called["action_type"] = action_type
        called["params"] = params
        return {"content": {"success": True}}

    monkeypatch.setattr("balatro_mcp_stdio._execute_action", fake_execute_action)
    result = asyncio.run(call_tool("choose_option", {"option_id": "small"}))
    payload = _parse_text(result)

    assert called == {"action_type": "choose_option", "params": {"option_id": "small"}}
    assert payload["content"]["success"] is True


def test_choose_blind_alias_routes_to_execute_action(monkeypatch):
    called = {}

    def fake_execute_action(action_type: str, **params):
        called["action_type"] = action_type
        called["params"] = params
        return {"content": {"success": True}}

    monkeypatch.setattr("balatro_mcp_stdio._execute_action", fake_execute_action)
    result = asyncio.run(call_tool("choose_blind", {"option_id": "boss"}))
    payload = _parse_text(result)

    assert called == {"action_type": "choose_option", "params": {"option_id": "boss"}}
    assert payload["content"]["success"] is True


def test_play_hand_routes_card_ids(monkeypatch):
    called = {}

    def fake_execute_action(action_type: str, **params):
        called["action_type"] = action_type
        called["params"] = params
        return {"content": {"success": True}}

    monkeypatch.setattr("balatro_mcp_stdio._execute_action", fake_execute_action)
    result = asyncio.run(call_tool("play_hand", {"card_ids": ["1", "2", "3", "4", "5"]}))
    payload = _parse_text(result)

    assert called == {
        "action_type": "play_hand",
        "params": {"card_ids": ["1", "2", "3", "4", "5"]},
    }
    assert payload["content"]["success"] is True
