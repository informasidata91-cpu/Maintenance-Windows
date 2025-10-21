<#
.SYNOPSIS
  Windows Maintenance All-in-One dengan logging utama di C:\MaintenanceLog.txt.

.DESCRIPTION
  Melakukan pemeliharaan menyeluruh Windows: DISM, SFC, Reset WU, Cleanup, Defrag, CHKDSK, Network Fix, dan Memory Diagnostic.
  Log disimpan di: C:\MaintenanceLog.txt

.PARAMETER Silent
  Menjalankan mode non-interaktif (tanpa prompt).

.PARAMETER SkipDISM, SkipSFC, SkipWUReset, SkipCleanup, SkipDefrag, SkipChkdsk, SkipNetworkFix, SkipMemoryDiag, SkipExtraCleanup
  Melewati task terkait (ditandai [SKIPPED] tanpa menaikkan counter).

.PARAMETER NoRestart
  Mencegah restart otomatis di akhir proses.

.NOTES
  - Jalankan sebagai Administrator.
  - Disarankan koneksi internet aktif untuk DISM RestoreHealth.
  - Log utama: C:\MaintenanceLog.txt
  - Versi: 2.3.6 (dengan pesan peringatan awal)
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

# ====== Konfigurasi dasar ======
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LogFile = "C:\MaintenanceLog.txt"
$script:StartTime = Get-Date

# ====== TLS Modern Support ======
$OriginalProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor `
    ([enum]::IsDefined([Net.SecurityProtocolType], 'Tls13') ? [Net.SecurityProtocolType]::Tls13 : 0)
} catch {}

# ====== Helper ======
function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "Elevating to Administrator..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($MyInvocation.Line.Split(' ') | Where-Object {$_ -notmatch 'powershell.exe'})
    $psi.Verb = "runas"
    try { [Diagnostics.Process]::Start($psi) | Out-Null } catch { throw "User cancelled UAC or elevation failed." }
    exit
  }
}

function Write-Status($msg, $color="Gray") {
  $timestamp = Get-Date -Format "HH:mm:ss"
  Write-Host "[$timestamp] $msg" -ForegroundColor $color
}

function New-Log {
  try {
    if (-not (Test-Path -LiteralPath $LogFile)) { New-Item -ItemType File -Path $LogFile -Force | Out-Null }
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Status "Logging started → $LogFile" "DarkCyan"
  } catch { Write-Warning "Gagal memulai transcript ke $LogFile." }
}
function Stop-Log {
  try { Stop-Transcript | Out-Null } catch {}
  $duration = (Get-Date) - $script:StartTime
  Write-Host "Log: $LogFile (Durasi: $([math]::Round($duration.TotalMinutes,2)) menit)" -ForegroundColor Cyan
}

function Invoke-External {
  param([Parameter(Mandatory)][string]$FilePath,[string]$Arguments = "",[int[]]$SuccessExitCodes = @(0))
  Write-Host ">> $FilePath $Arguments" -ForegroundColor DarkGray
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
  if ($SuccessExitCodes -notcontains $p.ExitCode) { throw "Command failed ($($p.ExitCode)): $FilePath $Arguments" }
}

function Run-AdminCommand {
  param([Parameter(Mandatory)][string]$Command)
  Start-Process -FilePath "cmd.exe" -ArgumentList "/c $Command" -Verb RunAs -WindowStyle Hidden -Wait
}

function Section($index, $total, $title) {
  Write-Host ("`n[{0}/{1}] {2}" -f $index, $total, $title) -ForegroundColor Yellow
  Write-Host ("=" * (12 + $title.Length)) -ForegroundColor DarkGray
}

# ====== Tugas Pemeliharaan ======
function Repair-ComponentStore-3Step {
  Write-Status "Menjalankan DISM 3-step..." "Gray"
  Invoke-External dism.exe "/Online /Cleanup-Image /CheckHealth"
  Invoke-External dism.exe "/Online /Cleanup-Image /ScanHealth"
  Invoke-External dism.exe "/Online /Cleanup-Image /RestoreHealth"
}
function Repair-SystemFiles {
  Write-Status "Menjalankan SFC /Scannow..." "Gray"
  Invoke-External sfc.exe "/scannow"
}
function Reset-WindowsUpdate {
  Write-Status "Reset komponen Windows Update..." "Gray"
  $services = "wuauserv","bits","cryptsvc","msiserver"
  foreach ($svc in $services) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
  Start-Sleep 2
  Rename-Item "$env:windir\SoftwareDistribution" "$env:windir\SoftwareDistribution.bak-$(Get-Date -f yyyyMMddHHmmss)" -ErrorAction SilentlyContinue
  Rename-Item "$env:windir\System32\catroot2" "$env:windir\System32\catroot2.bak-$(Get-Date -f yyyyMMddHHmmss)" -ErrorAction SilentlyContinue
  foreach ($svc in $services) { Start-Service -Name $svc -ErrorAction SilentlyContinue }
}
function Run-Cleanup {
  Write-Status "Membersihkan folder sementara & komponen sistem..." "Gray"
  $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Where-Object { Test-Path $_ }
  foreach ($p in $paths) {
    try { Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
  Invoke-External dism.exe "/Online /Cleanup-Image /StartComponentCleanup"
  Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}
function Extra-Cleanup {
  Write-Status "Melakukan pembersihan lanjutan..." "Gray"
  $targets = @(
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:WINDIR\SoftwareDistribution\DeliveryOptimization",
    "$env:WINDIR\Logs\CBS",
    "$env:WINDIR\Logs\DISM",
    "$env:WINDIR\Prefetch"
  )
  foreach ($t in $targets) {
    if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path "C:\Windows.old") {
    Run-AdminCommand "takeown /F C:\Windows.old /R /A /D Y"
    Run-AdminCommand "icacls C:\Windows.old /grant administrators:F /T"
    Run-AdminCommand "rmdir /s /q C:\Windows.old"
  }
}
function Optimize-Drives {
  Write-Status "Optimasi drive (Defrag/TRIM)..." "Gray"
  $vols = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
  foreach ($v in $vols) { Optimize-Volume -DriveLetter $v.DriveLetter -ErrorAction SilentlyContinue }
}
function Schedule-CHKDSK-RepairIfNeeded {
  Write-Status "Menjadwalkan CHKDSK..." "Gray"
  $drv = $env:SystemDrive.TrimEnd(':')
  Start-Process cmd.exe "/c chkdsk $drv`: /scan" -Wait -WindowStyle Hidden
}
function Flush-DNS { Write-Status "Flush DNS Cache..." "Gray"; Clear-DnsClientCache -ErrorAction SilentlyContinue }
function Reset-Winsock { Write-Status "Reset Winsock..." "Gray"; Invoke-External netsh.exe "winsock reset" }
function Schedule-MemoryDiagnostic {
  Write-Status "Menjadwalkan Windows Memory Diagnostic..." "Gray"
  Start-Process "$env:WINDIR\System32\mdsched.exe" "/s" -Verb RunAs -WindowStyle Hidden
}
function Schedule-AutoRestart {
  Write-Status "Menjadwalkan restart otomatis dalam 30 detik..." "Gray"
  Start-Process shutdown.exe "/r /t 30 /c `"Maintenance Windows selesai.`"" -WindowStyle Hidden
}

# ====== Eksekusi ======
try {
  Ensure-Admin
  New-Log

  if (-not $Silent) {
    Write-Host "`n*** MEMULAI MAINTENANCE WINDOWS ***" -ForegroundColor Cyan
    Write-Host "Proses akan memakan waktu beberapa menit." -ForegroundColor Yellow
    Start-Sleep 3
  }

# 🔔 Tambahan pesan peringatan di awal
  Write-Host ""
  Write-Host "Memulai proses Maintenance Windows. Mohon simpan pekerjaan Anda." -ForegroundColor Yellow
  Write-Host "Sistem akan restart otomatis setelah selesai." -ForegroundColor Yellow
  Write-Host "Jangan mematikan komputer sebelum proses maintenance selesai." -ForegroundColor Yellow
  Write-Host "--------------------------------------------------------------"
  Write-Host ""
  $TotalSteps = 10
  $executed = [System.Collections.ArrayList]::new()

  # ===== Daftar tugas =====
  $tasks = @(
    @{ Name="DISM 3-step"; Action={ if (-not $SkipDISM) { Repair-ComponentStore-3Step } }; Skip=$SkipDISM },
    @{ Name="SFC ScanNow"; Action={ if (-not $SkipSFC) { Repair-SystemFiles } }; Skip=$SkipSFC },
    @{ Name="Reset Windows Update"; Action={ if (-not $SkipWUReset) { Reset-WindowsUpdate } }; Skip=$SkipWUReset },
    @{ Name="Network Fix (FlushDNS & Winsock)"; Action={ if (-not $SkipNetworkFix) { Flush-DNS; Reset-Winsock } }; Skip=$SkipNetworkFix },
    @{ Name="Disk Cleanup"; Action={ if (-not $SkipCleanup) { Run-Cleanup } }; Skip=$SkipCleanup },
    @{ Name="Extra Cleanup"; Action={ if (-not $SkipExtraCleanup) { Extra-Cleanup } }; Skip=$SkipExtraCleanup },
    @{ Name="Optimize Drives"; Action={ if (-not $SkipDefrag) { Optimize-Drives } }; Skip=$SkipDefrag },
    @{ Name="CHKDSK"; Action={ if (-not $SkipChkdsk) { Schedule-CHKDSK-RepairIfNeeded } }; Skip=$SkipChkdsk },
    @{ Name="Memory Diagnostic"; Action={ if (-not $SkipMemoryDiag) { Schedule-MemoryDiagnostic } }; Skip=$SkipMemoryDiag }
  )

  $step = 0
  foreach ($t in $tasks) {
    $step++
    Section $step $TotalSteps $t.Name
    if ($t.Skip) {
      Write-Status "$($t.Name) → [SKIPPED]" "DarkYellow"
      [void]$executed.Add("[$step/$TotalSteps] $($t.Name) → SKIPPED")
    } else {
      try {
        & $t.Action
        Write-Status "$($t.Name) → [OK]" "Green"
        [void]$executed.Add("[$step/$TotalSteps] $($t.Name) → OK")
      } catch {
        Write-Status "$($t.Name) → [FAILED] $($_.Exception.Message)" "Red"
        [void]$executed.Add("[$step/$TotalSteps] $($t.Name) → FAILED: $($_.Exception.Message)")
      }
    }
  }

  Write-Host "`n===== RINGKASAN MAINTENANCE =====" -ForegroundColor Cyan
  $executed | ForEach-Object { Write-Host $_ }

  if (-not $NoRestart) {
    if (-not $Silent) {
      Write-Host "`nMaintenance selesai. Restart otomatis dalam 30 detik." -ForegroundColor Yellow
      Write-Host "Tekan [A] lalu Enter untuk membatalkan restart." -ForegroundColor DarkGray
      Schedule-AutoRestart
      $start = Get-Date
      while ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -lt 30) {
        if ($Host.UI.RawUI.KeyAvailable) {
          $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
          if ($key.Character -eq 'A' -or $key.Character -eq 'a') {
            Start-Process shutdown.exe "/a" -WindowStyle Hidden
            Write-Host "Restart dibatalkan." -ForegroundColor Cyan
            break
          }
        }
        Start-Sleep -Milliseconds 200
      }
    } else { Schedule-AutoRestart }
  } else {
    Write-Status "NoRestart aktif — sistem tidak akan di-restart otomatis." "DarkYellow"
  }

  exit 0
}
catch {
  Write-Host "Terjadi kesalahan fatal: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
finally {
  try { [Net.ServicePointManager]::SecurityProtocol = $OriginalProtocol } catch {}
  Stop-Log
}
