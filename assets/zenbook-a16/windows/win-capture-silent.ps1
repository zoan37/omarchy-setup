$ErrorActionPreference = 'Continue'
$out = 'C:\ecdump'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $out 'ec-dump.txt'; Remove-Item $log -ErrorAction SilentlyContinue
function Log($s) { $s | Tee-Object -FilePath $log -Append }
$atd = Get-CimInstance -Namespace root/wmi -ClassName ATD_STS
$iec = Get-CimInstance -Namespace root/wmi -ClassName IecToolkitInterface
function RecM([int]$addr) { $f0 = ([uint64]0x2357 -shl 32) -bor [uint64]0x00800007; $in = [uint64[]]@($f0,[uint64]0,[uint64]$addr,[uint64]1,[uint64]0,[uint64]0,[uint64]0); (Invoke-CimMethod -InputObject $iec -MethodName SystemMethod -Arguments @{ InData = $in }).OutData }
function Rpm { $lo=(RecM 0x0602)[1]; $hi=(RecM 0x0603)[1]; ([int]$hi -shl 8) -bor [int]$lo }
function Erb([int]$dev,[int]$reg) { (Invoke-CimMethod -InputObject $atd -MethodName ec_read_byte -Arguments @{ haddr=[byte]$dev; laddr=[byte]$reg }).value }
Log "=== $(Get-Date)  waiting for fan to stop (max 6 min)"
$stopped = $false
for ($i = 0; $i -lt 18; $i++) { $r = Rpm; Log ("t={0}s rpm={1}" -f ($i*20), $r); if ($r -eq 0) { $stopped = $true; break }; Start-Sleep 20 }
Log ("fan stopped: " + $stopped + "  (capturing regardless)")
Log "--- block engine 0xC9 [0x40..0x4F,0x6E,0x6F] and mailbox 0xC4 [0x30..0x32]"
Log ("0xC9[0x6E]={0} 0xC9[0x6F]={1} 0xC9[0x40..0x47]={2}" -f (Erb 0xC9 0x6E), (Erb 0xC9 0x6F), ((0x40..0x47 | ForEach-Object { Erb 0xC9 $_ }) -join ' '))
Log ("0xC4[0x30]={0} 0xC4[0x31]={1} 0xC4[0x32]={2}" -f (Erb 0xC4 0x30), (Erb 0xC4 0x31), (Erb 0xC4 0x32))
Log "--- ECCR reads (mailbox get): bank/feature both orders"
foreach ($p in @(@(0x83,2),@(2,0x83),@(0x84,2),@(2,0x84),@(0x87,1),@(1,0x87))) { $r = Invoke-CimMethod -InputObject $atd -MethodName ec_read_command_byte -Arguments @{ commandcode=[byte]$p[0]; param0=[byte]$p[1] }; Log ("ec_read_command_byte(0x{0:x2},{1}) = {2}" -f $p[0],$p[1],$r.value) }
Log ("--- sensors 0x0604/0x0B45..0x0B53: " + ((@(0x0604) + (0x0B45..0x0B53) | ForEach-Object { (RecM $_)[1] }) -join ' '))
Log "--- EC RAM dump 0x0000-0x0FFF"
$dump = Join-Path $out 'ecram-windows.txt'; $sb = New-Object System.Text.StringBuilder
for ($a = 0; $a -lt 0x1000; $a++) { $v = RecM $a; [void]$sb.AppendLine(('{0:x4} {1} {2}' -f $a, $v[0], $v[1])) }
[IO.File]::WriteAllText($dump, $sb.ToString())
Log ("dump lines: " + (Get-Content $dump).Count + "  rpm now: " + (Rpm))
Log "=== done"
