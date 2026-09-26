Zenbook A16 dual boot: Windows side tasks
1. After Windows is installed and you are at the desktop, run ASUS-Qualcomm-BSP-V1.312.4500.0.exe
   (installs Wi-Fi, audio, and the ASUS/Qualcomm platform drivers). Reboot.
2. Right-click Start > Terminal (Admin). Then:
     Set-ExecutionPolicy -Scope Process Bypass
     cd D:\a16-tools   (use the stick's drive letter)
     .\ec-dump.ps1
   Leave the laptop idle on AC while it runs (a few minutes).
3. Copy the folder C:\ecdump onto the stick as a16-tools\windows-results.
4. Observe: does the fan stop at idle? (MyASUS > Customization > fan profile also worth noting.)
