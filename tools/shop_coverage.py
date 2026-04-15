from __future__ import annotations

import json
import time
import urllib.request
from pathlib import Path
from typing import Any

BASE = "http://127.0.0.1:8000"
OUT_FILE = Path("e:/BalatroLLM/tools/shop_coverage_result.json")


def post(path: str, payload: dict[str, Any], timeout_s: float = 20.0) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        BASE + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        return json.loads(resp.read().decode("utf-8"))


def mcp(name: str, arguments: dict[str, Any], timeout_s: float = 20.0) -> Any:
    return post("/mcp/call", {"name": name, "arguments": arguments}, timeout_s=timeout_s).get("content")


def action(action_type: str, params: dict[str, Any] | None = None, timeout_s: float = 8.0) -> dict[str, Any]:
    timeout_ms = max(1000, int(timeout_s * 1000))
    c = mcp(
        "execute_action",
        {
            "action_type": action_type,
            "params": params or {},
            "relay": True,
            "wait_for_result": True,
            "timeout_ms": timeout_ms,
        },
        timeout_s=(timeout_s + 8.0),
    )
    if not c.get("queued", True):
        return {
            "command_id": None,
            "result": {
                "success": False,
                "error": str(c.get("error") or "enqueue_rejected"),
                "warnings": ["relay_enqueue_rejected"],
            },
        }
    result = c.get("result")
    if result is None:
        return {
            "command_id": c.get("command_id"),
            "result": {
                "success": False,
                "error": "timeout_waiting_result",
                "warnings": [],
            },
        }
    return result


def ensure_shop(max_steps: int = 40, max_runtime_s: float = 120.0) -> dict[str, Any]:
    started = time.time()
    for _ in range(max_steps):
        if time.time() - started > max_runtime_s:
            break

        s = mcp("get_game_state", {})
        phase = s.get("phase")
        if phase == "shop":
            return s

        if phase == "menu":
            action("continue", timeout_s=2.5)
        elif phase == "blind_select":
            action("choose_option", {"option_id": "small"}, timeout_s=2.5)
        elif phase == "in_round":
            hand = s.get("hand") or []
            ids = [c.get("card_id") for c in hand[:1] if c.get("card_id")]
            if len(ids) >= 1:
                action("play_hand", {"card_ids": ids}, timeout_s=3.0)
            else:
                action("end_turn", timeout_s=2.5)
        elif phase == "pack":
            action("skip", timeout_s=2.5)
        elif phase == "game_over":
            action("continue", timeout_s=2.5)

        time.sleep(0.35)

    return mcp("get_game_state", {})


def main() -> int:
    s = ensure_shop(max_steps=40, max_runtime_s=120.0)
    if s.get("phase") != "shop":
        out = {"shop_test": "not_reached", "phase": s.get("phase")}
        OUT_FILE.write_text(json.dumps(out, ensure_ascii=True), encoding="utf-8")
        print(json.dumps(out, ensure_ascii=True))
        return 1

    legal = mcp("list_legal_actions", {})
    legal_set = {x.get("action_type") for x in legal}

    reroll_result = None
    buy_result = None

    if "reroll_shop" in legal_set:
        reroll_result = action("reroll_shop")

    s2 = mcp("get_game_state", {})
    items = ((s2.get("shop") or {}).get("items") or [])
    if items and "buy_item" in legal_set:
        buy_result = action("buy_item", {"item_id": items[0].get("item_id")})

    out = {
        "shop_test": "reached",
        "phase": s2.get("phase"),
        "item_count": len(items),
        "reroll": reroll_result,
        "buy_item": buy_result,
    }
    OUT_FILE.write_text(json.dumps(out, ensure_ascii=True), encoding="utf-8")
    print(json.dumps(out, ensure_ascii=True))

    ok = True
    if reroll_result is not None and not reroll_result.get("result", {}).get("success"):
        ok = False
    if buy_result is not None and not buy_result.get("result", {}).get("success"):
        ok = False
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
