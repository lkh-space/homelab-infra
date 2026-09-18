@echo off
chcp 65001 >nul
title Homelab WSL2 PortProxy Setup

:: ==============================================================================
:: Homelab Infra - Windows WSL2 포트포워딩 자동 복구 스크립트
::
:: 동작 원리:
:: 1. 관리자 권한 자동 획득 (더블클릭 시 UAC 자동 요청)
:: 2. WSL2 우분투를 깨우고, 실시간 내부 IP(hostname -I)를 자동 감지
:: 3. 윈도우 방화벽 및 netsh portproxy를 통해 맥북 접속 포트를 우분투로 원클릭 전달
:: ==============================================================================

:: 1. 관리자 권한 확인 및 자동 승격 (Self-Elevation)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [안내] 관리자 권한이 필요합니다. 관리자 권한으로 다시 실행합니다...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ========================================================
echo 🏠 Homelab WSL2 포트포워딩 자동 구성 스크립트
echo ========================================================

:: 2. WSL2 실행 및 현재 내부 IP 자동 감지 (IP 변경 완벽 대응)
echo.
echo [1/3] WSL2(우분투)를 깨우고 내부 가상 IP를 조회 중...
for /f "tokens=1" %%i in ('wsl hostname -I') do set WSL_IP=%%i

if "%WSL_IP%"=="" (
    echo [오류] WSL2 IP를 가져올 수 없습니다. WSL이 설치되어 있는지 확인하세요.
    pause
    exit /b 1
)

echo [성공] 감지된 WSL2 내부 IP: %WSL_IP%

:: 3. 윈도우 방화벽 인바운드 규칙 보장 (6443, 22, 80, 443, 30900, 30901)
echo.
echo [2/3] Windows 방화벽 포트 허용 규칙 등록 중...
netsh advfirewall firewall delete rule name="Homelab_WSL_Ports" >nul 2>&1
netsh advfirewall firewall add rule name="Homelab_WSL_Ports" dir=in action=allow protocol=TCP localport=6443,22,80,443,30900,30901 >nul 2>&1
echo [성공] 방화벽 포트 등록 완료 (6443, 22, 80, 443, 30900, 30901)

:: 4. netsh portproxy 등록 (외부 -> WSL2 전달)
echo.
echo [3/3] 포트포워딩(PortProxy) 재등록 중...
netsh interface portproxy reset >nul 2>&1

set PORTS=6443 22 80 443 30900 30901
for %%p in (%PORTS%) do (
    netsh interface portproxy add v4tov4 listenport=%%p listenaddress=0.0.0.0 connectport=%%p connectaddress=%WSL_IP%
    echo   - 포트 %%p -^> %WSL_IP%:%%p
)

echo.
echo ========================================================
echo 🎉 모든 포트포워딩 설정이 완료되었습니다!
echo 맥북에서 'kubectl get nodes'를 실행해 보세요.
echo ========================================================
echo.
timeout /t 5
