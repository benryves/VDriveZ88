@echo off

call makeapp
if %ERRORLEVEL% neq 0 goto FAIL

if exist ..\ozvm\z88.jar (
	start ..\ozvm\z88.jar com COM2 crd2 32 27C VDriveZ88.epr
) else (
	start z88\bin\z88.jar crd2 32 27C VDriveZ88.epr
)
goto END

:FAIL
exit /b 1

:END