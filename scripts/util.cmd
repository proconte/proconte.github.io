@echo off
setx /M PATH "%PATH%;c:\util"
powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -Command Set-ExecutionPolicy Unrestricted -Force' -Verb RunAs"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0util.ps1"