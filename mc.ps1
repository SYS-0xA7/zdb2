[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==========================================
# 1. Disable QuickEdit & P/Invoke Setup
# ==========================================
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
        # Disable QuickEdit (0x0040) to prevent accidental script pausing
        $mode = $mode -band -not (0x0040 -bor 0x0020)
        $Kernel32::SetConsoleMode($hInput, $mode -bor 0x0080)
    }
}

Disable-QuickEdit

# ==========================================
# 2. Auto-Request Admin Privileges
# ==========================================
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n [!] Requesting Administrative Privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) { $scriptPath = $PSCommandPath } else {
        $scriptPath = Join-Path $env:TEMP "minecraft_setup_temp.ps1"
        $scriptText = $MyInvocation.MyCommand.ScriptBlock.ToString()
        Set-Content -Path $scriptPath -Value $scriptText -Encoding UTF8
    }
    # Relaunch as Admin
    Start-Process -FilePath "conhost.exe" -Verb RunAs -ArgumentList "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

# ==========================================
# 3. Setup UI & Variables
# ==========================================
$host.UI.RawUI.BackgroundColor = "Black"
$host.UI.RawUI.WindowTitle = "Minecraft Bedrock Setup Tool"
Clear-Host

$ErrorActionPreference = "Stop"

# Define Paths
$minecraftDir = "C:\XboxGames\Minecraft for Windows\Content"
$exePath = "$minecraftDir\Minecraft.Windows.exe"
$zipPath = "$minecraftDir\minecraft.zip"
$iconPath = "$minecraftDir\minecraftIcon.ico"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = "$desktopPath\Minecraft Bedrock.lnk"

# Define URLs
$urlPrimary = "https://zdb2.pages.dev/minecraft.zip"
$urlFallback = "https://github.com/WolfGames156/zdb2/raw/refs/heads/main/minecraft.zip"

Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "       Minecraft Bedrock Setup Tool       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Magenta

# ==========================================
# 4. Main Script Logic
# ==========================================

# Step 4: Add to Windows Defender Exclusions
Write-Host "`n[1] Adding directory to Windows Defender exclusions..." -ForegroundColor Cyan
try {
    Add-MpPreference -ExclusionPath $minecraftDir
    Write-Host "Successfully added to Defender exclusions!" -ForegroundColor Green
} catch {
    Write-Host "Warning: Failed to add Defender exclusion. (You might be using a third-party antivirus or Defender is disabled)." -ForegroundColor Yellow
}

# Step 1: Check if Minecraft exists
Write-Host "`n[2] Checking for Minecraft for Windows..." -ForegroundColor Cyan

if (-not (Test-Path -Path $exePath)) {
    Write-Host "Error: Minecraft.Windows.exe not found!" -ForegroundColor Red
    Write-Host "Please download the Minecraft for Windows trial version first." -ForegroundColor Yellow
    Write-Host "`nPress any key to close..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host "Minecraft found! Proceeding..." -ForegroundColor Green

# Ensure secure connections for downloading
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Step 2: Download the ZIP file
Write-Host "`n[3] Starting download..." -ForegroundColor Cyan
try {
    Write-Host "Attempting to download from primary source..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $urlPrimary -OutFile $zipPath
    Write-Host "Download successful from primary source!" -ForegroundColor Green
} catch {
    Write-Host "Primary download failed. Attempting fallback source..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $urlFallback -OutFile $zipPath
        Write-Host "Download successful from fallback source!" -ForegroundColor Green
    } catch {
        Write-Host "Error: Failed to download from both sources. Check your internet connection." -ForegroundColor Red
        Write-Host "`nPress any key to close..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
}

# Step 3: Extract the ZIP file
Write-Host "`n[4] Extracting files to game directory..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $zipPath -DestinationPath $minecraftDir -Force
    Write-Host "Extraction complete!" -ForegroundColor Green
    
    # Clean up
    Remove-Item -Path $zipPath -Force
} catch {
    Write-Host "Error: Failed to extract files." -ForegroundColor Red
    Write-Host "`nPress any key to close..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}


# Step 5: Create Desktop Shortcut
Write-Host "`n[5] Creating desktop shortcut..." -ForegroundColor Cyan
try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = $exePath
    $Shortcut.WorkingDirectory = $minecraftDir
    $Shortcut.IconLocation = $iconPath
    $Shortcut.Save()
    Write-Host "Shortcut created successfully on your Desktop!" -ForegroundColor Green
} catch {
    Write-Host "Warning: Failed to create shortcut." -ForegroundColor Yellow
}

# Step 6: Success and Exit
Write-Host "`n==========================================" -ForegroundColor Magenta
Write-Host "Setup completed successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "`nPress any key to close..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
