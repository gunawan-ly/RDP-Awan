<#
.DEPRECATED (Legacy) — PRD Fase 10 + Fase 19.
AnyDesk TIDAK lagi menjadi mekanisme remote-access utama/default.
Workflow default sekarang: Tailscale + native Windows RDP + Microsoft Windows App.
File ini dipertahankan untuk audit/diagnostik manual saja dan TIDAK dipanggil
oleh setup_rdp_tailscale.ps1 maupun GitHub workflows baru. Lihat README.md
bagian Legacy / Deprecated.

.SYNOPSIS
  Detect AnyDesk, optionally set unattended password, retrieve AnyDesk ID and public IP, and output JSON.

.PARAMETER Password
  (Optional) Unattended access password to set. Requires administrative privileges.

.PARAMETER AnyDeskPath
  (Optional) Full path to AnyDesk executable. If omitted, script tries common install locations.
#>

param(
    [string]$Password = $null,
    [string]$AnyDeskPath = $null,
    [int]$TimeoutSec = 10
)

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Find-AnyDesk {
    $paths = @()
    if ($AnyDeskPath) { $paths += $AnyDeskPath }
    $paths += Join-Path $env:ProgramFiles "AnyDesk\AnyDesk.exe"
    $paths += Join-Path ${env:ProgramFiles(x86)} "AnyDesk\AnyDesk.exe"
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-AnyDeskID($exe) {
    try {
        Start-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        
        # Coba ambil ID hingga 5 kali percobaan
        for ($i = 0; $i -lt 5; $i++) {
            $id = & $exe --get-id 2>&1
            if ($id -match '^\d+$') {
                return $id.Trim()
            }
            Start-Sleep -Seconds 3
        }

        # Cadangan: Baca langsung dari berkas konfigurasi AnyDesk
        $confPath = "$env:ProgramData\AnyDesk\system.conf"
        if (Test-Path $confPath) {
            $match = Select-String -Path $confPath -Pattern "ad.anynet.id=(\d+)"
            if ($match -and $match.Matches.Groups[1].Value) {
                return $match.Matches.Groups[1].Value
            }
        }
        return "error"
    } catch {
        return "error"
    }
}

function Set-AnyDeskPassword($exe, $pwd) {
    $tmp = Join-Path $env:TEMP ("ad_pwd_{0}.txt" -f ([guid]::NewGuid()))
    try {
        Set-Content -Path $tmp -Value $pwd -Encoding ASCII -Force
        $cmd = "type `"$tmp`" | `"$exe`" --set-password"
        # Cukup gunakan -NoNewWindow -Wait tanpa -WindowStyle
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -NoNewWindow -Wait
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Get-PublicIP {
    $urls = @('https://api.ipify.org', 'https://ifconfig.me/ip')
    foreach ($url in $urls) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $TimeoutSec
            if ($resp.Content) { return $resp.Content.Trim() }
        } catch {}
    }
    return ""
}

# --- Main Execution ---
$exe = Find-AnyDesk
$result = [ordered]@{
    anydesk_path = $exe
    anydesk_id   = $null
    public_ip    = $null
    set_password = $false
    note         = $null
}

if (-not $exe) {
    $result.note = "AnyDesk not found. Use -AnyDeskPath to specify manually."
    $result | ConvertTo-Json -Depth 4
    exit 1
}

$result.anydesk_id = Get-AnyDeskID $exe
$result.public_ip  = Get-PublicIP

if ($Password) {
    if (Test-IsAdmin) {
        $result.set_password = Set-AnyDeskPassword $exe $Password
        if (-not $result.set_password) {
            $result.note = "Failed to set password."
        }
    } else {
        $result.note = "Admin rights required to set password."
    }
}

# --- Output ---
$json = $result | ConvertTo-Json -Depth 4
Write-Output $json
Write-Output ""
Write-Output "AnyDesk Path : $($result.anydesk_path)"
Write-Output "AnyDesk ID   : $($result.anydesk_id)"
Write-Output "Public IP    : $($result.public_ip)"
if ($Password) {
    Write-Output "Password     : $(if ($result.set_password) { '(was set)' } else { '(failed)' })"
}
exit 0
