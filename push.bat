@echo off
cd /d D:\AI\GodotProject\MiniWoW\MiniWoW

echo ==========================================
echo    MiniWoW 一键备份推送（自动写注释）
echo ==========================================
echo.

git add -A
if errorlevel 1 goto :fail_add

set "changed=0"
for /f %%c in ('git status --porcelain ^| find /c /v ""') do set "changed=%%c"

if "%changed%"=="0" goto :no_change

for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "stamp=%%i"
echo [提交] MiniWoW 备份 %stamp%（%changed% 个文件变动）
git commit -m "MiniWoW 备份 %stamp%（%changed% 个文件变动）"
if errorlevel 1 goto :fail_commit
goto :push

:no_change
echo [提示] 没有检测到文件改动，跳过自动提交，直接推送。

:push
echo.
echo 正在推送到 GitHub ...
git push origin master:main
if errorlevel 1 goto :fail_push
git push origin --tags
if errorlevel 1 goto :fail_push

echo.
echo ==========================================
echo    推送成功！GitHub 仓库已更新
echo ==========================================
goto :end

:fail_add
echo [错误] git add 失败，请检查仓库状态。
goto :end

:fail_commit
echo [错误] git commit 失败，请检查仓库状态。
goto :end

:fail_push
echo.
echo [错误] 推送失败！常见原因：网络不通 / GitHub 登录过期。
echo        解决：重新双击本脚本，按提示完成 GitHub 登录后重试。
goto :end

:end
echo.
pause
