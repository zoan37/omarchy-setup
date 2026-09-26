$ErrorActionPreference = 'Continue'
$out = 'C:\ecdump'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $out 'ec-dump.txt'; Remove-Item $log -ErrorAction SilentlyContinue
function Log($s) { $s | Tee-Object -FilePath $log -Append }
Log "=== $(Get-Date)"
$atd = Get-CimInstance -Namespace root/wmi -ClassName ATD_STS
$iec = Get-CimInstance -Namespace root/wmi -ClassName IecToolkitInterface
$atk = Get-CimInstance -Namespace root/wmi -ClassName AsusAtkWmi_WMNB
Log ("ec version: " + (Invoke-CimMethod -InputObject $atd -MethodName ec_get_version).version)
function RecM([int]$addr) {
  $in = [uint64[]]@(0x00800007, 0, $addr, 1, 0, 0, 0)
  $r = Invoke-CimMethod -InputObject $iec -MethodName SystemMethod -Arguments @{ InData = $in }
  return $r.OutData
}
$t = RecM 0x0602; Log ("RECM(0x0602) OutData: " + ($t -join ' '))
$lo = (RecM 0x0602)[1]; $hi = (RecM 0x0603)[1]; Log ("FAN RPM = " + (([int]$hi -shl 8) -bor [int]$lo))
function Erb([int]$a, [int]$b) { (Invoke-CimMethod -InputObject $atd -MethodName ec_read_byte -Arguments @{ haddr = [byte]$a; laddr = [byte]$b }).value }
foreach ($p in @(@(0xC9,0x6E),@(0xC9,0x6F),@(0xC9,0x40),@(0xC4,0x30),@(0xC4,0x31),@(0xC4,0x32))) {
  Log ("ec_read_byte(haddr=0x{0:x2}, laddr=0x{1:x2}) = {2}   swapped(haddr=0x{1:x2}, laddr=0x{0:x2}) = {3}" -f $p[0], $p[1], (Erb $p[0] $p[1]), (Erb $p[1] $p[0]))
}
foreach ($p in @(@(0x83,2),@(2,0x83),@(0x84,2),@(0x81,1))) {
  $r = Invoke-CimMethod -InputObject $atd -MethodName ec_read_command_byte -Arguments @{ commandcode = [byte]$p[0]; param0 = [byte]$p[1] }
  Log ("ec_read_command_byte(commandcode=0x{0:x2}, param0={1}) = {2}" -f $p[0], $p[1], $r.value)
}
foreach ($id in @(0x00110024,0x00110025,0x00110026,0x00110019,0x00110018,0x00110035,0x00120057,0x00100071)) {
  $r = Invoke-CimMethod -InputObject $atk -MethodName DSTS -Arguments @{ Device_ID = [uint32]$id }
  Log ("DSTS(0x{0:x8}) = 0x{1:x8}" -f $id, [uint32]$r.device_status)
}
Log "--- EC RAM dump 0x0000-0x0FFF"
$dump = Join-Path $out 'ecram-windows.txt'; Remove-Item $dump -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
for ($a = 0; $a -lt 0x1000; $a++) { $v = RecM $a; [void]$sb.AppendLine(('{0:x4} {1} {2}' -f $a, $v[0], $v[1])) }
[IO.File]::WriteAllText($dump, $sb.ToString())
Log ("dump lines: " + (Get-Content $dump).Count)
Log "=== done"
