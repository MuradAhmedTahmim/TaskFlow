@echo off
rem Starts the TaskFlow backend (Django, port 8000) and frontend (port 8080),
rem then opens the app in the browser. Close the two server windows to stop.
cd /d "%~dp0"

if not exist "backend\.venv\Scripts\python.exe" (
  echo backend\.venv not found. See README.md for backend setup.
  pause
  exit /b 1
)
if not exist "frontend\build\web\index.html" (
  echo frontend\build\web not found. Run "flutter build web" in the frontend folder first.
  pause
  exit /b 1
)

start "TaskFlow backend" cmd /k "backend\.venv\Scripts\python.exe backend\manage.py runserver 127.0.0.1:8000"
start "TaskFlow frontend" cmd /k "backend\.venv\Scripts\python.exe -m http.server 8080 --bind 127.0.0.1 --directory frontend\build\web"

timeout /t 4 /nobreak >nul
start "" http://localhost:8080
