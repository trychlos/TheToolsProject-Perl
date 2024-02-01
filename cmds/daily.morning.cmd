rem @echo off
	rem daily.morning.cmd Workload tasks
	set ME=%~n0
	call :setLogFile
	call :logLine %~dpn0
	set i=0
	for /f "tokens=*" %%C in ('services.pl list -workload %ME% -commands ^| findstr /V /B "["') do call :doCommand %%C
	services.pl workload_summary -commands res_command -rc res_rc -start res_start -end res_end -count %i%
    exit /b

:doCommand
	rem - have a timestamped line before running each command
	rem - prepare the end summary
	set /A i=i+1
	set res_command[%i%]=%*
	set res_start[%i%]=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME%
	call :logLine %*
	rem %* >> %LOGFILE% 2>&1
	call :logLine RC=%ERRORLEVEL%
	set res_rc[%i%]=%ERRORLEVEL%
	set res_end[%i%]=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME%
	exit /b

:doRecap
	rem https://comp.os.ms-windows.programmer.win32.narkive.com/YIzuz12i/outputting-a-vertical-bar-on-the-commandline
	call :logLine +==============================================================================================+
	call :logLine § Summary                                                                                      §
	call :logLine + ---------------------------------------------------------------------------------------------+
	for /L %%j in (1,1,%i%) do (
		setlocal EnableDelayedExpansion
		call :logLine § + !command[%%j]!
		call :logLine §   RC=!rc[%%j]!
	)
	call :logLine +==============================================================================================+
	exit /b

:logLine
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %* >> %LOGFILE%
	exit /b

:setLogFile
	for /f "delims=" %%a in ('ttp.pl vars -logsdir ^| perl -pe "s/^\s+|\s+$//;"') do @set _logsdir=%%a
	set LOGFILE=%_logsdir%\\%COMPUTERNAME%-%ME%-%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
	exit /b
