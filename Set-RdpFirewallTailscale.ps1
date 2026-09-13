<#
.SYNOPSIS
  Konfigurasi Windows Firewall agar RDP hanya dapat diakses via Tailscale.
  PRD Fase 5. Idempotent. TIDAK PERNAH membuka 3389 ke Internet.

.DESCRIPTION
  Masalah legacy: enable_rdp_and_open_port.bat membuat rule
    netsh advfirewall firewall add rule name="Allow RDP TCP 3389" ... profile=any
  yang mengekspos RDP ke semua interface publik.

  Strategi robust (tidak bergantung pada nama adapter "Tailscale" yang rapuh):
  - Hapus/nonaktifkan legacy rule "Allow RDP TCP <port>" dengan profile=any.
  - Buat SATU rule idempotent:
      Name        : "Allow RDP from Tailscale only"
      Dir         : In, Action: Allow, Protocol: TCP, LocalPort: <RdpPort>
      RemoteAddress: 100.64.0.0/10  (Carrier-Grade NAT range resmi Tailscale, 100.x.x.x)
      Profile     : Any (profile host tetap aktif; pembatasan dilakukan via RemoteAddress,
                    sehingga interface publik dengan IP non-100.64/10 tetap DITOLAK)
  - Windows Firewall service tetap aktif (tidak pernah di-disable).
  - Tidak membuat duplicate rule saat dijalankan berulang.

  Catatan keamanan: RemoteAddress 100.64.0.0/10 mencakup seluruh tailnet CGNAT.
  Ini jauh lebih aman daripada profile=any tanpa batasan, dan portable di semua
  instalasi Windows tanpa menebak InterfaceAlias. Jika Tailnet memakai subnet
  tambahan (subnet router), admin dapat menambahkannya manual — tidak dibuka otomatis.

.PARAMETER RdpPort
  Default 3389, bisa via $env:RDP_PORT.

.PARAMETER RuleName
  Nama rule baru. Default "Allow RDP from Tailscale only".

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Set-RdpFirewallTailscale.ps1
#>
[CmdletBinding()]
param(
    [int]$RdpPort = 0,
    [string]$RuleName = 'Allow RDP from Tailscale only'
)

$ErrorActionPreference = 'Stop'

# Tailscale IPv4 resmi selalu di 100.64.0.0/10 (100.64.0.0 - 100.127.255.255).
$TailscaleCgnat = '100.64.0.0/10'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

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

if (-not (Test-IsAdmin)) {
    Write-Error 'ERROR: Script harus dijalankan sebagai Administrator. (exit 10)'
    exit 10
}

$Port = Get-RdpPort -Override $RdpPort

# 1. Pastikan Windows Firewall service ada dan berjalan (jangan pernah disable).
try {
    $fw = Get-Service -Name 'MpsSvc' -ErrorAction Stop
    if ($fw.Status -ne 'Running') {
        Write-Output 'Windows Firewall (MpsSvc): mencoba start...'
        Start-Service -Name 'MpsSvc' -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    Write-Output 'Windows Firewall (MpsSvc): Running.'
} catch {
    Write-Error "ERROR: Windows Firewall service (MpsSvc) tidak tersedia/ gagal start: $($_.Exception.Message) (exit 30)"
    exit 30
}

# 2. Hapus legacy rule publik "Allow RDP TCP <port>" (profile=any tanpa batasan).
#    Idempotent: tidak error jika tidak ada.
$legacyPatterns = @("Allow RDP TCP $Port", 'Allow RDP TCP 3389', 'Allow RDP TCP *')
foreach ($pat in $legacyPatterns) {
    try {
        $hits = Get-NetFirewallRule -DisplayName $pat -ErrorAction SilentlyContinue
        foreach ($h in $hits) {
            # Hanya hapus yang TIDAK dibatasi ke Tailscale (RemoteAddress = Any).
            $addr = (Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $h -ErrorAction SilentlyContinue).RemoteAddress
            if (-not $addr -or $addr -contains 'Any') {
                Remove-NetFirewallRule -DisplayName $h.DisplayName -ErrorAction SilentlyContinue
                Write-Output "Legacy public rule dihapus: '$($h.DisplayName)' (mengekspos 3389 ke ANY)."
            } else {
                Write-Output "Rule '$($h.DisplayName)' sudah dibatasi ($($addr -join ',')) — dipertahankan."
            }
        }
    } catch {
        Write-Warning "Gagal audit legacy rule '$pat': $($_.Exception.Message)"
    }
}

# 3. Buat/pastikan rule Tailscale-only (idempotent).
try {
    $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($existing) {
        # Verifikasi propertinya benar; perbaiki jika melenceng.
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing[0] -ErrorAction SilentlyContinue
        $addrFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $existing[0] -ErrorAction SilentlyContinue
        $needFix = $false
        if ($portFilter.Protocol -ne 'TCP' -or ($portFilter.LocalPort -notcontains "$Port")) { $needFix = $true }
        if (-not ($addrFilter.RemoteAddress -contains $TailscaleCgnat)) { $needFix = $true }
        if ($existing[0].Enabled -ne 'True' -or $existing[0].Direction -ne 'Inbound' -or $existing[0].Action -ne 'Allow') { $needFix = $true }
        if ($needFix) {
            Remove-NetFirewallRule -DisplayName $RuleName -ErrorAction Stop
            Write-Output "Rule '$RuleName' ada tapi tidak sesuai — dibuat ulang."
            $existing = $null
        } else {
            Write-Output "Rule '$RuleName': sudah benar (idempotent, skip). TCP/$Port dari $TailscaleCgnat."
        }
    }
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $RuleName `
            -Description 'RDP hanya via Tailscale tailnet (100.64.0.0/10). Dibuat oleh Set-RdpFirewallTailscale.ps1. Jangan ubah ke RemoteAddress Any.' `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
            -RemoteAddress $TailscaleCgnat `
            -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        Write-Output "Rule '$RuleName' dibuat: ALLOW TCP/$Port FROM $TailscaleCgnat."
    }
} catch {
    Write-Error "ERROR: Gagal membuat firewall rule: $($_.Exception.Message) (exit 31)"
    exit 31
}

# 4. Verifikasi akhir: pastikan tidak ada rule RDP lain yang ALLOW dari Any.
try {
    $suspicious = @()
    $all = Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object { $_.Action -eq 'Allow' -and $_.Enabled -eq 'True' }
    foreach ($r in $all) {
        $pf = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
        if ($pf -and $pf.Protocol -eq 'TCP' -and ($pf.LocalPort -contains "$Port" -or $pf.LocalPort -contains '3389')) {
            $af = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
            if ($af -and ($af.RemoteAddress -contains 'Any')) {
                if ($r.DisplayName -ne $RuleName) {
                    $suspicious += $r.DisplayName
                }
            }
        }
    }
    if ($suspicious.Count -gt 0) {
        Write-Warning ("Masih ada rule RDP lain yang ALLOW dari ANY: {0}. Hapus manual atau jalankan ulang script." -f ($suspicious -join '; '))
        Write-Error 'ERROR: Firewall belum aman — RDP masih terekspos via rule lain. (exit 32)'
        exit 32
    }
} catch {
    Write-Warning "Verifikasi akhir firewall tidak lengkap: $($_.Exception.Message)"
}

Write-Output "OK: Firewall aman. RDP TCP/$Port hanya dari $TailscaleCgnat (Tailscale). Tidak ada ALLOW FROM ANYWHERE."
exit 0
