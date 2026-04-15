import json
import time
import urllib.request

BASE = "http://127.0.0.1:8000"


def post(name: str, arguments: dict) -> dict:
    body = {"name": name, "arguments": arguments}
    req = urllib.request.Request(
        BASE + "/mcp/call",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())


def get_status() -> dict:
    with urllib.request.urlopen(BASE + "/bridge/mod/status", timeout=5) as resp:
        return json.loads(resp.read().decode())


print("step=continue")
print(json.dumps(post("execute_action", {
    "action_type": "continue",
    "params": {},
    "relay": True,
    "wait_for_result": True,
    "timeout_ms": 2500,
}), ensure_ascii=False))

for i in range(40):
    s = get_status()
    phase = s.get("phase")
    gw = s.get("gateway", {})
    print(f"status i={i} phase={phase} hb={gw.get('last_heartbeat')} q={gw.get('queue_depth')}")

    if phase == "blind_select":
        print("step=choose_option_small")
        print(json.dumps(post("execute_action", {
            "action_type": "choose_option",
            "params": {"option_id": "small"},
            "relay": True,
            "wait_for_result": True,
            "timeout_ms": 3000,
        }), ensure_ascii=False))

    if phase == "in_round":
        break

    time.sleep(0.8)

print("step=play_hand_empty")
print(json.dumps(post("execute_action", {
    "action_type": "play_hand",
    "params": {},
    "relay": True,
    "wait_for_result": True,
    "timeout_ms": 3000,
}), ensure_ascii=False))
