from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

MOD_URL = "http://127.0.0.1:12346"

app = FastAPI(title="Balatro MCP Server", version="0.2.0")


class ToolCallBody(BaseModel):
    name: str
    arguments: dict = Field(default_factory=dict)


def _mod_get(path: str) -> Any:
    try:
        with urllib.request.urlopen(f"{MOD_URL}{path}", timeout=5) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.URLError as exc:
        raise HTTPException(status_code=503, detail=f"Mod unreachable: {exc}")


def _mod_post(path: str, payload: dict) -> Any:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{MOD_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.URLError as exc:
        raise HTTPException(status_code=503, detail=f"Mod unreachable: {exc}")


@app.get("/health")
def health() -> dict:
    return _mod_get("/health")


@app.get("/mcp/tools")
def list_tools() -> dict:
    return _mod_get("/mcp/tools")


@app.post("/mcp/call")
def call_tool(body: ToolCallBody) -> dict:
    return _mod_post("/mcp/call", {"name": body.name, "arguments": body.arguments})
