from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=2) as resp:
        return json.loads(resp.read().decode("utf-8"))


def post_json(url: str, payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=2) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Live probe for balatro bridge/mod connectivity")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--watch-seconds", type=int, default=10)
    args = parser.parse_args()

    status_url = f"{args.base_url}/bridge/mod/status"
    mcp_call_url = f"{args.base_url}/mcp/call"

    print("[probe] Checking bridge status...")
    try:
        initial = get_json(status_url)
    except urllib.error.URLError as exc:
        print(f"[probe] bridge unreachable: {exc}")
        return

    print(json.dumps({"initial_status": initial}, ensure_ascii=True))

    print("[probe] Queueing request_mod_snapshot and pause/resume commands...")
    for tool_name in ["request_mod_snapshot", "pause_mod_control", "resume_mod_control"]:
        result = post_json(mcp_call_url, {"name": tool_name, "arguments": {}})
        print(json.dumps({tool_name: result}, ensure_ascii=True))

    print("[probe] Watching status updates...")
    deadline = time.time() + args.watch_seconds
    while time.time() < deadline:
        try:
            s = get_json(status_url)
            print(json.dumps({
                "queue_depth": s.get("gateway", {}).get("queue_depth"),
                "known_results": s.get("gateway", {}).get("known_results"),
                "last_heartbeat": s.get("gateway", {}).get("last_heartbeat"),
                "state_version": s.get("state_version"),
                "phase": s.get("phase"),
            }, ensure_ascii=True))
        except Exception as exc:
            print(json.dumps({"error": str(exc)}, ensure_ascii=True))
        time.sleep(1)


if __name__ == "__main__":
    main()
