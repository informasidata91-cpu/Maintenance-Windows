<#
Versi: 2.5.0 Deep Check
Fokus: logging andal, urutan SFC→DISM→CHKDSK online, Reset WU resmi, optimasi HDD/SSD.
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
$global:LogFile = "C:\MaintenanceLog.txt"
$script:StartTime = Get-Date

# TLS
$OriginalProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}


function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"") + $PSBoundParameters.GetEnumerator() | ForEach-Object {
      if ($_.Value -eq $true) { "-$($_.Key)" } else { "-$($_.Key) `"$($_.Value)`"" }
    }
    $psi.Arguments = $args -join ' '
    $psi.Verb = "runas"
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}

function Write-Status($msg, $color="Gray") {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$ts] $msg" -ForegroundColor $color
}

function New-Log {
  try {
    if (-not (Test-Path -LiteralPath $LogFile)) { New-Item -ItemType File -Path $LogFile -Force | Out-Null }
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Status "Transcript → $LogFile" "DarkCyan"
  } catch {
    Write-Host "Gagal memulai transcript: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

function Stop-Log {
  try { Stop-Transcript | Out-Null } catch {}
  $d = (Get-Date) - $script:StartTime
  Write-Host "Log: $LogFile (Durasi: $([Math]::Round($d.TotalMinutes,2)) menit)" -ForegroundColor Cyan
}

# Proses eksternal diarahkan ke host agar tercatat di transcript
function Invoke-External {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string]$Arguments = "",
    [int[]]$SuccessExitCodes = @(0),
    [int]$TimeoutSec = 0
  )
  Write-Host ">> $FilePath $Arguments" -ForegroundColor DarkGray
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/c `"$FilePath`" $Arguments"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $false
  $psi.RedirectStandardError = $false
  $psi.CreateNoWindow = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  if ($TimeoutSec -gt 0) {
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
      try { $p.Kill() } catch {}
      throw "Timeout menjalankan: $FilePath $Arguments"
    }
  } else { $p.WaitForExit() }
  if ($SuccessExitCodes -notcontains $p.ExitCode) {
    throw "ExitCode $($p.ExitCode): $FilePath $Arguments"
  }
}

function Section($i,$t,$name){ Write-Host ("`n[{0}/{1}] {2}" -f $i,$t,$name) -ForegroundColor Yellow; Write-Host ("=" * (12 + $name.Length)) -ForegroundColor DarkGray }

# ——— Integritas OS ———
function Run-SFC {
  Write-Status "SFC /Scannow..."
  Invoke-External sfc.exe "/scannow"
  # Kembalikan indikasi untuk keputusan DISM
  return $LASTEXITCODE
}

function Run-DISM-3 {
  Write-Status "DISM CheckHealth..."
  Invoke-External dism.exe "/Online /Cleanup-Image /CheckHealth"
  Write-Status "DISM ScanHealth..."
  Invoke-External dism.exe "/Online /Cleanup-Image /ScanHealth"
  Write-Status "DISM RestoreHealth..."
  Invoke-External dism.exe "/Online /Cleanup-Image /RestoreHealth"
}

# ——— Windows Update ———
function Reset-WindowsUpdate {
  Write-Status "Reset Windows Update components..."
  $svcs = "bits","wuauserv","cryptsvc","msiserver"
  foreach ($s in $svcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
  Start-Sleep 2
  $sd = Join-Path $env:windir "SoftwareDistribution"
  $cr = Join-Path $env:windir "System32\catroot2"
  $ts = Get-Date -f yyyyMMddHHmmss
  if (Test-Path $sd) { Rename-Item $sd "$sd.bak-$ts" -ErrorAction SilentlyContinue }
  if (Test-Path $cr) { Rename-Item $cr "$cr.bak-$ts" -ErrorAction SilentlyContinue }
  foreach ($s in $svcs) { Start-Service $s -ErrorAction SilentlyContinue }
}

# ——— Cleanup ———
function Run-Cleanup {
  Write-Status "Cleanup temp dan komponen..."
  $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Where-Object { $_ -and (Test-Path $_) }
  foreach ($p in $paths) {
    try { Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
  Invoke-External dism.exe "/Online /Cleanup-Image /StartComponentCleanup"
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
}

function Extra-Cleanup {
  Write-Status "Extra cleanup..."
  $targets = @(
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:WINDIR\SoftwareDistribution\DeliveryOptimization",
    "$env:WINDIR\Logs\CBS",
    "$env:WINDIR\Logs\DISM",
    "$env:WINDIR\Prefetch"
  )
  foreach ($t in $targets) { if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue } }
  if (Test-Path "C:\Windows.old") {
    Write-Status "Hapus Windows.old (rollback tidak lagi tersedia)..."
    try {
      Remove-Item "C:\Windows.old" -Recurse -Force -ErrorAction Stop
    } catch {
      Write-Status "Fallback takeown/icacls Windows.old..."
      Invoke-External takeown.exe "/F C:\Windows.old /R /A /D Y"
      Invoke-External icacls.exe "C:\Windows.old /grant administrators:F /T"
      Invoke-External cmd.exe "/c rmdir /s /q C:\Windows.old"
    }
  }
}

# ——— Network fix ———
function Flush-DNS { Write-Status "Flush DNS cache..."; try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {} }
function Reset-Winsock { Write-Status "Winsock reset..."; Invoke-External netsh.exe "winsock reset" }

# ——— Storage ———
function Optimize-Drives {
  Write-Status "Analyze + Defrag/ReTrim..."
  $vols = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
  foreach ($v in $vols) {
    try {
      Optimize-Volume -DriveLetter $v.DriveLetter -Analyze -Verbose -ErrorAction SilentlyContinue
      $dl = $v.DriveLetter
      $isSSD = $false
      try {
        $pd = Get-Partition -DriveLetter $dl | Get-Disk | Get-PhysicalDisk -ErrorAction Stop
        $isSSD = ($pd.MediaType -eq 'SSD')
      } catch {}
      if ($isSSD) {
        Optimize-Volume -DriveLetter $dl -ReTrim -Verbose -ErrorAction SilentlyContinue
      } else {
        Optimize-Volume -DriveLetter $dl -Defrag -Verbose -ErrorAction SilentlyContinue
      }
    } catch {
      Write-Status "Optimize gagal $($v.DriveLetter): $($_.Exception.Message)" "DarkYellow"
    }
  }
}

# ——— CHKDSK ———
function Chkdsk-Online-And-Schedule {
  Write-Status "CHKDSK online /scan..."
  $drv = $env:SystemDrive.TrimEnd(':')
  $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c chkdsk $drv`: /scan" -Wait -PassThru
  $needRepair = $LASTEXITCODE -ne 0
  if ($needRepair) {
    Write-Status "Menjadwalkan CHKDSK /F /R pada reboot..."
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c echo Y | chkdsk $drv`: /F /R" -Verb RunAs -Wait
  } else {
    Write-Status "Tidak perlu penjadwalan CHKDSK." "Green"
  }
}

# ——— Memory diag ———
function Schedule-MemoryDiagnostic {
  Write-Status "Jadwalkan Windows Memory Diagnostic..."
  Start-Process "$env:WINDIR\System32\mdsched.exe" "/s" -Verb RunAs
}

function Schedule-AutoRestart {
  Write-Status "Jadwalkan restart otomatis dalam 30 detik..."
  Start-Process shutdown.exe "/r /t 30 /c `"Maintenance Windows selesai.`""
}

# ===== Eksekusi =====
try {
  Ensure-Admin
  New-Log

  if (-not $Silent) {
    Write-Host "`n*** MEMULAI MAINTENANCE WINDOWS (Deep Check) ***" -ForegroundColor Cyan
    Write-Host "Proses bisa memakan waktu; simpan pekerjaan Anda." -ForegroundColor Yellow
    Start-Sleep 2
  }

  # Urutan mendalam dan adaptif: SFC -> DISM (kondisional) -> WU -> Network -> Cleanup -> Extra -> Optimize -> CHKDSK -> MemDiag
  $tasks = @()

  $tasks += @{ Name="SFC"; Action={ if (-not $SkipSFC) { $script:SfcExit = Run-SFC } }; Skip=$SkipSFC }
  $tasks += @{ Name="DISM 3-step (kondisional)"; Action={ if (-not $SkipDISM) {
      if ($script:SfcExit -ne 0) { Run-DISM-3 } else { Write-Status "SFC OK; DISM dilewati (tidak diperlukan)"; }
  } }; Skip=$SkipDISM }
  $tasks += @{ Name="Reset Windows Update"; Action={ if (-not $SkipWUReset) { Reset-WindowsUpdate } }; Skip=$SkipWUReset }
  $tasks += @{ Name="Network Fix"; Action={ if (-not $SkipNetworkFix) { Flush-DNS; Reset-Winsock } }; Skip=$SkipNetworkFix }
  $tasks += @{ Name="Disk Cleanup"; Action={ if (-not $SkipCleanup) { Run-Cleanup } }; Skip=$SkipCleanup }
  $tasks += @{ Name="Extra Cleanup"; Action={ if (-not $SkipExtraCleanup) { Extra-Cleanup } }; Skip=$SkipExtraCleanup }
  $tasks += @{ Name="Optimize Drives"; Action={ if (-not $SkipDefrag) { Optimize-Drives } }; Skip=$SkipDefrag }
  $tasks += @{ Name="CHKDSK"; Action={ if (-not $SkipChkdsk) { Chkdsk-Online-And-Schedule } }; Skip=$SkipChkdsk }
  $tasks += @{ Name="Memory Diagnostic"; Action={ if (-not $SkipMemoryDiag) { Schedule-MemoryDiagnostic } }; Skip=$SkipMemoryDiag }

  $TotalSteps = $tasks.Count
  $executed = [System.Collections.ArrayList]::new()
  $i = 0
  foreach ($t in $tasks) {
    $i++
    Section $i $TotalSteps $t.Name
    if ($t.Skip) {
      Write-Status "$($t.Name) → [SKIPPED]" "DarkYellow"
      [void]$executed.Add("[$i/$TotalSteps] $($t.Name) → SKIPPED")
    } else {
      try {
        & $t.Action
        Write-Status "$($t.Name) → [OK]" "Green"
        [void]$executed.Add("[$i/$TotalSteps] $($t.Name) → OK")
      } catch {
        Write-Status "$($t.Name) → [FAILED] $($_.Exception.Message)" "Red"
        [void]$executed.Add("[$i/$TotalSteps] $($t.Name) → FAILED: $($_.Exception.Message)")
      }
    }
  }

  Write-Host "`n===== RINGKASAN MAINTENANCE =====" -ForegroundColor Cyan
  $executed | ForEach-Object { Write-Host $_ }

  if (-not $NoRestart) {
    if (-not $Silent) {
      Write-Host "`nSelesai. Restart otomatis dalam 30 detik." -ForegroundColor Yellow
      Write-Host "Tekan [A] lalu Enter untuk membatalkan."
      Schedule-AutoRestart
      $start = Get-Date
      while ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -lt 30) {
        if ($Host.UI.RawUI.KeyAvailable) {
          $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
          if ($key.Character -in @('A','a')) {
            Start-Process shutdown.exe "/a"
            Write-Host "Restart dibatalkan." -ForegroundColor Cyan
            break
          }
        }
        Start-Sleep -Milliseconds 200
      }
    } else { Schedule-AutoRestart }
  } else {
    Write-Status "NoRestart aktif — tidak restart otomatis." "DarkYellow"
  }

  exit 0
}
catch {
  Write-Host ('Kesalahan fatal: ' + $($_.Exception.Message)) -ForegroundColor Red
  exit 1
}
finally {
  try { [Net.ServicePointManager]::SecurityProtocol = $OriginalProtocol } catch {}
  Stop-Log
}




