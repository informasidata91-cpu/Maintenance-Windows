@echo off
setlocal EnableExtensions
cd /d "%~dp0"

cls
echo =============================================
echo Perawatan rutin sistem sedang dimulai
echo =============================================
timeout /t 2 >nul

:: -------------------------------
:: Konfigurasi
:: -------------------------------
set "SCRIPT=Maintenance.ps1"
set "URL=https://raw.githubusercontent.com/informasidata91-cpu/Maintenance-Windows/main/Maintenance.ps1"

:: 1) Cek Administrator; jika tidak, minta elevasi
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [!] Script ini memerlukan hak Administrator.
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  echo Jendela ini akan ditutup. Lanjutkan di jendela baru.
  exit /b
)
cd /d %SystemDrive%\
echo [i] Working directory sekarang: %CD%

:: 2) Mengunduh skrip PS1 (overwrite bila ada)
echo [i] Mengunduh Maintenance.ps1 dari repository...
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "try { $ErrorActionPreference='Stop'; Invoke-WebRequest -Uri '%URL%' -OutFile '%SCRIPT%' -UseBasicParsing -TimeoutSec 60; exit 0 } catch { exit 1 }"
set "DL_EC=%ERRORLEVEL%"

:: 3) Set Execution Policy sementara (Scope=Process) TANPA output
powershell -NoProfile -Command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force *> $null"

:: 4) Jalankan Maintenance.ps1
echo.
echo Menjalankan %SCRIPT% ...
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%"
set "EC=%ERRORLEVEL%"

echo.
echo ================================
echo Maintenance script selesai. Kode keluar: %EC%
echo ================================
pause

exit /b %EC%
