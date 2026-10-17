@echo off
rem ============================================================
rem MiniWoW one-click dual-client multiplayer test launcher
rem Client 1 auto-hosts (Host, blue), client 2 auto-joins (Client, yellow).
rem NOTE: keep this file ASCII-only + CRLF to avoid cmd encoding issues.
rem On another machine, just edit GODOT_EXE below.
rem ============================================================
set "GODOT_EXE=C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe"
set "PROJECT_DIR=%~dp0.."

echo [1/2] Launching client 1 (auto host)...
start "" "%GODOT_EXE%" --path "%PROJECT_DIR%" -- --auto host

echo Waiting 3 seconds for the host to be ready...
ping -n 4 127.0.0.1 >nul

echo [2/2] Launching client 2 (auto join)...
start "" "%GODOT_EXE%" --path "%PROJECT_DIR%" -- --auto join

echo.
echo Both clients launched. You should see each other in the world.
echo Close the game windows to end the test.
