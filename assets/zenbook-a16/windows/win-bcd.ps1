$ErrorActionPreference='Continue'
mountvol S: '\\?\Volume{1905afe2-52c3-40dd-923c-087c6831f837}\' 2>&1 | Out-Null
"=== Omarchy ESP (S:) contents"; Get-ChildItem -Recurse S:\ -File | Select-Object FullName, Length | Format-Table -AutoSize | Out-String -Width 200
"=== grub.cfg head"; Get-Content S:\oma-snap\grub\grub.cfg -TotalCount 12
"=== bcdedit: create firmware entry for GRUB"
$out = bcdedit /copy '{bootmgr}' /d 'Omarchy (GRUB)' 2>&1; $out
$id = ([regex]::Match(($out -join ' '), '\{[0-9a-f-]{36}\}')).Value; "new id: $id"
if ($id) {
  bcdedit /set $id device 'partition=S:'
  bcdedit /set $id path '\EFI\oma-snap\grubaa64.efi'
  bcdedit /set '{fwbootmgr}' displayorder $id /addfirst
  bcdedit /enum '{fwbootmgr}'
  bcdedit /enum $id
}
