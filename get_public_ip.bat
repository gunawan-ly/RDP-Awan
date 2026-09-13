@echo off
setlocal
REM =====================================================================
REM DEPRECATED untuk workflow RDP (PRD Fase 11 + Fase 19).
REM RDP baru TIDAK boleh memakai public IP — gunakan Tailscale IP via:
REM   powershell -ExecutionPolicy Bypass -File Get-TailscaleIp.ps1
REM Script ini dipertahankan hanya untuk keperluan non-RDP.
REM =====================================================================

echo [DEPRECATED untuk RDP] Gunakan Get-TailscaleIp.ps1, bukan public IP, untuk alamat RDP.
echo.

set "JSONFILE=%TEMP%\public_ip.json"
if exist "%JSONFILE%" del "%JSONFILE%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command " $ip = Invoke-RestMethod 'https://api.ipify.org'; @{ip=$ip} | ConvertTo-Json | Out-File '%JSONFILE%' -Encoding UTF8 "

if exist "%JSONFILE%" (
    echo Public IP JSON:
    type "%JSONFILE%"
) else (
    echo Failed to retrieve public IP.
)

endlocal
