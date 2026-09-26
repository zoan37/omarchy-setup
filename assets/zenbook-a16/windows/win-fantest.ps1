$atd = Get-CimInstance -Namespace root/wmi -ClassName ATD_STS
$iec = Get-CimInstance -Namespace root/wmi -ClassName IecToolkitInterface
function RecM([int]$addr) { $f0 = ([uint64]0x2357 -shl 32) -bor [uint64]0x00800007; $in = [uint64[]]@($f0,[uint64]0,[uint64]$addr,[uint64]1,[uint64]0,[uint64]0,[uint64]0); (Invoke-CimMethod -InputObject $iec -MethodName SystemMethod -Arguments @{ InData = $in }).OutData }
function Rpm { $lo=(RecM 0x0602)[1]; $hi=(RecM 0x0603)[1]; $lo2=(RecM 0x0624)[1]; $hi2=(RecM 0x0625)[1]; "{0}/{1}" -f (([int]$hi -shl 8) -bor [int]$lo), (([int]$hi2 -shl 8) -bor [int]$lo2) }
# ECCW(bank, feature, value): ec_write_command_byte(commandcode=feature, param0=bank, param1=value) per ECAT cmd 4: ECCW(Arg1[2], Arg1[1], Arg1[0])?? -> verify both orders on a harmless read first
function Ecw([int]$bank,[int]$feat,[int]$val) { (Invoke-CimMethod -InputObject $atd -MethodName ec_write_command_byte -Arguments @{ commandcode=[byte]$val; param0=[byte]$feat; param1=[byte]$bank }).value }
function Ecr([int]$bank,[int]$feat) { (Invoke-CimMethod -InputObject $atd -MethodName ec_read_command_byte -Arguments @{ commandcode=[byte]$feat; param0=[byte]$bank }).value }
function Erb([int]$dev,[int]$reg) { (Invoke-CimMethod -InputObject $atd -MethodName ec_read_byte -Arguments @{ haddr=[byte]$dev; laddr=[byte]$reg }).value }
function Mbox { "mailbox 30/31/32 = " + ((0x30,0x31,0x32 | ForEach-Object { Erb 0xC4 $_ }) -join ' ') }
"t0  rpm=" + (Rpm) + "  mode=" + (Ecr 1 0x02) + "  " + (Mbox)
"== step1: fan mode -> manual (bank1 feat 0x82 = 2): ret=" + (Ecw 1 0x82 2) + "   " + (Mbox) + "  mode now=" + (Ecr 1 0x02)
"== step2: select fan0, pwm 120: ret=" + (Ecw 1 0x8c 0) + "/" + (Ecw 1 0x8a 120) + "   select fan1, pwm 120: ret=" + (Ecw 1 0x8c 1) + "/" + (Ecw 1 0x8a 120)
foreach ($t in 3,6,9,12) { Start-Sleep 3; "   +${t}s rpm=" + (Rpm) + "  pwm_rb(fan0)=" + (Ecr 1 0x0a) + "  tach_raw=" + (Ecr 1 0x09) }
"== step3: pwm 75 both"; Ecw 1 0x8c 0 | Out-Null; Ecw 1 0x8a 75 | Out-Null; Ecw 1 0x8c 1 | Out-Null; Ecw 1 0x8a 75 | Out-Null
foreach ($t in 4,8,12) { Start-Sleep 4; "   +${t}s rpm=" + (Rpm) + "  pwm_rb=" + (Ecr 1 0x0a) }
"== step4: pwm 0 both (does the EC allow off?)"; Ecw 1 0x8c 0 | Out-Null; Ecw 1 0x8a 0 | Out-Null; Ecw 1 0x8c 1 | Out-Null; Ecw 1 0x8a 0 | Out-Null
foreach ($t in 4,8,12) { Start-Sleep 4; "   +${t}s rpm=" + (Rpm) + "  pwm_rb=" + (Ecr 1 0x0a) }
"== step5: fan mode -> auto: ret=" + (Ecw 1 0x82 0) + "  mode now=" + (Ecr 1 0x02)
foreach ($t in 5,10) { Start-Sleep 5; "   +${t}s rpm=" + (Rpm) }
"done"
