from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request
from dataclasses import dataclass, field
from typing import Any

MOD_URL = "http://127.0.0.1:12346"
MCP_URL = f"{MOD_URL}/mcp/call"
STATUS_URL = f"{MOD_URL}/health"
REPORT_PATH = Path(__file__).resolve().parent / "out" / "auto_full_e2e_report.json"
STALE_HEARTBEAT_SECONDS = 10.0
PHASE_STALL_SECONDS = 30.0
MAX_CONSECUTIVE_STALE_LOOPS = 12
RETRYABLE_ACTION_ERRORS = {
    "timeout_waiting_result",
    "mod_heartbeat_stale",
    "action_cooldown",
    # Mod is busy with animation (DRAW_TO_HAND / HAND_PLAYED); retry after brief wait
    "control_paused",
}


def get_json(url: str) -> dict[str, Any]:
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=3) as resp:
        return json.loads(resp.read().decode("utf-8"))


def post_json(url: str, payload: dict[str, Any], timeout_s: float = 20.0) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        return json.loads(resp.read().decode("utf-8"))


def mcp_call(name: str, arguments: dict[str, Any], timeout_s: float = 20.0) -> Any:
    return post_json(MCP_URL, {"name": name, "arguments": arguments}, timeout_s=timeout_s).get("content")


def get_mod_health() -> dict[str, Any]:
    return get_json(STATUS_URL)


def mod_is_alive(max_age_s: float = STALE_HEARTBEAT_SECONDS) -> bool:
    try:
        health = get_mod_health()
        return health.get("status") == "ok"
    except Exception:
        return False


def execute_action(action_type: str, params: dict[str, Any] | None = None, timeout_s: float = 6.0) -> dict[str, Any]:
    resp = mcp_call(
        "execute_action",
        {"action_type": action_type, "params": params or {}},
        timeout_s=timeout_s,
    )
    result = resp.get("content") if isinstance(resp, dict) and "content" in resp else resp
    if result is None:
        result = {"success": False, "error": "no_content"}
    return {"result": result}


def execute_action_with_retry(
    action_type: str,
    params: dict[str, Any] | None = None,
    timeout_s: float = 6.0,
    attempts: int = 2,
) -> dict[str, Any]:
    for attempt in range(1, attempts + 1):
        call_params = dict(params or {})
        if action_type == "select_card" and attempt > 1:
            fresh_state = mcp_call("get_game_state", {})
            fresh_hand = fresh_state.get("hand") or []
            if fresh_hand and fresh_hand[0].get("card_id"):
                call_params["card_id"] = fresh_hand[0]["card_id"]

        relay_result = execute_action(action_type, params=call_params, timeout_s=timeout_s)
        result = relay_result.get("result", {})
        if result.get("success"):
            return relay_result

        err = str(result.get("error") or "")
        if err == "card_not_found" and action_type == "select_card" and attempt < attempts:
            backoff = 0.2 * attempt
            print(f"[auto] retry action={action_type} attempt={attempt + 1}/{attempts} reason={err}")
            time.sleep(backoff)
            continue

        if err not in RETRYABLE_ACTION_ERRORS or attempt == attempts:
            return relay_result

        if err == "mod_heartbeat_stale":
            wait_heartbeat(timeout_s=12.0)

        backoff = 0.25 * attempt
        print(f"[auto] retry action={action_type} attempt={attempt + 1}/{attempts} reason={err}")
        time.sleep(backoff)

    return {"command_id": None, "result": {"success": False, "error": "retry_exhausted", "warnings": []}}


def restart_balatro() -> None:
    # Kill existing instance and wait for it to fully exit before starting a new one.
    # lovely-injector deletes the game-dump dir on startup; if the old process still
    # holds a lock on that directory the new instance will crash immediately.
    kill_cmd = (
        "$p = Get-Process -Name 'Balatro' -ErrorAction SilentlyContinue;"
        "if($p){"
        "  $p | Stop-Process -Force;"
        "  $p | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue;"
        "  Write-Output 'Stopped Balatro';"
        "}"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", kill_cmd], check=False)
    time.sleep(2.0)  # extra grace period for file handles to release

    # Remove lovely's dump directories so it can recreate them cleanly on startup.
    # lovely-injector crashes if it can't delete these (file-locked by old process).
    for dump_dir in ("game-dump", "dump"):
        subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             f"Remove-Item 'C:\\Users\\ZacPC\\AppData\\Roaming\\Balatro\\Mods\\lovely\\{dump_dir}'"
             " -Recurse -Force -ErrorAction SilentlyContinue"],
            check=False,
        )

    start_cmd = (
        "$exe='D:\\steam\\steamapps\\common\\Balatro\\Balatro.exe';"
        "if(Test-Path $exe){Start-Process -FilePath $exe; Write-Output 'Started Balatro';}"
        "else{Start-Process 'steam://rungameid/2379780'; Write-Output 'Started via Steam URI';}"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", start_cmd], check=False)


def wait_heartbeat(timeout_s: float = 30.0) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if mod_is_alive():
            return True
        time.sleep(0.5)
    return False


@dataclass
class TestState:
    success_actions: set[str] = field(default_factory=set)
    failed_actions: dict[str, str] = field(default_factory=dict)


TARGET_ACTIONS = {
    "continue",
    "choose_option",
    "skip",
    "select_card",
    "deselect_card",
    "play_hand",
    "discard_selected",
    "end_turn",
    "buy_item",
    "reroll_shop",
}


def mark_result(ts: TestState, action: str, relay_result: dict[str, Any]) -> None:
    result = relay_result.get("result", {})
    if result.get("success"):
        ts.success_actions.add(action)
        ts.failed_actions.pop(action, None)
    else:
        ts.failed_actions[action] = str(result.get("error") or "unknown_error")


RANK_ORDER = {"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"10":10,"Jack":10,"Queen":10,"King":10,"Ace":11}


def ids_from_hand(state: dict[str, Any], max_cards: int = 5) -> list[str]:
    hand = state.get("hand") or []
    return [c.get("card_id") for c in hand[:max_cards] if c.get("card_id")]


def best_play_ids(state: dict[str, Any]) -> list[str]:
    """Pick up to 5 cards that form the highest-scoring hand."""
    hand = [c for c in (state.get("hand") or []) if c.get("card_id")]
    if not hand:
        return []

    from collections import Counter
    rank_groups: dict[str, list[dict]] = {}
    suit_groups: dict[str, list[dict]] = {}
    for c in hand:
        rank_groups.setdefault(c.get("rank","?"), []).append(c)
        suit_groups.setdefault(c.get("suit","?"), []).append(c)

    # Three of a kind (or better)
    triples = [cards for cards in rank_groups.values() if len(cards) >= 3]
    if triples:
        best = sorted(triples, key=lambda g: RANK_ORDER.get(g[0].get("rank","2"), 2), reverse=True)[0]
        chosen = best[:3]
        # Fill remaining slots with highest-value cards not in chosen
        chosen_ids = {c["card_id"] for c in chosen}
        fillers = sorted([c for c in hand if c["card_id"] not in chosen_ids],
                         key=lambda c: RANK_ORDER.get(c.get("rank","2"), 2), reverse=True)
        return [c["card_id"] for c in chosen + fillers[:2]]

    # Flush (5+ same suit)
    flushes = [cards for cards in suit_groups.values() if len(cards) >= 5]
    if flushes:
        best = sorted(flushes, key=lambda g: sum(RANK_ORDER.get(c.get("rank","2"),2) for c in g), reverse=True)[0]
        return [c["card_id"] for c in best[:5]]

    # Two pair
    pairs = [cards for cards in rank_groups.values() if len(cards) >= 2]
    if len(pairs) >= 2:
        pairs.sort(key=lambda g: RANK_ORDER.get(g[0].get("rank","2"), 2), reverse=True)
        chosen = pairs[0][:2] + pairs[1][:2]
        chosen_ids = {c["card_id"] for c in chosen}
        fillers = sorted([c for c in hand if c["card_id"] not in chosen_ids],
                         key=lambda c: RANK_ORDER.get(c.get("rank","2"), 2), reverse=True)
        return [c["card_id"] for c in chosen + fillers[:1]]

    # One pair
    if pairs:
        chosen = pairs[0][:2]
        chosen_ids = {c["card_id"] for c in chosen}
        fillers = sorted([c for c in hand if c["card_id"] not in chosen_ids],
                         key=lambda c: RANK_ORDER.get(c.get("rank","2"), 2), reverse=True)
        return [c["card_id"] for c in chosen + fillers[:3]]

    # High card: pick 5 highest-value cards
    ranked = sorted(hand, key=lambda c: RANK_ORDER.get(c.get("rank","2"), 2), reverse=True)
    return [c["card_id"] for c in ranked[:5]]


def recovery_action_for_phase(phase: str, legal_set: set[str], state: dict[str, Any]) -> tuple[str, dict[str, Any]] | None:
    if phase in {"menu", "round_eval", "game_over"} and "continue" in legal_set:
        return "continue", {}

    if phase == "blind_select":
        if "choose_option" in legal_set:
            return "choose_option", {"option_id": "small"}
        if "skip" in legal_set:
            return "skip", {}

    if phase == "in_round":
        card_ids = ids_from_hand(state)
        if "play_hand" in legal_set and card_ids:
            return "play_hand", {"card_ids": card_ids}
        if "end_turn" in legal_set:
            return "end_turn", {}
        if "continue" in legal_set:
            return "continue", {}

    if phase == "shop":
        if "end_turn" in legal_set:
            return "end_turn", {}
        if "continue" in legal_set:
            return "continue", {}
        if "reroll_shop" in legal_set:
            return "reroll_shop", {}

    if phase == "pack" and "skip" in legal_set:
        return "skip", {}

    return None


def write_report(ts: TestState, elapsed_s: float, exit_code: int) -> None:
    missing = sorted(TARGET_ACTIONS - ts.success_actions)
    payload = {
        "timestamp": int(time.time()),
        "elapsed_seconds": round(elapsed_s, 3),
        "exit_code": exit_code,
        "success_actions": sorted(ts.success_actions),
        "failed_actions": ts.failed_actions,
        "missing_actions": missing,
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"[auto] report_path={REPORT_PATH}")


def pick_and_execute(
    ts: TestState,
    state: dict[str, Any],
    legal: list[dict[str, Any]],
    phase_loop_count: int,
    prev_action_type: str | None,
    prev_action_age_s: float,
) -> tuple[str | None, dict[str, Any] | None]:
    phase = state.get("phase")
    legal_set = {x.get("action_type") for x in legal}

    if phase == "menu" and "continue" in legal_set and phase_loop_count <= 2:
        return "continue", execute_action_with_retry("continue")

    if phase in {"round_eval", "game_over"} and "continue" in legal_set:
        if prev_action_type == "continue" and prev_action_age_s < 1.5:
            return None, None
        return "continue", execute_action_with_retry("continue", {}, timeout_s=20.0)

    if phase == "blind_select":
        if prev_action_type in {"choose_option", "skip"} and prev_action_age_s < 1.1:
            return None, None
        # Test skip on the very first blind_select visit (phase_loop_count==1) so
        # we don't have to wait for a second step that may never come.
        if "skip" in legal_set and "skip" not in ts.success_actions:
            return "skip", execute_action_with_retry("skip")
        if "choose_option" in legal_set:
            return "choose_option", execute_action_with_retry("choose_option", {"option_id": "small"})
        if "skip" in legal_set:
            return "skip", execute_action_with_retry("skip")

    if phase == "in_round":
        if prev_action_type in {"play_hand", "discard_selected"} and prev_action_age_s < 1.5:
            return None, None
        hand = state.get("hand") or []
        action_points = state.get("action_points") or {}
        hands_left = int(action_points.get("hands_left") or 0)
        discards_left = int(action_points.get("discards_left") or 0)
        if hand:
            first = hand[0].get("card_id")
            # Coverage probes: do these once, then prioritize phase progression.
            if first and "select_card" in legal_set and "select_card" not in ts.success_actions:
                return "select_card", execute_action_with_retry("select_card", {"card_id": first})
            if first and "deselect_card" in legal_set and "deselect_card" not in ts.success_actions:
                return "deselect_card", execute_action_with_retry("deselect_card", {"card_id": first})
            if first and "discard_selected" in legal_set and "discard_selected" not in ts.success_actions and discards_left > 0:
                execute_action_with_retry("select_card", {"card_id": first})
                return "discard_selected", execute_action_with_retry("discard_selected")

            # Play the best possible hand to maximise score and reach the shop.
            if "play_hand" in legal_set and hands_left > 0 and len(hand) >= 1:
                ids = best_play_ids(state)
                if not ids:
                    return None, None
                return "play_hand", execute_action_with_retry("play_hand", {"card_ids": ids}, timeout_s=15.0)

            if "end_turn" in legal_set and hands_left <= 0:
                return "end_turn", execute_action_with_retry("end_turn")

    if phase == "shop":
        shop_data = state.get("shop") or {}
        items = shop_data.get("items") or []
        money = (state.get("resources") or {}).get("money", 0)

        # Shop items may not be populated yet when the shop first opens (timing).
        # G.shop_jokers.cards is filled async; retry a few times before giving up.
        if not items and "buy_item" in legal_set:
            for _ in range(3):
                time.sleep(0.5)
                fresh = mcp_call("get_game_state", {})
                items = (fresh.get("shop") or {}).get("items") or []
                money = (fresh.get("resources") or {}).get("money", 0)
                if items:
                    break

        # Try to buy an affordable item BEFORE rerolling (reroll costs money).
        if "buy_item" in legal_set and "buy_item" not in ts.success_actions:
            affordable = [
                it for it in items
                if it.get("item_id") and (it.get("price") or 999) <= money
            ]
            if affordable:
                return "buy_item", execute_action_with_retry("buy_item", {"item_id": affordable[0]["item_id"]})
            # Can't afford any item; reroll to get cheaper/different items.
            if "reroll_shop" in legal_set and "reroll_shop" not in ts.success_actions:
                return "reroll_shop", execute_action_with_retry("reroll_shop")
            # Can't buy or reroll; skip buy_item for this visit.

        # Test reroll if not yet done.
        if "reroll_shop" in legal_set and "reroll_shop" not in ts.success_actions:
            return "reroll_shop", execute_action_with_retry("reroll_shop")

        # Leave shop: use end_turn to test it (it works in shop — routes through continue_flow).
        if "end_turn" in legal_set and "end_turn" not in ts.success_actions:
            return "end_turn", execute_action_with_retry("end_turn")
        if "continue" in legal_set:
            return "continue", execute_action_with_retry("continue")

    if phase == "pack":
        if "skip" in legal_set:
            return "skip", execute_action_with_retry("skip")

    # fallback: try any legal action minimally
    if legal:
        preferred = [
            x.get("action_type")
            for x in legal
            if x.get("action_type") not in ts.success_actions
        ]
        act = (preferred[0] if preferred else legal[0].get("action_type"))

        if act == "continue" and act in ts.success_actions:
            return None, None
        if act == "choose_option":
            return act, execute_action_with_retry(act, {"option_id": "small"})
        if act in {"select_card", "deselect_card"}:
            hand = state.get("hand") or []
            if hand:
                return act, execute_action_with_retry(act, {"card_id": hand[0].get("card_id")})
        if act == "play_hand":
            hand = state.get("hand") or []
            ids = [c.get("card_id") for c in hand[:1] if c.get("card_id")]
            if len(ids) < 1:
                return None, None
            return act, execute_action_with_retry(act, {"card_ids": ids}, timeout_s=15.0)
        return act, execute_action_with_retry(act)

    return None, None


def main() -> int:
    print("[auto] restarting Balatro...")
    restart_balatro()
    if not wait_heartbeat():
        print("[auto] mod not reachable after restart")
        return 2

    ts = TestState()
    start = time.time()
    max_steps = int(os.getenv("AUTO_E2E_MAX_STEPS", "150"))
    max_runtime_s = float(os.getenv("AUTO_E2E_MAX_RUNTIME", "240"))
    last_phase: str | None = None
    phase_stable_since = time.time()
    phase_loop_count = 0
    consecutive_stale_loops = 0
    last_action_type: str | None = None
    last_action_at = time.time()

    for step in range(1, max_steps + 1):
        if not mod_is_alive():
            consecutive_stale_loops += 1
            print(f"[auto] mod unreachable loop={consecutive_stale_loops}")
            if consecutive_stale_loops >= MAX_CONSECUTIVE_STALE_LOOPS:
                print("[auto] stale heartbeat persisted; restarting Balatro for recovery")
                restart_balatro()
                if not wait_heartbeat(timeout_s=45.0):
                    print("[auto] heartbeat did not recover after restart")
                    return 3
                consecutive_stale_loops = 0
            time.sleep(1.0)
            continue

        consecutive_stale_loops = 0

        state = mcp_call("get_game_state", {})
        legal = mcp_call("list_legal_actions", {})
        phase = state.get("phase")
        print(f"[auto] step={step} phase={phase} legal={[x.get('action_type') for x in legal]}")

        now = time.time()
        if phase != last_phase:
            last_phase = phase
            phase_stable_since = now
            phase_loop_count = 1
        else:
            phase_loop_count += 1

        if phase == "blind_select" and phase_loop_count >= 4:
            legal_set = {x.get("action_type") for x in legal}
            if "choose_option" in legal_set:
                print("[auto] blind_select linger; forcing choose_option")
                relay_result = execute_action_with_retry("choose_option", {"option_id": "small"})
                mark_result(ts, "choose_option", relay_result)
                r = relay_result.get("result", {})
                print(f"[auto] forced-choose success={r.get('success')} error={r.get('error')}")
                time.sleep(0.5)
                continue

        # NOTE: this block must be at the same indent level as blind_select, not nested inside it
        if phase == "in_round" and phase_loop_count >= 8:
            legal_set = {x.get("action_type") for x in legal}
            hand = state.get("hand") or []
            action_points = state.get("action_points") or {}
            hands_left = int(action_points.get("hands_left") or 0)
            if "play_hand" in legal_set and hands_left > 0 and hand:
                ids = [c.get("card_id") for c in hand[:5] if c.get("card_id")]
                if ids:
                    print(f"[auto] in_round linger ({phase_loop_count} loops); forcing play_hand")
                    relay_result = execute_action_with_retry("play_hand", {"card_ids": ids}, timeout_s=12.0)
                    mark_result(ts, "play_hand", relay_result)
                    r = relay_result.get("result", {})
                    print(f"[auto] forced-play_hand success={r.get('success')} error={r.get('error')}")
                    time.sleep(0.8)
                    continue
            if "end_turn" in legal_set and hands_left <= 0:
                print("[auto] in_round linger (8+ loops); forcing end_turn to unblock shop entry")
                relay_result = execute_action_with_retry("end_turn", {})
                mark_result(ts, "end_turn", relay_result)
                r = relay_result.get("result", {})
                print(f"[auto] forced-end_turn success={r.get('success')} error={r.get('error')}")
                time.sleep(0.5)
                continue

        if (now - phase_stable_since) > PHASE_STALL_SECONDS:
            legal_set = {x.get("action_type") for x in legal}
            fallback = recovery_action_for_phase(phase, legal_set, state)
            if fallback is not None:
                action, params = fallback
                print(f"[auto] phase stall detected; recovery action={action} phase={phase}")
                relay_result = execute_action_with_retry(action, params)
                mark_result(ts, action, relay_result)
                r = relay_result.get("result", {})
                print(f"[auto] recovery success={r.get('success')} error={r.get('error')}")
                phase_stable_since = now
                time.sleep(0.4)
                continue

        action, relay_result = pick_and_execute(
            ts,
            state,
            legal,
            phase_loop_count,
            last_action_type,
            time.time() - last_action_at,
        )
        if action and relay_result:
            mark_result(ts, action, relay_result)
            r = relay_result.get("result", {})
            # A long-running action (play_hand ~15s) can make the elapsed time
            # since last phase change look like a stall. Reset the clock so the
            # next loop iteration doesn't immediately trigger stall recovery.
            phase_stable_since = time.time()
            print(f"[auto] action={action} success={r.get('success')} error={r.get('error')}")
            last_action_type = action
            last_action_at = time.time()

        if TARGET_ACTIONS.issubset(ts.success_actions):
            break

        time.sleep(0.4)

        if time.time() - start > max_runtime_s:
            break

    print("[auto] success_actions:", sorted(ts.success_actions))
    print("[auto] failed_actions:", ts.failed_actions)

    missing = sorted(TARGET_ACTIONS - ts.success_actions)
    if missing:
        print("[auto] missing:", missing)
        write_report(ts, time.time() - start, 1)
        return 1

    write_report(ts, time.time() - start, 0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
