@echo off
set JAVA_HOME=C:\Users\Zaid\AppData\Local\jdk17\jdk-17.0.19+10
set PATH=%JAVA_HOME%\bin;%PATH%
echo Running flutter build apk with JAVA_HOME=%JAVA_HOME%
G:\flutter_windows_3.44.6-stable\flutter\bin\flutter.bat build apk
