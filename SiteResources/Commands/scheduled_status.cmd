@echo off
	rem Display the status of a task
	rem Expected arguments:
	rem 1. a task name
	set ME=[%~nx0]
	call :setLogFile %~n0
	set argC=0
	for %%x in (%*) do set /A argC+=1
	if not %argC% == 1 (
		call :logMe expected 1 'TaskName' argument, found %argC%
		exit /b 1
	)
	set task=%1
	call :doExecute %*
	exit /b

:doExecute
	call :logMe ++ executing %~f0, querying "%task%" task
	for /f %%i in ('echo %task%') do set name=%%~nxi
	for /f "tokens=3" %%S in ('schtasks /Query /fo table /TN %task% ^| findstr %name%') do call :logShort %name%: %%S
	call :logMe done
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
