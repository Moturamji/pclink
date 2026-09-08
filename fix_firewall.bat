@echo off
:: This script adds a Windows Firewall rule to allow PCLink server connections
:: It must be run as Administrator

echo Adding PCLink firewall rule for port 8088...
netsh advfirewall firewall add rule name="PCLink Server" dir=in action=allow protocol=TCP localport=8088
if %ERRORLEVEL% EQU 0 (
    echo.
    echo SUCCESS! Firewall rule added. Android can now reach your PC.
    echo Restart both apps to connect.
) else (
    echo.
    echo FAILED - Please right-click this file and select "Run as administrator"
)
echo.
pause
