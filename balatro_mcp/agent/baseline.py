from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class BaselineDecision:
    reasoning: str
    action: dict[str, Any]


def choose_action(game_state: dict[str, Any], legal_actions: list[dict[str, Any]]) -> BaselineDecision:
    """Simple heuristic baseline for initial smoke testing.

    Strategy:
    - In round: prefer play_hand, fallback discard_selected, fallback end_turn.
    - In shop: buy first affordable item, else continue.
    - Otherwise: continue/skip first available.
    """

    phase = game_state.get("phase")
    action_types = [a.get("action_type") for a in legal_actions]

    if phase == "in_round":
        if "play_hand" in action_types:
            return BaselineDecision("play when possible", {"action_type": "play_hand", "params": {}})
        if "discard_selected" in action_types:
            return BaselineDecision("discard fallback", {"action_type": "discard_selected", "params": {}})
        if "end_turn" in action_types:
            return BaselineDecision("end turn fallback", {"action_type": "end_turn", "params": {}})

    if phase == "shop" and "buy_item" in action_types:
        money = game_state.get("resources", {}).get("money", 0)
        for item in game_state.get("shop", {}).get("items", []):
            if item.get("price", 9999) <= money:
                return BaselineDecision("buy affordable item", {"action_type": "buy_item", "params": {"item_id": item.get("item_id")}})

    for candidate in ["continue", "skip"]:
        if candidate in action_types:
            return BaselineDecision("advance flow", {"action_type": candidate, "params": {}})

    if legal_actions:
        first = legal_actions[0]
        return BaselineDecision("default first legal action", {"action_type": first.get("action_type"), "params": {}})

    return BaselineDecision("no-op", {"action_type": "continue", "params": {}})
