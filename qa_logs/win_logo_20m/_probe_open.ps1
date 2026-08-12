$ErrorActionPreference = "Stop"
$root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator"
. "$root\qa_logs\win_logo_hour\_win32.ps1"
$probe = "$root\qa_logs\win_logo_20m\probe"
New-Item -ItemType Directory -Force -Path $probe | Out-Null
Get-Process -Name swift_shipping_label -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
$exe = "$root\dist\Swift Document Generator\swift_shipping_label.exe"
Write-Host "launching"
Start-Process $exe
Start-Sleep 6
$hwnd = Ensure-AppWindow -W 1500 -H 1040
Write-Host "hwnd=$hwnd"
[Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
Send-KeysSafe "{ESC}{ESC}"
Start-Sleep 300
Send-KeysSafe "^2"
Start-Sleep 800
Capture-WindowShot -Hwnd $hwnd -Path "$probe\ctrl2.png" | Out-Null
Write-Host "ctrl2 shot"
Click-Rel -Hwnd $hwnd -Fx 0.72 -Fy 0.09 | Out-Null
Start-Sleep 300
[Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
Send-KeysSafe "^+f"
Start-Sleep 1200
Capture-WindowShot -Hwnd $hwnd -Path "$probe\hotkey_find.png" | Out-Null
Write-Host "hotkey shot"
Add-Type -AssemblyName System.Drawing
$b=[Drawing.Bitmap]::FromFile("$probe\hotkey_find.png"); $n=0
for($y=[int]($b.Height*0.55);$y -lt $b.Height;$y+=2){for($x=[int]($b.Width*0.35);$x -lt $b.Width;$x+=2){$c=$b.GetPixel($x,$y); if($c.R -gt 150 -and $c.G -lt 140 -and ($c.R-$c.G) -gt 40){$n++}}}
$b.Dispose(); Write-Host "hotkey_orange=$n"
if ($n -lt 100) {
  Send-KeysSafe "{ESC}"; Start-Sleep 250
  Click-Rel -Hwnd $hwnd -Fx 0.72 -Fy 0.09 | Out-Null
  Start-Sleep 200
  $info = Get-WindowRectInfo $hwnd
  foreach ($fy in @(360,375,390,345,330,405,420)) {
    [Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
    Click-Screen -X ($info.Left + 318) -Y ($info.Top + 48)
    Start-Sleep 450
    Click-Screen -X ($info.Left + 430) -Y ($info.Top + $fy)
    Start-Sleep 1000
    $p = "$probe\try_$fy.png"
    Capture-WindowShot -Hwnd $hwnd -Path $p | Out-Null
    $b=[Drawing.Bitmap]::FromFile($p); $n=0
    for($y=[int]($b.Height*0.55);$y -lt $b.Height;$y+=2){for($x=[int]($b.Width*0.35);$x -lt $b.Width;$x+=2){$c=$b.GetPixel($x,$y); if($c.R -gt 150 -and $c.G -lt 140 -and ($c.R-$c.G) -gt 40){$n++}}}
    $b.Dispose(); Write-Host "fy=$fy orange=$n"
    if ($n -gt 120) { Write-Host "OPEN_OK fy=$fy"; break }
    Send-KeysSafe "{ESC}"; Start-Sleep 250
  }
}
Write-Host DONE