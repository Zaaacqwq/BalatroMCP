@echo off
cd /d %~dp0\..
C:\Users\ZacPC\AppData\Local\Programs\Python\Python310\python.exe -m uvicorn balatro_mcp.mcp_server.server:app --port 8000 --reload
