@echo off
	rem Check that the backup tasks are enabled (resp. disabled) on the machine
	rem This is often as every status because of the VERY IMPORTANT fact that backup MUST NOT RUN on a live production
	rem Expects parms:
	rem 1: the string to (case insensitive) match to identify a task by its name (e.g. 'backup')
	rem 2: the task property to (case insensitive) match (e.g. 'Status')
	rem 3: the expected property value (case insensitive - e.g. 'enabled' or 'disabled')
	set ME=[%~nx0]
	set _name=%1
	set _property=%2
	set _expected=%3
	set a=0
	set b=0
	call :setLogFile %~n0.log
	call :doExecute %* >>%LOGFILE% 2>&1
	echo done (%a% found tasks, %b% sent alerts)
	exit /b

:doExecute
	call :logLine ++ executing %~f0 %*
	call :logLine - match task names with (insensitive) '%_name%'
	call :logLine - match searched property with (insensitive) '%_property%'
	call :logLine - match property value with (insensitive) '%_expected%'
	for /f "tokens=2" %%T in ('schtasks /Query /fo list ^| findstr /I Inlingua ^| findstr /I TaskName ^| findstr /I %_name%') do call :doCheckTask %%T
	call :logLine ++ done (%a% found tasks, %b% sent alerts)
    exit /b

:doCheckTask
	set _task=%1
	call :logLine examining %_task%
	set /A a=a+1
	for /f "tokens=2" %%V in ('schtasks /Query /fo list /TN %_task% ^| findstr /I %_property%') do call :doCheckValue %%V
	exit /b

:doCheckValue
	set _value=%1
	if /I %_value% EQU %_expected% (
		call :logLine found %_property%: %_value%: fine
	) else (
		call :logLine found %_property%=%_value%: NOT OK, sending an alert
		ttp.pl alert -level ALERT -message "%_task% %_property%=%_value% (while expected was %_expected%)"
		set /A b=b+1
	)
	exit /b

:logLine
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %*
	exit /b

:setLogFile
	for /f "tokens=2" %%a in ('ttp.pl vars -logsDir -nocolored') do @set _logsdir=%%a
	set _time=%TIME: =0%
	set LOGFILE=%_logsdir%\\%1
	exit /b
