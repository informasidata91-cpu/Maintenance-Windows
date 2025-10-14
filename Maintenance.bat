@echo off
cls
echo =============================================
echo    Perawatan rutin sistem sedang dimulai...
echo =============================================
timeout /t 3 >nul

@echo off
:: ================================
:: Maintenance Windows Auto Script
:: ================================

:: Cek apakah dijalankan sebagai Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Script ini memerlukan hak Administrator.
    echo     Membuka ulang dengan hak admin...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Set Execution Policy sementara
powershell -Command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force"

:: Unduh file Maintenance.ps1 dari GitHub
powershell -Command "Invoke-WebRequest 'https://raw.githubusercontent.com/informasidata91-cpu/Maintenance-Windows/main/Maintenance.ps1' -OutFile 'Maintenance.ps1'"

:: Jalankan Maintenance.ps1
powershell -ExecutionPolicy Bypass -File "Maintenance.ps1"

echo.
echo ================================
echo  Maintenance script selesai.
echo ================================
pause
