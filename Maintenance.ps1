<# 
.SYNOPSIS
  Windows Maintenance All-in-One dan log utama C:\MaintenanceLog.txt.

.PARAMETER Silent
  Non-interaktif (tanpa prompt).

.PARAMETER SkipDISM, SkipSFC, SkipWUReset, SkipCleanup, SkipDefrag, SkipChkdsk, SkipNetworkFix, SkipMemoryDiag, SkipExtraCleanup
  Melewati task terkait (tetap ditandai [skip] tanpa menaikkan counter).

.PARAMETER NoRestart
  Mencegah restart otomatis di akhir.

.NOTES
  - Jalankan sebagai Administrator.
  - Log utama: C:\MaintenanceLog.txt
#>

[CmdletBinding()]
param(
  [switch]$Silent,
  [switch]$SkipDISM,
  [switch]$SkipSFC,
  [switch]$SkipWUReset,
  [switch]$SkipCleanup,
  [switch]$SkipDefrag,
  [switch]$SkipChkdsk,
  [switch]$SkipNetworkFix,
  [switch]$SkipMemoryDiag,
  [switch]$SkipExtraCleanup,
  [switch]$NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===== TLS awal =====
$OriginalProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  if ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
  }
} catch {}

# ===== Helper =====
function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if (-not $isAdmin) {
    Write-Host "Elevating to Administrator..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $argsList = @()
    foreach ($kv in $MyInvocation.BoundParameters.GetEnumerator()) {
      $k = $kv.Key; $v = $kv.Value
      if ($v -is [switch] -and $v.IsPresent) { $argsList += "-$k" }
      elseif ($null -ne $v) { $argsList += "-$k `"$v`"" }
    }
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($argsList -join ' ')
    $psi.Verb = "runas"
    try { [Diagnostics.Process]::Start($psi) | Out-Null } catch { throw "User cancelled UAC or elevation failed." }
    exit
  }
}

$global:LogFile = "C:\MaintenanceLog.txt"
function New-Log {
  try {
    if (-not (Test-Path -LiteralPath $LogFile)) { New-Item -ItemType File -Path $LogFile -Force | Out-Null }
    Start-Transcript -Path $LogFile -Append | Out-Null
  } catch { Write-Warning "Gagal memulai transcript ke $LogFile." }
}
function Stop-Log { try { Stop-Transcript | Out-Null } catch {}; Write-Host "Log: $LogFile" }

function Invoke-External {
  param([Parameter(Mandatory)][string]$FilePath,[string]$Arguments = "",[int[]]$SuccessExitCodes = @(0))
  Write-Host ">> $FilePath $Arguments" -ForegroundColor DarkGray
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
  if ($SuccessExitCodes -notcontains $p.ExitCode) { throw "Command failed ($($p.ExitCode)): $FilePath $Arguments" }
}
function Run-AdminCommand { param([Parameter(Mandatory)][string]$Command) Start-Process -FilePath "cmd.exe" -ArgumentList "/c $Command" -Verb RunAs -WindowStyle Hidden -Wait }
if (-not $Silent) {
  Write-Host ""
  Write-Host "==============================================="
  Write-Host "  PEMBERITAHUAN MAINTENANCE WINDOWS"
  Write-Host "==============================================="
  Write-Host "Memulai proses Maintenance Windows. Mohon simpan pekerjaan Anda." -ForegroundColor Yellow
  Write-Host "Sistem akan restart otomatis setelah selesai." -ForegroundColor Yellow
  Write-Host "Jangan mematikan komputer sebelum proses maintenance selesai." -ForegroundColor Yellow
  Write-Host "-----------------------------------------------"
  Write-Host ""
  Start-Sleep -Seconds 3
}

# ===== Tugas =====
function Repair-ComponentStore-3Step {
  Write-Host "=== DISM /CheckHealth ===" -ForegroundColor DarkGray;   Invoke-External -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /CheckHealth" 
  Write-Host "=== DISM /ScanHealth ===" -ForegroundColor DarkGray;    Invoke-External -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /ScanHealth" 
  Write-Host "=== DISM /RestoreHealth ===" -ForegroundColor DarkGray; Invoke-External -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth" 
}
function Repair-SystemFiles { Write-Host "=== SFC /Scannow === " -ForegroundColor DarkGray; Invoke-External -FilePath "sfc.exe" -Arguments "/scannow" }

function Reset-WindowsUpdate {
  Write-Host "=== Reset Windows Update Components ===" -ForegroundColor DarkGray
  $services = "wuauserv","bits","cryptsvc","msiserver"
  foreach ($svc in $services) { try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue } catch {} }
  Start-Sleep -Seconds 2
  $dist = Join-Path $env:windir "SoftwareDistribution"
  $cat  = Join-Path $env:windir "System32\catroot2"
  if (Test-Path $dist) { Rename-Item $dist ($dist + ".bak-" + (Get-Date -f "yyyyMMddHHmmss")) -ErrorAction SilentlyContinue }
  if (Test-Path $cat)  { Rename-Item $cat  ($cat  + ".bak-" + (Get-Date -f "yyyyMMddHHmmss")) -ErrorAction SilentlyContinue }
  foreach ($svc in $services) { Start-Service -Name $svc -ErrorAction SilentlyContinue }
}

function Run-Cleanup {
  Write-Host "=== Cleanup: Temp, Component Store, Recycle Bin ===" -ForegroundColor DarkGray
  $paths = @($env:TEMP, $env:TMP, (Join-Path $env:windir "Temp")) | Where-Object { $_ -and (Test-Path $_) }
  foreach ($p in $paths) { try { Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
  Invoke-External -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /StartComponentCleanup"
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
}

function Disk-Cleanup-C {
  Write-Host "=== Disk Cleanup Drive C: (opsional) ===" -ForegroundColor DarkGray
  # Invoke-External -FilePath "cleanmgr.exe" -Arguments "/d C: /verylowdisk"
}

function Extra-Cleanup {
  Write-Host "=== Extra Cleanup (Temp, WU Download, DO Cache, Logs, Prefetch, Recycle Bin, Windows.old) ===" -ForegroundColor DarkGray
  # Temp user & system
  $extraTemp = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Where-Object { $_ -and (Test-Path $_) }
  foreach ($p in $extraTemp) { try { Get-ChildItem -LiteralPath $p -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch {} }
  # WU Download
  try {
    Stop-Service -Name wuauserv,bits -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
    $wuDownload = "C:\Windows\SoftwareDistribution\Download"
    if (Test-Path $wuDownload) { Get-ChildItem -LiteralPath $wuDownload -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }
    Start-Service -Name wuauserv,bits -ErrorAction SilentlyContinue
  } catch {}
  # Delivery Optimization cache
  try {
    $doPath = "C:\Windows\SoftwareDistribution\DeliveryOptimization"
    try { Stop-Service -Name dosvc -Force -ErrorAction SilentlyContinue } catch {}
    if (Test-Path $doPath) { Get-ChildItem -LiteralPath $doPath -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }
    try { Start-Service -Name dosvc -ErrorAction SilentlyContinue } catch {}
  } catch {}
  # Logs & Prefetch
  $logPaths = @("C:\Windows\Prefetch","C:\Windows\Logs\CBS","C:\Windows\Logs\DISM")
  foreach ($lp in $logPaths) { if (Test-Path $lp) { try { Get-ChildItem -LiteralPath $lp -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue } catch {} } }
  # Recycle Bin
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
  # Windows.old
  try {
    if (Test-Path "C:\Windows.old") {
      try { Remove-Item -LiteralPath "C:\Windows.old" -Recurse -Force -ErrorAction Stop }
      catch {
        Write-Host "Windows.old removal via PowerShell failed, trying fallback…" -ForegroundColor DarkGray
        try { Run-AdminCommand "takeown /F C:\Windows.old\* /R /A /D Y" } catch {}
        try { Run-AdminCommand "icacls C:\Windows.old\*.* /T /grant administrators:F" } catch {}
        try { Run-AdminCommand "rmdir /s /q C:\Windows.old" } catch {}
      }
    }
  } catch {}
}

function Flush-DNS { Write-Host "=== Flush DNS Cache ===" -ForegroundColor DarkGray; try { Clear-DnsClientCache } catch { Run-AdminCommand "ipconfig /flushdns" } }
function Reset-Winsock { Write-Host "=== Reset Winsock ===" -ForegroundColor DarkGray; Invoke-External -FilePath "netsh.exe" -Arguments "winsock reset"; Write-Host "Winsock reset; restart akan diperlukan untuk efektivitas penuh." -ForegroundColor DarkGray }

function Optimize-Drives {
  Write-Host "=== Optimize Volumes (Defrag/TRIM) ===" -ForegroundColor DarkGray
  $vols = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
  foreach ($v in $vols) { try { Optimize-Volume -DriveLetter $v.DriveLetter -Verbose -ErrorAction Continue } catch {} }
}

function Schedule-CHKDSK-RepairIfNeeded {
  Write-Host "=== CHKDSK (menyeluruh) ===" -ForegroundColor DarkGray
  $systemDrive = $env:SystemDrive.TrimEnd(':')
  chkdsk "$systemDrive`:\" /R | Out-Null
}


function Schedule-MemoryDiagnostic { Write-Host "=== Schedule Windows Memory Diagnostic ===" -ForegroundColor DarkGray; Start-Process -FilePath "$env:WINDIR\System32\mdsched.exe" -ArgumentList "/s" -Verb RunAs -WindowStyle Hidden }

function Schedule-AutoRestart {
  Write-Host "=== Auto Restart in 30s ===" -ForegroundColor DarkGray
  $msg = "Maintenance Windows selesai. Komputer akan restart otomatis."
  Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" -ArgumentList "/r /t 30 /c `"$msg`"" -WindowStyle Hidden
  Write-Host $msg
}

function Show-Summary { param([System.Collections.ArrayList]$Steps) Write-Host "`n=== Maintenance Summary ==="; foreach ($s in $Steps) { Write-Host "- $s" }; Write-Host "" }

# ===== Eksekusi dengan penomoran [n/10] =====
try {
  Ensure-Admin
  New-Log

  $executed = [System.Collections.ArrayList]::new()
  $TotalSteps = 10
  $Step = 0
  function NextStep([string]$title) {
    $script:Step++
    Write-Host ("[{0}/{1}] {2}" -f $script:Step, $script:TotalSteps, $title)
  }

  # [1/10] DISM 3-step
  NextStep "DISM (CheckHealth, ScanHealth, RestoreHealth)"
  if (-not $SkipDISM) { Repair-ComponentStore-3Step; [void]$executed.Add("[1/10] DISM 3-step completed") } else { [void]$executed.Add("[1/10] DISM skipped") }

  # [2/10] SFC
  NextStep "System File Checker (SFC)"
  if (-not $SkipSFC)  { Repair-SystemFiles; [void]$executed.Add("[2/10] SFC ScanNow completed") } else { [void]$executed.Add("[2/10] SFC skipped") }

  # [3/10] Reset Windows Update Components
  NextStep "Reset Windows Update Components"
  if (-not $SkipWUReset) { Reset-WindowsUpdate; [void]$executed.Add("[3/10] Windows Update components reset") } else { [void]$executed.Add("[3/10] WU reset skipped") }

  # [4/10] Network Fixes (Flush DNS & Reset Winsock)
  NextStep "Network Fixes (Flush DNS & Reset Winsock)"
  if (-not $SkipNetworkFix) {
    Flush-DNS;     [void]$executed.Add("[4/10] DNS cache flushed")
    Reset-Winsock; [void]$executed.Add("[4/10] Winsock reset (restart needed)")
  } else {
    [void]$executed.Add("[4/10] Network fixes skipped")
  }

  # [5/10] Disk Cleanup inti
  NextStep "Disk Cleanup"
  if (-not $SkipCleanup) { Run-Cleanup; [void]$executed.Add("[5/10] Cleanup completed") } else { [void]$executed.Add("[5/10] Cleanup skipped") }

  # [6/10] Disk Cleanup C: (opsional)
  NextStep "Disk Cleanup Drive C:"
  Disk-Cleanup-C; [void]$executed.Add("[6/10] Disk Cleanup C: executed (optional)")

  # [7/10] Extra Cleanup
  NextStep "Extra Cleanup"
  if (-not $SkipExtraCleanup) { Extra-Cleanup; [void]$executed.Add("[7/10] Extra cleanup executed") } else { [void]$executed.Add("[7/10] Extra cleanup skipped") }

  # [8/10] Optimize Volumes
  NextStep "Optimize Volumes (Defrag/TRIM)"
  if (-not $SkipDefrag) { Optimize-Drives; [void]$executed.Add("[8/10] Optimize-Volume executed") } else { [void]$executed.Add("[8/10] Defrag/TRIM skipped") }

  # [9/10] CHKDSK
  NextStep "CHKDSK (scan & schedule repair)"
  if (-not $SkipChkdsk) { Schedule-CHKDSK-RepairIfNeeded; [void]$executed.Add("[9/10] CHKDSK scanned; repair scheduled if needed") } else { [void]$executed.Add("[9/10] CHKDSK skipped") }

  # [10/10] Windows Memory Diagnostic
  NextStep "Windows Memory Diagnostic"
  if (-not $SkipMemoryDiag) { Schedule-MemoryDiagnostic; [void]$executed.Add("[10/10] Memory Diagnostic scheduled") } else { [void]$executed.Add("[10/10] Memory Diagnostic skipped") }

  # Ringkasan
  Show-Summary -Steps $executed

  # Restart otomatis 30 detik (kecuali NoRestart)
  if (-not $NoRestart) {
    if (-not $Silent) {
      Write-Host "Maintenance Windows selesai. Komputer akan restart otomatis dalam 30 detik."
      Write-Host "Tekan 'A' lalu Enter dalam 30 detik untuk membatalkan (shutdown /a)."
      Schedule-AutoRestart
      $start = Get-Date
      while ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -lt 30) {
        if ($Host.UI.RawUI.KeyAvailable) {
          $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
          if ($key.Character -eq 'A' -or $key.Character -eq 'a') {
            Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" -ArgumentList "/a" -WindowStyle Hidden
            Write-Host "Restart dibatalkan."
            break
          }
        }
        Start-Sleep -Milliseconds 200
      }
    } else {
      Schedule-AutoRestart
    }
  } else {
    Write-Host "NoRestart diaktifkan; tidak melakukan restart otomatis."
  }

  exit 0
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}
finally {
  try { [Net.ServicePointManager]::SecurityProtocol = $OriginalProtocol } catch {}
  Stop-Log
}

