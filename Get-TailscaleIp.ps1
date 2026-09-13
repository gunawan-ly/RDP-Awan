<#
.SYNOPSIS
  Tampilkan alamat Tailscale PC untuk koneksi Windows App. PRD Fase 7.
  TIDAK memakai public IP.

.DESCRIPTION
  - Cek tailscale.exe di PATH / "C:\Program Files\Tailscale".
  - Cek service Tailscale berjalan, cek "tailscale status" / "tailscale ip -4".
  - Ambil MagicDNS hostname via "tailscale status --json" (best-effort).
  - Cek TermService + NLA + port RDP untuk blok status.
  - Output format "RDP READY" sesuai PRD. Exit != 0 jika Tailscale tidak connected.

.PARAMETER RdpPort
  Default 3389 / $env:RDP_PORT.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Get-TailscaleIp.ps1
#>
[CmdletBinding()]
param(
    [int]$RdpPort = 0
)

$ErrorActionPreference = 'Continue'

function Get-RdpPort {
    param([int]$Override)
    if ($Override -gt 0) { return $Override }
    if ($env:RDP_PORT) {
        $parsed = 0
        if ([int]::TryParse($env:RDP_PORT, [ref]$parsed) -and $parsed -gt 0 -and $parsed -le 65535) {
            return $parsed
        }
    }
    return 3389
}

function Find-TailscaleExe {
    $cands = @()
    $fromPath = (Get-Command 'tailscale.exe' -ErrorAction SilentlyContinue)
    if ($fromPath) { $cands += $fromPath.Source }
    $cands += 'C:\Program Files\Tailscale\tailscale.exe'
    $cands += 'C:\Program Files (x86)\Tailscale\tailscale.exe'
    foreach ($c in $cands) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

$Port = Get-RdpPort -Override $RdpPort
$tailscaleExe = Find-TailscaleExe

if (-not $tailscaleExe) {
    Write-Error 'ERROR: Tailscale tidak terinstall (tailscale.exe tidak ditemukan). Install dari https://tailscale.com/download lalu "tailscale up". (exit 40)'
    exit 40
}

# Service check (best-effort: nama service resmi = Tailscale)
try {
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Write-Warning 'Service Tailscale tidak Running. Mencoba start...'
        try { Start-Service -Name 'Tailscale' -ErrorAction Stop; Start-Sleep -Seconds 3 } catch {}
    }
} catch {}

# Status + IPv4
$tsIp = ''
$tsStatus = 'Unknown'
$magicDns = ''
try {
    $ipOut = & $tailscaleExe ip -4 2>&1 | Where-Object { $_ -match '^100\.' } | Select-Object -First 1
    if ($ipOut) { $tsIp = $ipOut.ToString().Trim() }
} catch {}
try {
    $jsonRaw = & $tailscaleExe status --json 2>$null
    if ($jsonRaw) {
        $st = $jsonRaw | ConvertFrom-Json
        if ($st.BackendState) { $tsStatus = $st.BackendState }
        if ($st.Self) {
            if ($st.Self.DNSName) { $magicDns = $st.Self.DNSName.TrimEnd('.') }
            elseif ($st.Self.HostName) { $magicDns = $st.Self.HostName }
        }
    } else {
        $txt = & $tailscaleExe status 2>&1 | Out-String
        if ($txt -match 'Logged out|NeedsLogin|NoState') { $tsStatus = 'LoggedOut' }
        elseif ($txt -match '100\.') { $tsStatus = 'Running' }
    }
} catch {}

if (-not $tsIp) {
    Write-Error 'ERROR: Tidak ada Tailscale IPv4 (100.x.x.x). Kemungkinan: belum "tailscale up", belum login/auth, atau service tidak jalan. Jalankan "tailscale status" lalu "tailscale up". (exit 41)'
    exit 41
}
if (-not $tsStatus -or $tsStatus -eq 'Unknown') { $tsStatus = 'Connected' }

# RDP service + NLA (best-effort, untuk display)
$rdpSvc = 'Unknown'
try {
    $s = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
    if ($s) { $rdpSvc = $s.Status.ToString() }
} catch {}
$nla = 'Unknown'
try {
    $v = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
    if ($v -eq 1) { $nla = 'Enabled' } elseif ($null -ne $v) { $nla = "Disabled ($v)" }
} catch {}

$line = '========================================'
Write-Output $line
Write-Output 'RDP READY'
Write-Output ''
Write-Output ("Tailscale Status : {0}" -f $tsStatus)
Write-Output ("Tailscale IPv4   : {0}" -f $tsIp)
Write-Output ("RDP Port         : {0}" -f $Port)
Write-Output ("NLA              : {0}" -f $nla)
Write-Output ("RDP Service      : {0}" -f $rdpSvc)
Write-Output ''
Write-Output 'Windows App:'
Write-Output 'Connect to:'
Write-Output ("  {0}" -f $tsIp)
if ($Port -ne 3389) { Write-Output ("  {0}:{1}" -f $tsIp, $Port) }
if ($magicDns) {
    Write-Output 'MagicDNS:'
    Write-Output ("  {0}" -f $magicDns)
    if ($Port -ne 3389) { Write-Output ("  {0}:{1}" -f $magicDns, $Port) }
}
Write-Output ''
Write-Output '(Jangan gunakan public IP. RDP hanya via tailnet Tailscale.)'
Write-Output '(Display terkunci di sesi remote = normal. Atur resolusi & skala di'
Write-Output ' Windows App pengaturan PC -> Display; resize/fullscreen jendela'
Write-Output ' menyesuaikan otomatis.)'
Write-Output $line
exit 0
