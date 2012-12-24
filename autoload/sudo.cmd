@echo on

SETLOCAL ENABLEEXTENSIONS

:: File to write to
set myfile=%1
set newcontent=%2
set mode=%3
set sudo=%4
shift
shift
shift
shift

:: parameter for runas
:: Windows cmd.exe is very clumsy to use ;(
set params=%1
:loop
shift
if [%1]==[] goto afterloop
set params=%params% %1
goto loop
:afterloop
    
if '%mode%' == 'write' (
    %sudo% %params% "cmd.exe /c type %newcontent% >%myfile%"
    ) else (
    %sudo% %params% "cmd.exe /c type %myfile% >%newcontent%"
    )
