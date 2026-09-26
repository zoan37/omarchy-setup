mountvol T: '\\?\Volume{1c208cdb-67e1-4f84-8280-e9c965e404a3}\' 2>&1 | Out-Null
$serial = (cmd /c "vol T:" | Select-String 'Serial Number is ([0-9A-F]{4}-[0-9A-F]{4})').Matches[0].Groups[1].Value
"windows ESP serial: $serial"
$cfg = 'S:\oma-snap\grub\grub.cfg'
if (-not (Select-String -Path $cfg -Pattern 'win-ssd' -Quiet)) {
  $entry = "menuentry 'Windows Boot Manager' --id 'win-ssd' {`n  insmod part_gpt`n  insmod fat`n  insmod chain`n  search --no-floppy --fs-uuid --set=root $serial`n  chainloader /EFI/Microsoft/Boot/bootmgfw.efi`n}`n"
  Add-Content -Path $cfg -Value $entry -Encoding ascii
}
"grub.cfg menuentries: " + (Select-String -Path $cfg -Pattern '^menuentry' | Measure-Object).Count
"bundle on C:: " + (Get-ChildItem C:\a16-bundle | Measure-Object).Count + " files"
mountvol T: /D; mountvol S: /D
"ok"
