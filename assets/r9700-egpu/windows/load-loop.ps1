# Same test as Linux: repeated model loads, one llama-bench process each, stop at the first failure.
param([int]$Loads = 10, [string]$Dev = "", [string]$Model = "")
$root = "C:\egpu-test"; $bench = "$root\llama\llama-bench.exe"
$log = "$root\load-loop.log"
# The model: -Model, else C:\egpu-test\models\..., else <any drive>:\models\... (e.g. the USB stick)
$name = "Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
$model = if ($Model) { $Model } else { @("$root\models\$name") + (Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root "models\$name" }) | Where-Object { Test-Path $_ } | Select-Object -First 1 }
if (-not $Dev) { $Dev = ((& $bench --list-devices 2>&1) | Select-String "^\s*Vulkan\d+:.*R9700" | Select-Object -First 1).ToString().Trim().Split(":")[0] }
"start $(Get-Date -Format T) device=$Dev" | Set-Content $log
for ($n = 1; $n -le $Loads; $n++) {
  $t0 = Get-Date
  $p = Start-Process $bench -ArgumentList "-m `"$model`" -dev $Dev -ngl 99 -fa 1 -p 64 -n 16 -r 1" -NoNewWindow -PassThru `
       -RedirectStandardOutput "$root\bench-$n.out" -RedirectStandardError "$root\bench-$n.err"
  $null = $p.Handle   # without this, PowerShell often reports an empty ExitCode
  if (-not $p.WaitForExit(300000)) { $p.Kill(); $rc = "TIMEOUT" } else { $rc = $p.ExitCode }
  $tg = (Select-String -Path "$root\bench-$n.out" -Pattern "tg16\s*\|\s*([0-9.]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ""
  "$(Get-Date -Format T) load=$n rc=$rc secs=$([int]((Get-Date)-$t0).TotalSeconds) tg16=$(if ($tg) {$tg} else {'none'})" | Add-Content $log
  if ($rc -ne 0 -or -not $tg) { "FAILED at load $n" | Add-Content $log; break }
}
"done $(Get-Date -Format T)" | Add-Content $log; Get-Content $log
