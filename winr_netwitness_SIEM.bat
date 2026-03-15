@echo off
REM =======================================================
REM  Variables
REM =======================================================
set SRC=\\10.3.71.90\Fixit\Winrm Configuration\winrmconfig.ps1

set DST=C:\Windows\Web

set SCRIPT=%DST%\winrmconfig.ps1

set FLAG=%DST%\configured.txt

                                
REM =======================================================
REM  Exit if already configured
REM =======================================================
REM if exist "%FLAG%" exit /b 0

REM =======================================================
REM  Create local directory
REM =======================================================
if not exist "%DST%" (
mkdir  "%DST%"
)

REM =======================================================
REM  Copy script locally only once
REM =======================================================
if not exist "%SCRIPT%" (
copy "%SRC%" "%SCRIPT%" > nul 2>&1

)

REM =======================================================
REM  Run Powershell Script locally
REM =======================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action enable -ListenerType http -User syslogsiem@nausena.mil

REM =======================================================
REM  Marks as completed
REM =======================================================
if %ERRORLEVEL% EQU 0 (
echo configured > "%FLAG%"
)

REM =======================================================
REM  Winrm service running
REM =======================================================
sc config WinRM start= auto >nul
sc start WinRM >nul 2>&1
exit /b 0

