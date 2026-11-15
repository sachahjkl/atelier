@echo off
rem Shortcut: build.bat [release] is ateliertool build.
rem Every other step: odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -- <command> (help lists them).
cd /d "%~dp0"
if not exist build mkdir build
odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -keep-executable -- build %*
