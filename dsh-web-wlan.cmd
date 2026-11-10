@echo off
rem 在 WLAN 地址 192.168.1.4:8787 上开 DSH Web，供手机 / 「赛博姐姐」APK 访问
rem
rem 用法：
rem   1) 确认手机与电脑连的是同一个 Wi-Fi
rem   2) 双击运行本脚本
rem   3) 窗口里会打印形如 http://192.168.1.4:8787/?token=xxxx 的地址
rem   4) 在 App 右上角 ⚙ 里粘贴这个完整地址（token 每次都会变）
rem
rem 停止：直接关掉本窗口，或运行 dsh-web-wlan-stop.cmd

setlocal
set "DSH=C:\Users\meiji\AppData\Local\Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd"
set "HOST=192.168.1.4"
set "PORT=8787"

echo [DSH] 绑定 %HOST%:%PORT% ...
call "%DSH%" web --host %HOST% --port %PORT% --no-open
