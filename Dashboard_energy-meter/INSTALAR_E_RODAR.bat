@echo off
setlocal
cd /d "%~dp0"
echo Instalando dependencias...
call npm install
if errorlevel 1 (
  pause
  exit /b 1
)
echo.
echo Iniciando o dashboard em uma janela separada...
start "Dashboard Energy Meter" cmd /k "npm run dev"
timeout /t 2 /nobreak >nul
start "" "http://localhost:5173/"
endlocal
