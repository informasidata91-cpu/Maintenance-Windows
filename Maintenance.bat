::[Bat To Exe Converter]
::
::YAwzoRdxOk+EWAjk
::fBw5plQjdCyDJGyX8VAjFDpXSRa+GGStCLkT6ezo0+eGq0MJUew+dozelL2NL4A=
::YAwzuBVtJxjWCl3EqQJgSA==
::ZR4luwNxJguZRRnk
::Yhs/ulQjdF+5
::cxAkpRVqdFKZSDk=
::cBs/ulQjdF+5
::ZR41oxFsdFKZSDk=
::eBoioBt6dFKZSDk=
::cRo6pxp7LAbNWATEpCI=
::egkzugNsPRvcWATEpCI=
::dAsiuh18IRvcCxnZtBJQ
::cRYluBh/LU+EWAnk
::YxY4rhs+aU+IeA==
::cxY6rQJ7JhzQF1fEqQJhZkgaHkrSXA==
::ZQ05rAF9IBncCkqN+0xwdVsFAlfMbiXqZg==
::ZQ05rAF9IAHYFVzEqQIdKRJaWAGMPWW5A/Ur4eb/4P2Uwg==
::eg0/rx1wNQPfEVWB+kM9LVsJDCmDNWWuA7sd5uv+oe+fpy0=
::fBEirQZwNQPfEVWB+kM9LVsJDCmDNWWuA7sd5uv+jw==
::cRolqwZ3JBvQF1fEqQIHIRVQQxORfEa7D7sI7eb64emC4ngJXe42bJa7
::dhA7uBVwLU+EWDk=
::YQ03rBFzNR3SWATE0EMkKVt9QgKNLma7FbyeDCqb
::dhAmsQZ3MwfNWATEVotweksGGUSmPX+7RpwS7ufp4uuUq8/5lqx/WYPXmqaHJ+gH+QX2cIUoxGxfnIVs
::ZQ0/vhVqMQ3MEVWAtB9wSA==
::Zg8zqx1/OA3MEVWAtB9wSA==
::dhA7pRFwIByZRRmm4Us8PFtCRQXCDGStA6cv4O3346qGrEldd+0ydY7V3vS+Mu8e+lGqFQ==
::Zh4grVQjdCuDJH6N4EolKid5TQ2MKG60B7sf7aXM5uSDrVoOaM8+cYHP37qPLuMWpED8cPY=
::YB416Ek+ZW8=
::
::
::978f952a14a936cc963da21a135fa983
@echo off
setlocal EnableExtensions

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
