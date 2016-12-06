@echo off
cd %TMP%

rem Download the Pike installer and Gypsum's archive
rem http://superuser.com/a/760010
powershell -command "& { (New-Object Net.WebClient).DownloadFile('http://pike.lysator.liu.se/pub/pike/latest-stable/Pike-v8.0.358-win32-oldlibs.msi', 'pike.msi') }"
start /wait pike.msi
mkdir c:\stillebot
mkdir c:\stillebot\modules
cd c:\stillebot
powershell -command "& { (New-Object Net.WebClient).DownloadFile('http://rosuav.github.io/StilleBot/modules/dlupdate.pike', 'modules\dlupdate.pike') }"

modules\dlupdate.pike

rem Create a shortcut. In theory, WindowStyle=7 should give a minimized window.
rem TODO: Find the desktop directory even if it isn't obvious.
rem TODO: Put a shortcut also into the Start menu? Does that require elevation?
rem (Shouldn't - not for per-user start menu at least.) Where should it be put?
powershell "$s=(New-Object -COM WScript.Shell).CreateShortcut('%userprofile%\Desktop\stillebot.lnk');$s.TargetPath='c:\stillebot\stillebot.pike';$s.WorkingDirectory='c:\stillebot';$s.WindowStyle=7;$s.Save()"
