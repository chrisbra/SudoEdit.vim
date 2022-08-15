@echo off
cls

:: File to write to
set mode=%1
set myfile=%2
set newcontent=%3
set sudo=%4
shift
shift
shift
shift

:: Use runas or something alike to elevate privileges, but
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
    :: echo %sudo% %params% "%COMSPEC% /c copy /Y \"%newcontent:"=%\" \"%myfile:"=%\""
    %sudo% %params% "%COMSPEC% /c copy /Y \"%newcontent:"\"=% \"%myfile:"=%\""
) else (
    :: echo %sudo% %params% "%COMSPEC% /c copy /Y \"%myfile:"="%\" \"%newcontent:"="%\""
    %sudo% %params% "%COMSPEC% /c copy /Y \"%myfile:"="%\" \"%newcontent:"="%\""
)
exit /B %ERRORLEVEL%
