@echo off
	rem args must be:
	rem 1: the action: start/stop
	rem 2: the daemon name - by convention, this is the basename of the JSON configuration in configurations/daemons/
	rem 3 and others: others args to be passed to the daemon
	set ME=[%~nx0 %1]
	call :setLogFile %1
	call :logLine executing %~f0 %*
	rem find the json file
	for /f "tokens=2" %%a in ('daemon.pl vars -confdir -nocolored') do @set _confdir=%%a
	set _json=%_confdir%\%2.json
	daemon.pl %1 -json %_json% -- %3 %4 %5 %6 %7 %8 %9 >> %LOGFILE%
    exit /b

:logLine
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %* >> %LOGFILE%
	exit /b

:setLogFile
	for /f "tokens=2" %%a in ('ttp.pl vars -logsdir -nocolored') do @set _logsdir=%%a
	set _time=%TIME: =0%
	set LOGFILE=%_logsdir%\\%COMPUTERNAME%-%1-%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%-%_time:~0,2%%_time:~3,2%%_time:~6,2%.log
	exit /b
