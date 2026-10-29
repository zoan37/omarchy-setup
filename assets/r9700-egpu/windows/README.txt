R9700 eGPU test on Windows (Zephyrus / K6)
1. Boot Windows. Install the AMD driver for the Radeon AI PRO R9700 from amd.com (Radeon PRO or Adrenalin).
2. Power-cycle the DEG2 (blue button), then plug its USB-C into the laptop's Thunderbolt port.
   Device Manager > Display adapters should show "AMD Radeon AI PRO R9700".
3. Copy this folder to the laptop, open PowerShell as Administrator in it, and run:
     Set-ExecutionPolicy -Scope Process Bypass; .\setup.ps1
   (enables SSH for the test laptop, downloads llama.cpp + the 18.6 GB model, prints the IP address)
4. Tell Claude the IP address. Or run the test yourself:  C:\egpu-test\load-loop.ps1
