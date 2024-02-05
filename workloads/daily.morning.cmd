@echo off
	rem daily.morning.cmd Workload tasks
	set ME=%~n0
	set MEDPN=%~dpn0
	call %~dp0\workload.cmd
