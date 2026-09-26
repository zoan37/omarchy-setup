$b = Get-CimInstance Win32_BIOS
"bios: " + $b.SMBIOSBIOSVersion + "  released " + $b.ReleaseDate
"boot: " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
"secureboot: " + (Confirm-SecureBootUEFI)
"--- firmware boot order:"
bcdedit /enum '{fwbootmgr}' | Select-String -Pattern 'displayorder|^\s+\{'
"--- firmware entries:"
bcdedit /enum firmware | Select-String -Pattern 'identifier|description' | ForEach-Object { $_.Line.Trim() }
"--- firmware driver (BIOS 312) device status:"
Get-PnpDevice -Class Firmware -ErrorAction SilentlyContinue | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 200
"--- recent firmware/update events:"
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-3)} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'firmware|UEFI|capsule' } | Select-Object TimeCreated, Id, @{n='Msg';e={$_.Message.Substring(0,[Math]::Min(160,$_.Message.Length))}} | Format-Table -AutoSize | Out-String -Width 220
