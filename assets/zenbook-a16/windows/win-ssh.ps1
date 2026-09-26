# Enable OpenSSH Server on Windows and authorize the Beelink's key. Run in an elevated PowerShell:
#   irm http://192.168.0.24:53317/win-ssh.ps1 | iex
$ErrorActionPreference = 'Stop'
Write-Host "== installing OpenSSH Server (may take a minute)"
$cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
Set-Service sshd -StartupType Automatic
Start-Service sshd
Write-Host "== authorizing key"
$raw = (Invoke-WebRequest -UseBasicParsing 'http://192.168.0.24:53317/key.pub').Content
if ($raw -is [byte[]]) { $raw = [System.Text.Encoding]::ASCII.GetString($raw) }
$key = ([string]$raw).Trim()
$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
Set-Content -Path $f -Value $key -Encoding ascii
icacls $f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
Write-Host "== firewall"
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
Restart-Service sshd
Write-Host "== done. user: $env:USERNAME  computer: $env:COMPUTERNAME"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | ForEach-Object { Write-Host ("   ip: " + $_.IPAddress) }
