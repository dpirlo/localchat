Option Explicit

Dim shell, files, folder, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "\iniciar-chat.ps1"""
exitCode = shell.Run(command, 0, True)

If exitCode <> 0 Then
  MsgBox "No se pudo iniciar el chat. Ejecutá instalar-windows.bat para instalar Node.js, Ollama y los modelos.", 16, "Mini chat local"
End If
