@echo off
	rem List the scheduled tasks
	rem Expected arguments:
	rem 1. a task name regular expression suitable for FINDSTR
	set ME=[%~nx0]
	rem set FULL=%~f0
	call :setLogFile %~n0
	set argC=0
	for %%x in (%*) do set /A argC+=1
	if not %argC% == 1 (
		call :logMe expected 1 'TaskName' regular expression argument, found %argC%
		exit /b 1
	)
	set name=%1
	set cTasks=0
	call :doExecute %*
	exit /b

:doExecute
	call :logMe ++ executing %~f0 %*, matching (insensitively) %name% tasks
	for /f "tokens=2" %%T in ('schtasks /Query /fo list ^| findstr TaskName: ^| findstr /I %name%') do call :doListTask %%T
	call :logMe done (%cTasks% found tasks)
    exit /b

:doListTask
	set task=%1
	find "%task%" "%VALUES%" >nul
	if not %ERRORLEVEL% == 0 (
		echo "%task%" >> "%VALUES%"
		set /A cTasks+=1
		call :logShort %task%
	)
	exit /b

:logShort
	echo.  %*
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %ME% %* >>%LOGFILE%
	exit /b

:logMe
	echo %ME% %*
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %ME% %* >>%LOGFILE%
	exit /b

:setLogFile
	for /f "tokens=2" %%a in ('ttp.pl vars -logsDir -nocolored') do @set _logsdir=%%a
	set _time=%TIME: =0%
	set LOGFILE=%_logsdir%\\%1.log
	set VALUES=%_logsdir%\\%1.values
	echo > %VALUES%
	exit /b
