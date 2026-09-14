@echo off
rem Impeller(OpenGLES) cannot present the first frame in RDP sessions, which
rem keeps the window hidden forever. Disable Impeller to fall back to Skia.
rem (Engine switches from env vars are honored in debug/profile builds only.)
set FLUTTER_ENGINE_SWITCHES=1
set FLUTTER_ENGINE_SWITCH_1=enable-impeller=false
start "" "%~dp0build\windows\x64\runner\Debug\novel_editor.exe"
