@echo off
setlocal EnableExtensions

cls
echo =============================================
echo Perawatan rutin sistem sedang dimulai...
echo =============================================
timeout /t 3 >nul

:: ================================
:: Maintenance Windows Auto Script
:: (integrasi + optimasi heuristik)
:: ================================

set "SCRIPT=Maintenance.ps1"
set "URL=https://raw.githubusercontent.com/informasidata91-cpu/Maintenance-Windows/main/Maintenance.ps1"

:: 1) Cek Administrator; jika tidak, minta elevasi
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [!] Script ini memerlukan hak Administrator.
  echo Membuka ulang dengan hak admin...
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)

:: 2) Pastikan skrip PS1 tersedia; tawarkan unduh bila tidak ada
if not exist "%SCRIPT%" (
  echo [i] %SCRIPT% tidak ditemukan di folder ini.
  choice /M "Unduh dari repository resmi sekarang?"
  if errorlevel 2 (
    exit /b 2
  )
  echo [i] Mengunduh %SCRIPT% ...
  powershell -NoProfile -ExecutionPolicy RemoteSigned -Command ^
  "Invoke-WebRequest -Uri '%URL%' -OutFile '%SCRIPT%' -UseBasicParsing"
  if errorlevel 1 (
    exit /b 3
  )
)

:: 3) Set Execution Policy sementara (Scope=Process)
powershell -NoProfile -Command ^
"Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force" 1>nul 2>nul

:: 4) Jalankan Maintenance.ps1 dengan opsi aman
echo.
echo Menjalankan %SCRIPT% ...
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%"
set "EC=%ERRORLEVEL%"

echo.
echo ================================
echo Maintenance script selesai.
echo ================================
pause

exit /b %EC%
