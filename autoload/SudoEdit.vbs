' Small vbs Script to generate an UAC dialog and request copying some privileged file
' Uses UAC to elevate rights, idea taken from:
' http://stackoverflow.com/questions/7044985
'
' Distributed together with the SudoEdit Vim plugin. The Vim License applies
Dim FSO, WshShell, UAC, cmd

' Safety check
' Vim might give more arguments, they will be just ignored
if WScript.Arguments.Count < 3 then
    WScript.Echo "Syntax: cscript.exe SudoEdit.vbs [write|read] sourcefile targetfile"
    Wscript.Quit 1
end if

Set WshShell = CreateObject("WScript.Shell")
Set FSO	     = CreateObject("Scripting.FileSystemObject")
Set UAC      = CreateObject("Shell.Application") 
cmd = WshShell.ExpandEnvironmentStrings("%COMSPEC%")

' All given Files exist
If (Not(FSO.FileExists(WScript.Arguments(1)))) Then
    WScript.Echo "Files " & WScript.Arguments(1) & " does not exist"
    WScript.Quit 2
ElseIf  (Not(FSO.FileExists(WScript.Arguments(2))) AND WScript.Arguments(0) = "read") Then
    WScript.Echo "Files " & WScript.Arguments(2) & " does not exist"
    WScript.Quit 2
END if

if (WScript.Arguments(0) = "write") then
    ' Write Files (delete source file afterwards, so we can easily check, if the copy worked
    UAC.ShellExecute cmd, "/c copy /Y " & WScript.Arguments(2) & " " & WScript.Arguments(1) & " && del /Q " & WScript.Arguments(2), "", "runas", 1
else
    ' Read Files
    UAC.ShellExecute cmd, "/c copy /Y " & WScript.Arguments(1) & " " & WScript.Arguments(2), "", "runas", 1
end if

' Sleep a moment, so that the FileExists check works correctly
' This only works for when writing the file,
' assume the read operation worked....
WScript.Sleep 100
If (FSO.FileExists(WScript.Arguments(2)) AND WScript.Arguments(0) = "write") Then
    WScript.Echo "Copy Failed"
    WScript.Quit 3
end if
Wscript.Quit 0
