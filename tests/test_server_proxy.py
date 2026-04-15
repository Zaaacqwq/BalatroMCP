from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from balatro_mcp.mcp_server.server import app

client = TestClient(app)


def _mock_urlopen(response_data: dict):
    """Return a context-manager mock that yields a fake HTTP response."""
    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps(response_data).encode()
    mock_resp.__enter__ = lambda s: s
    mock_resp.__exit__ = MagicMock(return_value=False)
    return mock_resp


def test_health_proxies_to_mod():
    with patch("urllib.request.urlopen", return_value=_mock_urlopen({"status": "ok"})):
        resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_list_tools_proxies_to_mod():
    tools_payload = {"tools": [{"name": "get_game_state"}]}
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(tools_payload)):
        resp = client.get("/mcp/tools")
    assert resp.status_code == 200
    assert resp.json()["tools"][0]["name"] == "get_game_state"


def test_call_tool_get_game_state():
    state_payload = {"content": {"phase": "blind_select", "resources": {"money": 4}}}
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(state_payload)):
        resp = client.post("/mcp/call", json={"name": "get_game_state", "arguments": {}})
    assert resp.status_code == 200
    assert resp.json()["content"]["phase"] == "blind_select"


def test_call_tool_execute_action():
    result_payload = {"content": {"success": True}}
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(result_payload)):
        resp = client.post(
            "/mcp/call",
            json={"name": "execute_action", "arguments": {"action_type": "continue", "params": {}}},
        )
    assert resp.status_code == 200
    assert resp.json()["content"]["success"] is True


def test_mod_unreachable_returns_503():
    import urllib.error
    with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("refused")):
        resp = client.get("/health")
    assert resp.status_code == 503
    assert "Mod unreachable" in resp.json()["detail"]
