<#
.SYNOPSIS
    DeployHelpers - 通用 Windows 部署輔助模組
.DESCRIPTION
    封裝在繁體中文 Windows 下踩過的兩個坑的解法：
      1. Get-NetTCPConnection 取代 netstat 文字解析（不受系統語言影響）
      2. Start-Process -WindowStyle Hidden 取代 cmd /c start /B（子行程不卡 console）
.NOTES
    Version: 1.0
    Author: chenweihanfool
#>

# ============================================
# Test-PortListening
# ============================================
<#
.SYNOPSIS
    檢查指定 port 有無程序在監聽（純淨列舉值，不受系統語言影響）
.DESCRIPTION
    用 Get-NetTCPConnection -State Listen 取代 netstat -ano | Select-String "LISTENING"。
    後者在繁體中文 Windows 輸出「監聽中」，硬編碼的 "LISTENING" 永遠比對不到。
    .State 是 System.Net.NetworkInformation.TcpState 列舉，值是固定的 "Listen"。
.PARAMETER Port
    要檢查的 port 號碼（必填）
.PARAMETER IncludeProcessInfo
    是否回傳包含 OwningProcess 的詳細資訊（預設 $false 只回傳 $true/$false）
.EXAMPLE
    Test-PortListening -Port 3456
    # 回傳 $true（有在監聽）或 $false（沒在監聽）
.EXAMPLE
    $procs = Test-PortListening -Port 3456 -IncludeProcessInfo
    # $procs 是 array of PSObject，含 OwningProcess / LocalPort / State
#>
function Test-PortListening {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,
        [switch]$IncludeProcessInfo
    )
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $connections) {
        return $false
    }
    if ($IncludeProcessInfo) {
        return $connections | Select-Object OwningProcess, LocalPort, State
    }
    return $true
}

# ============================================
# Stop-ProcessByPort
# ============================================
<#
.SYNOPSIS
    強制終止監聽指定 port 的所有程序
.PARAMETER Port
    要釋放的 port 號碼
.PARAMETER Force
    略過確認，直接砍（預設 $true）
.EXAMPLE
    Stop-ProcessByPort -Port 3456
#>
function Stop-ProcessByPort {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,
        [switch]$Force = $true
    )
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $connections) {
        Write-Host "  >> Port $Port is free" -ForegroundColor Gray
        return
    }
    foreach ($conn in $connections) {
        $pid = $conn.OwningProcess
        Stop-Process -Id $pid -Force:$Force -ErrorAction SilentlyContinue
        Write-Host "  >> Killed PID $pid (was listening on port $Port)" -ForegroundColor Gray
    }
}

# ============================================
# Start-DetachedProcess
# ============================================
<#
.SYNOPSIS
    啟動一個真正背景執行的程序（不共用 console、不卡父腳本）
.DESCRIPTION
    用 Start-Process -WindowStyle Hidden 取代 cmd /c start /B。
    後者會把子程序掛在 cmd.exe 底下，cmd.exe 共用父 PowerShell 的 console 串流，
    導致父腳本卡在等待子程序結束的狀態。
    Start-Process -WindowStyle Hidden 會建立全新的、完全獨立的行程，
    父腳本立即返回。
.PARAMETER FilePath
    可執行檔路徑（必填，例如 "node" 或 "C:\Program Files\nodejs\node.exe"）
.PARAMETER Arguments
    傳遞的參數字串（選填，例如 "proxy.js"）
.PARAMETER WorkingDirectory
    工作目錄（選填，預設為目前目錄）
.PARAMETER Environment
    Hashtable of 環境變數（選填），啟動前設定的環境變數只影響子程序，不影響父行程
.EXAMPLE
    Start-DetachedProcess -FilePath "node" -Arguments "proxy.js" -WorkingDirectory "F:\project\scripts"
.EXAMPLE
    Start-DetachedProcess -FilePath "python" -Arguments "server.py" -Environment @{PORT="8080"}
#>
function Start-DetachedProcess {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [hashtable]$Environment = @{}
    )
    # 設定環境變數（只影響子程序）
    foreach ($key in $Environment.Keys) {
        $env:$key = $Environment[$key]
    }
    if ($WorkingDirectory -and -not (Test-Path $WorkingDirectory)) {
        throw "Working directory does not exist: $WorkingDirectory"
    }
    $psParams = @{
        FilePath = $FilePath
        WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        PassThru = $false
    }
    if ($Arguments) { $psParams['ArgumentList'] = $Arguments }
    if ($WorkingDirectory) { $psParams['WorkingDirectory'] = $WorkingDirectory }
    $null = Start-Process @psParams
    Write-Host "  >> Started '$FilePath $Arguments' (PID: --detached--)" -ForegroundColor Gray
}

# ============================================
# Wait-ForPort
# ============================================
<#
.SYNOPSIS
    等待指定 port 開始監聽（最多重試 N 次，用於啟動後驗證）
.PARAMETER Port
    Port 號碼
.PARAMETER Retries
    重試次數（預設 5）
.PARAMETER DelaySeconds
    每次重試間隔秒數（預設 2）
.EXAMPLE
    Wait-ForPort -Port 3456 -Retries 3 -DelaySeconds 2
#>
function Wait-ForPort {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,
        [int]$Retries = 5,
        [int]$DelaySeconds = 2
    )
    for ($i = 1; $i -le $Retries; $i++) {
        $listening = Test-PortListening -Port $Port
        if ($listening) {
            return $true
        }
        if ($i -lt $Retries) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return $false
}

# ============================================
# Export
# ============================================
Export-ModuleMember -Function Test-PortListening, Stop-ProcessByPort, Start-DetachedProcess, Wait-ForPort
