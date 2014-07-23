@echo off
cls

setlocal DisableDelayedExpansion
set "batchPath=%~0"
setlocal EnableDelayedExpansion

:: File to write to
set mode=%1
set myfile=%2
set newcontent=%3
set sudo=%4
shift
shift
shift
shift

if '%sudo%' == 'uac' goto CHECKPRIVILEGES

:: Use runas or something alike to elevate priviliges, but
:: first parse parameter for runas
:: Windows cmd.exe is very clumsy to use ;(
set params=%1
:LOOP
shift
if [%1]==[] goto AFTERLOOP
set params=%params% %1
goto LOOP

:AFTERLOOP

:: Use runas or so to elevate rights
echo.
echo ***************************************
echo Calling %sudo% for Privilege Escalation
echo ***************************************
if '%mode%' == 'write' (
    %sudo% %params% "cmd.exe /c type %newcontent% >%myfile%"
    ) else (
    %sudo% %params% "cmd.exe /c type %myfile% >%newcontent%"
    )
goto END

:: Use UAC to elevate rights, idea taken from:
:: http://stackoverflow.com/questions/7044985/how-can-i-auto-elevate-my-batch-file-so-that-it-requests-from-uac-admin-rights
:CHECKPRIVILEGES
set vbs="%temp%\GetPrivileges.vbs"

echo.
echo **************************************
echo Invoking UAC for Privilege Escalation 
echo **************************************

echo Set UAC = CreateObject^("Shell.Application"^) > %vbs%
if '%mode%' == 'write' (
    echo UAC.ShellExecute "%COMSPEC%", "/c copy /Y "%newcontent%" "%myfile%"", "", "runas", 1 >> %vbs%
) else (
    echo UAC.ShellExecute "%COMSPEC%", "/c copy /Y "%myfile%" "%newcontent%"", "", "runas", 1 >> %vbs%
)
:: Run VBS script
%vbs%

:END
if exist %vbs% (del %vbs%)
