Option Explicit

' Silent, zero-flash launcher for EggRoom.ps1.
' Forwards any command-line arguments to EggRoom.ps1 cleanly.

Dim shell, fso, scriptDir, psScriptPath, powershellPath, command, i, arg
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScriptPath = fso.BuildPath(scriptDir, "EggRoom.ps1")

If Not fso.FileExists(psScriptPath) Then
    WScript.Quit 2
End If

powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
                 "\System32\WindowsPowerShell\v1.0\powershell.exe"

command = """" & powershellPath & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScriptPath & """"

For i = 0 To WScript.Arguments.Count - 1
    arg = Replace(WScript.Arguments(i), """", "\""")
    command = command & " """ & arg & """"
Next

' 0 = hidden window (no console flash); False = do not wait for exit.
shell.Run command, 0, False
