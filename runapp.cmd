@echo off

call makeapp
if %ERRORLEVEL% neq 0 goto FAIL

start ..\ozvm\z88.jar com COM2 crd2 32 27C VDriveZ88.epr
goto END

:FAIL
exit /b 1

:END