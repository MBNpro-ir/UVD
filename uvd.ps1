param (
    [Alias('h')]
    [switch]$Help
)

# --- Script Wide Settings ---
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load required .NET assemblies
Add-Type -AssemblyName System.Web

$scriptDir = $PSScriptRoot
$settingsPath = Join-Path $scriptDir "settings.json"
$settings = $null
$DebugLogPath = $null  # Will be set after loading settings

$originalBackground = $Host.UI.RawUI.BackgroundColor
$originalForeground = $Host.UI.RawUI.ForegroundColor

# Browser cookie state
$script:useBrowserCookies = $false
$script:browserCookieSource = ""

# --- Configure Terminal Size ---
try {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;

    public class ConsoleHelper {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetConsoleWindow();

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFOEX lpConsoleCurrentFont);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CONSOLE_FONT_INFOEX {
            public int cbSize;
            public int nFont;
            public short FontWidth;
            public short FontHeight;
            public int FontFamily;
            public int FontWeight;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string FaceName;
        }

        public static int GetFontHeight() {
            IntPtr hConsole = GetConsoleWindow();
            if (hConsole == IntPtr.Zero) return 16;
            CONSOLE_FONT_INFOEX fontInfo = new CONSOLE_FONT_INFOEX();
            fontInfo.cbSize = Marshal.SizeOf(fontInfo);
            if (GetCurrentConsoleFontEx(hConsole, false, ref fontInfo)) {
                return fontInfo.FontHeight;
            }
            return 16;
        }
    }
"@ -ErrorAction SilentlyContinue

    $desiredWidth = 120
    $targetHeightPixels = 870

    $fontHeight = 16
    try {
        $fontHeight = [ConsoleHelper]::GetFontHeight()
    } catch {
        $fontHeight = 16
    }
    if ($fontHeight -le 0) { $fontHeight = 16 }

    $desiredHeight = [Math]::Ceiling($targetHeightPixels / $fontHeight)

    $maxWindowSize = $Host.UI.RawUI.MaxWindowSize
    
    $finalWidth = [Math]::Min($desiredWidth, $maxWindowSize.Width)
    $finalHeight = [Math]::Min($desiredHeight, $maxWindowSize.Height)
    
    $currentBufferSize = $Host.UI.RawUI.BufferSize
    $newBufferSize = $currentBufferSize
    $newBufferSize.Width = [Math]::Max($finalWidth, $currentBufferSize.Width)
    $newBufferSize.Height = [Math]::Max([Math]::Max($finalHeight, 1000), $currentBufferSize.Height)
    $Host.UI.RawUI.BufferSize = $newBufferSize
    
    $newWindowSize = $Host.UI.RawUI.WindowSize
    $newWindowSize.Width = $finalWidth
    $newWindowSize.Height = $finalHeight
    $Host.UI.RawUI.WindowSize = $newWindowSize
    
    Write-Host "Terminal size configured: $($finalWidth)x$($finalHeight) (~${targetHeightPixels}px)" -ForegroundColor Green
} catch {
    Write-Warning "Could not set terminal size: $($_.Exception.Message)"
}

# --- Enhanced Error Handling Functions ---

function Get-DetailedErrorMessage {
    param (
        [string]$ErrorMessage,
        [string]$ExitCode = ""
    )
    
    $detailedMessage = ""
    $solution = @()
    
    switch -Regex ($ErrorMessage) {
        "HTTP Error 403.*Forbidden" {
            $detailedMessage = "ACCESS DENIED - The video server rejected the download request"
            $solution = @(
                "• Try using cookies from your browser",
                "• Check if video is age-restricted or region-blocked", 
                "• Video might be private or members-only",
                "• Try using a VPN if region-blocked"
            )
        }
        "HTTP Error 429.*Too Many Requests" {
            $detailedMessage = "RATE LIMITED - Too many requests sent to server"
            $solution = @(
                "• Wait 15-30 minutes before trying again",
                "• Use a different IP address or VPN",
                "• Try downloading at a different time"
            )
        }
        "HTTP Error 404.*Not Found" {
            $detailedMessage = "VIDEO NOT FOUND - The video no longer exists or URL is incorrect"
            $solution = @(
                "• Check if the video URL is correct",
                "• Video might have been deleted or made private",
                "• Try accessing the video in browser first"
            )
        }
        "SSL.*CERTIFICATE_VERIFY_FAILED" {
            $detailedMessage = "SSL CERTIFICATE ERROR - Cannot verify website security certificate"
            $solution = @(
                "• Your system clock might be incorrect",
                "• Antivirus software might be interfering",
                "• Update your system certificates"
            )
        }
        "sign in to confirm your age" {
            $detailedMessage = "AGE-RESTRICTED CONTENT - Video requires age verification"
            $solution = @(
                "• Use cookies from a logged-in browser session",
                "• Log in to YouTube in your browser first",
                "• Export cookies.txt file from your browser"
            )
        }
        "URLError.*timed out|timeout" {
            $detailedMessage = "NETWORK TIMEOUT - Connection to server timed out"
            $solution = @(
                "• Check your internet connection",
                "• Try using a VPN or proxy",
                "• Try again later when network is stable"
            )
        }
        "Unknown encoder" {
            $detailedMessage = "MISSING CODEC - FFmpeg doesn't support the requested encoder"
            $solution = @(
                "• Install a complete ffmpeg build with all codecs",
                "• Download ffmpeg from official sources",
                "• Use a different output format"
            )
        }
        "Permission denied|Access denied" {
            $detailedMessage = "ACCESS DENIED - Insufficient permissions to write files"
            $solution = @(
                "• Run as administrator",
                "• Check folder permissions",
                "• Choose a different download location"
            )
        }
        "No space left on device|Disk full" {
            $detailedMessage = "DISK FULL - Insufficient storage space"
            $solution = @(
                "• Free up disk space",
                "• Choose a different download location",
                "• Download smaller quality video"
            )
        }
        "FileNotFoundError.*ffmpeg" {
            $detailedMessage = "FFMPEG NOT FOUND - FFmpeg executable is missing"
            $solution = @(
                "• Install ffmpeg from official website",
                "• Add ffmpeg to system PATH",
                "• Place ffmpeg.exe in script directory"
            )
        }
        "JSON.*decode.*error|Invalid.*JSON" {
            $detailedMessage = "DATA PARSING ERROR - Cannot parse video information"
            $solution = @(
                "• Try clearing cache and retry",
                "• Update yt-dlp to latest version",
                "• Video site might have changed format"
            )
        }
        default {
            $detailedMessage = "UNKNOWN ERROR - An unexpected error occurred"
            $solution = @(
                "• Check debug.txt for detailed error information",
                "• Try updating yt-dlp and ffmpeg to latest versions",
                "• Try with a different video URL"
            )
        }
    }
    
    return @{
        DetailedMessage = $detailedMessage
        Solutions = $solution
        ExitCode = $ExitCode
    }
}

function Show-EnhancedError {
    param (
        [string]$TechnicalError,
        [string]$ExitCode = "",
        [string]$Context = ""
    )
    
    $errorInfo = Get-DetailedErrorMessage -ErrorMessage $TechnicalError -ExitCode $ExitCode
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                                    ERROR DETECTED                              ║" -ForegroundColor Red  
    Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "🔍 ERROR TYPE:" -ForegroundColor Yellow
    Write-Host "   $($errorInfo.DetailedMessage)" -ForegroundColor Red
    Write-Host ""
    
    if ($Context) {
        Write-Host "📍 CONTEXT:" -ForegroundColor Yellow
        Write-Host "   $Context" -ForegroundColor White
        Write-Host ""
    }
    
    if ($ExitCode) {
        Write-Host "🔢 EXIT CODE:" -ForegroundColor Yellow
        Write-Host "   $ExitCode" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "💡 POSSIBLE SOLUTIONS:" -ForegroundColor Green
    foreach ($solution in $errorInfo.Solutions) {
        Write-Host "   $solution" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "📋 TECHNICAL DETAILS:" -ForegroundColor Yellow
    # Truncate very long technical errors to avoid terminal spam
    $truncatedTechnicalError = if ($TechnicalError.Length -gt 800) {
        $TechnicalError.Substring(0, 800) + "... [Error message truncated - full details in debug log]"
    } else {
        $TechnicalError
    }
    Write-Host "   $truncatedTechnicalError" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "🔗 NEED HELP?" -ForegroundColor Cyan
    Write-Host "   Send debug.txt and description to: https://t.me/mbnproo" -ForegroundColor White
    Write-Host ""
    
    Write-ErrorLog "Enhanced Error: $($errorInfo.DetailedMessage) | Technical: $TechnicalError | Exit Code: $ExitCode"
}

function Get-ValidatedUserInput {
    param (
        [string]$Prompt,
        [string]$InputType = "text", # text, yesno, number, url, choice
        [array]$ValidChoices = @(),
        [int]$MinValue = 0,
        [int]$MaxValue = 0,
        [int]$MaxAttempts = 3
    )
    
    $attempts = 0
    
    while ($attempts -lt $MaxAttempts) {
        $attempts++
        
        if ($attempts -gt 1) {
            Write-Host ""
            Write-Host "⚠️  Invalid input. Please try again. (Attempt $attempts of $MaxAttempts)" -ForegroundColor Yellow
        }
        
        Write-Host $Prompt -NoNewline -ForegroundColor Green
        $userInput = Read-Host " "
        Write-UserInputLog $Prompt $userInput
        
        # Validate based on input type
        switch ($InputType) {
            "yesno" {
                if ($userInput -match "^[yYnN]$" -or $userInput.ToLower() -in @("yes", "no", "y", "n")) {
                    return $userInput.ToLower()[0]
                }
                Write-Host "Please enter Y (yes) or N (no)" -ForegroundColor Red
            }
            
            "number" {
                if ($userInput -match "^\d+$") {
                    $number = [int]$userInput
                    if ($MaxValue -gt 0 -and ($number -lt $MinValue -or $number -gt $MaxValue)) {
                        Write-Host "Please enter a number between $MinValue and $MaxValue" -ForegroundColor Red
                    } else {
                        return $number
                    }
                } else {
                    Write-Host "Please enter a valid number" -ForegroundColor Red
                }
            }
            
            "url" {
                if ($userInput -match "^https?://.*" -or
                    $userInput -in @("help", "-h", "exit", "restart", "clear-cache", "folder", "downloads", "settings")) {
                    return $userInput
                }
                Write-Host "Please enter a valid URL or command (help, exit, restart, clear-cache, folder, downloads, settings)" -ForegroundColor Red
            }
            
            "choice" {
                if ($userInput -in $ValidChoices) {
                    return $userInput
                }
                Write-Host "Please choose from: $($ValidChoices -join ', ')" -ForegroundColor Red
            }
            
            "text" {
                if (![string]::IsNullOrWhiteSpace($userInput)) {
                    return $userInput
                }
                Write-Host "Please enter a valid response" -ForegroundColor Red
            }
        }
    }
    
    Write-Host ""
    Write-Host "❌ Maximum attempts reached. Using default or exiting..." -ForegroundColor Red
    return $null
}

# --- Function Definitions ---

function Load-Settings {
    $defaultSettings = Get-DefaultSettings
    
    if (Test-Path $settingsPath) {
        try {
            $fileSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            
            # Merge file settings with default settings
            $global:settings = @{
                general = if ($fileSettings.general) { $fileSettings.general } else { $defaultSettings.general }
                proxy = if ($fileSettings.proxy) { $fileSettings.proxy } else { $defaultSettings.proxy }
                cookies = if ($fileSettings.cookies) { $fileSettings.cookies } else { $defaultSettings.cookies }
                youtube_login = if ($fileSettings.youtube_login) { $fileSettings.youtube_login } else { $defaultSettings.youtube_login }
                download = if ($fileSettings.download) { $fileSettings.download } else { $defaultSettings.download }
                optimization = if ($fileSettings.optimization) { $fileSettings.optimization } else { $defaultSettings.optimization }
                advanced = if ($fileSettings.advanced) { $fileSettings.advanced } else { $defaultSettings.advanced }
            }
            
            # Initialize debug logging after settings are loaded
            $debugInitialized = Initialize-DebugLogging
            
            Write-Host "Settings loaded from $settingsPath" -ForegroundColor Green
            if ($debugInitialized) {
                Write-ErrorLog "=== SCRIPT STARTUP ==="
                Write-ErrorLog "Settings loaded successfully from $settingsPath"
                Write-ErrorLog "Debug logging enabled - Level: $([bool]$settings.advanced.enable_debug_logging)"
                Write-ErrorLog "Log file path: $global:DebugLogPath"
                Write-ErrorLog "Script arguments: $($MyInvocation.BoundParameters | ConvertTo-Json -Compress)"
            }
        } catch {
            Write-Warning "Failed to load settings from $settingsPath. Using default settings."
            $global:settings = $defaultSettings
            Initialize-DebugLogging
            Write-ErrorLog "Failed to load settings: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Settings file not found. Creating new settings file..."
        $global:settings = $defaultSettings
        Initialize-DebugLogging
        Write-ErrorLog "Settings file not found, creating new one"
        
        # Create settings file
        if (Create-SettingsFile -Path $settingsPath) {
            Write-Host "Created new settings file with default values." -ForegroundColor Green
            Write-ErrorLog "Settings file created successfully"
        } else {
            Write-Warning "Could not create settings file. Using default settings in memory."
            Write-ErrorLog "Failed to create settings file, using default settings in memory"
        }
    }
}

function Get-DefaultSettings {
    return @{
        general = @{
            request_timeout_seconds = 20
            max_retries = 3
            show_processing_messages = $true
            use_database_cache = $true
            database_file = "video_cache.json"
        }
        proxy = @{
            use_system_proxy = $true
            custom_proxy_enabled = $false
            custom_proxy_host = ""
            custom_proxy_port = ""
            custom_proxy_username = ""
            custom_proxy_password = ""
        }
        cookies = @{
            use_cookies = $false
            cookie_file_path = "cookies.txt"
            cookie_file_directory = ""
            cookie_source = ""
        }
        youtube_login = @{
            enable_auto_login = $true
            chrome_profile_path = ""
            login_timeout_seconds = 60
        }
        download = @{
            temp_directory = "Temp"
            output_directory = "Downloaded"
            video_subdirectory = "Video"
            audio_subdirectory = "Audio"
            covers_subdirectory = "Covers"
        }
        optimization = @{
            concurrent_fragments = 4
            fragment_retries = 10
            retry_sleep = 5
            socket_timeout = 30
            sleep_requests = 1
            sleep_interval = 3
            max_sleep_interval = 7
            extractor_args = "youtube:player_client=web,android_vr,tv_downgraded"
            extractor_retries = 3
            use_aria2c_downloader = $false
            rate_limit = ""
            enable_optimization = $true
        }
        advanced = @{
            enable_debug_logging = $false
            log_file_path = "debug.txt"
            cleanup_temp_files = $true
            max_description_lines = 5
        }

    }
}

function Create-SettingsFile {
    param ([string]$Path = $settingsPath)
    
    try {
        $jsonContent = @"
{
    "general": {
        "request_timeout_seconds": 20,
        "max_retries": 3,
        "show_processing_messages": true,
        "use_database_cache": true,
        "database_file": "video_cache.json"
    },
    "proxy": {
        "use_system_proxy": true,
        "custom_proxy_enabled": false,
        "custom_proxy_host": "",
        "custom_proxy_port": "",
        "custom_proxy_username": "",
        "custom_proxy_password": ""
    },
    "cookies": {
        "use_cookies": false,
        "cookie_file_path": "cookies.txt",
        "cookie_file_directory": "",
        "cookie_source": ""
    },
    "youtube_login": {
        "enable_auto_login": true,
        "chrome_profile_path": "",
        "login_timeout_seconds": 60
    },
    "download": {
        "temp_directory": "Temp",
        "output_directory": "Downloaded",
        "video_subdirectory": "Video",
        "audio_subdirectory": "Audio",
        "covers_subdirectory": "Covers"
    },
    "optimization": {
        "concurrent_fragments": 4,
        "fragment_retries": 10,
        "retry_sleep": 5,
        "socket_timeout": 30,
        "sleep_requests": 1,
        "sleep_interval": 3,
        "max_sleep_interval": 7,
        "extractor_args": "youtube:player_client=web,android_vr,tv_downgraded",
        "extractor_retries": 3,
        "use_aria2c_downloader": false,
        "rate_limit": "",
        "enable_optimization": true
    },
    "advanced": {
        "enable_debug_logging": false,
        "log_file_path": "debug.txt",
        "cleanup_temp_files": true,
        "max_description_lines": 5
    }
}
"@
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $jsonContent, $utf8NoBom)
        Write-Host "Settings file created successfully at: $Path" -ForegroundColor Green
        Write-ErrorLog "Settings file created at: $Path"
        return $true
    } catch {
        Write-Warning "Failed to create settings file: $($_.Exception.Message)"
        Write-ErrorLog "Failed to create settings file: $($_.Exception.Message)"
        return $false
    }
}

function Save-Settings {
    param ([string]$Path = $settingsPath)
    
    try {
        $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        Write-ErrorLog "Settings saved to: $Path"
        return $true
    } catch {
        Write-Warning "Failed to save settings: $($_.Exception.Message)"
        Write-ErrorLog "Failed to save settings: $($_.Exception.Message)"
        return $false
    }
}

function Create-CookieFile {
    param ([string]$Path)
    
    try {
        if (Test-Path $Path) {
            return $true
        }
        
        $cookieContent = @"
# Netscape HTTP Cookie File
# This file is generated by UVD. Do not edit manually.
# To use cookies, export them from your browser in Netscape format.
# https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies

# Example format:
# .youtube.com	TRUE	/	FALSE	0	cookie_name	cookie_value
"@
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $cookieContent, $utf8NoBom)
        Write-ErrorLog "Cookie template created at: $Path"
        return $true
    } catch {
        Write-Warning "Failed to create cookie file: $($_.Exception.Message)"
        Write-ErrorLog "Failed to create cookie file: $($_.Exception.Message)"
        return $false
    }
}

function Get-SystemProxy {
    try {
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings -and $proxySettings.ProxyEnable -eq 1 -and $proxySettings.ProxyServer) {
            Write-ErrorLog "System proxy detected: $($proxySettings.ProxyServer)"
            return $proxySettings.ProxyServer
        }
    } catch {
        Write-ErrorLog "Failed to get system proxy settings: $($_.Exception.Message)"
    }
    return $null
}

function Set-ProxyConfiguration {
    $systemProxy = $null
    if ([bool]$settings.proxy.use_system_proxy) {
        $systemProxy = Get-SystemProxy
    }
    
    if ($systemProxy) {
        $env:HTTP_PROXY = "http://$systemProxy"
        $env:HTTPS_PROXY = "http://$systemProxy"
        Write-ErrorLog "Proxy configuration set to system proxy: $systemProxy"
        return "Using system proxy: $systemProxy"
    } elseif ([bool]$settings.proxy.custom_proxy_enabled -and $settings.proxy.custom_proxy_host -and $settings.proxy.custom_proxy_port) {
        $customProxy = "$($settings.proxy.custom_proxy_host):$($settings.proxy.custom_proxy_port)"
        $env:HTTP_PROXY = "http://$customProxy"
        $env:HTTPS_PROXY = "http://$customProxy"
        Write-ErrorLog "Proxy configuration set to custom proxy: $customProxy"
        return "Using custom proxy: $customProxy"
    } else {
        Write-ErrorLog "No proxy configuration applied"
        return "No proxy configuration detected or enabled"
    }
}

function Initialize-Database {
    $dbPath = Join-Path $scriptDir $settings.general.database_file
    if (-not (Test-Path $dbPath)) {
        try {
            $emptyDb = @{ videos = @() }
            $emptyDb | ConvertTo-Json -Depth 10 | Out-File -FilePath $dbPath -Encoding UTF8
            Write-ErrorLog "Database initialized at $dbPath"
            return "Database initialized at $dbPath"
        } catch {
            Write-Warning "Failed to initialize database: $($_.Exception.Message)"
            Write-ErrorLog "Failed to initialize database: $($_.Exception.Message)"
        }
    }
    return $null
}

function Clear-VideoCache {
    param ([switch]$Force)
    
    $dbPath = Join-Path $scriptDir $settings.general.database_file
    if (-not (Test-Path $dbPath)) {
        Write-Host ""
        Write-Host "⚠️  No cache file found." -ForegroundColor Yellow
        return
    }
    
    if (-not $Force) {
        $confirm = Get-ValidatedUserInput -Prompt "⚠️ Clear all cached video information? (y/n):" -InputType "yesno" -MaxAttempts 3
        if ($confirm -eq 'n' -or $null -eq $confirm) {
            Write-Host ""
            Write-Host "❌ Cache clear cancelled." -ForegroundColor Red
            return
        }
    }
    
    try {
        $db = @{ videos = @() }
        $db | ConvertTo-Json -Depth 10 | Out-File -FilePath $dbPath -Encoding UTF8
        Write-Host ""
        Write-Host "✅ Video cache cleared successfully!" -ForegroundColor Green
        Write-ErrorLog "Video cache cleared by user"
    } catch {
        Write-Host ""
        Write-Host "❌ Failed to clear cache: $($_.Exception.Message)" -ForegroundColor Red
        Write-ErrorLog "Failed to clear cache: $($_.Exception.Message)"
    }
}

function Get-VideoFromCache {
    param ([string]$Url)
    
    if (-not [bool]$settings.general.use_database_cache) {
        return $null
    }
    
    $dbPath = Join-Path $scriptDir $settings.general.database_file
    if (-not (Test-Path $dbPath)) {
        return $null
    }
    
    try {
        $db = Get-Content $dbPath -Raw | ConvertFrom-Json
        $cachedEntry = $db.videos | Where-Object { $_.url -eq $Url }
        if ($cachedEntry) {
            # Validate cached entry has required fields
            if ($cachedEntry.info -and $cachedEntry.info.title -and $cachedEntry.info.formats) {
                Write-Host "Video information found in cache" -ForegroundColor Green
                Write-ErrorLog "Video retrieved from cache for URL: $Url"
                return $cachedEntry
            } else {
                Write-Warning "Cached entry is corrupted. Will re-fetch video information."
                Write-ErrorLog "Corrupted cache entry for URL: $Url"
                # Remove corrupted entry
                Remove-VideoFromCache -Url $Url
                return $null
            }
        }
    } catch {
        Write-ErrorLog "Failed to retrieve from cache: $($_.Exception.Message)"
        Write-Warning "Cache file might be corrupted. Consider deleting $dbPath"
    }
    
    return $null
}

function Remove-VideoFromCache {
    param ([string]$Url)
    
    $dbPath = Join-Path $scriptDir $settings.general.database_file
    if (-not (Test-Path $dbPath)) {
        return
    }
    
    try {
        $db = Get-Content $dbPath -Raw | ConvertFrom-Json
        $db.videos = @($db.videos | Where-Object { $_.url -ne $Url })
        $db | ConvertTo-Json -Depth 10 | Out-File -FilePath $dbPath -Encoding UTF8
        Write-ErrorLog "Removed corrupted cache entry for URL: $Url"
    } catch {
        Write-ErrorLog "Failed to remove cache entry: $($_.Exception.Message)"
    }
}

function Save-VideoToCache {
    param (
        [string]$Url,
        [psobject]$VideoInfo
    )
    
    if (-not [bool]$settings.general.use_database_cache) {
        return
    }
    
    $dbPath = Join-Path $scriptDir $settings.general.database_file
    
    try {
        $db = @{ videos = @() }
        if (Test-Path $dbPath) {
            $db = Get-Content $dbPath -Raw | ConvertFrom-Json
        }
        
        # Remove any existing entry for this URL
        $db.videos = @($db.videos | Where-Object { $_.url -ne $Url })
        
        # Add new entry
        $newEntry = @{
            url = $Url
            info = $VideoInfo
            cached_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $db.videos += $newEntry
        
        $db | ConvertTo-Json -Depth 10 | Out-File -FilePath $dbPath -Encoding UTF8
        Write-Host "Video information saved to cache" -ForegroundColor Green
        Write-ErrorLog "Video cached for URL: $Url"
    } catch {
        Write-Warning "Failed to save to cache: $($_.Exception.Message)"
        Write-ErrorLog "Failed to save to cache: $($_.Exception.Message)"
    }
}

function Get-CookieFilePath {
    $cookieFile = $settings.cookies.cookie_file_path
    if ($settings.cookies.cookie_file_directory) {
        $cookieFile = Join-Path $settings.cookies.cookie_file_directory $cookieFile
    } else {
        $cookieFile = Join-Path $scriptDir $cookieFile
    }
    
    if (-not (Test-Path $cookieFile)) {
        Write-ErrorLog "Cookie file not found at: $cookieFile (user must provide their own)"
    }
    
    if ([bool]$settings.cookies.use_cookies) {
        if (Test-Path $cookieFile) {
            Write-Host "Using cookie file: $cookieFile" -ForegroundColor Green
            Write-ErrorLog "Cookie file found and will be used: $cookieFile"
            return $cookieFile
        } else {
            Write-Warning "Cookie file not found at: $cookieFile"
            Write-ErrorLog "Cookie file not found at: $cookieFile"
            return $null
        }
    }
    
    return $cookieFile
}

function Show-ProcessingMessage {
    param ([string]$Message = "Processing, please wait...")
    
    if ([bool]$settings.general.show_processing_messages) {
        Write-Host $Message -ForegroundColor Yellow
        Write-ErrorLog "Processing message displayed: $Message"
    }
}

function Show-CustomDownloadProgress {
    param (
        [string]$Activity = "Downloading",
        [double]$Percentage = 0,
        [string]$TotalSize = "",
        [string]$Speed = "",
        [string]$ETA = "",
        [string]$CurrentSize = "",
        [string]$FileName = "",
        [string]$Stage = "download"  # download, merge, process
    )
    
    # Clear current line
    $clearLine = "`r" + (" " * [Math]::Min($Host.UI.RawUI.WindowSize.Width, 120)) + "`r"
    Write-Host $clearLine -NoNewline
    
    # Build progress bar
    $barWidth = 30
    $filledBars = [Math]::Floor($Percentage / 100 * $barWidth)
    $emptyBars = $barWidth - $filledBars
    
    # Use different characters for different stages
    $fillChar = switch ($Stage) {
        "download" { "█" }
        "merge" { "▓" }
        "process" { "▒" }
        default { "█" }
    }
    
    $progressBar = "[" + ($fillChar * $filledBars) + ("░" * $emptyBars) + "]"
    
    # Build status line
    $statusParts = @()
    
    # Add activity icon
    $activityIcon = switch ($Activity) {
        "Downloading" { "⬇" }
        "Merging" { "🔀" }
        "Processing" { "⚙" }
        "Converting" { "🔄" }
        "Extracting" { "📦" }
        default { "•" }
    }
    
    $statusParts += $activityIcon
    
    if ($FileName) {
        # Truncate filename if too long
        $maxFileNameLength = 35
        if ($FileName.Length -gt $maxFileNameLength) {
            $FileName = $FileName.Substring(0, $maxFileNameLength - 3) + "..."
        }
        $statusParts += $FileName
    }
    
    $statusParts += $progressBar
    $statusParts += "$([Math]::Round($Percentage, 1))%"
    
    if ($CurrentSize -and $TotalSize) {
        $statusParts += "$CurrentSize/$TotalSize"
    } elseif ($TotalSize) {
        $statusParts += $TotalSize
    }
    
    if ($Speed) {
        $statusParts += "@ $Speed"
    }
    
    if ($ETA -and $ETA -ne "Unknown") {
        $statusParts += "ETA: $ETA"
    }
    
    $statusLine = $statusParts -join " "
    
    # Color based on percentage and stage
    $color = if ($Percentage -ge 100) { "Green" } 
             elseif ($Stage -eq "merge") { "Magenta" }
             elseif ($Stage -eq "process") { "Cyan" }
             elseif ($Percentage -ge 75) { "Yellow" } 
             elseif ($Percentage -ge 50) { "Cyan" } 
             else { "White" }
    
    Write-Host $statusLine -ForegroundColor $color -NoNewline
}

function Initialize-DebugLogging {
    # Set global debug logging path based on settings
    if ($settings -and [bool]$settings.advanced.enable_debug_logging) {
        $global:DebugLogPath = Join-Path $scriptDir $settings.advanced.log_file_path
        
        # Create/Clear the debug log file for new session
        try {
            $sessionStart = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $header = @"
===============================================================================
DEBUG LOG SESSION STARTED: $sessionStart
Script Directory: $scriptDir
PowerShell Version: $($PSVersionTable.PSVersion)
OS Version: $([System.Environment]::OSVersion.VersionString)
===============================================================================

"@
            Set-Content -Path $global:DebugLogPath -Value $header -Encoding UTF8 -ErrorAction Stop
            return $true
        } catch {
            Write-Warning "Failed to initialize debug log: $($_.Exception.Message)"
            $global:DebugLogPath = $null
            return $false
        }
    } else {
        $global:DebugLogPath = $null
        return $false
    }
}

function Write-ErrorLog {
    param ([string]$message)
    
    # Only log if debug logging is enabled and path is set
    if (-not $global:DebugLogPath -or -not $settings -or -not [bool]$settings.advanced.enable_debug_logging) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    try {
        Add-Content -Path $global:DebugLogPath -Value $logMessage -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Silently fail to avoid spam if logging fails
    }
}

function Write-UserInputLog {
    param (
        [string]$prompt,
        [string]$userInput
    )
    
    if ($global:DebugLogPath) {
        Write-ErrorLog "USER INPUT - Prompt: '$prompt' | Input: '$userInput'"
    }
}

function Write-SessionEndLog {
    if ($global:DebugLogPath) {
        $sessionEnd = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $footer = @"

===============================================================================
DEBUG LOG SESSION ENDED: $sessionEnd
===============================================================================
"@
        try {
            Add-Content -Path $global:DebugLogPath -Value $footer -Encoding UTF8 -ErrorAction Stop
        } catch {
            # Silently fail
        }
    }
}

function Get-LocalVersion {
    param (
        [string]$ExecutablePath,
        [string]$VersionArg = "--version"
    )
    
    if (-not (Test-Path $ExecutablePath)) {
        return $null
    }
    
    try {
        $versionOutput = & $ExecutablePath $VersionArg 2>&1 | Select-Object -First 1
        if ($versionOutput -match '(\d+\.[\d.]+)') {
            return $matches[1]
        }
        return "unknown"
    } catch {
        Write-ErrorLog "Failed to get version for $ExecutablePath : $($_.Exception.Message)"
        return "unknown"
    }
}

function Get-LatestYtDlpVersion {
    try {
        $apiUrl = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
        return $response.tag_name
    } catch {
        Write-ErrorLog "Failed to get latest yt-dlp version: $($_.Exception.Message)"
        return $null
    }
}

function Get-LatestFfmpegVersion {
    try {
        $apiUrl = "https://api.github.com/repos/GyanD/codexffmpeg/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
        foreach ($asset in $response.assets) {
            if ($asset.name -match 'ffmpeg-(.+?)-essentials_build\.zip') {
                return $matches[1]
            }
        }
        return $response.tag_name
    } catch {
        Write-ErrorLog "Failed to get latest ffmpeg version: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-StartupTask {
    param(
        [string]$Message,
        [scriptblock]$Action
    )
    
    # Store cursor position
    $cursorPos = $Host.UI.RawUI.CursorPosition
    
    # Write initial task status
    Write-Host -NoNewline "  [ ] $Message"
    
    # Execute the action and capture its output and success/failure
    $actionOutput = & $Action
    $success = $? # Check if the last command was successful
    
    # Move cursor back to the start of the line and clear it
    $Host.UI.RawUI.CursorPosition = $cursorPos
    $clearLine = " " * ($Host.UI.RawUI.WindowSize.Width - 1)
    Write-Host -NoNewline $clearLine
    $Host.UI.RawUI.CursorPosition = $cursorPos

    # Write final status
    if ($success) {
        Write-Host "  [✓] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [✗] $Message" -ForegroundColor Red
    }
    
    # If the action produced any output, display it on a new line, indented
    if ($actionOutput) {
        $outputString = $actionOutput | Out-String
        if (-not [string]::IsNullOrWhiteSpace($outputString)) {
            $indentedOutput = $outputString.Trim() -replace '(?m)^', '      '
            Write-Host $indentedOutput -ForegroundColor Gray
        }
    }
}

function Test-WingetAvailable {
    try {
        $null = Get-Command "winget" -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Find-ToolInPath {
    param ([string]$ToolName)
    
    $foundPath = Get-Command $ToolName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
    if ($foundPath) {
        return $foundPath
    }
    
    $wingetPackages = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
        "$env:PROGRAMFILES\WinGet\Packages",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
    )
    
    foreach ($pkgDir in $wingetPackages) {
        if (Test-Path $pkgDir) {
            $found = Get-ChildItem -Path $pkgDir -Recurse -Filter "$ToolName.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                return $found.FullName
            }
        }
    }
    
    return $null
}

function Resolve-ToolPath {
    param (
        [string]$ToolName,
        [string]$LocalPath
    )
    
    $systemPath = Find-ToolInPath -ToolName $ToolName
    if ($systemPath -and (Test-Path $systemPath)) {
        return $systemPath
    }
    
    if (Test-Path $LocalPath) {
        return $LocalPath
    }
    
    return $LocalPath
}

function Update-YtDlp {
    param ([string]$YtDlpPath, [switch]$Quiet)
    
    if (-not $Quiet) { Write-Host "Checking yt-dlp version..." -ForegroundColor Yellow }
    
    $wingetAvailable = Test-WingetAvailable
    $localVersion = Get-LocalVersion -ExecutablePath $YtDlpPath
    
    if ($null -eq $localVersion -and $wingetAvailable) {
        $systemYtDlp = Find-ToolInPath -ToolName "yt-dlp"
        if ($systemYtDlp) {
            $localVersion = Get-LocalVersion -ExecutablePath $systemYtDlp
            if ($localVersion -and $localVersion -ne "unknown") {
                $YtDlpPath = $systemYtDlp
                if (-not $Quiet) { Write-Host "Found system yt-dlp: $systemYtDlp" -ForegroundColor Cyan }
            }
        }
    }
    
    $latestVersion = Get-LatestYtDlpVersion
    
    $needsUpdate = $false
    if ($null -eq $localVersion) {
        if (-not $Quiet) { Write-Host "yt-dlp not found. Installing via winget..." -ForegroundColor Yellow }
        $needsUpdate = $true
    } elseif ($null -eq $latestVersion) {
        if (-not $Quiet) { Write-Host "Could not check latest yt-dlp version. Using existing version." -ForegroundColor Yellow }
        return @{ Success = $true; NeedsRestart = $false }
    } elseif ($localVersion -eq "unknown") {
        if (-not $Quiet) { Write-Host "Could not determine local yt-dlp version. Re-installing..." -ForegroundColor Yellow }
        $needsUpdate = $true
    } else {
        if (-not $Quiet) {
            Write-Host "Local yt-dlp version: $localVersion" -ForegroundColor Cyan
            Write-Host "Latest yt-dlp version: $latestVersion" -ForegroundColor Cyan
        }
        
        if ($localVersion -ne $latestVersion) {
            if (-not $Quiet) { Write-Host "New version available! Updating..." -ForegroundColor Green }
            $needsUpdate = $true
        } else {
            if (-not $Quiet) { Write-Host "yt-dlp is up to date." -ForegroundColor Green }
            return @{ Success = $true; NeedsRestart = $false }
        }
    }
    
    if ($needsUpdate) {
        $needsRestart = $false
        
        if ($wingetAvailable) {
            if (-not $Quiet) { Write-Host "Installing yt-dlp via winget (official)..." -ForegroundColor Cyan }
            
            $installResult = $null
            try {
                if ($localVersion) {
                    $installResult = & winget upgrade --id yt-dlp.yt-dlp --accept-package-agreements --accept-source-agreements 2>&1
                } else {
                    $installResult = & winget install --id yt-dlp.yt-dlp --accept-package-agreements --accept-source-agreements 2>&1
                }
                
                $installOutput = $installResult | Out-String
                
                if ($installOutput -match "Successfully installed" -or $installOutput -match "Successfully upgraded" -or $installOutput -match "No applicable update") {
                    if (-not $Quiet) { Write-Host "yt-dlp installed/updated via winget successfully!" -ForegroundColor Green }
                    Write-ErrorLog "yt-dlp installed/updated via winget"
                    $needsRestart = $true
                    
                    $newSystemPath = Find-ToolInPath -ToolName "yt-dlp"
                    if ($newSystemPath) {
                        $YtDlpPath = $newSystemPath
                        if (-not $Quiet) { Write-Host "yt-dlp found at: $newSystemPath" -ForegroundColor Cyan }
                    }
                    
                    return @{ Success = $true; NeedsRestart = $needsRestart }
                }
            } catch {
                if (-not $Quiet) { Write-Host "Winget installation failed, falling back to manual download..." -ForegroundColor Yellow }
                Write-ErrorLog "Winget install failed for yt-dlp: $($_.Exception.Message)"
            }
        }
        
        if (Test-Path $YtDlpPath) {
            $backupPath = "$YtDlpPath.old"
            try {
                Move-Item -Path $YtDlpPath -Destination $backupPath -Force -ErrorAction Stop
                if (-not $Quiet) { Write-Host "Backed up old version to $backupPath" -ForegroundColor Gray }
            } catch {
                if (-not $Quiet) { Write-Warning "Failed to backup old yt-dlp: $($_.Exception.Message)" }
            }
        }
        
        $ytDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        try {
            if (-not $Quiet) { Write-Host "Downloading yt-dlp manually from GitHub..." -ForegroundColor Yellow }
            Invoke-WebRequest -Uri $ytDlpUrl -OutFile $YtDlpPath -ErrorAction Stop
            if (-not $Quiet) { Write-Host "yt-dlp updated successfully to version $latestVersion" -ForegroundColor Green }
            Write-ErrorLog "yt-dlp updated manually to version $latestVersion"
            
            if (Test-Path "$YtDlpPath.old") {
                Remove-Item -Path "$YtDlpPath.old" -Force -ErrorAction SilentlyContinue
            }
            return @{ Success = $true; NeedsRestart = $false }
        } catch {
            if (Test-Path "$YtDlpPath.old") {
                Move-Item -Path "$YtDlpPath.old" -Destination $YtDlpPath -Force -ErrorAction SilentlyContinue
            }
            Resolve-ScriptError -UserMessage "Failed to download yt-dlp. Check your internet connection." `
                               -InternalLogMessage "Invoke-WebRequest failed for yt-dlp. URL: $ytDlpUrl. Exception: $($_.Exception.Message)" `
                               -IsCritical $true
            return @{ Success = $false; NeedsRestart = $false }
        }
    }
    return @{ Success = $true; NeedsRestart = $false }
}

function Update-Ffmpeg {
    param ([string]$FfmpegPath, [switch]$Quiet)
    
    if (-not $Quiet) { Write-Host "Checking ffmpeg version..." -ForegroundColor Yellow }
    
    $wingetAvailable = Test-WingetAvailable
    $localVersion = Get-LocalVersion -ExecutablePath $FfmpegPath -VersionArg "-version"
    
    if ($null -eq $localVersion -and $wingetAvailable) {
        $systemFfmpeg = Find-ToolInPath -ToolName "ffmpeg"
        if ($systemFfmpeg) {
            $localVersion = Get-LocalVersion -ExecutablePath $systemFfmpeg -VersionArg "-version"
            if ($localVersion -and $localVersion -ne "unknown") {
                $FfmpegPath = $systemFfmpeg
                if (-not $Quiet) { Write-Host "Found system ffmpeg: $systemFfmpeg" -ForegroundColor Cyan }
            }
        }
    }
    
    $needsUpdate = $false
    if ($null -eq $localVersion) {
        if (-not $Quiet) { Write-Host "ffmpeg not found. Installing via winget..." -ForegroundColor Yellow }
        $needsUpdate = $true
    } else {
        if (Test-Path $FfmpegPath) {
            $fileAge = (Get-Date) - (Get-Item $FfmpegPath).LastWriteTime
            if ($fileAge.Days -gt 30) {
                if (-not $Quiet) { Write-Host "ffmpeg is more than 30 days old. Updating..." -ForegroundColor Yellow }
                $needsUpdate = $true
            } else {
                if (-not $Quiet) { Write-Host "ffmpeg is relatively recent (less than 30 days old)." -ForegroundColor Green }
                return @{ Success = $true; NeedsRestart = $false }
            }
        }
    }
    
    if ($needsUpdate) {
        $needsRestart = $false
        
        if ($wingetAvailable) {
            if (-not $Quiet) { Write-Host "Installing ffmpeg via winget (official Gyan.FFmpeg)..." -ForegroundColor Cyan }
            
            try {
                $installResult = & winget install --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements 2>&1
                $installOutput = $installResult | Out-String
                
                if ($installOutput -match "Successfully installed" -or $installOutput -match "No applicable update") {
                    if (-not $Quiet) { Write-Host "ffmpeg installed via winget successfully!" -ForegroundColor Green }
                    Write-ErrorLog "ffmpeg installed/updated via winget (Gyan.FFmpeg)"
                    $needsRestart = $true
                    
                    $newSystemPath = Find-ToolInPath -ToolName "ffmpeg"
                    if ($newSystemPath) {
                        $FfmpegPath = $newSystemPath
                        if (-not $Quiet) { Write-Host "ffmpeg found at: $newSystemPath" -ForegroundColor Cyan }
                    }
                    
                    return @{ Success = $true; NeedsRestart = $needsRestart }
                }
            } catch {
                if (-not $Quiet) { Write-Host "Winget installation failed, falling back to manual download..." -ForegroundColor Yellow }
                Write-ErrorLog "Winget install failed for ffmpeg: $($_.Exception.Message)"
            }
        }
        
        if (Test-Path $FfmpegPath) {
            $backupPath = "$FfmpegPath.old"
            try {
                Move-Item -Path $FfmpegPath -Destination $backupPath -Force -ErrorAction Stop
                if (-not $Quiet) { Write-Host "Backed up old version to $backupPath" -ForegroundColor Gray }
            } catch {
                if (-not $Quiet) { Write-Warning "Failed to backup old ffmpeg: $($_.Exception.Message)" }
            }
        }
        
        $ffmpegZipUrl = "https://github.com/GyanD/codexffmpeg/releases/download/$latestVersion/ffmpeg-$latestVersion-essentials_build.zip"
        $tempZipPath = Join-Path $env:TEMP "ffmpeg_uvd_temp.zip"
        $tempExtractPath = Join-Path $env:TEMP "ffmpeg_uvd_extract"
        
        if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue }
        
        try {
            if (-not $Quiet) {
                Write-Host "Downloading ffmpeg essentials build manually..." -ForegroundColor Yellow
                Write-Host "This is a smaller package (~50MB) with essential codecs only." -ForegroundColor Yellow
            }
            Invoke-WebRequest -Uri $ffmpegZipUrl -OutFile $tempZipPath -ErrorAction Stop
            if (-not $Quiet) { Write-Host "ffmpeg downloaded. Extracting..." -ForegroundColor Yellow }
            Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractPath -Force -ErrorAction Stop
            
            $ffmpegExeFile = Get-ChildItem -Path $tempExtractPath -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
            if ($ffmpegExeFile) {
                Copy-Item -Path $ffmpegExeFile.FullName -Destination $FfmpegPath -Force -ErrorAction Stop
                if (-not $Quiet) { Write-Host "ffmpeg essentials build installed successfully!" -ForegroundColor Green }
                Write-ErrorLog "ffmpeg essentials build updated manually to version $latestVersion"
                
                if (Test-Path "$FfmpegPath.old") {
                    Remove-Item -Path "$FfmpegPath.old" -Force -ErrorAction SilentlyContinue
                }
            } else {
                throw "ffmpeg.exe not found within the downloaded files."
            }
            return @{ Success = $true; NeedsRestart = $false }
        } catch {
            if (Test-Path "$FfmpegPath.old") {
                Move-Item -Path "$FfmpegPath.old" -Destination $FfmpegPath -Force -ErrorAction SilentlyContinue
            }
            Resolve-ScriptError -UserMessage "Failed during ffmpeg download or setup." `
                               -InternalLogMessage "Error during ffmpeg setup. URL: $ffmpegZipUrl. Exception: $($_.Exception.Message)" `
                               -IsCritical $true
            return @{ Success = $false; NeedsRestart = $false }
        } finally {
            if (Test-Path $tempZipPath) { Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tempExtractPath) { Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    return @{ Success = $true; NeedsRestart = $false }
}

function Invoke-YouTubeLogin {
    param ([string]$Url)
    
    Write-Host "`n-------------------- BROWSER COOKIE LOGIN --------------------" -ForegroundColor Cyan
    Write-Host "This extracts cookies directly from your browser." -ForegroundColor White
    Write-Host "Make sure you are signed in to YouTube in one of these browsers:" -ForegroundColor White
    Write-Host "  - Google Chrome" -ForegroundColor Gray
    Write-Host "  - Microsoft Edge" -ForegroundColor Gray
    Write-Host "  - Mozilla Firefox" -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
    
    # Detect installed browsers
    $browsers = @()
    $chromePath = Get-Command "chrome" -ErrorAction SilentlyContinue
    $edgePath = Get-Command "msedge" -ErrorAction SilentlyContinue
    $firefoxPath = Get-Command "firefox" -ErrorAction SilentlyContinue
    
    if ($chromePath) { $browsers += @{ Name = "chrome"; Label = "Google Chrome"; Path = $chromePath.Source } }
    if ($edgePath) { $browsers += @{ Name = "edge"; Label = "Microsoft Edge"; Path = $edgePath.Source } }
    if ($firefoxPath) { $browsers += @{ Name = "firefox"; Label = "Mozilla Firefox"; Path = $firefoxPath.Source } }
    
    if ($browsers.Count -eq 0) {
        Write-Host "No supported browsers found (Chrome, Edge, Firefox)." -ForegroundColor Red
        Write-ErrorLog "No supported browsers found for cookie extraction"
        return $false
    }
    
    Write-Host "`nDetected browsers:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $browsers.Count; $i++) {
        Write-Host "  [$($i+1)] $($browsers[$i].Label)" -ForegroundColor White
    }
    Write-Host "  [0] Cancel" -ForegroundColor Gray
    
    $browserChoice = Get-ValidatedUserInput -Prompt "Select browser to extract cookies from:" -InputType "number" -MinValue 0 -MaxValue $browsers.Count -MaxAttempts 3
    
    if ($browserChoice -eq 0 -or $null -eq $browserChoice) {
        Write-Host "Browser login cancelled." -ForegroundColor Yellow
        return $false
    }
    
    $selectedBrowser = $browsers[$browserChoice - 1]
    Write-Host "`nExtracting cookies from $($selectedBrowser.Label)..." -ForegroundColor Yellow
    Write-ErrorLog "Attempting browser cookie extraction from: $($selectedBrowser.Name)"
    
    # Test --cookies-from-browser with this browser
    $testResult = & $ytDlpPath --cookies-from-browser $selectedBrowser.Name --dump-json --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1
    $testExit = $LASTEXITCODE
    
    if ($testExit -eq 0) {
        Write-Host "Successfully extracted cookies from $($selectedBrowser.Label)!" -ForegroundColor Green
        Write-ErrorLog "Browser cookie extraction successful from: $($selectedBrowser.Name)"
        
        # Update settings to use browser cookies
        $settings.cookies.use_cookies = $true
        $settings.cookies.cookie_source = $selectedBrowser.Name
        Save-Settings
        
        # Enable --cookies-from-browser in download arguments
        $script:useBrowserCookies = $true
        $script:browserCookieSource = $selectedBrowser.Name
        
        Write-Host "Cookie authentication enabled. Downloads will use browser cookies." -ForegroundColor Green
        return $true
    } else {
        $errorMsg = ($testResult | Where-Object { $_ -match "ERROR|error|failed|couldn" }) -join "`n"
        Write-Host "Failed to extract cookies from $($selectedBrowser.Label)." -ForegroundColor Red
        Write-Host "Error: $errorMsg" -ForegroundColor Yellow
        Write-ErrorLog "Browser cookie extraction failed from $($selectedBrowser.Name): $errorMsg"
        
        Write-Host "`nPossible solutions:" -ForegroundColor Yellow
        Write-Host "  1. Make sure you are signed in to YouTube in $($selectedBrowser.Label)" -ForegroundColor White
        Write-Host "  2. Close all $($selectedBrowser.Label) windows and try again" -ForegroundColor White
        Write-Host "  3. Try a different browser" -ForegroundColor White
        return $false
    }
}

function Add-EnhancedHeaders {
    param (
        [System.Collections.Generic.List[string]]$ArgumentsList
    )
    
    # Add enhanced headers to avoid 403 errors, aligned with Get-VideoInfoWithTimeout
    $ArgumentsList.Add("--no-check-certificate")
    $ArgumentsList.Add("--user-agent")
    $ArgumentsList.Add("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
    $ArgumentsList.Add("--add-header")
    $ArgumentsList.Add("Accept-Language:en-US,en;q=0.9")
    $ArgumentsList.Add("--add-header")
    $ArgumentsList.Add("Accept:text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    $ArgumentsList.Add("--add-header")
    $ArgumentsList.Add("Sec-Fetch-Mode:navigate")
}

function Get-QualityPrefix {
    param (
        [string]$Type,
        [object]$SelectedOption
    )
    
    switch ($Type) {
        "best" {
            if ($SelectedOption -and $SelectedOption.TotalBitrate) {
                return "[Best-$($SelectedOption.TotalBitrate)k]"
            } else {
                return "[Best]"
            }
        }
        "combined" {
            $format = $SelectedOption.Format
            $height = $format.height
            $ext = $format.ext
            if (-not $height -and $format.resolution -and $format.resolution -match 'x') {
                $height = ($format.resolution -split 'x')[1]
            }
            if ($height -and $ext) {
                return "[${height}p-${ext}]"
            }
            return "[${format.format_id}]"
        }
        "specific_video" {
            $format = $SelectedOption.Format
            $height = $format.height
            $ext = $format.ext
            if (-not $height -and $format.resolution -and $format.resolution -match 'x') {
                $height = ($format.resolution -split 'x')[1]
            }
            if ($height -and $ext) {
                return "[${height}p-${ext}]"
            }
            return "[${format.format_id}]"
        }
        "mp3_conversion" {
            $bitrate = $SelectedOption.Bitrate
            return "[MP3-${bitrate}k]"
        }
        "specific_audio" {
            $format = $SelectedOption.Format
            if ($format.abr) {
                return "[Audio-$($format.abr)k]"
            } else {
                return "[Audio-${format.format_id}]"
            }
        }
        "original_audio" {
            $format = $SelectedOption.Format
            $ext = $format.ext
            if ($format.abr) {
                return "[Original-$($ext)-$($format.abr)k]"
            } else {
                return "[Original-$($ext)-${format.format_id}]"
            }
        }

        default {
            return "[Download]"
        }
    }
}

function New-DownloadArguments {
    param (
        [string]$FfmpegPath,
        [string]$OutputTemplate,
        [string]$Format,
        [string]$Url,
        [string]$Type = "video",  # "video", "audio", "audio_specific", "original_audio", "original_video", "original_no_conversion", "force_mp4"
        [int]$Bitrate = 0,
        [bool]$UseCookies = $false,
        [string]$CookieFilePath = ""
    )
    
    $argsList = New-Object System.Collections.Generic.List[string]
    $argsList.Add("--no-warnings")
    Add-EnhancedHeaders -ArgumentsList $argsList
    
    # Add optimization and anti-bot settings if enabled
    if ([bool]$settings.optimization.enable_optimization) {
        Write-ErrorLog "Applying optimization settings for improved speed and reliability"
        
        # Anti-bot extractor args for YouTube
        if (-not [string]::IsNullOrWhiteSpace($settings.optimization.extractor_args)) {
            $argsList.Add("--extractor-args"); $argsList.Add($settings.optimization.extractor_args)
            Write-ErrorLog "Extractor args set to: $($settings.optimization.extractor_args)"
        }
        
        # Extractor retries
        if ($settings.optimization.extractor_retries -gt 0) {
            $argsList.Add("--extractor-retries"); $argsList.Add($settings.optimization.extractor_retries.ToString())
            Write-ErrorLog "Extractor retries set to: $($settings.optimization.extractor_retries)"
        }
        
        # Concurrent fragments for faster downloads
        if ($settings.optimization.concurrent_fragments -gt 0) {
            $argsList.Add("--concurrent-fragments"); $argsList.Add($settings.optimization.concurrent_fragments.ToString())
            Write-ErrorLog "Concurrent fragments set to: $($settings.optimization.concurrent_fragments)"
        }
        
        # Fragment retry settings
        if ($settings.optimization.fragment_retries -gt 0) {
            $argsList.Add("--fragment-retries"); $argsList.Add($settings.optimization.fragment_retries.ToString())
            Write-ErrorLog "Fragment retries set to: $($settings.optimization.fragment_retries)"
        }
        
        # Retry sleep settings
        if ($settings.optimization.retry_sleep -gt 0) {
            $argsList.Add("--retry-sleep"); $argsList.Add($settings.optimization.retry_sleep.ToString())
            Write-ErrorLog "Retry sleep set to: $($settings.optimization.retry_sleep) seconds"
        }
        
        # Socket timeout
        if ($settings.optimization.socket_timeout -gt 0) {
            $argsList.Add("--socket-timeout"); $argsList.Add($settings.optimization.socket_timeout.ToString())
            Write-ErrorLog "Socket timeout set to: $($settings.optimization.socket_timeout) seconds"
        }
        
        # Sleep between requests to avoid rate limiting
        if ($settings.optimization.sleep_requests -gt 0) {
            $argsList.Add("--sleep-requests"); $argsList.Add($settings.optimization.sleep_requests.ToString())
            Write-ErrorLog "Sleep between requests set to: $($settings.optimization.sleep_requests) seconds"
        }
        
        # Sleep interval settings for random delays
        if ($settings.optimization.sleep_interval -gt 0) {
            $argsList.Add("--sleep-interval"); $argsList.Add($settings.optimization.sleep_interval.ToString())
            Write-ErrorLog "Sleep interval set to: $($settings.optimization.sleep_interval) seconds"
        }
        
        if ($settings.optimization.max_sleep_interval -gt 0 -and $settings.optimization.max_sleep_interval -gt $settings.optimization.sleep_interval) {
            $argsList.Add("--max-sleep-interval"); $argsList.Add($settings.optimization.max_sleep_interval.ToString())
            Write-ErrorLog "Max sleep interval set to: $($settings.optimization.max_sleep_interval) seconds"
        }
        
        # Rate limiting to avoid throttling
        if (![string]::IsNullOrWhiteSpace($settings.optimization.rate_limit)) {
            $argsList.Add("--limit-rate"); $argsList.Add($settings.optimization.rate_limit)
            Write-ErrorLog "Rate limit set to: $($settings.optimization.rate_limit)"
        }
        
        # Use aria2c downloader for faster downloads
        if ([bool]$settings.optimization.use_aria2c_downloader) {
            $argsList.Add("--downloader"); $argsList.Add("aria2c")
            Write-ErrorLog "Using aria2c downloader for improved speed"
        }
    } else {
        Write-ErrorLog "Optimization settings are disabled"
    }
    
    # Add proxy if configured
    if ($env:HTTP_PROXY) {
        $argsList.Add("--proxy"); $argsList.Add($env:HTTP_PROXY)
        Write-ErrorLog "Download proxy added: $($env:HTTP_PROXY)"
    } else {
        Write-ErrorLog "No proxy configured for download"
    }
    
    # Add cookies if available - prefer browser cookies over file
    if ($script:useBrowserCookies -and $script:browserCookieSource) {
        $argsList.Add("--cookies-from-browser"); $argsList.Add($script:browserCookieSource)
        Write-ErrorLog "Browser cookie source added: $($script:browserCookieSource)"
    } elseif ($UseCookies -and $CookieFilePath -and (Test-Path $CookieFilePath)) {
        # Copy cookies.txt to temp file so yt-dlp doesn't modify the original
        $tempCookieFile = Join-Path ([System.IO.Path]::GetTempPath()) "uvd_dl_cookies_$([System.IO.Path]::GetRandomFileName()).txt"
        try {
            Copy-Item -Path $CookieFilePath -Destination $tempCookieFile -Force
            $argsList.Add("--cookies"); $argsList.Add($tempCookieFile)
            Write-ErrorLog "Download cookies added from temp copy: $tempCookieFile (original: $CookieFilePath)"
        } catch {
            $argsList.Add("--cookies"); $argsList.Add($CookieFilePath)
            Write-ErrorLog "Download cookies added (original, copy failed): $CookieFilePath"
        }
    } else {
        Write-ErrorLog "No cookies configured for download - UseCookies: $UseCookies, CookieFilePath: $CookieFilePath, FileExists: $(if ($CookieFilePath) { Test-Path $CookieFilePath } else { 'N/A' })"
    }
    
    $argsList.Add("--ffmpeg-location"); $argsList.Add($FfmpegPath)
    $argsList.Add("-o"); $argsList.Add($OutputTemplate)
    $argsList.Add("-f"); $argsList.Add($Format)
    
    # Enhanced metadata extraction and embedding
    # Note: We skip --write-info-json and --write-description to keep download folder clean
    # Metadata is embedded directly into the media files
    
    # Parse additional metadata fields for better tagging
    $argsList.Add("--parse-metadata"); $argsList.Add("%(title)s:%(meta_title)s")
    $argsList.Add("--parse-metadata"); $argsList.Add("%(uploader)s:%(meta_artist)s")
    $argsList.Add("--parse-metadata"); $argsList.Add("%(upload_date)s:%(meta_date)s")
    $argsList.Add("--parse-metadata"); $argsList.Add("%(description)s:%(meta_comment)s")
    $argsList.Add("--parse-metadata"); $argsList.Add("%(duration)s:%(meta_length)s")
    
    switch ($Type) {
        "video" {
            $argsList.Add("--merge-output-format"); $argsList.Add("mp4")
            $argsList.Add("--write-subs")
            $argsList.Add("--sub-lang"); $argsList.Add("fa,en")
            $argsList.Add("--embed-subs")
            $argsList.Add("--convert-subs"); $argsList.Add("srt")
            # Add metadata embedding for video files
            $argsList.Add("--embed-metadata")
            $argsList.Add("--add-metadata")
        }
        "original_video" {
            # Keep original format without conversion but merge with audio
            $argsList.Add("--write-subs")
            $argsList.Add("--sub-lang"); $argsList.Add("fa,en")
            $argsList.Add("--embed-subs")
            $argsList.Add("--convert-subs"); $argsList.Add("srt")
            # No merge-output-format to preserve original container
            # Add metadata embedding for video files
            $argsList.Add("--embed-metadata")
            $argsList.Add("--add-metadata")
        }
        "force_mp4" {
            # Force MP4 container for specific formats
            $argsList.Add("--merge-output-format"); $argsList.Add("mp4")
            $argsList.Add("--write-subs")
            $argsList.Add("--sub-lang"); $argsList.Add("fa,en")
            $argsList.Add("--embed-subs")
            $argsList.Add("--convert-subs"); $argsList.Add("srt")
            # Add metadata embedding for MP4 video files
            $argsList.Add("--embed-metadata")
            $argsList.Add("--add-metadata")
        }
        "audio" {
            $argsList.Add("--extract-audio")
            $argsList.Add("--audio-format"); $argsList.Add("mp3")
            if ($Bitrate -gt 0) {
                $argsList.Add("--audio-quality"); $argsList.Add("$($Bitrate)K")
            }
            # Add metadata and thumbnail embedding for MP3 files
            $argsList.Add("--embed-metadata")
            $argsList.Add("--embed-thumbnail")
            $argsList.Add("--add-metadata")
            
            # Enhanced metadata for audio files
            $argsList.Add("--parse-metadata"); $argsList.Add("%(uploader)s:%(artist)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(title)s:%(track)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(playlist)s:%(album)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(upload_date>%Y)s:%(date)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(description)s:%(comment)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("Music:%(genre)s")
        }
        "audio_specific" {
            $argsList.Add("--extract-audio")
            $argsList.Add("--audio-format"); $argsList.Add("mp3")
            # Add metadata and thumbnail embedding for MP3 files
            $argsList.Add("--embed-metadata")
            $argsList.Add("--embed-thumbnail")
            $argsList.Add("--add-metadata")
            
            # Enhanced metadata for audio files
            $argsList.Add("--parse-metadata"); $argsList.Add("%(uploader)s:%(artist)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(title)s:%(track)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(playlist)s:%(album)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(upload_date>%Y)s:%(date)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(description)s:%(comment)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("Music:%(genre)s")
        }

        "original_no_conversion" {
            # Keep original format without any conversion
            # Add metadata embedding for original formats
            $argsList.Add("--embed-metadata")
            $argsList.Add("--add-metadata")
        }
        "original_audio" {
            # Extract audio in original format without conversion
            $argsList.Add("--extract-audio")
            # No --audio-format specified to keep original format
            # Add metadata and thumbnail embedding (if supported by format)
            $argsList.Add("--embed-metadata")
            $argsList.Add("--embed-thumbnail")
            $argsList.Add("--add-metadata")
            
            # Enhanced metadata for audio files
            $argsList.Add("--parse-metadata"); $argsList.Add("%(uploader)s:%(artist)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(title)s:%(track)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(playlist)s:%(album)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(upload_date>%Y)s:%(date)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("%(description)s:%(comment)s")
            $argsList.Add("--parse-metadata"); $argsList.Add("Music:%(genre)s")
        }
    }
    
    $argsList.Add($Url)
    return $argsList
}

function Get-VideoInfoWithTimeout {
    param (
        [string]$Url,
        [string]$YtDlpPath,
        [int]$TimeoutSeconds = 20,
        [switch]$UseCookies = $false,
        [string]$CookieFilePath = ""
    )
    
    Write-ErrorLog "Attempting to get video info with timeout: $TimeoutSeconds seconds"
    Write-ErrorLog "Target URL: $Url"
    Write-ErrorLog "Using cookies: $UseCookies"
    if ($UseCookies -and $CookieFilePath) {
        Write-ErrorLog "Cookie file path: $CookieFilePath"
        Write-ErrorLog "Cookie file exists: $(Test-Path $CookieFilePath)"
    }
    
    # Pass proxy info explicitly to job since environment variables don't transfer
    $proxyUrl = $env:HTTP_PROXY
    
    $job = Start-Job -ScriptBlock {
        param($url, $ytDlpPath, $useCookies, $cookieFilePath, $proxyUrl)
        
        $argumentList = @(
            "--dump-json", 
            "--no-warnings", 
            "--no-check-certificate",
            "--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "--add-header", "Accept-Language:en-US,en;q=0.9",
            "--add-header", "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "--add-header", "Sec-Fetch-Mode:navigate"
        )
        
        # Add anti-bot settings from config
        if ([bool]$settings.optimization.enable_optimization) {
            if (-not [string]::IsNullOrWhiteSpace($settings.optimization.extractor_args)) {
                $argumentList += "--extractor-args"
                $argumentList += $settings.optimization.extractor_args
            }
            if ($settings.optimization.extractor_retries -gt 0) {
                $argumentList += "--extractor-retries"
                $argumentList += $settings.optimization.extractor_retries.ToString()
            }
            if ($settings.optimization.sleep_requests -gt 0) {
                $argumentList += "--sleep-requests"
                $argumentList += $settings.optimization.sleep_requests.ToString()
            }
            if ($settings.optimization.sleep_interval -gt 0) {
                $argumentList += "--sleep-interval"
                $argumentList += $settings.optimization.sleep_interval.ToString()
            }
            if ($settings.optimization.max_sleep_interval -gt 0) {
                $argumentList += "--max-sleep-interval"
                $argumentList += $settings.optimization.max_sleep_interval.ToString()
            }
        }
        
        # Add proxy if configured (now passed explicitly)
        if ($proxyUrl) {
            $argumentList += "--proxy"
            $argumentList += $proxyUrl
        }
        
        # Add cookies - prefer browser cookies over file to prevent yt-dlp from modifying user's cookies.txt
        if ($script:useBrowserCookies -and $script:browserCookieSource) {
            $argumentList += "--cookies-from-browser"
            $argumentList += $script:browserCookieSource
        } elseif ($useCookies -and $cookieFilePath -and (Test-Path $cookieFilePath)) {
            # Copy cookies.txt to temp file so yt-dlp doesn't modify the original
            $tempCookieFile = Join-Path ([System.IO.Path]::GetTempPath()) "uvd_cookies_$([System.IO.Path]::GetRandomFileName()).txt"
            try {
                Copy-Item -Path $cookieFilePath -Destination $tempCookieFile -Force
                $argumentList += "--cookies"
                $argumentList += $tempCookieFile
            } catch {
                # If copy fails, use original as fallback
                $argumentList += "--cookies"
                $argumentList += $cookieFilePath
            }
        }
        $argumentList += $url
        
        # Debug logging for troubleshooting
        # Note: This runs in a job, so we can't use Write-ErrorLog here
        # But we can return debug info that will be logged in the main script
        
        try {
            $output = & $ytDlpPath @argumentList 2>&1
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -eq 0) {
                return @{
                    Success = $true
                    Output = $output
                    ExitCode = $exitCode
                }
            } else {
                return @{
                    Success = $false
                    Error = ($output -join "`n")
                    ExitCode = $exitCode
                }
            }
        } catch {
            return @{
                Success = $false
                Error = "Exception: $($_.Exception.Message)"
                ExitCode = -1
            }
        }
    } -ArgumentList $Url, $YtDlpPath, $UseCookies, $CookieFilePath, $proxyUrl
    
    try {
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        
        if ($completed) {
            $result = Receive-Job -Job $job
            
            # Handle case where result is not a proper hashtable
            if ($result -is [array]) {
                # Find the hashtable in the array
                $hashtable = $null
                foreach ($item in $result) {
                    if ($item -is [hashtable] -and $item.ContainsKey("Success")) {
                        $hashtable = $item
                        break
                    }
                }
                if ($hashtable) {
                    $result = $hashtable
                } else {
                    $result = @{
                        Success = $false
                        Error = "Job returned array without valid result"
                        ExitCode = -1
                    }
                }
            } elseif ($null -eq $result -or -not ($result -is [hashtable])) {
                $msg = if ($result) { $result.ToString() } else { "Job returned null" }
                $result = @{
                    Success = $false
                    Error = $msg
                    ExitCode = -1
                }
            }
            
            Remove-Job -Job $job
            Write-ErrorLog "Video info job completed. Success: $($result.Success), ExitCode: $($result.ExitCode)"
            return $result
        } else {
            Write-ErrorLog "Video info retrieval timed out after $TimeoutSeconds seconds"
            Remove-Job -Job $job -Force
            return @{
                Success = $false
                Error = "Request timed out after $TimeoutSeconds seconds"
                ExitCode = -2
            }
        }
    } catch {
        Write-ErrorLog "Error in Get-VideoInfoWithTimeout: $($_.Exception.Message)"
        try { Remove-Job -Job $job -Force } catch { }
        return @{
            Success = $false
            Error = "Timeout handling error: $($_.Exception.Message)"
            ExitCode = -3
        }
    }
}

function Show-ErrorHandlingOptions {
    param (
        [string]$Url,
        [string]$ErrorMessage
    )
    
    Write-Host "`n-------------------- ERROR HANDLING OPTIONS --------------------" -ForegroundColor Red
    $briefError = if ($ErrorMessage.Length -gt 200) {
        $ErrorMessage.Substring(0, 200) + "... [See debug log for full details]"
    } else {
        $ErrorMessage
    }
    Write-Host "Failed to retrieve video information: $briefError" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available options:" -ForegroundColor Yellow
    Write-Host "1. Try with cookies (auto-enable and retry)" -ForegroundColor White
    Write-Host "2. Sign in via browser (extract cookies)" -ForegroundColor White
    Write-Host "3. Retry with current settings" -ForegroundColor White
    Write-Host "4. Enter a different URL" -ForegroundColor White
    Write-Host "5. Exit" -ForegroundColor White
    Write-Host "--------------------------------------------------------------" -ForegroundColor Red
    
    $choice = Get-ValidatedUserInput -Prompt "Please select an option:" -InputType "number" -MinValue 1 -MaxValue 5 -MaxAttempts 3
    
    switch ($choice) {
        "1" {
            # Auto-enable cookies if not already enabled
            if (-not [bool]$settings.cookies.use_cookies) {
                Write-Host "Auto-enabling cookie support in settings.json..." -ForegroundColor Yellow
                $settings.cookies.use_cookies = $true
                Save-Settings
                Write-ErrorLog "Auto-enabled cookies in settings.json from error menu"
            }
            
            # Check if browser cookies are configured
            if (-not [string]::IsNullOrWhiteSpace($settings.cookies.cookie_source)) {
                Write-Host "Using browser cookie source: $($settings.cookies.cookie_source)" -ForegroundColor Yellow
                $script:useBrowserCookies = $true
                $script:browserCookieSource = $settings.cookies.cookie_source
            }
            
            Write-Host "Attempting to use cookies..." -ForegroundColor Yellow
            return "cookies"
        }
        "2" {
            Write-Host "Attempting browser cookie login..." -ForegroundColor Yellow
            return "login"
        }
        "3" {
            Write-Host "Retrying with current settings..." -ForegroundColor Yellow
            return "retry"
        }
        "4" {
            Write-Host "Please enter a different URL..." -ForegroundColor Yellow
            return "new_url"
        }
        "5" {
            Write-Host "Exiting..." -ForegroundColor Yellow
            return "exit"
        }
        default {
            if ($null -eq $choice) {
                Write-Host "No valid option selected. Using retry as default." -ForegroundColor Yellow
                return "retry"
            }
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            return Show-ErrorHandlingOptions -Url $Url -ErrorMessage $ErrorMessage
        }
    }
}

function Resolve-ScriptError {
    param (
        [string]$UserMessage,
        [string]$InternalLogMessage,
        [switch]$IsCritical = $false
    )
    
    # Use enhanced error display
    Show-EnhancedError -TechnicalError $InternalLogMessage -Context $UserMessage

    if ($IsCritical) {
        Write-Host "The script will now exit due to a critical error." -ForegroundColor Red
        $Host.UI.RawUI.BackgroundColor = $originalBackground
        $Host.UI.RawUI.ForegroundColor = $originalForeground
        Clear-Host
        exit 1
    }
}

function Open-ProgramFolder {
    try {
        Write-Host ""
        Write-Host "🔍 Opening program folder..." -ForegroundColor Green
        Start-Process -FilePath "explorer.exe" -ArgumentList $scriptDir -ErrorAction Stop
        Write-ErrorLog "Successfully opened program folder: $scriptDir"
        Write-Host "✅ Program folder opened successfully!" -ForegroundColor Green
        Write-Host "📁 Location: $scriptDir" -ForegroundColor Cyan
    } catch {
        Write-ErrorLog "Failed to open program folder: $($_.Exception.Message)"
        Write-Host "❌ Could not open program folder automatically" -ForegroundColor Red
        Write-Host "📁 Program folder location: $scriptDir" -ForegroundColor Yellow
    }
}

function Open-SettingsFile {
    try {
        Write-Host ""
        Write-Host "⚙️ Opening settings file..." -ForegroundColor Green
        if (Test-Path $settingsPath) {
            Start-Process -FilePath "notepad.exe" -ArgumentList $settingsPath -ErrorAction Stop
            Write-ErrorLog "Successfully opened settings file: $settingsPath"
            Write-Host "✅ Settings file opened successfully!" -ForegroundColor Green
            Write-Host "📄 Location: $settingsPath" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️ Settings file not found. Creating new settings file..." -ForegroundColor Yellow
            if (Create-SettingsFile -Path $settingsPath) {
                Start-Process -FilePath "notepad.exe" -ArgumentList $settingsPath -ErrorAction Stop
                Write-Host "✅ New settings file created and opened!" -ForegroundColor Green
                Write-Host "📄 Location: $settingsPath" -ForegroundColor Cyan
            } else {
                Write-Host "❌ Failed to create settings file" -ForegroundColor Red
            }
        }
    } catch {
        Write-ErrorLog "Failed to open settings file: $($_.Exception.Message)"
        Write-Host "❌ Could not open settings file automatically" -ForegroundColor Red
        Write-Host "📄 Settings file location: $settingsPath" -ForegroundColor Yellow
    }
}

function Open-DownloadsFolder {
    try {
        Write-Host ""
        Write-Host "📁 Opening downloads folder..." -ForegroundColor Green
        $downloadsDir = Join-Path $scriptDir $settings.download.output_directory
        
        # Create the folder if it doesn't exist
        if (-not (Test-Path $downloadsDir)) {
            Initialize-Directory $downloadsDir
        }
        
        Start-Process -FilePath "explorer.exe" -ArgumentList $downloadsDir -ErrorAction Stop
        Write-ErrorLog "Successfully opened downloads folder: $downloadsDir"
        Write-Host "✅ Downloads folder opened successfully!" -ForegroundColor Green
        Write-Host "📁 Location: $downloadsDir" -ForegroundColor Cyan
    } catch {
        Write-ErrorLog "Failed to open downloads folder: $($_.Exception.Message)"
        Write-Host "❌ Could not open downloads folder automatically" -ForegroundColor Red
        Write-Host "📁 Downloads folder location: $downloadsDir" -ForegroundColor Yellow
    }
}

function Show-ScriptHelp {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      Universal Video Downloader - Complete Guide              ║" -ForegroundColor Cyan
    Write-Host "║                                 Created by MBNPRO                             ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "📖 TABLE OF CONTENTS" -ForegroundColor Yellow
    Write-Host "───────────────────" -ForegroundColor Gray
    Write-Host "  1. Quick Start" -ForegroundColor White
    Write-Host "  2. Available Commands" -ForegroundColor White
    Write-Host "  3. Features Overview" -ForegroundColor White
    Write-Host "  4. Download Options" -ForegroundColor White
    Write-Host "  5. Configuration Guide" -ForegroundColor White
    Write-Host "  6. Troubleshooting" -ForegroundColor White
    Write-Host "  7. Settings.json Reference" -ForegroundColor White
    Write-Host ""
    
    Write-Host "⚡ 1. QUICK START" -ForegroundColor Green
    Write-Host "─────────────────" -ForegroundColor Gray
    Write-Host "  Simply run: " -NoNewline; Write-Host ".\uvd_latest.ps1" -ForegroundColor Yellow
    Write-Host "  Then paste any video URL when prompted!" -ForegroundColor White
    Write-Host ""
    
    Write-Host "🎯 2. AVAILABLE COMMANDS" -ForegroundColor Green
    Write-Host "────────────────────────" -ForegroundColor Gray
    Write-Host "  During URL prompt, you can use these commands:" -ForegroundColor White
    Write-Host ""
    Write-Host "  URL            : " -NoNewline; Write-Host "Paste any video link (YouTube, TikTok, Instagram, etc.)" -ForegroundColor Gray
    Write-Host "  help, -h       : " -NoNewline; Write-Host "Show this comprehensive help guide" -ForegroundColor Gray
    Write-Host "  restart        : " -NoNewline; Write-Host "Restart the script" -ForegroundColor Gray
    Write-Host "  clear-cache    : " -NoNewline; Write-Host "Clear cached video information" -ForegroundColor Gray
    Write-Host "  folder         : " -NoNewline; Write-Host "Open program folder in explorer" -ForegroundColor Gray
    Write-Host "  downloads      : " -NoNewline; Write-Host "Open downloads folder" -ForegroundColor Gray
    Write-Host "  settings       : " -NoNewline; Write-Host "Open settings.json file for editing" -ForegroundColor Gray
    Write-Host "  exit           : " -NoNewline; Write-Host "Exit the program gracefully" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Command line options:" -ForegroundColor White
    Write-Host "  .\uvd_latest.ps1 -Help    : " -NoNewline; Write-Host "Show help and exit" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "✨ 3. FEATURES OVERVIEW" -ForegroundColor Green
    Write-Host "───────────────────────" -ForegroundColor Gray
    Write-Host "  🎥 VIDEO DOWNLOADS" -ForegroundColor Cyan
    Write-Host "     • Download videos in ANY available quality (144p to 8K)" -ForegroundColor White
    Write-Host "     • Automatic merging of best video + audio streams" -ForegroundColor White
    Write-Host "     • Subtitle support (English, Farsi, and more)" -ForegroundColor White
    Write-Host "     • Smart format conversion to MP4" -ForegroundColor White
    Write-Host ""
    Write-Host "  🎵 AUDIO EXTRACTION" -ForegroundColor Cyan
    Write-Host "     • Extract audio from any video" -ForegroundColor White
    Write-Host "     • Convert to MP3 with custom bitrates (128/256/320 kbps)" -ForegroundColor White
    Write-Host "     • Preserve original audio quality (e.g., opus, m4a)" -ForegroundColor White
    Write-Host ""
    Write-Host "  🖼️  THUMBNAIL DOWNLOADS" -ForegroundColor Cyan
    Write-Host "     • Download video thumbnails in highest quality" -ForegroundColor White
    Write-Host "     • Multiple download methods for reliability" -ForegroundColor White
    Write-Host ""
    Write-Host "  🚀 PERFORMANCE & RELIABILITY" -ForegroundColor Cyan
    Write-Host "     • Smart caching system for instant video info retrieval" -ForegroundColor White
    Write-Host "     • Automatic retry on failures and intelligent error handling" -ForegroundColor White
    Write-Host "     • Beautiful progress display with speed and ETA" -ForegroundColor White
    Write-Host "     • Proxy support (system and custom)" -ForegroundColor White
    Write-Host "     • Cookie and YouTube Login for private/age-restricted videos" -ForegroundColor White
    Write-Host ""
    
    Write-Host "📥 4. DOWNLOAD OPTIONS" -ForegroundColor Green
    Write-Host "──────────────────────" -ForegroundColor Gray
    Write-Host "  When you enter a video URL, you'll see a detailed menu of options:" -ForegroundColor White
    Write-Host ""
    Write-Host "  1️⃣  BEST QUALITY (Recommended)" -ForegroundColor Yellow
    Write-Host "     • Automatically selects the best available video and audio streams." -ForegroundColor Gray
    Write-Host "     • Merges them into a single high-quality MP4 file." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2️⃣  SPECIFIC VIDEO FORMATS" -ForegroundColor Yellow
    Write-Host "     • Choose from a list of video-only formats (like VP9, AV1)." -ForegroundColor Gray
    Write-Host "     • These are automatically merged with the best available audio." -ForegroundColor Gray
    Write-Host "     • Great for specific quality or file size needs." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3️⃣  AUDIO ONLY OPTIONS" -ForegroundColor Yellow
    Write-Host "     • MP3 Conversion: Convert audio to high-quality MP3 (320, 256, or 128 kbps)." -ForegroundColor Gray
    Write-Host "     • Original Audio: Download audio in its original format (e.g., opus, m4a) without re-encoding, preserving source quality." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4️⃣  THUMBNAIL DOWNLOAD" -ForegroundColor Yellow
    Write-Host "     • Save the video's full-resolution cover image as a JPG or WEBP file." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  5️⃣  PRE-COMBINED FORMATS (If available)" -ForegroundColor Yellow
    Write-Host "     • Some older videos offer pre-combined video and audio files." -ForegroundColor Gray
    Write-Host "     • These are usually lower quality but download faster as they don't require merging." -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "⚙️  5. CONFIGURATION GUIDE" -ForegroundColor Green
    Write-Host "──────────────────────────" -ForegroundColor Gray
    Write-Host "  All settings are stored in: " -NoNewline; Write-Host "settings.json" -ForegroundColor Yellow
    Write-Host "  💡 Quick access: Use " -NoNewline; Write-Host "'settings'" -NoNewline -ForegroundColor Cyan; Write-Host " command to open the file" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  📁 File Locations:" -ForegroundColor Cyan
    Write-Host "     • Downloads  : Downloaded\Video, Downloaded\Audio, Downloaded\Covers" -ForegroundColor White
    Write-Host "     • Temp files : Temp\" -ForegroundColor White
    Write-Host "     • Cache      : video_cache.json" -ForegroundColor White
    Write-Host "     • Cookies    : cookies.txt" -ForegroundColor White
    Write-Host "     • Debug log  : debug.txt" -ForegroundColor White
    Write-Host "     💡 Quick access: Use " -NoNewline; Write-Host "'folder'" -NoNewline -ForegroundColor Cyan; Write-Host " command to open program folder" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "🔧 6. TROUBLESHOOTING" -ForegroundColor Green
    Write-Host "─────────────────────" -ForegroundColor Gray
    Write-Host "  ❌ Download fails or '403 Forbidden' error?" -ForegroundColor Red
    Write-Host "     • Check your internet connection." -ForegroundColor White
    Write-Host "     • The video might be private or region-locked. Try a VPN." -ForegroundColor White
    Write-Host "     • For age-restricted videos, you need to use cookies." -ForegroundColor White
    Write-Host "     • Open settings file with 'settings' command and set 'use_cookies' to true." -ForegroundColor White
    Write-Host "     • Use 'clear-cache' to refetch video info." -ForegroundColor White
    Write-Host ""
    Write-Host "  🔒 How to download age-restricted or private videos?" -ForegroundColor Red
    Write-Host "     • The best method is using a cookies.txt file from your logged-in browser." -ForegroundColor White
    Write-Host "     • The script may also prompt you to log in to YouTube. This will open a Chrome window for you to sign in." -ForegroundColor White
    Write-Host "     • This method can help with some restricted content." -ForegroundColor White
    Write-Host ""
    Write-Host "  🐛 Other issues?" -ForegroundColor Red
    Write-Host "     • Check 'debug.txt' for detailed error logs. Use the 'folder' command to find it." -ForegroundColor White
    Write-Host "     • The script automatically updates yt-dlp and ffmpeg on startup to prevent many common issues." -ForegroundColor White
    Write-Host "     • If the program window closes immediately, run it from a PowerShell terminal to see the error message." -ForegroundColor White
    Write-Host ""
    
    Write-Host "📋 7. SETTINGS.JSON REFERENCE" -ForegroundColor Green
    Write-Host "─────────────────────────────" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  🔹 general:" -ForegroundColor Cyan
    Write-Host "     • request_timeout_seconds : Network timeout for fetching video info (default: 20)" -ForegroundColor White
    Write-Host "     • max_retries             : Retry attempts for failed network requests (default: 3)" -ForegroundColor White
    Write-Host "     • show_processing_messages: Show messages like 'Processing...' (default: true)" -ForegroundColor White
    Write-Host "     • use_database_cache      : Enable local caching of video info for speed (default: true)" -ForegroundColor White
    Write-Host "     • database_file           : Name of the video cache file (default: 'video_cache.json')" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔹 proxy:" -ForegroundColor Cyan
    Write-Host "     • use_system_proxy        : Automatically use Windows proxy settings (default: true)" -ForegroundColor White
    Write-Host "     • custom_proxy_enabled    : Enable custom proxy settings below (default: false)" -ForegroundColor White
    Write-Host "     • custom_proxy_host       : Custom proxy IP or address" -ForegroundColor White
    Write-Host "     • custom_proxy_port       : Custom proxy port" -ForegroundColor White
    Write-Host "     • custom_proxy_username   : Username for proxy (if needed)" -ForegroundColor White
    Write-Host "     • custom_proxy_password   : Password for proxy (if needed)" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔹 cookies:" -ForegroundColor Cyan
    Write-Host "     • use_cookies             : Enable cookie authentication for private/restricted videos (default: false)" -ForegroundColor White
    Write-Host "     • cookie_file_path        : Name of the cookie file (e.g., cookies.txt) (default: 'cookies.txt')" -ForegroundColor White
    Write-Host "     • cookie_file_directory   : Directory where cookie file is located (leave blank for script directory)" -ForegroundColor White
    Write-Host "     • cookie_source           : Browser name for --cookies-from-browser (e.g., 'chrome', 'edge', 'firefox')" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔹 youtube_login:" -ForegroundColor Cyan
    Write-Host "     • enable_auto_login       : Enable browser cookie login feature (default: true)" -ForegroundColor White
    Write-Host "     • chrome_profile_path     : Path to a custom Chrome profile for persistent logins" -ForegroundColor White
    Write-Host "     • login_timeout_seconds   : Time to wait for user to log in (default: 60)" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔹 download:" -ForegroundColor Cyan
    Write-Host "     • temp_directory          : Folder for temporary download files (default: 'Temp')" -ForegroundColor White
    Write-Host "     • output_directory        : Main folder for all finished downloads (default: 'Downloaded')" -ForegroundColor White
    Write-Host "     • video_subdirectory      : Subfolder for downloaded videos (default: 'Video')" -ForegroundColor White
    Write-Host "     • audio_subdirectory      : Subfolder for downloaded audio (default: 'Audio')" -ForegroundColor White
    Write-Host "     • covers_subdirectory     : Subfolder for downloaded thumbnails (default: 'Covers')" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔹 optimization:" -ForegroundColor Cyan
    Write-Host "     • enable_optimization     : Enable/disable all optimization features (default: true)" -ForegroundColor White
    Write-Host "     • concurrent_fragments    : Number of fragments to download simultaneously (default: 4)" -ForegroundColor White
    Write-Host "     • fragment_retries        : Retry attempts for failed fragments (default: 10)" -ForegroundColor White
    Write-Host "     • retry_sleep             : Sleep time between retries in seconds (default: 5)" -ForegroundColor White
    Write-Host "     • socket_timeout          : Network socket timeout in seconds (default: 30)" -ForegroundColor White
    Write-Host "     • sleep_requests          : Sleep between requests to avoid rate limiting (default: 1)" -ForegroundColor White
    Write-Host "     • sleep_interval          : Random sleep interval minimum in seconds (default: 3)" -ForegroundColor White
    Write-Host "     • max_sleep_interval      : Random sleep interval maximum in seconds (default: 7)" -ForegroundColor White
    Write-Host "     • extractor_args          : yt-dlp extractor args for anti-bot (default: 'youtube:player_client=web,android_vr,tv_downgraded')" -ForegroundColor White
    Write-Host "     • extractor_retries       : Retries for extractor errors (default: 3)" -ForegroundColor White
    Write-Host "     • use_aria2c_downloader   : Use aria2c for faster downloads (default: false)" -ForegroundColor White
    Write-Host "     • rate_limit              : Download speed limit (e.g., '1M', '500K') (default: '')" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔹 advanced:" -ForegroundColor Cyan
    Write-Host "     • enable_debug_logging    : Save detailed logs to debug.txt (default: false)" -ForegroundColor White
    Write-Host "     • log_file_path           : Name of the debug log file (default: 'debug.txt')" -ForegroundColor White
    Write-Host "     • cleanup_temp_files      : Automatically delete temporary files after download (default: true)" -ForegroundColor White
    Write-Host "     • max_description_lines   : Number of video description lines to show (default: 5)" -ForegroundColor White
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         Press any key to continue...                          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function Initialize-Directory {
    param ([string]$Path)
    if (-not (Test-Path $Path)) {
        try {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-ErrorLog "Successfully created directory: $Path"
        } catch {
            Resolve-ScriptError -UserMessage "Failed to create a necessary directory: $Path. Please check permissions." `
                               -InternalLogMessage "New-Item failed for directory '$Path'. Exception: $($_.Exception.Message)" `
                               -IsCritical $true
        }
    }
}

function Convert-FileNameToComparable {
    param (
        [string]$FileName
    )
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return ""
    }
    
    # Keep square brackets for quality prefixes
    $invalidChars = '[{0}]' -f ([System.IO.Path]::GetInvalidFileNameChars() -replace '\[|\]', '' | ForEach-Object { [regex]::Escape($_) })
    $cleanName = $FileName -replace $invalidChars, ''
    
    # Replace common separators with a space for better readability and consistency
    $cleanName = $cleanName -replace '[\s\p{P}-[\]]]+', ' ' # Replace punctuation (except brackets) and whitespace with a single space
    
    return $cleanName.Trim()
}

function Clean-FileName {
    param (
        [string]$FileName
    )
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return "untitled"
    }
    
    # Replace problematic Unicode characters with safe alternatives
    $cleanName = $FileName
    $cleanName = $cleanName.Replace('｜', '|')          # Fullwidth vertical bar to normal pipe
    $cleanName = $cleanName.Replace('：', '-')          # Fullwidth colon
    $cleanName = $cleanName.Replace('？', '')           # Fullwidth question mark
    $cleanName = $cleanName.Replace('＜', '(')          # Fullwidth less than
    $cleanName = $cleanName.Replace('＞', ')')          # Fullwidth greater than
    $cleanName = $cleanName.Replace('＂', "'")          # Fullwidth quotation mark
    $cleanName = $cleanName.Replace('＊', '-')          # Fullwidth asterisk
    $cleanName = $cleanName.Replace('＼', '-')          # Fullwidth backslash
    $cleanName = $cleanName.Replace('／', '-')          # Fullwidth forward slash
    
    # Replace other problematic characters
    $cleanName = $cleanName.Replace('|', '-')           # Pipe to dash
    $cleanName = $cleanName.Replace(':', '-')           # Colon to dash
    $cleanName = $cleanName.Replace('?', '')            # Remove question marks
    $cleanName = $cleanName.Replace('<', '(')           # Less than to parenthesis
    $cleanName = $cleanName.Replace('>', ')')           # Greater than to parenthesis
    $cleanName = $cleanName.Replace('"', "'")           # Double quote to single
    $cleanName = $cleanName.Replace('*', '-')           # Asterisk to dash
    $cleanName = $cleanName.Replace('\', '-')           # Backslash to dash
    $cleanName = $cleanName.Replace('/', '-')           # Forward slash to dash
    
    # Remove invalid filename characters
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        $cleanName = $cleanName.Replace($char, '_')
    }
    
    # Clean up multiple dashes and spaces
    $cleanName = $cleanName -replace '\s+', ' '         # Multiple spaces to single
    $cleanName = $cleanName -replace '-{2,}', '-'       # Multiple dashes to single
    $cleanName = $cleanName -replace '_+', '_'          # Multiple underscores to single
    
    # Trim and ensure it's not empty
    $cleanName = $cleanName.Trim(' ', '-', '_')
    if ([string]::IsNullOrWhiteSpace($cleanName)) {
        $cleanName = "video_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    }
    
    # Limit length (Windows has 260 char path limit)
    if ($cleanName.Length -gt 200) {
        $cleanName = $cleanName.Substring(0, 200).Trim(' ', '-', '_')
    }
    
    return $cleanName
}

function Format-Bytes {
    param ($bytes)
    if ($null -eq $bytes -or $bytes -lt 0) { return "N/A" }
    if ($bytes -eq 0) { return "0 B" }
    $suffixes = "B", "KB", "MB", "GB", "TB", "PB"
    $order = 0
    [double]$bytesDouble = $bytes
    while ($bytesDouble -ge 1024 -and $order -lt ($suffixes.Length - 1)) {
        $bytesDouble /= 1024
        $order++
    }
    return "{0:N2} {1}" -f $bytesDouble, $suffixes[$order]
}

function Get-HighestBitrateFormat {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Formats
    )
    
    Write-ErrorLog "Finding highest bitrate format from $($Formats.Count) available formats"
    
    # Separate formats by type
    $videoFormats = @()
    $audioFormats = @()
    $combinedFormats = @()
    
    foreach ($format in $Formats) {
        if ($format.vcodec -ne 'none' -and $format.acodec -ne 'none') {
            $combinedFormats += $format
        } elseif ($format.vcodec -ne 'none') {
            $videoFormats += $format
        } elseif ($format.acodec -ne 'none') {
            $audioFormats += $format
        }
    }
    
    # Find highest bitrate video format
    $bestVideoFormat = $null
    $highestVideoBitrate = 0
    
    foreach ($format in $videoFormats) {
        $bitrate = 0
        if ($format.tbr) {
            $bitrate = [double]$format.tbr
        } elseif ($format.vbr) {
            $bitrate = [double]$format.vbr
        }
        
        if ($bitrate -gt $highestVideoBitrate) {
            $highestVideoBitrate = $bitrate
            $bestVideoFormat = $format
        }
    }
    
    # Find highest bitrate audio format
    $bestAudioFormat = $null
    $highestAudioBitrate = 0
    
    foreach ($format in $audioFormats) {
        $bitrate = 0
        if ($format.abr) {
            $bitrate = [double]$format.abr
        } elseif ($format.tbr) {
            $bitrate = [double]$format.tbr
        }
        
        if ($bitrate -gt $highestAudioBitrate) {
            $highestAudioBitrate = $bitrate
            $bestAudioFormat = $format
        }
    }
    
    # Check if we have a combined format with higher total bitrate
    $bestCombinedFormat = $null
    $highestCombinedBitrate = 0
    
    foreach ($format in $combinedFormats) {
        $bitrate = 0
        if ($format.tbr) {
            $bitrate = [double]$format.tbr
        }
        
        if ($bitrate -gt $highestCombinedBitrate) {
            $highestCombinedBitrate = $bitrate
            $bestCombinedFormat = $format
        }
    }
    
    # Compare and choose the best option
    $totalSeparateBitrate = $highestVideoBitrate + $highestAudioBitrate
    
    $result = @{
        FormatString = ""
        Description = ""
        VideoBitrate = 0
        AudioBitrate = 0
        TotalBitrate = 0
        VideoFormat = $null
        AudioFormat = $null
        IsCombined = $false
    }
    
    if ($bestCombinedFormat -and $highestCombinedBitrate -gt $totalSeparateBitrate) {
        # Use combined format if it has higher bitrate
        $result.FormatString = $bestCombinedFormat.format_id
        $result.Description = "Combined format with highest bitrate ($($highestCombinedBitrate)k)"
        $result.TotalBitrate = $highestCombinedBitrate
        $result.VideoFormat = $bestCombinedFormat
        $result.IsCombined = $true
        Write-ErrorLog "Selected combined format: $($bestCombinedFormat.format_id) with bitrate $($highestCombinedBitrate)k"
    } elseif ($bestVideoFormat -and $bestAudioFormat) {
        # Use separate video+audio with highest bitrates
        $result.FormatString = "$($bestVideoFormat.format_id)+$($bestAudioFormat.format_id)"
        $result.Description = "Highest bitrate video ($($highestVideoBitrate)k) + audio ($($highestAudioBitrate)k)"
        $result.VideoBitrate = $highestVideoBitrate
        $result.AudioBitrate = $highestAudioBitrate
        $result.TotalBitrate = $totalSeparateBitrate
        $result.VideoFormat = $bestVideoFormat
        $result.AudioFormat = $bestAudioFormat
        $result.IsCombined = $false
        Write-ErrorLog "Selected separate formats: video $($bestVideoFormat.format_id) ($($highestVideoBitrate)k) + audio $($bestAudioFormat.format_id) ($($highestAudioBitrate)k)"
    } else {
        # Fallback to standard best
        $result.FormatString = "bestvideo+bestaudio/best"
        $result.Description = "Fallback to standard best quality"
        Write-ErrorLog "No suitable high bitrate formats found, using fallback"
    }
    
    return $result
}

function Get-FormatDetails {
    param ([psobject]$Format)
    
    $details = @{
        FormatId = $Format.format_id
        Extension = $Format.ext
        Resolution = ""
        VideoCodec = ""
        AudioCodec = ""
        FileSize = ""
        Bitrate = ""
        FPS = ""
        Note = ""
        Type = ""
    }
    
    # Determine type
    if ($Format.vcodec -ne 'none' -and $Format.acodec -ne 'none') {
        $details.Type = "video+audio"
    } elseif ($Format.vcodec -ne 'none') {
        $details.Type = "video"
    } elseif ($Format.acodec -ne 'none') {
        $details.Type = "audio"
    } else {
        $details.Type = "unknown"
    }
    
    # Resolution
    if ($Format.width -and $Format.height) {
        $details.Resolution = "$($Format.width)x$($Format.height)"
    } elseif ($Format.height) {
        $details.Resolution = "$($Format.height)p"
    }
    
    # Video codec
    if ($Format.vcodec -and $Format.vcodec -ne 'none') {
        $details.VideoCodec = $Format.vcodec
    }
    
    # Audio codec
    if ($Format.acodec -and $Format.acodec -ne 'none') {
        $details.AudioCodec = $Format.acodec
    }
    
    # File size
    if ($Format.filesize) {
        $details.FileSize = Format-Bytes $Format.filesize
    } elseif ($Format.filesize_approx) {
        $details.FileSize = "~$(Format-Bytes $Format.filesize_approx)"
    }
    
    # Bitrate
    if ($Format.tbr) {
        $details.Bitrate = "$([int]$Format.tbr)k"
    } elseif ($Format.vbr -and $Format.abr) {
        $details.Bitrate = "$([int]($Format.vbr + $Format.abr))k"
    } elseif ($Format.vbr) {
        $details.Bitrate = "$([int]$Format.vbr)k"
    } elseif ($Format.abr) {
        $details.Bitrate = "$([int]$Format.abr)k"
    }
    
    # FPS
    if ($Format.fps) {
        $details.FPS = "$($Format.fps)fps"
    }
    
    # Note
    if ($Format.format_note -and $Format.format_note -ne "default") {
        $details.Note = $Format.format_note
    }
    
    return $details
}

function Show-FormatsMenu {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Formats,
        [Parameter(Mandatory=$true)]
        [string]$VideoTitle
    )
    
    Write-Host ""
    Write-Host "📊 " -NoNewline -ForegroundColor Yellow
    Write-Host "Analyzing available formats..." -ForegroundColor White
    
    # Separate formats by type
    $videoFormats = @()
    $audioFormats = @()
    $combinedFormats = @()
    
    foreach ($format in $Formats) {
        $details = Get-FormatDetails -Format $format
        
        $formatObj = [PSCustomObject]@{
            Format = $format
            Details = $details
        }
        
        switch ($details.Type) {
            "video+audio" { $combinedFormats += $formatObj }
            "video" { $videoFormats += $formatObj }
            "audio" { $audioFormats += $formatObj }
        }
    }
    
    # Sort formats
    $combinedFormats = $combinedFormats | Sort-Object -Property {$_.Format.height}, {$_.Format.tbr} -Descending
    $videoFormats = $videoFormats | Sort-Object -Property {$_.Details.VideoCodec}, {$_.Format.height}, {$_.Format.tbr} -Descending
    $audioFormats = $audioFormats | Sort-Object -Property {$_.Details.AudioCodec}, {$_.Format.abr} -Descending
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                           AVAILABLE DOWNLOAD OPTIONS                          ║" -ForegroundColor Cyan
    Write-Host "╠═══════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ " -NoNewline -ForegroundColor Cyan
    Write-Host "Video: " -NoNewline -ForegroundColor Yellow
    $titleDisplay = $VideoTitle
    if ($titleDisplay.Length -gt 65) { $titleDisplay = $titleDisplay.Substring(0, 62) + "..." }
    Write-Host $titleDisplay.PadRight(71) -NoNewline -ForegroundColor White
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $menuOptions = @()
    $optionNumber = 1
    
    # --- Best quality option (merge best video + best audio) ---
    Write-Host ""
    Write-Host "⭐ QUICK OPTIONS" -ForegroundColor Yellow
    Write-Host "────────────────" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "$([string]($optionNumber++)).".PadRight(4) -NoNewline -ForegroundColor Cyan
    Write-Host "🏆 " -NoNewline
    Write-Host "Highest Bitrate Quality " -NoNewline -ForegroundColor Green
    Write-Host "(Recommended - Selects highest bitrate video + audio)" -ForegroundColor Gray
    $menuOptions += @{
        Number = $optionNumber - 1
        Type = "best"
        Description = "Download highest bitrate available quality"
    }
    
    # --- Combined formats (video+audio) ---
    if ($combinedFormats.Count -gt 0) {
        Write-Host "`n--- Pre-Combined Formats (Video + Audio) ---" -ForegroundColor Green
        $headerCombined = "{0,-9} | {1,-4} | {2,-10} | {3,-15} | {4,-15} | {5,-11} | {6,-8} | {7}" -f "Format ID", "Ext", "Resolution", "Video Codec", "Audio Codec", "Size", "Bitrate", "Note"
        Write-Host (" " * 4) $headerCombined -ForegroundColor Yellow
        Write-Host (" " * 4) ("-" * $headerCombined.Length) -ForegroundColor Gray
        
        foreach ($fmt in $combinedFormats) {
            $d = $fmt.Details
            $line = "{0,-9} | {1,-4} | {2,-10} | {3,-15} | {4,-15} | {5,-11} | {6,-8} | {7}" -f $d.FormatId, $d.Extension, $d.Resolution, $d.VideoCodec, $d.AudioCodec, $d.FileSize, $d.Bitrate, $d.Note
            $displayNum = "{0,2}." -f $optionNumber
            Write-Host " $displayNum $line" -ForegroundColor White
            
            $menuOptions += @{ Number = $optionNumber; Type = "combined"; Format = $fmt.Format; Description = "Download combined $($d.Resolution)" }
            $optionNumber++
        }
    }
    
    # --- Video-Only Formats (Grouped by Extension) ---
    if ($videoFormats.Count -gt 0) {
        Write-Host "`n--- Video-Only Formats (merged with best audio) ---" -ForegroundColor Yellow
        $videoExtGroups = $videoFormats | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Details.Extension) } | Group-Object -Property {$_.Details.Extension}
        
        foreach ($group in $videoExtGroups) {
            Write-Host "`n  $($group.Name)" -ForegroundColor Yellow
            $headerVideo = "{0,-9} | {1,-4} | {2,-10} | {3,-15} | {4,-11} | {5,-8} | {6,-8} | {7}" -f "Format ID", "Ext", "Resolution", "Video Codec", "Size", "Bitrate", "FPS", "Note"
            Write-Host (" " * 4) $headerVideo -ForegroundColor Yellow
            Write-Host (" " * 4) ("-" * $headerVideo.Length) -ForegroundColor Gray

            foreach ($fmt in $group.Group) {
                $d = $fmt.Details
                $line = "{0,-9} | {1,-4} | {2,-10} | {3,-15} | {4,-11} | {5,-8} | {6,-8} | {7}" -f $d.FormatId, $d.Extension, $d.Resolution, $d.VideoCodec, $d.FileSize, $d.Bitrate, $d.FPS, $d.Note
                $displayNum = "{0,2}." -f $optionNumber
                Write-Host " $displayNum $line" -ForegroundColor White

                $menuOptions += @{ Number = $optionNumber; Type = "specific_video"; Format = $fmt.Format; Description = "Download $($d.Resolution) video merged with audio as $($d.Extension)" }
                $optionNumber++
            }
        }
    }

    # --- Audio Only Options ---
    Write-Host "`n--- Audio-Only Formats ---" -ForegroundColor Green

    # --- MP3 Conversion Options ---
    Write-Host "`n  🎧 MP3 CONVERSION OPTIONS" -ForegroundColor Magenta
    Write-Host "  ─────────────────────────" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "$([string]($optionNumber++)).".PadRight(4) -NoNewline -ForegroundColor Cyan
    Write-Host "💎 " -NoNewline
    Write-Host "MP3 - 320 kbps " -NoNewline -ForegroundColor White
    Write-Host "(Studio Quality)" -ForegroundColor Green
    $menuOptions += @{ Number = $optionNumber - 1; Type = "mp3_conversion"; Bitrate = 320; Description = "Convert to MP3 at 320k" }
    
    Write-Host "  " -NoNewline
    Write-Host "$([string]($optionNumber++)).".PadRight(4) -NoNewline -ForegroundColor Cyan
    Write-Host "✨ " -NoNewline
    Write-Host "MP3 - 256 kbps " -NoNewline -ForegroundColor White
    Write-Host "(Premium Quality)" -ForegroundColor Yellow
    $menuOptions += @{ Number = $optionNumber - 1; Type = "mp3_conversion"; Bitrate = 256; Description = "Convert to MP3 at 256k" }
    
    Write-Host "  " -NoNewline
    Write-Host "$([string]($optionNumber++)).".PadRight(4) -NoNewline -ForegroundColor Cyan
    Write-Host "🎵 " -NoNewline
    Write-Host "MP3 - 128 kbps " -NoNewline -ForegroundColor White
    Write-Host "(Standard Quality)" -ForegroundColor Gray
    $menuOptions += @{ Number = $optionNumber - 1; Type = "mp3_conversion"; Bitrate = 128; Description = "Convert to MP3 at 128k" }

    # --- Specific Original Audio Formats ---
    if ($audioFormats.Count -gt 0) {
        Write-Host "`n  --- Original Audio Formats (keep original format) ---" -ForegroundColor Green
        $audioCodecGroups = $audioFormats | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Details.AudioCodec) } | Group-Object -Property {$_.Details.AudioCodec}

        foreach ($group in $audioCodecGroups) {
            Write-Host "`n    Codec: $($group.Name)" -ForegroundColor Green
            $headerAudio = "{0,-9} | {1,-4} | {2,-15} | {3,-11} | {4,-8} | {5}" -f "Format ID", "Ext", "Audio Codec", "Size", "Bitrate", "Note"
            Write-Host (" " * 6) $headerAudio -ForegroundColor Green
            Write-Host (" " * 6) ("-" * $headerAudio.Length) -ForegroundColor Gray

            foreach ($fmt in $group.Group) {
                $d = $fmt.Details
                $line = "{0,-9} | {1,-4} | {2,-15} | {3,-11} | {4,-8} | {5}" -f $d.FormatId, $d.Extension, $d.AudioCodec, $d.FileSize, $d.Bitrate, $d.Note
                $displayNum = "{0,2}." -f $optionNumber
                Write-Host "   $displayNum $line" -ForegroundColor White

                $menuOptions += @{ Number = $optionNumber; Type = "original_audio"; Format = $fmt.Format; Description = "Download $($d.AudioCodec) audio (original format)" }
                $optionNumber++
            }
        }
        
        # Add separator for MP3 conversion options
        Write-Host "`n  --- Audio to MP3 Conversion Options ---" -ForegroundColor Yellow
        foreach ($group in $audioCodecGroups) {
            Write-Host "`n    Codec: $($group.Name) → MP3" -ForegroundColor Yellow
            $headerAudio = "{0,-9} | {1,-4} | {2,-15} | {3,-11} | {4,-8} | {5}" -f "Format ID", "Ext", "Audio Codec", "Size", "Bitrate", "Note"
            Write-Host (" " * 6) $headerAudio -ForegroundColor Yellow
            Write-Host (" " * 6) ("-" * $headerAudio.Length) -ForegroundColor Gray

            foreach ($fmt in $group.Group) {
                $d = $fmt.Details
                $line = "{0,-9} | {1,-4} | {2,-15} | {3,-11} | {4,-8} | {5}" -f $d.FormatId, $d.Extension, $d.AudioCodec, $d.FileSize, $d.Bitrate, $d.Note
                $displayNum = "{0,2}." -f $optionNumber
                Write-Host "   $displayNum $line" -ForegroundColor White

                $menuOptions += @{ Number = $optionNumber; Type = "specific_audio"; Format = $fmt.Format; Description = "Download $($d.AudioCodec) audio and convert to MP3" }
                $optionNumber++
            }
        }
    }

    # --- Other Options ---
    Write-Host ""
    Write-Host "🎨 OTHER OPTIONS" -ForegroundColor Yellow
    Write-Host "────────────────" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "$([string]($optionNumber++)).".PadRight(4) -NoNewline -ForegroundColor Cyan
    Write-Host "🖼️  " -NoNewline
    Write-Host "Download Video Thumbnail " -NoNewline -ForegroundColor White
    Write-Host "(Cover Image)" -ForegroundColor Gray
    $menuOptions += @{
        Number = $optionNumber - 1
        Type = "cover"
        Description = "Download video thumbnail"
    }
    
    Write-Host "  " -NoNewline
    Write-Host "$([string]($optionNumber++)).".PadRight(4) -NoNewline -ForegroundColor Cyan
    Write-Host "🔗 " -NoNewline
    Write-Host "(Send New Link)" -ForegroundColor Gray
    $menuOptions += @{
        Number = $optionNumber - 1
        Type = "new_link"
        Description = "Send new video link"
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    return $menuOptions
}

function Show-DownloadProgress {
    param (
        [string]$Activity,
        [double]$Percentage = -1,
        [string]$TotalSize = "",
        [string]$Speed = "",
        [string]$ETA = ""
    )

    $barWidth = [int]($Host.UI.RawUI.WindowSize.Width * 0.4) # 40% of window width
    if ($barWidth -lt 20) { $barWidth = 20 }
    if ($barWidth -gt 50) { $barWidth = 50 }
    
    $line = "`r" 

    if ($Percentage -ge 0) {
        $completedWidth = [int]($barWidth * $Percentage / 100)
        $remainingWidth = $barWidth - $completedWidth
        $progressBar = ("█" * $completedWidth) + ("░" * $remainingWidth)
        $percentText = "{0,5:N1}%" -f $Percentage
        $speedText = if ($Speed) { "{0,12}" -f $Speed } else { " " * 12 }
        $etaText = if ($ETA) { "ETA: {0,-8}" -f $ETA } else { " " * 13 }
        $sizeText = if ($TotalSize) { "{0,10}" -f $TotalSize } else { " " * 10 }
        
        $line += "{0,-12} [{1}] {2} {3} {4} {5}" -f $Activity, $progressBar, $percentText, $sizeText, $speedText, $etaText
    } else {
        $line += "{0,-20}..." -f $Activity
    }

    $line = $line.PadRight($Host.UI.RawUI.WindowSize.Width - 1)
    Write-Host -NoNewline $line -ForegroundColor Green
}

function Invoke-YtDlpSimple {
    param (
        [string]$YtDlpPath,
        [System.Collections.Generic.List[string]]$YtDlpArguments,
        [int]$MaxRetries = 2
    )

    if ($null -eq $YtDlpArguments) {
        Write-ErrorLog "Invoke-YtDlpSimple called with null arguments."
        return @{ ExitCode = -1; Output = @(); Error = @("Internal Script Error: Download arguments were not provided.") }
    }
    
    # Verify yt-dlp exists
    if (-not (Test-Path $YtDlpPath)) {
        Write-ErrorLog "yt-dlp.exe not found at: $YtDlpPath"
        return @{ ExitCode = -1; Output = @(); Error = @("yt-dlp.exe not found at: $YtDlpPath") }
    }

    $lastResult = $null
    
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        if ($attempt -gt 0) {
            $delay = $attempt * 5
            Write-Host "`n  Retry attempt $attempt of $MaxRetries (waiting ${delay}s)..." -ForegroundColor Yellow
            Write-ErrorLog "Download retry attempt $attempt of $MaxRetries after ${delay}s delay"
            Start-Sleep -Seconds $delay
        }
        
        $outputLines = [System.Collections.Generic.List[string]]::new()
        $errorLines = [System.Collections.Generic.List[string]]::new()

        try {
            if ($attempt -eq 0) {
                Write-Host "Initializing download..." -ForegroundColor Yellow
            }
            Write-ErrorLog "Executing command (attempt $($attempt+1)): $YtDlpPath $($YtDlpArguments -join ' ')"
            Write-ErrorLog "Working Directory: $(Split-Path $YtDlpPath -Parent)"
            
            # Use the simplest method - direct execution with & operator
            $currentLocation = Get-Location
            Set-Location (Split-Path $YtDlpPath -Parent)
            
            try {
                # Variables for progress tracking
                $currentFileName = ""
                $lastProgress = -1
                
                # Execute yt-dlp directly and capture output line by line
                & $YtDlpPath $YtDlpArguments 2>&1 | ForEach-Object {
                    $line = $_
                    
                    if ($line -is [System.Management.Automation.ErrorRecord]) {
                        $errorLines.Add($line.ToString())
                        # Don't show error lines in real-time unless critical
                        if ($line.ToString() -match "ERROR|CRITICAL") {
                            Write-Host $line -ForegroundColor Red
                        }
                    } else {
                        $outputLines.Add($line.ToString())
                        
                        # Parse different types of output
                        # Extract filename
                        if ($line -match 'Destination:\s+(.+)') {
                            $currentFileName = [System.IO.Path]::GetFileName($matches[1])
                        }
                        
                        # Parse download progress
                        $dlRegex = '\[download\]\s+(?<percent>[\d\.]+)%\s+of\s+(?:~\s*)?(?<size>[\d\.]+)(?<unit>\w+)(?:\s+at\s+(?<speed>[\d\.]+\w+/s))?(?:\s+ETA\s+(?<eta>[\d:]+))?'
                        $dlMatch = [regex]::Match($line, $dlRegex)
                        
                        if ($dlMatch.Success) {
                            $percent = [double]$dlMatch.Groups['percent'].Value
                            $size = $dlMatch.Groups['size'].Value + $dlMatch.Groups['unit'].Value
                            $speed = $dlMatch.Groups['speed'].Value
                            $eta = $dlMatch.Groups['eta'].Value
                            
                            # Only update if progress changed significantly
                            if ([Math]::Abs($percent - $lastProgress) -ge 0.2 -or $percent -eq 100) {
                                Show-CustomDownloadProgress -Activity "Downloading" `
                                                          -Percentage $percent `
                                                          -TotalSize $size `
                                                          -Speed $speed `
                                                          -ETA $eta `
                                                          -FileName $currentFileName `
                                                          -Stage "download"
                                $lastProgress = $percent
                            }
                        }
                        # Parse merging
                        elseif ($line -match '\[Merger\]') {
                            Show-CustomDownloadProgress -Activity "Merging" `
                                                      -Percentage 95 `
                                                      -FileName $currentFileName `
                                                      -Stage "merge"
                        }
                        # Parse audio extraction
                        elseif ($line -match '\[ExtractAudio\]') {
                            Show-CustomDownloadProgress -Activity "Extracting" `
                                                      -Percentage 90 `
                                                      -FileName $currentFileName `
                                                      -Stage "process"
                        }
                        # Parse conversion
                        elseif ($line -match '\[ffmpeg\]\s+Converting') {
                            Show-CustomDownloadProgress -Activity "Converting" `
                                                      -Percentage 92 `
                                                      -FileName $currentFileName `
                                                      -Stage "process"
                        }
                        # Parse subtitle embedding
                        elseif ($line -match '\[EmbedSubtitle\]') {
                            Show-CustomDownloadProgress -Activity "Processing" `
                                                      -Percentage 98 `
                                                      -FileName $currentFileName `
                                                      -Stage "process"
                        }
                        # Parse post-processing
                        elseif ($line -match '\[PostProcessor\]') {
                            Show-CustomDownloadProgress -Activity "Finalizing" `
                                                      -Percentage 99 `
                                                      -FileName $currentFileName `
                                                      -Stage "process"
                        }
                        # Show other important messages
                        elseif ($line -match '\[(youtube|info|warning)\]' -or 
                                $line -match 'Deleting original file' -or
                                $line -match 'has already been downloaded') {
                            # Don't show these lines to keep output clean
                        }
                    }
                }
                
                $exitCode = $LASTEXITCODE
                
                # Clear progress line and show completion
                Write-Host "`r" + (" " * [Math]::Min($Host.UI.RawUI.WindowSize.Width, 120)) + "`r" -NoNewline
                
                if ($exitCode -eq 0) {
                    Write-Host "✓ Download completed successfully!" -ForegroundColor Green
                    return @{ 
                        ExitCode = $exitCode
                        Output = $outputLines.ToArray()
                        Error = $errorLines.ToArray()
                    }
                } else {
                    $lastResult = @{ 
                        ExitCode = $exitCode
                        Output = $outputLines.ToArray()
                        Error = $errorLines.ToArray()
                    }
                    Write-ErrorLog "Download attempt $($attempt+1) failed with exit code: $exitCode"
                    # Check if error is retryable (bot detection, timeout, etc.)
                    $errorOutput = ($errorLines -join "`n") + ($outputLines -join "`n")
                    if ($errorOutput -match "Sign in to confirm|bot|403|429|timed out|timeout" -and $attempt -lt $MaxRetries) {
                        Write-Host "  ⚠ Retryable error detected, will retry..." -ForegroundColor Yellow
                        continue
                    } else {
                        Write-Host "✗ Download completed with errors (Exit code: $exitCode)" -ForegroundColor Yellow
                        return $lastResult
                    }
                }
            }
            finally {
                Set-Location $currentLocation
            }
        }
        catch {
            $errorMessage = "Failed to start yt-dlp process: $($_.Exception.Message)"
            Write-ErrorLog $errorMessage
            $errorLines.Add($errorMessage)
            
            # Clear any progress line
            Write-Host "`r" + (" " * [Math]::Min($Host.UI.RawUI.WindowSize.Width, 120)) + "`r" -NoNewline
            Write-Host "✗ Download failed!" -ForegroundColor Red
            Write-Host ""
            
            $lastResult = @{ 
                ExitCode = -1
                Output = $outputLines.ToArray()
                Error = $errorLines.ToArray()
            }
            if ($attempt -lt $MaxRetries) {
                continue
            }
            return $lastResult
        }
    }
    
    # Return last result if all retries exhausted
    if ($lastResult) { return $lastResult }
    return @{ ExitCode = -1; Output = @(); Error = @("All retry attempts failed") }
}

function Invoke-YtDlpWithProgress {
    param (
        [string]$YtDlpPath,
        [System.Collections.Generic.List[string]]$YtDlpArguments
    )

    if ($null -eq $YtDlpArguments) {
        Write-ErrorLog "Invoke-YtDlpWithProgress called with null arguments."
        return @{ ExitCode = -1; Output = @(); Error = @("Internal Script Error: Download arguments were not provided.") }
    }
    
    # Verify yt-dlp exists
    if (-not (Test-Path $YtDlpPath)) {
        Write-ErrorLog "yt-dlp.exe not found at: $YtDlpPath"
        return @{ ExitCode = -1; Output = @(); Error = @("yt-dlp.exe not found at: $YtDlpPath") }
    }

    $process = $null
    $outputLines = [System.Collections.Generic.List[string]]::new()
    $errorLines = [System.Collections.Generic.List[string]]::new()

    try {
        $process = New-Object System.Diagnostics.Process
        if ($null -eq $process) {
            throw "Failed to create Process object"
        }

        $process.StartInfo.FileName = $YtDlpPath
        $process.StartInfo.Arguments = $YtDlpArguments -join ' '
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.WorkingDirectory = Split-Path $YtDlpPath -Parent

        # Add event handlers with proper error handling
        $outputAction = {
            if (-not [string]::IsNullOrWhiteSpace($_.Data)) {
                $line = $_.Data
                $outputLines.Add($line)

                $dlRegex = '\[download\]\s+(?<percent>[\d\.]+)%\s+of\s+(?:~)?(?<size>[\d\.]+\w+)(?:\s+at\s+(?<speed>[\d\.]+\w+\/s))?(?:\s+ETA\s+(?<eta>[\d:]+))?'
                $dlMatch = [regex]::Match($line, $dlRegex)

                $procRegex = '\[(?<process>\w+)\]'
                $procMatch = [regex]::Match($line, $procRegex)

                if ($dlMatch.Success) {
                    Show-DownloadProgress -Activity "Downloading" `
                                          -Percentage ([double]$dlMatch.Groups['percent'].Value) `
                                          -TotalSize $dlMatch.Groups['size'].Value `
                                          -Speed $dlMatch.Groups['speed'].Value `
                                          -ETA $dlMatch.Groups['eta'].Value
                } elseif ($procMatch.Success -and $procMatch.Groups['process'].Value -ne 'youtube') {
                    $processName = $procMatch.Groups['process'].Value
                    Show-DownloadProgress -Activity "$($processName)..."
                }
            }
        }

        $errorAction = {
            if (-not [string]::IsNullOrWhiteSpace($_.Data)) {
                $errorLines.Add($_.Data)
            }
        }

        # Register event handlers using simpler approach
        Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $outputAction | Out-Null
        Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $errorAction | Out-Null

        Write-Host "Starting yt-dlp process..." -ForegroundColor Yellow
        
        # Start the process with better error handling
        $started = $false
        try {
            $started = $process.Start()
        } catch {
            throw "Failed to start process: $_"
        }
        
        if (-not $started) {
            throw "Process.Start() returned false. The process could not be started."
        }
        
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        $process.WaitForExit()

        Write-Host ("`r".PadRight($Host.UI.RawUI.WindowSize.Width)) -NoNewline
        Write-Host "`rDownload task finished." -ForegroundColor Green
        Write-Host ""

        return @{ 
            ExitCode = $process.ExitCode
            Output = $outputLines.ToArray()
            Error = $errorLines.ToArray()
        }

    } catch {
        $errorMessage = "Failed to start yt-dlp process: $($_.Exception.Message)"
        Write-ErrorLog $errorMessage
        $errorLines.Add($errorMessage)
        
        return @{ 
            ExitCode = -1
            Output = $outputLines.ToArray()
            Error = $errorLines.ToArray()
        }
    } finally {
        # Clean up event handlers
        Get-EventSubscriber | Where-Object SourceObject -eq $process | Unregister-Event -Force
        
        if ($process) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
                $process.Dispose()
            } catch {
                Write-ErrorLog "Error disposing process: $($_.Exception.Message)"
            }
        }
    }
}

function Show-VideoDetails {
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$VideoInfo
    )

    Write-Host ""
    Write-Host "╭───────────────────────────────────────────────────────────────────────────────╮" -ForegroundColor Cyan
    Write-Host "│                             VIDEO INFORMATION                                 │" -ForegroundColor Cyan
    Write-Host "╰───────────────────────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
    Write-Host ""
    
    if ($VideoInfo.title) { 
        Write-Host " 📌 Title         : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.title)" -ForegroundColor White 
    }
    
    if ($VideoInfo.webpage_url) { 
        Write-Host " 🔗 URL           : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.webpage_url)" -ForegroundColor DarkGray 
    }
    
    if ($VideoInfo.uploader) { 
        Write-Host " 👤 Uploader      : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.uploader)" -ForegroundColor White 
    }
    
    if ($VideoInfo.channel -and $VideoInfo.channel -ne $VideoInfo.uploader) { 
        Write-Host " 📺 Channel       : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.channel)" -ForegroundColor White 
    }
    
    if ($VideoInfo.upload_date) {
        try {
            $year = $VideoInfo.upload_date.Substring(0,4)
            $month = $VideoInfo.upload_date.Substring(4,2)
            $day = $VideoInfo.upload_date.Substring(6,2)
            $uploadDateObject = Get-Date -Year $year -Month $month -Day $day
            Write-Host " 📅 Upload Date   : " -NoNewline -ForegroundColor Yellow
            Write-Host "$($uploadDateObject.ToString("yyyy-MM-dd (dddd)"))" -ForegroundColor White
        } catch {
            Write-Host " 📅 Upload Date   : " -NoNewline -ForegroundColor Yellow
            Write-Host "$($VideoInfo.upload_date)" -ForegroundColor Yellow
        }
    }
    
    if ($VideoInfo.duration_string) { 
        Write-Host " ⏱️ Duration      : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.duration_string)" -ForegroundColor White 
    }
    elseif ($VideoInfo.duration) { 
        Write-Host " ⏱️ Duration      : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.duration) seconds" -ForegroundColor White 
    }

    if ($null -ne $VideoInfo.view_count) { 
        Write-Host " 👁️ Views         : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.view_count.ToString("N0"))" -ForegroundColor Green 
    }
    
    if ($null -ne $VideoInfo.like_count) { 
        Write-Host " 👍 Likes         : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.like_count.ToString("N0"))" -ForegroundColor Green 
    }
    else {
        Write-Host " 👍 Likes         : " -NoNewline -ForegroundColor Yellow
        Write-Host "N/A" -ForegroundColor Gray
    }
    
    if ($VideoInfo.live_status) { 
        Write-Host " 🔴 Live Status   : " -NoNewline -ForegroundColor Yellow
        $statusColor = if ($VideoInfo.live_status -eq "is_live") { "Red" } 
                      elseif ($VideoInfo.live_status -eq "was_live") { "DarkRed" } 
                      else { "White" }
        Write-Host "$($VideoInfo.live_status)" -ForegroundColor $statusColor 
    }
    
    if ($null -ne $VideoInfo.age_limit -and $VideoInfo.age_limit -gt 0) { 
        Write-Host " 🔞 Age Limit     : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.age_limit)+" -ForegroundColor Red 
    }

    if ($VideoInfo.categories -and $VideoInfo.categories.Count -gt 0) { 
        Write-Host " 🏷️ Categories    : " -NoNewline -ForegroundColor Yellow
        Write-Host "$($VideoInfo.categories -join ', ')" -ForegroundColor White 
    }

    if ($VideoInfo.tags -and $VideoInfo.tags.Count -gt 0) {
        $tagsString = $VideoInfo.tags -join ', '
        if ($tagsString.Length -gt 100) { $tagsString = $tagsString.Substring(0, 100) + "..." }
        Write-Host " 🔖 Tags          : " -NoNewline -ForegroundColor Yellow
        Write-Host "$tagsString" -ForegroundColor DarkGray
    }
    
    if ($VideoInfo.description) {
        Write-Host ""
        Write-Host " 📝 Description:" -ForegroundColor Yellow
        Write-Host " ───────────────" -ForegroundColor Gray
        $descText = $VideoInfo.description
        # Handle different description formats from various sites
        $descriptionLines = $descText -split '\r?\n'
        $maxDescLines = $settings.advanced.max_description_lines
        $shownLines = 0
        for ($i = 0; $i -lt $descriptionLines.Count -and $shownLines -lt $maxDescLines; $i++) {
            $line = $descriptionLines[$i].Trim()
            if ($line.Length -gt 0) {
                if ($line.Length -gt 76) { $line = $line.Substring(0, 76) + "..." }
                Write-Host "    $line" -ForegroundColor White
                $shownLines++
            }
        }
        if ($descriptionLines.Count -gt $maxDescLines -or $descText.Length -gt ($maxDescLines * 80)) {
            Write-Host "    [...]" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "" 
}

function Show-StartupAnimation {
    param(
        [string]$Message = "Loading...",
        [int]$DurationSeconds = 2
    )
    
    $animationChars = @("🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘")
    $startTime = Get-Date
    $cursorPos = $Host.UI.RawUI.CursorPosition
    
    while ((Get-Date) -lt $startTime.AddSeconds($DurationSeconds)) {
        foreach ($char in $animationChars) {
            $Host.UI.RawUI.CursorPosition = $cursorPos
            Write-Host -NoNewline "$char $Message" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 100
        }
    }
    
    # Clear the animation line
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host (" " * ($Message.Length + 5))
    $Host.UI.RawUI.CursorPosition = $cursorPos
}

if ($Help) {
    Show-ScriptHelp
    exit 0
}

# Load settings with error handling
try {
    Load-Settings
} catch {
    Show-EnhancedError -TechnicalError $_.Exception.Message -Context "Failed to load settings configuration"
    Write-Host "Using default settings due to configuration error." -ForegroundColor Yellow
}

# --- Startup Sequence ---
Clear-Host
Show-StartupAnimation -Message "Initializing UVD Engine..." -DurationSeconds 1

Write-Host "🚀 Preparing launch sequence..." -ForegroundColor Cyan
Write-Host "────────────────────────────────" -ForegroundColor Gray

Invoke-StartupTask -Message "Configuring system proxy" -Action {
    Set-ProxyConfiguration
    return $true # Assume success
}

Invoke-StartupTask -Message "Initializing video cache database" -Action {
    Initialize-Database
    return $true # Assume success
}

$localYtDlpPath = Join-Path $scriptDir "yt-dlp.exe"
$localFfmpegPath = Join-Path $scriptDir "ffmpeg.exe"

$needsTerminalRestart = $false

$updateYtDlpResult = $null
Invoke-StartupTask -Message "Checking for yt-dlp updates" -Action {
    $global:updateYtDlpResult = Update-YtDlp -YtDlpPath $localYtDlpPath -Quiet
    return $global:updateYtDlpResult.Success
}

$updateFfmpegResult = $null
Invoke-StartupTask -Message "Checking for ffmpeg updates" -Action {
    $global:updateFfmpegResult = Update-Ffmpeg -FfmpegPath $localFfmpegPath -Quiet
    return $global:updateFfmpegResult.Success
}

if ($global:updateYtDlpResult.NeedsRestart -or $global:updateFfmpegResult.NeedsRestart) {
    $needsTerminalRestart = $true
}

$ytDlpPath = Resolve-ToolPath -ToolName "yt-dlp" -LocalPath $localYtDlpPath
$ffmpegPath = Resolve-ToolPath -ToolName "ffmpeg" -LocalPath $localFfmpegPath
Write-ErrorLog "yt-dlp resolved path: $ytDlpPath"
Write-ErrorLog "ffmpeg resolved path: $ffmpegPath"

Invoke-StartupTask -Message "Configuring environment" -Action {
    $dirsToAdd = @()
    
    $ytDlpDir = Split-Path $ytDlpPath -Parent
    if ($ytDlpDir -and $env:PATH -notlike "*$ytDlpDir*") {
        $dirsToAdd += $ytDlpDir
    }
    
    $ffmpegDir = Split-Path $ffmpegPath -Parent
    if ($ffmpegDir -and $env:PATH -notlike "*$ffmpegDir*") {
        $dirsToAdd += $ffmpegDir
    }
    
    if ($env:PATH -notlike "*$scriptDir*") {
        $dirsToAdd += $scriptDir
    }
    
    if ($dirsToAdd.Count -gt 0) {
        $env:PATH = ($dirsToAdd -join ";") + ";$env:PATH"
        Write-ErrorLog "Added directories to PATH: $($dirsToAdd -join ', ')"
    }
    
    return $true
}

Write-Host ""
Write-Host "✅ System check complete. Launching..." -ForegroundColor Green

if ($needsTerminalRestart) {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                         TERMINAL RESTART RECOMMENDED                         ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  yt-dlp and/or ffmpeg were installed via winget." -ForegroundColor White
    Write-Host "  For PATH changes to take effect, please restart your terminal." -ForegroundColor White
    Write-Host ""
    Write-Host "  You can continue now (tools may work), or restart for full functionality." -ForegroundColor Gray
    Write-Host ""
    
    $restartChoice = Get-ValidatedUserInput -Prompt "  Restart terminal now? (y/n):" -InputType "yesno" -MaxAttempts 3
    
    if ($restartChoice -eq 'y') {
        Write-Host ""
        Write-Host "  Restarting terminal..." -ForegroundColor Cyan
        Write-Host "  UVD will resume automatically after restart." -ForegroundColor Gray
        Write-Host ""
        
        $batchPath = Join-Path $scriptDir "..\uvd.bat"
        if (Test-Path $batchPath) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batchPath`""
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        }
        exit 0
    } else {
        Write-Host ""
        Write-Host "  Continuing with current session..." -ForegroundColor Yellow
        Write-Host "  Note: If tools don't work, please restart manually." -ForegroundColor Yellow
        Write-Host ""
    }
}

Start-Sleep -Seconds 1
# --- End of Startup Sequence ---

$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

Write-ErrorLog "=== USER INTERFACE INITIALIZED ==="
Write-ErrorLog "Background color set to: Black"
Write-ErrorLog "Foreground color set to: White"
Write-ErrorLog "Screen cleared for fresh start"

# Function to display quick start guide and available commands
function Show-QuickGuide {
    Write-Host ""
    Write-Host "⚡ QUICK START GUIDE" -ForegroundColor Green
    Write-Host "═══════════════════" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1] Paste video URL and press Enter" -ForegroundColor White
    Write-Host "  [2] Choose download format from the displayed options" -ForegroundColor White
    Write-Host "  [3] Wait for download to complete" -ForegroundColor White
    Write-Host "  [4] Find your file in the Downloaded folder" -ForegroundColor White
    Write-Host ""
    Write-Host "📋 AVAILABLE COMMANDS" -ForegroundColor Yellow
    Write-Host "════════════════════" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  help, -h     : Show detailed help and guide" -ForegroundColor Cyan
    Write-Host "  restart      : Restart the script" -ForegroundColor Cyan
    Write-Host "  clear-cache  : Clear video information cache" -ForegroundColor Cyan
    Write-Host "  folder       : Open program folder in explorer" -ForegroundColor Cyan
    Write-Host "  downloads    : Open downloads folder" -ForegroundColor Cyan
    Write-Host "  settings     : Open settings file" -ForegroundColor Cyan
    Write-Host "  exit         : Exit the program" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "💡 Tip: Configure settings.json for proxy, cookies, and advanced options" -ForegroundColor White
    Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

# Display welcome banner (only once at startup)
Write-ErrorLog "Displaying welcome banner"
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "║                      Universal Video Downloader by MBNPRO                     ║" -ForegroundColor Yellow
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "║         Download from YouTube, TikTok, Instagram, Twitter, Facebook,          ║" -ForegroundColor White
Write-Host "║              Twitch, Vimeo, SoundCloud, Reddit & 1800+ sites                  ║" -ForegroundColor White
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "║                        Version 3.0 - Modern Edition                           ║" -ForegroundColor Gray
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Show quick guide on first run
Show-QuickGuide

# Use settings for directory paths
$tempDir = Join-Path $scriptDir $settings.download.temp_directory
$downloadedDir = Join-Path $scriptDir $settings.download.output_directory
$videoOutputDir = Join-Path $downloadedDir $settings.download.video_subdirectory
$audioOutputDir = Join-Path $downloadedDir $settings.download.audio_subdirectory
$coversOutputDir = Join-Path $downloadedDir $settings.download.covers_subdirectory

Write-ErrorLog "=== INITIALIZING DIRECTORIES ==="
Write-ErrorLog "Creating directory: $tempDir"
Initialize-Directory $tempDir
Write-ErrorLog "Creating directory: $downloadedDir"
Initialize-Directory $downloadedDir
Write-ErrorLog "Creating directory: $videoOutputDir"
Initialize-Directory $videoOutputDir
Write-ErrorLog "Creating directory: $audioOutputDir"
Initialize-Directory $audioOutputDir
Write-ErrorLog "Creating directory: $coversOutputDir"
Initialize-Directory $coversOutputDir

$continueWithNewLink = 'y' 
Write-ErrorLog "=== MAIN EXECUTION LOOP STARTED ==="

do { 
    Write-Host "╭──────────────────────────────╮" -ForegroundColor Cyan
    Write-Host "│          MAIN MENU           │" -ForegroundColor Cyan
    Write-Host "╰──────────────────────────────╯" -ForegroundColor Cyan
    Write-Host ""
    $userInputUrl = Get-ValidatedUserInput -Prompt "📥 Enter URL (or command):" -InputType "url" -MaxAttempts 5
    
    if ($null -eq $userInputUrl) {
        Write-Host "No valid input received. Exiting..." -ForegroundColor Red
        $continueWithNewLink = 'n'
        continue
    }

    if ($userInputUrl -eq 'exit') {
        Write-ErrorLog "User selected exit command"
        $continueWithNewLink = 'n'
        continue
    }

    if ($userInputUrl -match '^\-h$' -or $userInputUrl -match '^\-{1,2}help$' -or $userInputUrl -eq 'help') {
        Write-ErrorLog "User requested help"
        Clear-Host
        Show-ScriptHelp
        Write-Host ""
        Write-Host "Press any key to return to main menu..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Clear-Host
        Show-QuickGuide
        continue
    }
    
    if ($userInputUrl -eq 'restart') {
        Write-ErrorLog "User requested restart"
        Clear-Host
        Write-Host "Restarting UVD..." -ForegroundColor Cyan
        Write-Host ""
        $batchPath = Join-Path $scriptDir "..\uvd.bat"
        if (Test-Path $batchPath) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batchPath`""
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        }
        exit 0
    }
    
    if ($userInputUrl -eq 'clear-cache') {
        Write-ErrorLog "User requested clear-cache"
        Clear-Host
        Clear-VideoCache
        Write-Host ""
        Write-Host "Press any key to return to main menu..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Clear-Host
        Show-QuickGuide
        continue
    }
    
    if ($userInputUrl -eq 'folder') {
        Write-ErrorLog "User requested folder open"
        Open-ProgramFolder
        continue
    }
    
    if ($userInputUrl -eq 'downloads') {
        Write-ErrorLog "User requested downloads folder open"
        Open-DownloadsFolder
        continue
    }
    
    if ($userInputUrl -eq 'settings') {
        Write-ErrorLog "User requested settings open"
        Open-SettingsFile
        continue
    }
    
    # Clean the URL to remove potentially problematic parameters
    $currentUrl = $userInputUrl
    
    # For video URLs, remove certain parameters that might cause 403 errors
    if ($currentUrl -match "youtube\.com|youtu\.be") {
        $currentUrl = $currentUrl -replace "&pp=[^&]*", ""  # Remove pp parameter
        $currentUrl = $currentUrl -replace "\?pp=[^&]*&?", "?"  # Remove pp parameter if it's first
        $currentUrl = $currentUrl -replace "\?&", "?"  # Clean up malformed query string
        $currentUrl = $currentUrl -replace "\?$", ""  # Remove trailing question mark
        
        if ($currentUrl -ne $userInputUrl) {
            Write-ErrorLog "URL cleaned from: $userInputUrl"
            Write-ErrorLog "URL cleaned to: $currentUrl"
        }
    }
    
    Write-ErrorLog "Attempting to process URL: $currentUrl"
    
    # Always initialize cookie variables for each URL processing
    $cookieFilePath = Get-CookieFilePath
    $useCookies = [bool]$settings.cookies.use_cookies -and ($null -ne $cookieFilePath)
    
    # Also enable cookies if browser cookie source is configured
    if (-not $useCookies -and $script:useBrowserCookies -and -not [string]::IsNullOrWhiteSpace($script:browserCookieSource)) {
        $useCookies = $true
    }
    
    # Check cache first
    $cachedVideoInfo = Get-VideoFromCache -Url $currentUrl
    if ($cachedVideoInfo) {
        Write-Host ""
        Write-Host "💾 Using cached video information for faster processing!" -ForegroundColor Green
        $videoInfo = $cachedVideoInfo.info
        Show-VideoDetails -VideoInfo $videoInfo
    } else {
        # Show processing message
        Write-Host ""
        Write-Host "🔍 Fetching video information, please wait..." -ForegroundColor Yellow
        
        # Initialize variables for retry logic
        $videoInfo = $null
        $maxRetries = [int]$settings.general.max_retries
        $retryCount = 0
        
        while ($retryCount -lt $maxRetries -and $null -eq $videoInfo) {
            $retryCount++
            if ($retryCount -gt 1) {
                Write-Host ""
                Write-Host "🔄 Retry attempt $retryCount of $maxRetries..." -ForegroundColor Yellow
            }
            
            # Attempt to get video info with timeout
            $result = Get-VideoInfoWithTimeout -Url $currentUrl -YtDlpPath $ytDlpPath -TimeoutSeconds $settings.general.request_timeout_seconds -UseCookies $useCookies -CookieFilePath $cookieFilePath
            
            if ($null -eq $result) {
                $result = @{ Success = $false; Error = "No result returned from video info lookup"; ExitCode = -1 }
            }
            
            if ($result.Success -and $result.ExitCode -eq 0) {
                # Success - parse the JSON
                try {
                    $videoInfo = ($result.Output -join [System.Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
                    Write-Host "Video information retrieved successfully!" -ForegroundColor Green
                    Write-ErrorLog "Successfully obtained and parsed JSON for $currentUrl"
                    
                    # Save to cache
                    Save-VideoToCache -Url $currentUrl -VideoInfo $videoInfo
                    
                    # Display video details
                    Show-VideoDetails -VideoInfo $videoInfo
                    break
                } catch {
                    # Create a truncated version for console display
                    $fullJsonString = $result.Output -join [System.Environment]::NewLine
                    $truncatedJson = if ($fullJsonString.Length -gt 500) {
                        $fullJsonString.Substring(0, 500) + "... [JSON truncated for display]"
                    } else {
                        $fullJsonString
                    }
                    
                    # Log full JSON to debug file only
                    $fullLogMsg = "Failed to parse JSON for '$currentUrl'. Full JSON String: $fullJsonString. Exception: $($_.Exception.Message)"
                    Write-ErrorLog $fullLogMsg
                    
                    # Create user-friendly message for console
                    $userFriendlyLogMsg = "Failed to parse JSON for '$currentUrl'. JSON Preview: $truncatedJson. Exception: $($_.Exception.Message)"
                    
                    if ($retryCount -eq $maxRetries) {
                        Resolve-ScriptError -UserMessage "Received invalid video information from yt-dlp. The video might be unsupported or an internal error occurred." `
                                           -InternalLogMessage $userFriendlyLogMsg
                        break
                    }
                }
            } else {
                # Failed - handle error
                $errorMessage = if ($result.Error) { $result.Error } else { "Unknown error occurred" }
                
                # Truncate very long error messages for display
                $truncatedErrorMessage = if ($errorMessage.Length -gt 1000) {
                    $errorMessage.Substring(0, 1000) + "... [Error truncated - full details in debug log]"
                } else {
                    $errorMessage
                }
                
                Write-ErrorLog "Failed to get video info for '$currentUrl'. Error: $errorMessage. Exit Code: $($result.ExitCode)"
                
                if ($retryCount -eq $maxRetries) {
                    # Show error handling options
                    $userChoice = Show-ErrorHandlingOptions -Url $currentUrl -ErrorMessage $truncatedErrorMessage
                    
                    switch ($userChoice) {
                        "cookies" {
                            if ($cookieFilePath) {
                                $useCookies = $true
                                $retryCount = 0  # Reset retry count for cookie attempt
                                Write-Host "Retrying with cookie authentication..." -ForegroundColor Yellow
                            } else {
                                Write-Host "Cookie file not found. Please check settings.json configuration." -ForegroundColor Red
                                break
                            }
                        }
                        "login" {
                            $loginSuccess = Invoke-YouTubeLogin -Url $currentUrl
                            if ($loginSuccess) {
                                $retryCount = 0  # Reset retry count for login attempt
                                Write-Host "Retrying after login..." -ForegroundColor Yellow
                            } else {
                                Write-Host "Login failed. Please try manually or check settings." -ForegroundColor Red
                                break
                            }
                        }
                        "retry" {
                            $retryCount = 0  # Reset retry count for manual retry
                            Write-Host "Retrying with current settings..." -ForegroundColor Yellow
                        }
                        "new_url" {
                            break  # Exit inner loop to get new URL
                        }
                        "exit" {
                            $continueWithNewLink = 'n'
                            break
                        }
                        "configure_cookies" {
                            Write-Host "Please configure cookies in settings.json and restart the script." -ForegroundColor Yellow
                            break
                        }
                        default {
                            break
                        }
                    }
                    
                    if ($userChoice -in @("new_url", "exit", "configure_cookies")) {
                        break
                    }
                }
            }
        }
        
        # If we still don't have video info, continue to next iteration
        if ($null -eq $videoInfo) {
            continue
        }
    }

    $downloadAnotherFormatForSameUrl = 'y' 
    $firstTimeShowingMenu = $true
    $downloadQueue = @()
    $queueOptionNumbers = @()
    
    # Phase 1: Build download queue
    do { 

        $formats = $videoInfo.formats
        
        # Show the new detailed formats menu only first time
        if ($firstTimeShowingMenu) {
            $menuOptions = Show-FormatsMenu -Formats $formats -VideoTitle $videoInfo.title
            $firstTimeShowingMenu = $false
        } else {
            Write-Host ""
            Write-Host "📊 " -NoNewline -ForegroundColor Yellow
            Write-Host "Current queue: $($downloadQueue.Count) item(s)" -ForegroundColor White
            if ($downloadQueue.Count -gt 0) {
                foreach ($qi in $downloadQueue) {
                    Write-Host "   ✓ $($qi.Description)" -ForegroundColor Green
                }
            }
            Write-Host ""
            Write-Host "💡 Enter a number to add, or type 'done' to start download" -ForegroundColor Cyan
            Write-Host "🔄 Type 'menu' to show the full format table again" -ForegroundColor Gray
            Write-Host "🗑️  Type 'clear' to clear the queue" -ForegroundColor Yellow
        }
        
        $maxOption = $menuOptions.Count
        Write-Host ""
        
        # Get user input
        do {
            $showMenuAgain = $false
            Write-Host "👉 Select an option: " -NoNewline -ForegroundColor Green
            $userInput = Read-Host " "
            
            if ($userInput.ToLower() -eq "menu") {
                $menuOptions = Show-FormatsMenu -Formats $formats -VideoTitle $videoInfo.title
                $maxOption = $menuOptions.Count
                $showMenuAgain = $true
                Write-Host ""
            } elseif ($userInput.ToLower() -eq "done") {
                if ($downloadQueue.Count -eq 0) {
                    Write-Host "Queue is empty! Please select at least one option." -ForegroundColor Red
                    $showMenuAgain = $true
                } else {
                    break
                }
            } elseif ($userInput.ToLower() -eq "clear") {
                $downloadQueue = @()
                $queueOptionNumbers = @()
                Write-Host "Queue cleared." -ForegroundColor Yellow
                $showMenuAgain = $true
            } elseif ($userInput -match "^\d+$") {
                $userSelectionInput = [int]$userInput
                if ($userSelectionInput -ge 1 -and $userSelectionInput -le $maxOption) {
                    break
                } else {
                    Write-Host "Please enter a number between 1 and $maxOption" -ForegroundColor Red
                    $showMenuAgain = $true
                }
            } else {
                Write-Host "Please enter a number, 'done', 'menu', or 'clear'" -ForegroundColor Red
                $showMenuAgain = $true
            }
        } while ($showMenuAgain)
        
        Write-Host ""

        if ($userInput.ToLower() -eq "done") {
            break
        }

        if ($null -eq $userSelectionInput) {
            Write-Host "No valid selection made. Returning to main menu..." -ForegroundColor Red
            break
        }
        
        $selectedOption = $menuOptions | Where-Object { $_.Number -eq $userSelectionInput }
        
        if (-not $selectedOption) {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Write-ErrorLog "Invalid selection: $userSelectionInput"
            continue
        }
        
        # Prevent duplicates
        if ($queueOptionNumbers -contains $userSelectionInput) {
            Write-Host "Option $userSelectionInput is already in the queue." -ForegroundColor Yellow
            continue
        }
        
        # Skip non-downloadable options for queue
        if ($selectedOption.Type -in @("cover", "new_link")) {
            Write-Host "Cannot add '$($selectedOption.Type)' to download queue." -ForegroundColor Yellow
            continue
        }
        
        $queueOptionNumbers += $userSelectionInput
        $downloadQueue += $selectedOption
        Write-Host "✓ Added: $($selectedOption.Description)" -ForegroundColor Green
        Write-ErrorLog "Added to queue: Option $userSelectionInput - Type: $($selectedOption.Type) - Format: $($selectedOption.Format.format_id)"
        
    } while ($true)
    
    # Phase 2: Process download queue
    if ($downloadQueue.Count -gt 0) {
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                        STARTING BATCH DOWNLOAD                               ║" -ForegroundColor Cyan
        Write-Host "║                        $($downloadQueue.Count) item(s) in queue" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        
        $downloadResults = @()
        $batchSuccessCount = 0
        $batchFailCount = 0
        $batchTotalCount = $downloadQueue.Count
        
        for ($qi = 0; $qi -lt $downloadQueue.Count; $qi++) {
            $selectedOption = $downloadQueue[$qi]
            $queueNum = $qi + 1
            
            Write-Host ""
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
            Write-Host "[$queueNum/$batchTotalCount] " -NoNewline -ForegroundColor Yellow
            Write-Host "$($selectedOption.Description)" -ForegroundColor White
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
            
            Write-ErrorLog "Processing queue item $queueNum/$batchTotalCount - Option $($selectedOption.Number) - Type: $($selectedOption.Type)"
        
            $isVideoDownload = $false
            $ytDlpArgsForDownload = $null
            $formatStringForDownload = ""
            $downloadType = ""

            switch ($selectedOption.Type) {
                "best" {
                    $highestBitrateResult = Get-HighestBitrateFormat -Formats $formats
                    $formatStringForDownload = $highestBitrateResult.FormatString
                    $qualityPrefix = Get-QualityPrefix -Type "best" -SelectedOption $highestBitrateResult
                    $ytdlpOutputTemplate = Join-Path -Path $scriptDir -ChildPath "Temp\$qualityPrefix %(title)s.%(ext)s"
                    
                    Write-Host "  Format: $formatStringForDownload" -ForegroundColor Gray
                    
                    $downloadType = if ($highestBitrateResult.IsCombined) { "original_video" } else { "video" }
                    $ytDlpArgsForDownload = New-DownloadArguments -FfmpegPath $ffmpegPath -OutputTemplate $ytdlpOutputTemplate -Format $formatStringForDownload -Url $currentUrl -Type $downloadType -UseCookies $useCookies -CookieFilePath $cookieFilePath
                    
                    $isVideoDownload = $true
                }

                "combined" {
                    $formatStringForDownload = $selectedOption.Format.format_id
                    $qualityPrefix = Get-QualityPrefix -Type "combined" -SelectedOption $selectedOption
                    $ytdlpOutputTemplate = Join-Path -Path $scriptDir -ChildPath "Temp\$qualityPrefix %(title)s.%(ext)s"
                    $selectedExt = $selectedOption.Format.ext
                    Write-Host "  Format: $formatStringForDownload ($selectedExt)" -ForegroundColor Gray
                    
                    $downloadType = if ($selectedExt -eq "mp4") { "force_mp4" } else { "original_video" }
                    $ytDlpArgsForDownload = New-DownloadArguments -FfmpegPath $ffmpegPath -OutputTemplate $ytdlpOutputTemplate -Format $formatStringForDownload -Url $currentUrl -Type $downloadType -UseCookies $useCookies -CookieFilePath $cookieFilePath
                    $isVideoDownload = $true
                }

                "specific_video" {
                    $formatStringForDownload = $selectedOption.Format.format_id
                    $qualityPrefix = Get-QualityPrefix -Type "specific_video" -SelectedOption $selectedOption
                    $ytdlpOutputTemplate = Join-Path -Path $scriptDir -ChildPath "Temp\$qualityPrefix %(title)s.%(ext)s"
                    Write-Host "  Format: $formatStringForDownload" -ForegroundColor Gray
                    
                    $downloadType = "video"
                    $ytDlpArgsForDownload = New-DownloadArguments -FfmpegPath $ffmpegPath -OutputTemplate $ytdlpOutputTemplate -Format $formatStringForDownload -Url $currentUrl -Type $downloadType -UseCookies $useCookies -CookieFilePath $cookieFilePath
                    $isVideoDownload = $true
                }

                "mp3_conversion" {
                    $formatStringForDownload = $selectedOption.Format.format_id
                    $qualityPrefix = Get-QualityPrefix -Type "mp3_conversion" -SelectedOption $selectedOption
                    $ytdlpOutputTemplate = Join-Path -Path $scriptDir -ChildPath "Temp\$qualityPrefix %(title)s.%(ext)s"
                    $bitrate = if ($selectedOption.Format.abr) { [int]$selectedOption.Format.abr } else { 192 }
                    Write-Host "  Format: $formatStringForDownload -> MP3 ${bitrate}kbps" -ForegroundColor Gray
                    
                    $downloadType = "audio"
                    $ytDlpArgsForDownload = New-DownloadArguments -FfmpegPath $ffmpegPath -OutputTemplate $ytdlpOutputTemplate -Format $formatStringForDownload -Url $currentUrl -Type $downloadType -Bitrate $bitrate -UseCookies $useCookies -CookieFilePath $cookieFilePath
                    $isVideoDownload = $false
                }

                "specific_audio" {
                    $formatStringForDownload = $selectedOption.Format.format_id
                    $qualityPrefix = Get-QualityPrefix -Type "specific_audio" -SelectedOption $selectedOption
                    $ytdlpOutputTemplate = Join-Path -Path $scriptDir -ChildPath "Temp\$qualityPrefix %(title)s.%(ext)s"
                    $bitrate = if ($selectedOption.Format.abr) { [int]$selectedOption.Format.abr } else { 128 }
                    Write-Host "  Format: $formatStringForDownload -> MP3" -ForegroundColor Gray
                    
                    $downloadType = "audio_specific"
                    $ytDlpArgsForDownload = New-DownloadArguments -FfmpegPath $ffmpegPath -OutputTemplate $ytdlpOutputTemplate -Format $formatStringForDownload -Url $currentUrl -Type $downloadType -Bitrate $bitrate -UseCookies $useCookies -CookieFilePath $cookieFilePath
                    $isVideoDownload = $false
                }

                "original_audio" {
                    $formatStringForDownload = $selectedOption.Format.format_id
                    $qualityPrefix = Get-QualityPrefix -Type "original_audio" -SelectedOption $selectedOption
                    $ytdlpOutputTemplate = Join-Path -Path $scriptDir -ChildPath "Temp\$qualityPrefix %(title)s.%(ext)s"
                    Write-Host "  Format: $formatStringForDownload (original)" -ForegroundColor Gray
                    
                    $downloadType = "original_audio"
                    $ytDlpArgsForDownload = New-DownloadArguments -FfmpegPath $ffmpegPath -OutputTemplate $ytdlpOutputTemplate -Format $formatStringForDownload -Url $currentUrl -Type $downloadType -UseCookies $useCookies -CookieFilePath $cookieFilePath
                    $isVideoDownload = $false
                }
            }
            
            if ($null -eq $ytDlpArgsForDownload) {
                Write-Host "  ⚠ Could not generate download arguments. Skipping." -ForegroundColor Red
                $batchFailCount++
                $downloadResults += @{ Success = $false; Description = $selectedOption.Description; Error = "Could not generate arguments" }
                continue
            }

            Write-ErrorLog "Executing Download: `"$ytDlpPath`" $($ytDlpArgsForDownload -join ' ')"
            $downloadResult = Invoke-YtDlpSimple -YtDlpPath $ytDlpPath -YtDlpArguments $ytDlpArgsForDownload
            
            $exitCodeDownload = $downloadResult.ExitCode
            $downloadProcessOutputLines = $downloadResult.Output
            
            if ($downloadResult.Error.Count -gt 0) {
                $errorLogMessage = $downloadResult.Error -join [System.Environment]::NewLine
                Write-ErrorLog "Errors captured during yt-dlp execution: $errorLogMessage"
            }
            
            if ($exitCodeDownload -eq 0) {
                Write-Host "  ✓ Download completed successfully!" -ForegroundColor Green
                $batchSuccessCount++
                $downloadResults += @{ Success = $true; Description = $selectedOption.Description; Error = $null }
                
                # Find and move the downloaded file
                $downloadOutputStringForParsing = $downloadProcessOutputLines -join [System.Environment]::NewLine
                $downloadedFileInTemp = $null
                $tempFilesList = Get-ChildItem -Path $tempDir -File -ErrorAction SilentlyContinue
                
                $expectedFileExtension = switch ($selectedOption.Type) {
                    "best" { ".mp4" }
                    "combined" { "." + $selectedOption.Format.ext }
                    "specific_video" { "." + $selectedOption.Format.ext }
                    "mp3_conversion" { ".mp3" }
                    "specific_audio" { ".mp3" }
                    "original_audio" { "." + $selectedOption.Format.ext }
                    default { if ($isVideoDownload) { ".mp4" } else { ".mp3" } }
                }
                
                $qualityPrefixForSearch = Get-QualityPrefix -Type $selectedOption.Type -SelectedOption $selectedOption
                if ($tempFilesList) {
                    foreach ($fileInTempDir in $tempFilesList) {
                        $fileName = $fileInTempDir.Name
                        if ($fileName.EndsWith($expectedFileExtension) -and $fileName.StartsWith($qualityPrefixForSearch)) {
                            $downloadedFileInTemp = $fileInTempDir.FullName
                            break
                        }
                    }
                }
                
                if (-not $downloadedFileInTemp) {
                    $patternForMethod2 = if ($isVideoDownload) {
                        [regex]'\[Merger\] Merging formats into "(?<FileNameFromOutput>.*?)"'
                    } else {
                        [regex]'\[ExtractAudio\] Destination: (?<FileNameFromOutput>.*?)$'
                    }
                    $matchMethod2 = $patternForMethod2.Match($downloadOutputStringForParsing)
                    if (-not $matchMethod2.Success) {
                        $patternForMethod2 = [regex]'\[ffmpeg\] Destination: (?<FileNameFromOutput>.*?)$'
                        $matchMethod2 = $patternForMethod2.Match($downloadOutputStringForParsing)
                    }
                    if ($matchMethod2.Success) {
                        $filePathFromRegex = $matchMethod2.Groups["FileNameFromOutput"].Value.Trim()
                        if (Test-Path -LiteralPath $filePathFromRegex) {
                            $downloadedFileInTemp = $filePathFromRegex
                        }
                    }
                }
                
                if (-not $downloadedFileInTemp -and $tempFilesList) {
                    foreach ($fileInTempDir in $tempFilesList) {
                        if ($fileInTempDir.Name.StartsWith($qualityPrefixForSearch)) {
                            $downloadedFileInTemp = $fileInTempDir.FullName
                            break
                        }
                    }
                    if (-not $downloadedFileInTemp) {
                        foreach ($fileInTempDir in $tempFilesList) {
                            if ($fileInTempDir.Name.EndsWith($expectedFileExtension)) {
                                $downloadedFileInTemp = $fileInTempDir.FullName
                                break
                            }
                        }
                    }
                }
                
                if ($downloadedFileInTemp -and (Test-Path -LiteralPath $downloadedFileInTemp)) {
                    $originalFileName = Split-Path -Path $downloadedFileInTemp -Leaf
                    $destinationDir = if ($isVideoDownload) { $videoOutputDir } else { $audioOutputDir }
                    $tempDestinationPath = Join-Path $destinationDir $originalFileName
                    $baseNameForDedup = [System.IO.Path]::GetFileNameWithoutExtension($originalFileName)
                    $extensionForDedup = [System.IO.Path]::GetExtension($originalFileName)
                    $counterForDedup = 1
                    $finalDestinationPath = Join-Path $destinationDir "$($baseNameForDedup)_$($counterForDedup)$($extensionForDedup)"
                    while (Test-Path -LiteralPath $finalDestinationPath) {
                        $counterForDedup++
                        $finalDestinationPath = Join-Path $destinationDir "$($baseNameForDedup)_$($counterForDedup)$($extensionForDedup)"
                    }
                    
                    try {
                        Move-Item -LiteralPath $downloadedFileInTemp -Destination $finalDestinationPath -Force -ErrorAction Stop
                        Write-Host "  📁 Saved: $finalDestinationPath" -ForegroundColor Cyan
                    } catch {
                        Write-Host "  ⚠ Failed to move file: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  ⚠ Download completed but file not found in Temp" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  ✗ Download failed (Exit code: $exitCodeDownload)" -ForegroundColor Red
                $batchFailCount++
                $downloadResults += @{ Success = $false; Description = $selectedOption.Description; Error = "Exit code: $exitCodeDownload" }
                
                # Check for bot detection
                $isBotError = ($downloadProcessOutputLines -join ' ') -match "Sign in to confirm you.*not a bot|cookies.*authentication|HTTP Error 403|Forbidden"
                if ($isBotError) {
                    Write-Host "  YouTube bot detection triggered. Try running browser login first." -ForegroundColor Yellow
                }
            }
        }
        
        # Batch summary
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                         BATCH DOWNLOAD SUMMARY                               ║" -ForegroundColor Cyan
        Write-Host "╠═══════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        Write-Host "║  Total: $batchTotalCount  |  ✓ Success: $batchSuccessCount  |  ✗ Failed: $batchFailCount" -ForegroundColor $(if ($batchFailCount -eq 0) { "Green" } else { "Yellow" })
        Write-Host "╠═══════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        foreach ($result in $downloadResults) {
            $icon = if ($result.Success) { "✓" } else { "✗" }
            $color = if ($result.Success) { "Green" } else { "Red" }
            Write-Host "║  $icon $($result.Description)" -ForegroundColor $color
        }
        Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        
        # Open download folder once
        if ($batchSuccessCount -gt 0) {
            try {
                Write-Host ""
                Write-Host "🔍 Opening download folder..." -ForegroundColor Green
                $folderToOpen = if ($downloadResults | Where-Object { $_.Success -and $_.Description -match "audio|mp3|MP3" }) { $audioOutputDir } else { $videoOutputDir }
                if (Test-Path $folderToOpen) {
                    Start-Process -FilePath "explorer.exe" -ArgumentList "`"$folderToOpen`"" -ErrorAction SilentlyContinue
                }
            } catch {
                Write-ErrorLog "Failed to open folder: $($_.Exception.Message)"
            }
        }
    }

    Write-Host ""
    Write-Host "─────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    $userContinueChoiceWithNewLink = Get-ValidatedUserInput -Prompt "🆕 Download from a NEW URL? (y/n):" -InputType "yesno" -MaxAttempts 3
    Write-ErrorLog "User response for new URL: $userContinueChoiceWithNewLink"
    if ($userContinueChoiceWithNewLink -eq 'n' -or $null -eq $userContinueChoiceWithNewLink) {
        $continueWithNewLink = 'n' 
    }

} while ($continueWithNewLink.ToLower() -eq 'y') 
# Cleanup temporary files if enabled
if ([bool]$settings.advanced.cleanup_temp_files) {
    try {
        $tempFiles = Get-ChildItem -Path $tempDir -File -ErrorAction SilentlyContinue
        if ($tempFiles) {
            foreach ($file in $tempFiles) {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
            Write-Host "Cleaned up temporary files." -ForegroundColor Green
            Write-ErrorLog "Cleaned up $($tempFiles.Count) temporary files"
        }
    } catch {
        Write-ErrorLog "Failed to cleanup temporary files: $($_.Exception.Message)"
    }
}

$Host.UI.RawUI.BackgroundColor = $originalBackground
$Host.UI.RawUI.ForegroundColor = $originalForeground
Clear-Host

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "║                              Thank you for using                              ║" -ForegroundColor Yellow
Write-Host "║                       Universal Video Downloader by MBNPRO                    ║" -ForegroundColor White
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "║                               See you next time!                              ║" -ForegroundColor Green
Write-Host "║                                                                               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-ErrorLog "Script session ended gracefully."
Write-SessionEndLog
