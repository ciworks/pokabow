@echo off
rem Milestone 0 repeatable command: project validation + headless smoke tests.
rem
rem Usage:  tools\validate.cmd
rem
rem Engine resolution order:
rem   1. %GODOT_BIN%
rem   2. godot / godot4 / Godot on PATH
rem   3. the engine bundled with the Summer app (development convenience)
rem
rem Exit codes: 0 = all checks passed, 1 = a check failed, 2 = no engine found.

setlocal enabledelayedexpansion

for %%i in ("%~dp0..") do set "PROJECT_DIR=%%~fi"
set "ENGINE="

if defined GODOT_BIN (
	set "ENGINE=%GODOT_BIN%"
	goto :found
)

for %%c in (godot.exe godot4.exe Godot.exe) do (
	if not defined ENGINE (
		for /f "delims=" %%p in ('where %%c 2^>nul') do (
			if not defined ENGINE set "ENGINE=%%p"
		)
	)
)

if not defined ENGINE (
	if exist "%LOCALAPPDATA%\SummerEngine\current\Summer.exe" (
		set "ENGINE=%LOCALAPPDATA%\SummerEngine\current\Summer.exe"
	)
)

if not defined ENGINE (
	echo No Godot engine binary found.
	echo Install Godot 4.6, or set GODOT_BIN, then re-run:
	echo     set GODOT_BIN=C:\path\to\godot.exe
	echo     tools\validate.cmd
	exit /b 2
)

:found
echo engine:  %ENGINE%
echo project: %PROJECT_DIR%
echo.

echo == project validation (import) ==
"%ENGINE%" --headless --path "%PROJECT_DIR%" --import
set "IMPORT_STATUS=%ERRORLEVEL%"

echo.
echo == headless smoke tests ==
"%ENGINE%" --headless --path "%PROJECT_DIR%" --script res://tests/harness/test_runner.gd
set "TEST_STATUS=%ERRORLEVEL%"

echo.
if not "%IMPORT_STATUS%"=="0" (
	echo RESULT: FAIL ^(project validation exited %IMPORT_STATUS%^)
	exit /b 1
)
if not "%TEST_STATUS%"=="0" (
	echo RESULT: FAIL ^(headless tests exited %TEST_STATUS%^)
	exit /b 1
)

echo RESULT: PASS
exit /b 0
