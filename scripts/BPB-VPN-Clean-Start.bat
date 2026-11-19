@echo off
setlocal
cd /d "%~dp0"
start "" "%~dp0BPB-VPN.exe" --bpb-clean-start
endlocal
