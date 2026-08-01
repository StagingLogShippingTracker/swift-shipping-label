' Launch Swift Document Generator (Flutter Windows) without a console window.
Option Explicit
Dim sh, fso, root, exe
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
exe = root & "\dist\Swift Document Generator\swift_shipping_label.exe"
If Not fso.FileExists(exe) Then
  exe = root & "\dist\Swift Shipping Label\swift_shipping_label.exe"
End If
If Not fso.FileExists(exe) Then
  exe = root & "\mobile\build\windows\x64\runner\Release\swift_shipping_label.exe"
End If
If fso.FileExists(exe) Then
  sh.Run """" & exe & """", 1, False
Else
  MsgBox "Build the Windows app first:" & vbCrLf & _
    "cd mobile" & vbCrLf & "flutter build windows --release", 16, "Swift Document Generator"
End If
