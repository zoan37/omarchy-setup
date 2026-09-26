"=== WMI classes with ASUS methods"
Get-CimClass -Namespace root/wmi | Where-Object { $_.CimClassMethods.Name -match '^(WMTK|WMAT|WMNB)$' } | ForEach-Object {
  $c = $_; "class " + $c.CimClassName
  $c.CimClassMethods | ForEach-Object { "  " + $_.Name + "(" + (($_.Parameters | ForEach-Object { $_.CimType.ToString() + " " + $_.Name }) -join ", ") + ")" }
}
"=== bitlocker"
manage-bde -status C: | Select-String -Pattern "Conversion Status|Protection Status|Percentage Encrypted"
"=== partitions (disk 0)"
Get-Partition -DiskNumber 0 | Select-Object PartitionNumber, Type, @{n="GB";e={[math]::Round($_.Size/1GB,1)}}, DriveLetter | Format-Table -AutoSize | Out-String
"=== ASUS services/drivers"
Get-Service | Where-Object { $_.DisplayName -match 'ASUS' } | Select-Object Status, Name, DisplayName | Format-Table -AutoSize | Out-String
"=== power scheme / MyASUS fan"
powercfg /getactivescheme
