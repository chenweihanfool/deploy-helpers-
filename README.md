# DeployHelpers

Windows 部署腳本通用輔助模組，封裝在繁體中文 Windows 下踩過的兩個坑的標準解法。

## 解決的問題

### 1. Port 監聽判斷（`Test-PortListening` / `Stop-ProcessByPort` / `Wait-ForPort`）

`netstat -ano | Select-String "LISTENING"` 在繁體中文 Windows 輸出是「監聽中」，硬編碼的 `"LISTENING"` 永遠比對不到，導致：
- 舊程序永遠殺不掉（以為沒人在聽）
- 新程序永遠啟動失敗（以為 port 沒空）
- 每一次「更新」其實都在跑舊程式碼

→ 改用 `Get-NetTCPConnection -State Listen`，`.State` 是固定列舉值 `Listen`，不受系統語言影響。

### 2. 背景程序啟動（`Start-DetachedProcess`）

`cmd /c start /B node proxy.js` 把子程序掛在 `cmd.exe` 底下，`cmd.exe` 共用父 PowerShell 的 console 串流，導致父腳本卡在等待子程序結束的狀態。

→ 改用 `Start-Process -WindowStyle Hidden`，建立全新獨立的行程，父腳本立即返回。

## 使用方式

```powershell
Import-Module "F:\deploy-helpers\DeployHelpers.psm1"

# 檢查 port
if (Test-PortListening -Port 3456) { "Port 3456 is in use" }

# 砍掉佔 port 的程序
Stop-ProcessByPort -Port 3456

# 啟動背景程序
Start-DetachedProcess -FilePath "node" -Arguments "proxy.js" -WorkingDirectory "F:\project\scripts"

# 等待 port 上線
if (Wait-ForPort -Port 3456 -Retries 5 -DelaySeconds 2) { "Proxy started" }
```

## 專案清單

`projects.json` 記錄各專案的部署腳本路徑，供通用「更新 XXX」Skill 查詢使用。
