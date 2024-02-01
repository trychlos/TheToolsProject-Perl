@echo off
	rem daily.morning.cmd Workload tasks
	set ME=%~n0
	call :setLogFile
	call :logLine %~dpn0
	set i=0
	for /f "tokens=*" %%C in ('services.pl list -workload %ME% -commands ^| findstr /V /B "["') do call :doCommand %%C
	call :doRecap
    exit /b

:doCommand
	rem this level to have a timestamped line before running each command
	set /A i=i+1
	set command[%i%]=%*
	call :logLine %*
	%* >> %LOGFILE% 2>&1
	call :logLine RC=%ERRORLEVEL%
	set rc[%i%]=%ERRORLEVEL%
	exit /b

:doRecap
	call :logLine +==============================================================================================+
	call :logLine ! Summary                                                                                      !
	call :logLine + ---------------------------------------------------------------------------------------------+
	for /L %%j in (1,1,%i%) do (
		setlocal EnableDelayedExpansion
		call :logLine ! + !command[%%j]!
		call :logLine !   RC=!rc[%%j]!
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
