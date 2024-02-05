rem @echo off
	rem this .cmd is expected to be called with the workload name as unique argument, may have until 8 additional arguments to be passed to underlying commands
	rem e.g. "C:\INLINGUA\Scripts\cmds\workload.cmd daily.morning -dummy"
	rem Note 1: this workload.cmd adds itself the -nocolor option to every run command. Tou should take care that your run commands accept (if not honor) this command-line option.
	set ME=[%~nx0 %1]
	call :setLogFile %1
	call :logLine executing %~f0 %*
	set i=0
	for /f "tokens=*" %%C in ('services.pl list -workload %1 -commands -hidden %2 %3 %4 %5 %6 %7 %8 %9 -nocolored ^| findstr /V "[services.pl list]"') do call :doCommand %%C %2 %3 %4 %5 %6 %7 %8 %9
	services.pl workload_summary -workload %1 -commands res_command -start res_start -end res_end -rc res_rc -count %i% %2 %3 %4 %5 %6 %7 %8 %9 -nocolored >> %LOGFILE%
    exit /b

:doCommand
	rem - have a timestamped line before running each command
	rem - prepare the end summary
	set /A i=i+1
	set res_command[%i%]=%*
	set res_start[%i%]=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME%
	call :logLine %ME% %*
	%* >> %LOGFILE% 2>&1
	call :logLine %ME% RC=%ERRORLEVEL%
	set res_rc[%i%]=%ERRORLEVEL%
	set res_end[%i%]=%DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME%
	exit /b

:logLine
	echo %DATE:~6,4%-%DATE:~3,2%-%DATE:~0,2% %TIME:~0,8% %* >> %LOGFILE%
	exit /b

:setLogFile
	for /f "tokens=2" %%a in ('ttp.pl vars -logsdir -nocolored') do @set _logsdir=%%a
	set LOGFILE=%_logsdir%\\%COMPUTERNAME%-%1-%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
	exit /b
