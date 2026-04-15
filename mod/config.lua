local M = {}

M.bridge_base_url = "http://127.0.0.1:8000"
M.enable_bridge_client = false
M.snapshot_interval_seconds = 0.20
M.command_poll_interval_seconds = 0.05
M.http_timeout_seconds = 0.5
M.enable_heartbeat = true
M.heartbeat_interval_seconds = 2.0

M.enable_embedded_api = true
M.embedded_api_host = "127.0.0.1"
M.embedded_api_port = 12346
M.embedded_api_max_history = 200
M.log_prefix = "[balatro-mcp-mod]"

return M
