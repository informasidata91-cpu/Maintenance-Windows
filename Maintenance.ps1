<#
Version: 1.3.3.0
#>

# ============ Header & Setup ============
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
  [switch]$NoRestart,
  [switch]$ForceAutoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LogFile = 'C:\MaintenanceLog.txt'
$script:StartTime = Get-Date

# OS guard (opsional bisa Anda pertahankan seperti semula)
$os = Get-CimInstance Win32_OperatingSystem
$ver = [Version]$os.Version
if ($ver.Major -lt 10) { throw "Unsupported OS: $($os.Caption) $($os.Version)" }

# TLS normalize
$OriginalProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
  if ($PSVersionTable.PSVersion.Major -ge 7) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::SystemDefault
  } else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  }
} catch {}

function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
      if ($kv.Value -eq $true) {
        $argList += "-$($kv.Key)"
      } else {
        $argList += "-$($kv.Key) `"$($kv.Value)`""
      }
    }
    $psi.Arguments = ($argList -join ' ')
    $psi.Verb = 'runas'
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}

# ============ Logging & Status ============
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warn','Error','Success','Green','Yellow','Red','Cyan','Gray','DarkYellow','DarkCyan')]
        [string]$Level = 'Info'
    )
    $fg = switch ($Level) {
        'Info'       { 'Cyan' }
        'Warn'       { 'Yellow' }
        'Error'      { 'Red' }
        'Success'    { 'Green' }
        'Green'      { 'Green' }
        'Yellow'     { 'Yellow' }
        'Red'        { 'Red' }
        'Cyan'       { 'Cyan' }
        'Gray'       { 'Gray' }
        'DarkYellow' { 'DarkYellow' }
        'DarkCyan'   { 'DarkCyan' }
        default      { 'Gray' }
    }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] $Message" -ForegroundColor $fg
}

function New-Log {
  try {
    if (-not (Test-Path -LiteralPath $LogFile)) { New-Item -ItemType File -Path $LogFile -Force | Out-Null }
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Status "Transcript -> $LogFile" 'DarkCyan'
  } catch {
    Write-Host ('Gagal memulai transcript: ' + $($_.Exception.Message)) -ForegroundColor Yellow
  }
}

function Stop-Log {
  try { Stop-Transcript | Out-Null } catch {}
  $d = (Get-Date) - $script:StartTime
  Write-Host ('Log: ' + $LogFile + ' (Durasi: ' + [Math]::Round($d.TotalMinutes,2) + ' menit)') -ForegroundColor Cyan
}

function Section($i,$t,$name){
  Write-Host ("`n[{0}/{1}] {2}" -f $i,$t,$name) -ForegroundColor Yellow
  Write-Host ('=' * (12 + $name.Length)) -ForegroundColor DarkGray
}

# ============ External invocation ============
function Invoke-External {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string]$Arguments = '',
    [int[]]$SuccessExitCodes = @(0),
    [int]$TimeoutSec = 0
  )
  Write-Host ('>> ' + $FilePath + ' ' + $Arguments) -ForegroundColor DarkGray
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'cmd.exe'
  $psi.Arguments = '/c "' + $FilePath + '" ' + $Arguments
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $false
  $psi.RedirectStandardError = $false
  $psi.CreateNoWindow = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  if ($TimeoutSec -gt 0) {
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
      try { $p.Kill() } catch {}
      throw ('Timeout menjalankan: ' + $FilePath + ' ' + $Arguments)
    }
  } else { $p.WaitForExit() }
  if ($SuccessExitCodes -notcontains $p.ExitCode) {
    throw ('ExitCode ' + $p.ExitCode + ': ' + $FilePath + ' ' + $Arguments)
  }
}

# ===================== SFC =====================
function Run-SFC {
  Write-Status 'SFC /Scannow...' 'Info'

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName  = 'cmd.exe'
  $psi.Arguments = '/c sfc.exe /scannow'
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow = $true

  $p = [System.Diagnostics.Process]::Start($psi)
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  $outFile = Join-Path $env:TEMP ("sfc_out_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $script:SfcOutFile = $outFile
  try {
    $stdout | Out-File -FilePath $outFile -Encoding UTF8 -Force
    if ($stderr) { $stderr | Out-File -FilePath $outFile -Append -Encoding UTF8 }
    Write-Status ("Log SFC -> " + $outFile) 'DarkCyan'
  } catch {}

  return $p.ExitCode
}

function Get-DismTailInfo {
    param([int]$TailChars = 400000)
    $log = Join-Path $env:WINDIR 'Logs\DISM\dism.log'
    if (-not (Test-Path -LiteralPath $log)) { return '[dism.log not found]' }
    try {
        $txt = Get-Content -LiteralPath $log -Raw -ErrorAction Stop
        if ($txt.Length -gt $TailChars) { $txt = $txt.Substring($txt.Length - $TailChars) }
        $lines = $txt -split "\r?\n"
        $keys = 'CheckHealth','ScanHealth','RestoreHealth','Error:','FAILED','successfully','reboot'
        $hit = $lines | Where-Object { $_ -match ($keys -join '|') } | Select-Object -Last 5
        if ($hit) { return ($hit -join "`r`n") } else { return '[no key lines in tail]' }
    } catch { return "[read dism.log failed] $($_.Exception.Message)" }
}

function Invoke-Dism-Step {
    param(
        [Parameter(Mandatory)][string]$Args,   # '/Online /Cleanup-Image /ScanHealth'
        [Parameter(Mandatory)][string]$Label
    )
    Write-Status "DISM $Label..." 'Info'
    $proc = Start-Process -FilePath 'dism.exe' -ArgumentList $Args -WindowStyle Hidden -Wait -PassThru
    $code = $proc.ExitCode
    $tail = Get-DismTailInfo
    if ($code -eq 0) {
        Write-Status "[$Label] OK (exit 0)" 'Green'
    } else {
        Write-Status "[$Label] ExitCode: $code" 'Yellow'
    }
    Write-Status ("Log DISM (tail):`n" + $tail) 'DarkCyan'
    return $code
}

function Run-DISM-3 {
    $t0 = Get-Date
    $e1 = Invoke-Dism-Step -Args '/Online /Cleanup-Image /CheckHealth'    -Label 'CheckHealth'
    $e2 = Invoke-Dism-Step -Args '/Online /Cleanup-Image /ScanHealth'     -Label 'ScanHealth'
    $e3 = Invoke-Dism-Step -Args '/Online /Cleanup-Image /RestoreHealth'  -Label 'RestoreHealth'
    $dur = (Get-Date) - $t0

    if ($e3 -eq 0) {
        Write-Status ("DISM selesai tanpa error. Durasi: {0:N1} menit" -f $dur.TotalMinutes) 'Green'
    } else {
        Write-Status ("DISM selesai dengan error (exit $e3). Lihat ringkasan log di atas. Durasi: {0:N1} menit" -f $dur.TotalMinutes) 'Yellow'
    }
}

# ============ Windows Update reset ============
function Reset-WindowsUpdate {
  Write-Status 'Reset Windows Update components...' 'Info'
  $svcs = 'bits','wuauserv','cryptsvc','msiserver'
  foreach ($s in $svcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
  Start-Sleep 2
  $sd = Join-Path $env:windir 'SoftwareDistribution'
  $cr = Join-Path $env:windir 'System32\catroot2'
  $ts = Get-Date -f yyyyMMddHHmmss
  if (Test-Path $sd) { Rename-Item $sd "$sd.bak-$ts" -ErrorAction SilentlyContinue }
  if (Test-Path $cr) { Rename-Item $cr "$cr.bak-$ts" -ErrorAction SilentlyContinue }
  foreach ($s in $svcs) { Start-Service $s -ErrorAction SilentlyContinue }
}

# ============ Cleanup ============
function Run-Cleanup {
  Write-Status 'Cleanup temp dan komponen...' 'Info'
  $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Where-Object { $_ -and (Test-Path $_) }
  foreach ($p in $paths) {
    try { Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
  Invoke-External dism.exe '/Online /Cleanup-Image /StartComponentCleanup'
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
}

function Extra-Cleanup {
  Write-Status 'Extra cleanup...' 'Info'
  $targets = @(
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:WINDIR\SoftwareDistribution\DeliveryOptimization",
    "$env:WINDIR\Logs\CBS",
    "$env:WINDIR\Logs\DISM",
    "$env:WINDIR\Prefetch"
  )
  foreach ($t in $targets) { if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue } }
  if (Test-Path 'C:\Windows.old') {
    Write-Status 'Hapus Windows.old (rollback tidak lagi tersedia)...' 'Warn'
    try {
      Remove-Item 'C:\Windows.old' -Recurse -Force -ErrorAction Stop
    } catch {
      Write-Status 'Fallback takeown/icacls Windows.old...' 'Warn'
      Invoke-External takeown.exe '/F C:\Windows.old /R /A /D Y'
      Invoke-External icacls.exe 'C:\Windows.old /grant administrators:F /T'
      Invoke-External cmd.exe '/c rmdir /s /q C:\Windows.old'
    }
  }
}

# ============ Network fixes ============
function Flush-DNS { Write-Status 'Flush DNS cache...' 'Info'; try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {} }
function Reset-Winsock { Write-Status 'Winsock reset...' 'Info'; Invoke-External netsh.exe 'winsock reset' }

# ============ Storage optimization ============
function Optimize-Drives {
  Write-Status 'Analyze + Defrag/ReTrim...' 'Info'
  $vols = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
  foreach ($v in $vols) {
    try {
      Optimize-Volume -DriveLetter $v.DriveLetter -Analyze -ErrorAction SilentlyContinue 4> $null
      $dl = $v.DriveLetter
      $isSSD = $false
      try {
        $pd = Get-Partition -DriveLetter $dl | Get-Disk | Get-PhysicalDisk -ErrorAction Stop
        $isSSD = ($pd.MediaType -eq 'SSD')
      } catch {}
      if ($isSSD) {
        Optimize-Volume -DriveLetter $dl -ReTrim -ErrorAction SilentlyContinue 4> $null
      } else {
        Optimize-Volume -DriveLetter $dl -Defrag -ErrorAction SilentlyContinue 4> $null
      }
    } catch {
      Write-Status ('Optimize gagal ' + $v.DriveLetter + ': ' + $_.Exception.Message) 'Warn'
    }
  }
}

# ============ CHKDSK ============
function Invoke-ChkdskOnlineAndSchedule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Drive = $env:SystemDrive,
        [switch]$UseSpotFix,
        [switch]$Hidden
    )

    # Normalisasi drive
    $drv = ($Drive.TrimEnd('\')).TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($drv)) { throw "Drive tidak valid: '$Drive'" }

    Write-Status "CHKDSK online /scan pada $drv`: ..." 'Info'
    $winStyle = if ($Hidden) { 'Hidden' } else { 'Normal' }

    # Jalankan scan dan ambil ExitCode dari objek proses (deterministik)
    $proc = Start-Process -FilePath 'cmd.exe' `
             -ArgumentList "/c chkdsk $drv`: /scan & exit %ERRORLEVEL%" `
             -WindowStyle $winStyle `
             -Wait -PassThru
    $code = $proc.ExitCode

    switch ($code) {
        0 { Write-Status "Tidak ada error terdeteksi oleh /scan pada $drv`:." 'Green' }
        1 { Write-Status "Ada error dan telah diperbaiki secara online (jika memungkinkan) pada $drv`:." 'Warn' }
        2 { Write-Status "Perlu perbaikan offline (tanpa /f). Pertimbangkan penjadwalan." 'Warn' }
        3 { Write-Status "Volume memerlukan pemeriksaan/perbaikan offline atau pemeriksaan gagal." 'Warn' }
        default { Write-Status "Kode keluar CHKDSK tak dikenal: $code" 'Warn' }
    }

    $needSchedule = ($code -in 2,3)
    if ($needSchedule) {
        $modeLabel = if ($UseSpotFix) { '/spotfix' } else { '/F /R' }
        if ($PSCmdlet.ShouldProcess("$drv`:", "Schedule CHKDSK $modeLabel at next reboot")) {
            Write-Status "Menjadwalkan CHKDSK $modeLabel pada reboot..." 'Warn'
            $fixArgs = if ($UseSpotFix) { "/spotfix" } else { "/F /R" }

            # Jalankan penjadwalan dengan elevasi dan ambil ExitCode deterministik
            $proc2 = Start-Process -FilePath 'cmd.exe' `
                      -ArgumentList "/c echo Y | chkdsk $drv`: $fixArgs & exit %ERRORLEVEL%" `
                      -Verb RunAs `
                      -WindowStyle $winStyle `
                      -Wait -PassThru
            $scheduleExit = $proc2.ExitCode

            if ($scheduleExit -eq 0) {
                Write-Status "CHKDSK $modeLabel telah dijadwalkan. Simpan pekerjaan Anda dan lakukan restart untuk memulai pemeriksaan." 'Warn'
            } else {
                Write-Status "Penjadwalan CHKDSK mungkin gagal (exit code: $scheduleExit). Coba jalankan sebagai Administrator." 'Error'
            }
        }
    } else {
        Write-Status 'Tidak perlu penjadwalan CHKDSK.' 'Green'
    }
}

# ============ Memory diagnostic ============
function Invoke-MemoryDiagnostic {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateSet('Schedule','RunNow')]
        [string]$Mode = 'Schedule',
        [switch]$Hidden
    )

    Write-Status 'Jalankan Windows Memory Diagnostic...' 'Info'
    $Exe = Join-Path $env:WINDIR 'System32\mdsched.exe'
    if (-not (Test-Path -LiteralPath $Exe)) {
        Write-Error "Tidak menemukan $Exe. Pastikan komponen Windows Memory Diagnostic tersedia."
        return
    }

    $Arg = if ($Mode -eq 'RunNow') { '/r' } else { '/s' }
    $winStyle = if ($Hidden) { 'Hidden' } else { 'Normal' }

    try {
        $target = "Windows Memory Diagnostic ($Mode)"
        if ($PSCmdlet.ShouldProcess($target, "Start-Process $($Exe) $Arg as Administrator")) {
            Start-Process -FilePath $Exe -ArgumentList $Arg -Verb RunAs -WindowStyle $winStyle -ErrorAction Stop
            if ($Mode -eq 'Schedule') {
                Write-Status "Tes RAM dijadwalkan pada boot berikutnya. Cek Event Viewer > Windows Logs > System, Source: MemoryDiagnostics-Results." 'Info'
            } else {
                Write-Status "Tes RAM akan berjalan segera (butuh restart). Cek hasil di Event Viewer setelah boot." 'Warn'
            }
        }
    }
    catch {
        Write-Error "Gagal memulai Windows Memory Diagnostic: $($_.Exception.Message)"
    }
}

# ============ Restart helpers ============
function Schedule-AutoRestart {
  param(
    [int]$TimeoutSec = 30,
    [string]$Comment = 'Maintenance Windows selesai.'
  )
  Write-Status "Jadwalkan restart otomatis dalam $TimeoutSec detik..." 'Warn'
  $args = "/r /t $TimeoutSec /c `"$Comment`""
  $p = Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" -ArgumentList $args -Verb RunAs -PassThru -WindowStyle Hidden
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "Gagal menjadwalkan restart (exit $($p.ExitCode))." }
}

function Abort-Restart {
  try {
    $p = Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" -ArgumentList '/a' -PassThru -WindowStyle Hidden
    $p.WaitForExit()
    Write-Host 'Restart dibatalkan.' -ForegroundColor Cyan
  } catch {
    Write-Host 'Gagal membatalkan restart.' -ForegroundColor Yellow
  }
}

# ============ Eksekusi utama ============
try {
  Ensure-Admin
  New-Log

  if (-not $Silent) {
    Write-Host "==============================================="
    Write-Host "  PEMBERITAHUAN MAINTENANCE WINDOWS"
    Write-Host "==============================================="
    Write-Host "Sistem akan restart otomatis setelah selesai." -ForegroundColor Yellow
    Write-Host "Jangan mematikan komputer sebelum proses maintenance selesai." -ForegroundColor Yellow
    Write-Host 'Proses bisa memakan waktu - simpan pekerjaan Anda.' -ForegroundColor Yellow
    Write-Host "-----------------------------------------------"
    Write-Host "`n*** MEMULAI MAINTENANCE WINDOWS ***" -ForegroundColor Cyan
    Start-Sleep 2
  }

function Ensure-Folder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        try { New-Item -ItemType Directory -Force -Path $Path | Out-Null } catch {}
    }
    return $Path
}

function Get-FileTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TailLines = 0,
        [int]$TailChars = 0
    )
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    if ($TailLines -gt 0) {
        return ((Get-Content -LiteralPath $Path -Tail $TailLines -ErrorAction Stop) -join "`r`n")
    } elseif ($TailChars -gt 0) {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ($text.Length -gt $TailChars) { return $text.Substring($text.Length - $TailChars) }
        return $text
    } else {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
    }
}

function Test-SFCIndicatesCorruption {
  param([int]$TailLines = 4000)
  $cbsDir = Join-Path $env:WINDIR 'Logs\CBS'
  Ensure-Folder $cbsDir | Out-Null
  $candidates = @(
    Join-Path $cbsDir 'CBS.log'
    Join-Path $cbsDir 'CBS.persist.log'
  ) | Where-Object { Test-Path -LiteralPath $_ }
  if (-not $candidates) { return $false }
  foreach ($p in $candidates) {
    try {
      $tail = Get-FileTail -Path $p -TailLines $TailLines
      if ([string]::IsNullOrEmpty($tail)) { continue }
      if ($tail -match 'Windows Resource Protection found corrupt files') { return $true }
      if ($tail -match 'unable to fix') { return $true }
      if ($tail -match 'successfully repaired') { return $true }
      if ($tail -match '\[SR\].*(cannot|repair|corrupt|hash)') { return $true }
    } catch { continue }
  }
  return $false
}

  $tasks = @(
	@{ Name='SFC'; Action={ if (-not $SkipSFC) { $script:SfcExit = Run-SFC } }; Skip=$SkipSFC },
	@{ Name='DISM 3-step'; Action={
		  if (-not $SkipDISM) {
			  Write-Status 'DISM akan dijalankan (unconditional).' 'Info'
			  Run-DISM-3
		  }
		}; Skip=$SkipDISM },
    @{ Name='Reset Windows Update'; Action={ if (-not $SkipWUReset) { Reset-WindowsUpdate } }; Skip=$SkipWUReset },
    @{ Name='Network Fix'; Action={ if (-not $SkipNetworkFix) { Flush-DNS; Reset-Winsock } }; Skip=$SkipNetworkFix },
    @{ Name='Disk Cleanup'; Action={ if (-not $SkipCleanup) { Run-Cleanup } }; Skip=$SkipCleanup },
    @{ Name='Extra Cleanup'; Action={ if (-not $SkipExtraCleanup) { Extra-Cleanup } }; Skip=$SkipExtraCleanup },
    @{ Name='Optimize Drives'; Action={ if (-not $SkipDefrag) { Optimize-Drives } }; Skip=$SkipDefrag },
    @{ Name='CHKDSK'; Action={ if (-not $SkipChkdsk) { Invoke-ChkdskOnlineAndSchedule } }; Skip=$SkipChkdsk },
    @{ Name='Memory Diagnostic'; Action={ if (-not $SkipMemoryDiag) { Invoke-MemoryDiagnostic } }; Skip=$SkipMemoryDiag }
  )

  $TotalSteps = $tasks.Count
  $executed = [System.Collections.ArrayList]::new()
  $i = 0
  foreach ($t in $tasks) {
    $i++
    Section $i $TotalSteps $t.Name
    if ($t.Skip) {
      Write-Status ($t.Name + ' -> [SKIPPED]') 'DarkYellow'
      [void]$executed.Add("[$i/$TotalSteps] $($t.Name) -> SKIPPED")
    } else {
      try {
        & $t.Action
        Write-Status ($t.Name + ' -> [OK]') 'Green'
        [void]$executed.Add("[$i/$TotalSteps] $($t.Name) -> OK")
      } catch {
        Write-Status ($t.Name + ' -> [FAILED] ' + $_.Exception.Message) 'Error'
        [void]$executed.Add("[$i/$TotalSteps] $($t.Name) -> FAILED: $($_.Exception.Message)")
      }
    }
  }

  Write-Host "`n===== RINGKASAN MAINTENANCE =====" -ForegroundColor Cyan
  $executed | ForEach-Object { Write-Host $_ }

  if (-not $NoRestart) {
    if ($ForceAutoRestart -or $Silent) {
      try {
        Schedule-AutoRestart -TimeoutSec 30 -Comment 'Maintenance Windows selesai.'
        Start-Sleep -Seconds 2
      } catch {
        Write-Status 'Fallback: Restart-Computer -Force dalam 30 detik' 'Warn'
        Start-Sleep -Seconds 30
        Restart-Computer -Force
      }
    } else {
      Write-Host "`nSelesai. Restart otomatis dalam 30 detik." -ForegroundColor Yellow
      Write-Host 'Tekan [A] lalu Enter untuk membatalkan.'
      try {
        Schedule-AutoRestart -TimeoutSec 30 -Comment 'Maintenance Windows selesai.'
      } catch {
        Write-Status 'Gagal menjadwalkan via shutdown.exe, gunakan fallback.' 'Warn'
        Start-Sleep -Seconds 30
        Restart-Computer -Force
        throw
      }
      $start = Get-Date
      while ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -lt 30) {
        if ($Host.UI.RawUI.KeyAvailable) {
          $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
          if ($key.Character -in @('A','a')) {
            Abort-Restart
            break
          }
        }
        Start-Sleep -Milliseconds 200
      }
    }
  } else {
    Write-Status 'NoRestart aktif - tidak restart otomatis.' 'DarkYellow'
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

# SIG # Begin signature block
# MIIdhAYJKoZIhvcNAQcCoIIddTCCHXECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBHUowRJxLmjd6x
# LFKIFJ880gCir3y0c7FIpcAzf+qAI6CCA14wggNaMIICQqADAgECAhBKXDr997nE
# lEV/LmcB/M7aMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNVBAYTAklEMRowGAYDVQQK
# DBFEYXRhIEluZm9ybWFzaeKEojEaMBgGA1UEAwwRRGF0YSBJbmZvcm1hc2nihKIw
# HhcNMjUxMDI0MTc1NTQzWhcNMjYxMDI0MTgxNTQzWjBFMQswCQYDVQQGEwJJRDEa
# MBgGA1UECgwRRGF0YSBJbmZvcm1hc2nihKIxGjAYBgNVBAMMEURhdGEgSW5mb3Jt
# YXNp4oSiMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5fkXu9YwJxGQ
# iQTT1aqTxHyoQBqAVN0I+sMwDIGdfU3Gw4GIgSiPFhaMEngvWPg4hhP5aRG01ckW
# V+Eny8TIA5HDI1PCrnJxyzBANu0I4LyXNHyr3YA1W65Y3keOThPRUh2HsZ3i8MfX
# OeBUUeXW30CVZISum9LajAMQYnO2KVDBEOIINiGTuDHWlFCFpB0CfI23SZilZMR5
# gvAcBB5oW1A6gA+MQbBmhuuLFb3fc9SWeWgV0OA3rMLmXqTdgnRY/v1VVzzzmdE6
# xHd2do0bzNF47aXFGxO2OHE0NlVZfeqOJZrl1J25YYPDInOK2tXDwK7s0eTh/kOS
# 7HhMtlQxtQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYB
# BQUHAwMwHQYDVR0OBBYEFNjvWw4GL634EOZ5WOhycVJS3FyiMA0GCSqGSIb3DQEB
# CwUAA4IBAQAZpts/ruWrZ0S+PzpTYxpfOiFHmIi1IYoXEp9/zFcC+UJEvwJL5mzy
# qNwci3hy+XByL9sisUlTdHyPiyKxJZqlfhl9bNaddCKD42agaXMn43+/JfELrGSh
# fKneeRhkOu6Y0cnjEjhLgFINtBwdveWiZm8DJXgYGbrs8S4D4E9D9MX4YvQ6w7Gh
# pSOElYreTMFc8SHtHx1gUEhX0dV8WbdJADeWkI4LQPfaMI53VvPclSjh7i7P/csl
# 6NiaWF9NI2JlwvMwYvPbXUweOROERXsw1oTpEMc5ztlCFb3OAhk5qm+OuXYwtOY7
# ctmseQ2f5Up9VcjnPp+FUsvbv2hhLOnQMYIZfDCCGXgCAQEwWTBFMQswCQYDVQQG
# EwJJRDEaMBgGA1UECgwRRGF0YSBJbmZvcm1hc2nihKIxGjAYBgNVBAMMEURhdGEg
# SW5mb3JtYXNp4oSiAhBKXDr997nElEV/LmcB/M7aMA0GCWCGSAFlAwQCAQUAoHww
# EAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPHOWGA/
# B53rb/thY5lfGMniTWJcWddxnBoopCQaJGFZMA0GCSqGSIb3DQEBAQUABIIBAMMe
# vU79/fTOPYYKzOqvhTEQXMgOWYwGqzIuuqd1PSolmYGbEvDIbz8r6r+cWU225BWK
# ngGMAaDPLNCNGnpnPKZNJMaBupwENZ7qgVK35h+4+FjO4VtSnQ5EWZi+TiU9uIGJ
# ef/MLKaR/LKyF6byKAGt/XfKi7PweMgBt6PtmdYdvzhIDg8d5aZ8PPAq5TYUntNL
# 3SUcJkfWtYOwtiNKge9p0grd2IbEth3z4vyfc/hAaTRUeOjYg4gSDuME7ye9qOUd
# 00nynkIumcvEH/dW71BOWsstmK355i1Z7CXgzkTynn8jzHMlVGtRLOdMAV0jb8M4
# 25VSt7NAKk0k+WghTUyhghd2MIIXcgYKKwYBBAGCNwMDATGCF2IwghdeBgkqhkiG
# 9w0BBwKgghdPMIIXSwIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgNTfgo6C6EN1L
# jRaZoTNq/WAwbC2wgerUeGaFhg4rZjUCEAEZsBhi70co6jyj9h19DiIYDzIwMjUx
# MDMwMTM1NzQyWqCCEzowggbtMIIE1aADAgECAhAKgO8YS43xBYLRxHanlXRoMA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwHhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAz
# MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# OzA5BgNVBAMTMkRpZ2lDZXJ0IFNIQTI1NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNw
# b25kZXIgMjAyNSAxMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0Eas
# LRLGntDqrmBWsytXum9R/4ZwCgHfyjfMGUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI
# 54um8+dnxk36+jx0Tb+k+87H9WPxNyFPJIDZHhAqlUPt281mHrBbZHqRK71Em3/h
# CGC5KyyneqiZ7syvFXJ9A72wzHpkBaMUNg7MOLxI6E9RaUueHTQKWXymOtRwJXcr
# cTTPPT2V1D/+cFllESviH8YjoPFvZSjKs3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg
# 0NP3yiSyi5MxgU6cehGHr7zou1znOM8odbkqoK+lJ25LCHBSai25CFyD23DZgPfD
# rJJJK77epTwMP6eKA0kWa3osAe8fcpK40uhktzUd/Yk0xUvhDU6lvJukx7jphx40
# DQt82yepyekl4i0r8OEps/FNO4ahfvAk12hE5FVs9HVVWcO5J4dVmVzix4A77p3a
# wLbr89A90/nWGjXMGn7FQhmSlIUDy9Z2hSgctaepZTd0ILIUbWuhKuAeNIeWrzHK
# YueMJtItnj2Q+aTyLLKLM0MheP/9w6CtjuuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4C
# WIvuiNN1Lk9Y+xZ66lazs2kKFSTnnkrT3pXWETTJkhd76CIDBbTRofOsNyEhzZtC
# GmnQigpFHti58CSmvEyJcAlDVcKacJ+A9/z7eacCAwEAAaOCAZUwggGRMAwGA1Ud
# EwEB/wQCMAAwHQYDVR0OBBYEFOQ7/PIx7f391/ORcWMZUEPPYYzoMB8GA1UdIwQY
# MBaAFO9vU0rp5AZ8esrikFb2L9RJ7MtOMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDCBlQYIKwYBBQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBdBggrBgEFBQcwAoZRaHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3J0MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGlu
# Z1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAGUqrfEcJwS5rmBB7NEIRJ5j
# QHIh+OT2Ik/bNYulCrVvhREafBYF0RkP2AGr181o2YWPoSHz9iZEN/FPsLSTwVQW
# o2H62yGBvg7ouCODwrx6ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7YXwBD9R0oU62Ptgx
# Oao872bOySCILdBghQ/ZLcdC8cbUUO75ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM
# 3pHfKBAEcxQFoHlt2s9sXoxFizTeHihsQyfFg5fxUFEp7W42fNBVN4ueLaceRf9C
# q9ec1v5iQMWTFQa0xNqItH3CPFTG7aEQJmmrJTV3Qhtfparz+BW60OiMEgV5GWoB
# y4RVPRwqxv7Mk0Sy4QHs7v9y69NBqycz0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdj
# nQ4eBpjtP+XB3pQCtv4E5UCSDag6+iX8MmB10nfldPF9SVD7weCC3yXZi/uuhqdw
# kgVxuiMFzGVFwYbQsiGnoa9F5AaAyBjFBtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d
# 1SVDTmjFjLbNFZUWMXuZyvgLfgyPehwJVxwC+UpX2MSey2ueIu9THFVkT+um1vsh
# ETaWyQo8gmBto/m3acaP9QsuLj3FNwFlTxq25+T4QwX9xa6ILs84ZPvmpovq90K8
# eWyG2N01c4IhSOxqt81nMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjAN
# BgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5
# WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx
# 0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz
# 4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJ
# gMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQ
# bzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6
# bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJ
# RfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU1
# 4lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDD
# jAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cn
# T6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq
# 1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqg
# PrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1Ud
# EwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8G
# A1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjAT
# BgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYD
# VR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9
# bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfF
# iBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4
# /iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/
# DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HR
# trYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2
# o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K
# 9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc
# 3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLi
# Ru7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAv
# jSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3J
# E3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM
# 1pD2T7m3XDCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFowDQYJKoZIhvcN
# AQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJl
# ZCBJRCBSb290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIzNTk1OVowYjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2jeu+RdSjwwIjBp
# M+zCpyUuySE98orYWcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bGl20dq7J58soR
# 0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBEEC7fgvMHhOZ0
# O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/NrDRAX7F6Zu53
# yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A2raRmECQecN4
# x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8IUzUvK4bA3Vd
# eGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfBaYh2mHY9WV1C
# doeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaaRBkrfsCUtNJh
# besz2cXfSwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZifvaAsPvoZKYz
# 0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXeeqxfjT/JvNNB
# ERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g/KEexcCPorF+
# CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB/wQFMAMBAf8w
# HQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQYMBaAFEXroq/0
# ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEFBQcBAQRtMGsw
# JAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcw
# AoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElE
# Um9vdENBLmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1UdIAQKMAgwBgYE
# VR0gADANBgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22Ftf3v1cHvZqs
# oYcs7IVeqRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih9/Jy3iS8UgPI
# TtAq3votVs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYDE3cnRNTnf+hZ
# qPC/Lwum6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c2PR3WlxUjG/v
# oVA9/HYJaISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88nq2x2zm8jLfR+
# cWojayL/ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5lDGCA3wwggN4
# AgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEw
# PwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2
# IFNIQTI1NiAyMDI1IENBMQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEF
# AKCB0TAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkFMQ8X
# DTI1MTAzMDEzNTc0MlowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQU3WIwrIYKLTBr
# 2jixaHlSMAf7QX4wLwYJKoZIhvcNAQkEMSIEINEC9BiBC+I0ij2EBqyjLalRg5Hy
# lxvpazTbNqh0x0A7MDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIEqgP6Is11yExVyT
# j4KOZ2ucrsqzP+NtJpqjNPFGEQozMA0GCSqGSIb3DQEBAQUABIICAAPMfLmz1GpY
# GSbf2YsSX2ASHsoZNmeY98k0ZgUE7Zu7pm8ZkyDlyD6TNs26huDCnCPc2WcZR6zm
# WKy332anGR9Li0Hh3TQYC/XFeGTiruShZnJIUPGdSVr2tUbz2blFBeVAa9V/amKu
# rXW48if3sAvBdloZPJc+BVlF4ImiJGFKkBgS4GZmzagGnSSRHKrjk9Et8Q4m0AwS
# jrN8yPJKH7Qeky24QarpzMbYGxSUGFIoWKtZQ3wI/wpTL2J9jw68DIGSbLdHupBa
# Y54Pfdi6x7or9uWKWXAkHxx/ENH8dVtLv2JJvNOAAm3gbqnc84XerYQFI6nZXgKf
# rWAOOCz8pM0thKZivu0pSOEyR9HDXWTUFE2e8LiFlpWaMjGNFUVR/Afap23IS2GB
# p3NAeUSK9eOQwBDNGJDwKIQ+6rZu7l2A/SycVHthqlAC0oupYpNialP61z4qXHtU
# fViJBkQkVrRjATjMC0WQNCd6U7nGqnJqKnAW4dYK4w1ZO47E6BpEIxqIqIB+MWMR
# akc+rd62Z6PM7buKJrlaQ4TnNPmkVqe7q1UaeKo6q+eFVJsmyT//g1jafj1geYSN
# ZRjIkd9rxz1s8MhnMAXtWxW46kFzGHoXtRiUecAc21OFpYEmLwDtaf+KP7nY+2JC
# O4VuN/cMnJQ9UlFphAIUSb3JJy/VfnS2
# SIG # End signature block

