@echo off
rem Double-click wrapper for install.ps1. Pass-through args, e.g.:  install.cmd -SubagentModel haiku
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
