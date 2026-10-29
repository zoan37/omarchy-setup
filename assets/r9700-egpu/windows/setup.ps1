# R9700 eGPU test kit for Windows. Run in an *Administrator* PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass; .\setup.ps1
$ErrorActionPreference = "Stop"
$root = "C:\egpu-test"; New-Item -ItemType Directory -Force -Path "$root\models" | Out-Null

# 1. OpenSSH server, so the laptop can run the tests remotely (key login only for this key)
if (-not (Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0).State.Equals("Installed")) {
  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null }
Set-Service sshd -StartupType Automatic; Start-Service sshd
$ak = "C:\ProgramData\ssh\administrators_authorized_keys"
Get-Content "$PSScriptRoot\claude-laptop.pub" | Add-Content $ak
icacls $ak /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Protocol TCP -LocalPort 22 -Action Allow -Direction Inbound | Out-Null }

# 2. llama.cpp, Windows Vulkan build (same backend as the Linux tests)
$ver = "b11969"
Invoke-WebRequest "https://github.com/ggml-org/llama.cpp/releases/download/$ver/llama-$ver-bin-win-vulkan-x64.zip" -OutFile "$root\llama.zip"
Expand-Archive "$root\llama.zip" -DestinationPath "$root\llama" -Force

# 3. The same model as on Linux (18.6 GB)
$m = "$root\models\Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
# Use a copy on any drive (e.g. the USB stick: <drive>:\models\...) before downloading
$stick = Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root "models\Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf" } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not (Test-Path $m) -and $stick) { Write-Host "Copying the model from the USB stick..."; Copy-Item $stick $m }
if (-not (Test-Path $m)) { curl.exe -L -o $m "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf" }

Copy-Item "$PSScriptRoot\load-loop.ps1" $root -Force
Write-Host "Done. IP address(es):"; Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object InterfaceAlias, IPAddress
& "$root\llama\llama-bench.exe" --list-devices
