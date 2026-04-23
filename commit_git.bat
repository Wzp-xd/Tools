@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===== Git commit helper =====
REM Default commit message: current datetime (yyyy-MM-dd HH:mm:ss)

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 1
)

for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set "MSG=%%t"
if "!MSG!"=="" (
  echo [ERROR] Failed to get current datetime.
  pause
  exit /b 1
)

echo [INFO] Commit message: !MSG!
echo.
echo [1/4] git add -A
git add -A
if errorlevel 1 goto :fail

echo [2/4] git commit -m "!MSG!"
git commit -m "!MSG!"
if errorlevel 1 goto :fail

echo [3/4] Detect current branch
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set BRANCH=%%b
if "!BRANCH!"=="" (
  echo [ERROR] Failed to detect current branch.
  goto :fail
)

echo [4/4] git push origin !BRANCH!
git push origin !BRANCH!
if errorlevel 1 goto :fail

echo.
echo [OK] Commit and push completed on branch: !BRANCH!
pause
exit /b 0

:fail
echo.
echo [ERROR] Failed. Check logs above.
pause
exit /b 1
