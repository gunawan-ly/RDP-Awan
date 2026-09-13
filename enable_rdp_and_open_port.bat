@echo off
REM =====================================================================
REM DEPRECATED (Legacy) — enable_rdp_and_open_port.bat
REM PRD Fase 5 + Fase 19: versi lama membuat rule "profile=any" yang
REM mengekspos RDP (TCP 3389) ke Internet. JANGAN dipakai untuk setup baru.
REM
REM Workflow baru (default):
REM   powershell -ExecutionPolicy Bypass -File setup_rdp_tailscale.ps1
REM yang mengaktifkan RDP+NLA dan membatasi firewall hanya via Tailscale
REM (100.64.0.0/10). Lihat README.md bagian Legacy / Deprecated.
REM
REM File ini dipertahankan sebagai wrapper kompatibilitas: ia meneruskan
REM ke Enable-RdpHost.ps1 + Set-RdpFirewallTailscale.ps1 yang aman.
REM Run as Administrator.
REM =====================================================================

set RDP_PORT=3389
if defined RDP_PORT_ENV set RDP_PORT=%RDP_PORT_ENV%

echo [DEPRECATED] enable_rdp_and_open_port.bat diteruskan ke workflow Tailscale-only...
echo [DEPRECATED] Gunakan: powershell -ExecutionPolicy Bypass -File setup_rdp_tailscale.ps1
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enable-RdpHost.ps1" -RdpPort %RDP_PORT%
if %errorlevel% neq 0 (
  echo ERROR: Enable-RdpHost.ps1 gagal dengan exit code %errorlevel%.
  exit /b %errorlevel%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-RdpFirewallTailscale.ps1" -RdpPort %RDP_PORT%
if %errorlevel% neq 0 (
  echo ERROR: Set-RdpFirewallTailscale.ps1 gagal dengan exit code %errorlevel%.
  echo RDP TIDAK dibiarkan setengah aman. Periksa output di atas.
  exit /b %errorlevel%
)

echo.
echo Done (via deprecated wrapper).
echo - Remote Desktop enabled dengan NLA.
echo - Firewall: RDP TCP %RDP_PORT% HANYA via Tailscale (100.64.0.0/10), bukan profile=any publik.
echo - Lihat Tailscale IP dengan: powershell -ExecutionPolicy Bypass -File "%~dp0Get-TailscaleIp.ps1"
echo Catatan: jangan membuka 3389 ke Internet / port-forwarding. Gunakan Windows App + Tailscale IP.
