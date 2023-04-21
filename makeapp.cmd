@echo off

del /Q *.obj *.sym *.bin *.map *.6? *.epr 2>nul >nul

:: return version of Mpm to command line environment.
:: Only V1.5 or later of Mpm supports macros
mpm -version 2>nul >nul
if ERRORLEVEL 15 goto COMPILE
echo Mpm version is less than V1.5, compilation aborted.
echo Mpm displays the following:
mpm
goto FAIL

:COMPILE

:: Assemble the application
mpm -b -I.\z88\oz\def VDriveZ88.asm
if %ERRORLEVEL% neq 0 goto FAIL

:: Assemble the card header
mpm -b -I.\z88\oz\def romheader.asm
if %ERRORLEVEL% neq 0 goto FAIL

:: Create the card image
z88card -f VDriveZ88.loadmap
if %ERRORLEVEL% neq 0 goto FAIL

goto END

:FAIL
exit /b 1

:END
