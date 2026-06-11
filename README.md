<div align="center">
  <img src="https://img.shields.io/badge/PowerShell-%3E%3D5.1-blue?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell"/>
  <img src="https://img.shields.io/badge/Windows-7%20%7C%2010%20%7C%2011-brightgreen?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/Version-1.0-orange?style=for-the-badge&logo=github&logoColor=white" alt="Version"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge&logo=mit&logoColor=white" alt="License"/>
  <br/>
  <br/>
  <img src="logo.ico" width="100" alt="UVD Logo"/>
  <h1>UVD - Universal Video Downloader</h1>
  <p><strong>Download from YouTube, TikTok, Instagram, Twitter, Facebook, Twitch, Vimeo, SoundCloud, Reddit & 1800+ sites</strong></p>
  <p>PowerShell-based video downloader with smart features, multi-download queue, and anti-bot protection.</p>
  
  [![GitHub stars](https://img.shields.io/github/stars/MBNpro-ir/UVD?style=social)](https://github.com/MBNpro-ir/UVD/stargazers)
  [![GitHub forks](https://img.shields.io/github/forks/MBNpro-ir/UVD?style=social)](https://github.com/MBNpro-ir/UVD/network/members)
  [![GitHub issues](https://img.shields.io/github/issues/MBNpro-ir/UVD)](https://github.com/MBNpro-ir/UVD/issues)
  [![GitHub pull requests](https://img.shields.io/github/issues-pr/MBNpro-ir/UVD)](https://github.com/MBNpro-ir/UVD/pulls)
  
  <br/>
  
  [![Telegram](https://img.shields.io/badge/Telegram-@mbnproo-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/mbnproo)
  [![GitHub Release](https://img.shields.io/github/v/release/MBNpro-ir/UVD?style=for-the-badge)](https://github.com/MBNpro-ir/UVD/releases/latest)
</div>

---

## Quick Install

Open CMD or PowerShell and run:

**CMD:**
```cmd
curl -o uvd.bat https://github.com/MBNpro-ir/UVD/raw/refs/heads/master/uvd.bat && uvd.bat
```

**PowerShell:**
```powershell
curl.exe -o uvd.bat https://github.com/MBNpro-ir/UVD/raw/refs/heads/master/uvd.bat; .\uvd.bat
```

This will:
1. Download `uvd.bat` to your current folder
2. Auto-download `uvd.ps1` and dependencies
3. Create a desktop shortcut with the UVD logo
4. Launch the downloader

---

## Supported Sites

UVD supports **1800+ websites** via [yt-dlp](https://github.com/yt-dlp/yt-dlp). Major platforms include:

| Platform | Support |
|---|---|
| YouTube | Videos, playlists, channels, live streams, shorts |
| TikTok | Videos, user profiles, live streams |
| Instagram | Videos, stories, reels |
| Twitter/X | Videos, spaces |
| Facebook | Videos, reels, stories |
| Twitch | VODs, clips, live streams |
| Vimeo | Videos, albums, channels |
| SoundCloud | Tracks, playlists, users |
| Reddit | Videos and media posts |
| Dailymotion | Videos, playlists, users |
| + 1800 more | Via yt-dlp extractors |

---

## Features

| Feature | Description |
|---|---|
| **Multi-Site Support** | Download from 1800+ websites |
| **Video Download** | Download in any quality from 144p to 8K |
| **Audio Extraction** | Extract audio as MP3 (128/256/320 kbps) |
| **Multi-Download Queue** | Select multiple qualities, download all at once |
| **Batch Download Summary** | Progress for each download + final summary |
| **Thumbnail Download** | Save video thumbnails in original quality |
| **Auto-Updates** | Automatically updates yt-dlp and ffmpeg |
| **Smart Error Handling** | Intelligent error messages with solutions |
| **Cookie Support** | Download age-restricted and private content |
| **Browser Login** | Extract cookies directly from Chrome/Edge/Firefox |
| **Anti-Bot Protection** | Built-in bypass for YouTube bot detection |
| **Proxy Support** | System proxy auto-detection and custom proxy |
| **Video Cache** | Caches metadata for faster repeated downloads |

---

## System Requirements

| Requirement | Details |
|---|---|
| **Operating System** | Windows 7, 8, 10, or 11 |
| **PowerShell** | Version 5.1 or newer |
| **winget** (optional) | For automatic official installation |
| **Internet** | Active internet connection |
| **Disk Space** | ~50MB for dependencies |

---

## Usage

### Basic Usage

1. **Launch UVD** - Double-click `uvd.bat` or use the desktop shortcut
2. **Paste URL** - Enter any video URL when prompted
3. **Select Format** - Choose your preferred download format
4. **Multi-Download** - Add multiple qualities to queue, type `done` to start
5. **Wait** - UVD will download and organize your files automatically

### Available Commands

| Command | Description |
|---|---|
| `help` or `-h` | Show detailed help guide |
| `exit` | Exit the program |
| `restart` | Restart the application |
| `clear-cache` | Clear video information cache |
| `folder` | Open program folder |
| `downloads` | Open downloads folder |
| `settings` | Open settings file |

### Multi-Download Queue

1. Select a quality option (e.g., `2`)
2. Add more options (e.g., `4`, `22`)
3. Type `done` when ready
4. All downloads start with progress for each
5. Summary shown at the end

---

## Configuration

### File Structure

```
UVD/
├── uvd.ps1              # Main script
├── settings.json        # Configuration file
├── cookies.txt          # Browser cookies (optional)
├── yt-dlp.exe           # Video downloader engine
├── ffmpeg.exe           # Media processing tool
├── video_cache.json     # Video metadata cache
├── Temp/                # Temporary files
└── Downloaded/          # Your downloads
    ├── Video/
    ├── Audio/
    └── Covers/
```

### Settings Reference

#### General Settings

| Setting | Default | Description |
|---|---|---|
| `request_timeout_seconds` | `20` | Timeout for server requests |
| `max_retries` | `3` | Number of retry attempts |
| `show_processing_messages` | `true` | Show detailed progress |
| `use_database_cache` | `true` | Cache video metadata |

#### Download Settings

| Setting | Default | Description |
|---|---|---|
| `output_directory` | `"Downloaded"` | Main download folder |
| `temp_directory` | `"Temp"` | Temporary files folder |
| `video_subdirectory` | `"Video"` | Video output folder |
| `audio_subdirectory` | `"Audio"` | Audio output folder |
| `covers_subdirectory` | `"Covers"` | Thumbnail output folder |

#### Optimization Settings (Anti-Bot)

| Setting | Default | Description |
|---|---|---|
| `enable_optimization` | `true` | Enable all optimization features |
| `concurrent_fragments` | `4` | Fragments to download simultaneously |
| `fragment_retries` | `10` | Retry attempts for failed fragments |
| `sleep_requests` | `1` | Sleep between requests (rate limiting) |
| `sleep_interval` | `3` | Random sleep interval minimum |
| `max_sleep_interval` | `7` | Random sleep interval maximum |
| `extractor_args` | `"youtube:player_client=web,android_vr,tv_downgraded"` | Anti-bot extractor args |
| `extractor_retries` | `3` | Retries for extractor errors |

#### Proxy Settings

| Setting | Default | Description |
|---|---|---|
| `use_system_proxy` | `true` | Auto-detect system proxy |
| `custom_proxy_enabled` | `false` | Use custom proxy |
| `custom_proxy_host` | `""` | Proxy server address |
| `custom_proxy_port` | `""` | Proxy server port |

#### Cookie Settings

| Setting | Default | Description |
|---|---|---|
| `use_cookies` | `false` | Enable cookie authentication |
| `cookie_file_path` | `"cookies.txt"` | Cookie file name |
| `cookie_file_directory` | `""` | Custom cookie folder |
| `cookie_source` | `""` | Browser for `--cookies-from-browser` (chrome/edge/firefox) |

---

## Troubleshooting

| Error | Cause | Solution |
|---|---|---|
| **Sign in to confirm you're not a bot** | YouTube bot detection | Use browser login (option 2 in error menu) |
| **403 Forbidden** | Age-restricted or private video | Use cookies from browser |
| **429 Too Many Requests** | Rate limiting | Wait 15-30 minutes |
| **404 Not Found** | Video deleted or wrong URL | Check the URL |
| **Permission Denied** | Write access denied | Run as administrator |
| **Missing Codec** | ffmpeg issue | Delete Temp folder to force re-download |

### Debug Mode

Enable debug logging in `settings.json`:
```json
{
  "advanced": {
    "enable_debug_logging": true
  }
}
```

Check `debug.txt` for detailed error information.

---

## Contributing

### Bug Reports

[Open an issue](https://github.com/MBNpro-ir/UVD/issues) with:
- Error message
- Steps to reproduce
- System information

### Feature Requests

[Create an issue](https://github.com/MBNpro-ir/UVD/issues) with the `enhancement` label.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - Core downloading engine (1800+ site support)
- [ffmpeg](https://ffmpeg.org/) - Media processing framework
- [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) - Windows ffmpeg builds

---

<div align="center">
  <strong>Made with ❤️ by MBNPRO</strong>
  <br/>
  <a href="https://t.me/mbnproo">Telegram: @mbnproo</a>
  <br/>
  <br/>
  <a href="README-fa.md">خواندن این راهنما به فارسی</a>
</div>
