<div dir="rtl" align="center">
  <img src="https://img.shields.io/badge/PowerShell-%3E%3D5.1-blue?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell"/>
  <img src="https://img.shields.io/badge/Windows-7%20%7C%2010%20%7C%2011-brightgreen?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/Version-1.0-orange?style=for-the-badge&logo=github&logoColor=white" alt="Version"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge&logo=mit&logoColor=white" alt="License"/>
  <br/>
  <br/>
  <img src="logo.ico" width="100" alt="UVD Logo"/>
  <h1>UVD - دانلودر جهانی ویدیو</h1>
  <p><strong>دانلود از یوتیوب، تیکتاک، اینستاگرام، توییتر، فیسبوک، توییچ، ویمئو، ساندکلاد، ردیت و بیش از ۱۸۰۰ سایت</strong></p>
  <p>دانلودر ویدیوی مبتنی بر PowerShell با امکانات هوشمند، صف دانلود چندگانه و محافظت ضدبات.</p>
  
  [![GitHub stars](https://img.shields.io/github/stars/MBNpro-ir/UVD?style=social)](https://github.com/MBNpro-ir/UVD/stargazers)
  [![GitHub forks](https://img.shields.io/github/forks/MBNpro-ir/UVD?style=social)](https://github.com/MBNpro-ir/UVD/network/members)
  [![GitHub issues](https://img.shields.io/github/issues/MBNpro-ir/UVD)](https://github.com/MBNpro-ir/UVD/issues)
  
  <br/>
  
  [![Telegram](https://img.shields.io/badge/Telegram-@mbnproo-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/mbnproo)
  [![GitHub Release](https://img.shields.io/github/v/release/MBNpro-ir/UVD?style=for-the-badge)](https://github.com/MBNpro-ir/UVD/releases/latest)
</div>

---

## نصب سریع

CMD یا PowerShell را باز کنید و این دستور را اجرا کنید:

**CMD:**
```cmd
curl -o uvd.bat https://github.com/MBNpro-ir/UVD/raw/refs/heads/master/uvd.bat && uvd.bat
```

**PowerShell:**
```powershell
curl.exe -o uvd.bat https://github.com/MBNpro-ir/UVD/raw/refs/heads/master/uvd.bat; .\uvd.bat
```

این کار:
1. فایل `uvd.bat` را در پوشه فعلی دانلود می‌کند
2. `uvd.ps1` و وابستگی‌ها را به صورت خودکار دانلود می‌کند
3. یک میانبر دسکتاپ با لوگوی UVD ایجاد می‌کند
4. دانلودر را اجرا می‌کند

---

## سایت‌های پشتیبانی شده

UVD از **بیش از ۱۸۰۰ وب‌سایت** از طریق [yt-dlp](https://github.com/yt-dlp/yt-dlp) پشتیبانی می‌کند. پلتفرم‌های اصلی:

| پلتفرم | پشتیبانی |
|---|---|
| یوتیوب | ویدیو، پلی‌لیست، کانال، لایو استریم، شورتز |
| تیکتاک | ویدیو، پروفایل کاربر، لایو استریم |
| اینستاگرام | ویدیو، استوری، ریلز |
| توییتر/X | ویدیو، اسپیس‌ها |
| فیسبوک | ویدیو، ریلز، استوری |
| توییچ | VODها، کلیپ، لایو استریم |
| ویمئو | ویدیو، آلبوم، کانال |
| ساندکلاد | ترک‌ها، پلی‌لیست، کاربران |
| ردیت | ویدیو و پست‌های مدیا |
| دیلیموشن | ویدیو، پلی‌لیست، کاربران |
| + ۱۸۰۰ سایت دیگر | از طریق اکسترکتورهای yt-dlp |

---

## امکانات

| امکان | توضیح |
|---|---|
| **پشتیبانی چندسایتی** | دانلود از بیش از ۱۸۰۰ وب‌سایت |
| **دانلود ویدیو** | دانلود در هر کیفیت از 144p تا 8K |
| **استخراج صدا** | استخراج صدا به صورت MP3 (128/256/320 kbps) |
| **صف دانلود چندگانه** | انتخاب چند کیفیت، دانلود همه با هم |
| **خلاصه دانلود دسته‌ای** | پیشرفت هر دانلود + خلاصه نهایی |
| **دانلود تصویر کوچک** | ذخیره تصاویر کوچک ویدیو با کیفیت اصلی |
| **به‌روزرسانی خودکار** | به‌روزرسانی خودکار yt-dlp و ffmpeg |
| **مدیریت هوشمند خطا** | پیام‌های خطای هوشمند با راه حل‌ها |
| **پشتیبانی از Cookie** | دانلود محتوای محدود سنی و خصوصی |
| **ورود از مرورگر** | استخراج کوکی مستقیماً از کروم/اج‌فایرفاکس |
| **محافظت ضدبات** | دور زدن تشخیص بات یوتیوب |
| **پشتیبانی از پروکسی** | تشخیص خودکار پروکسی سیستم |
| **کش ویدیو** | کش متادیتا برای دانلودهای سریع‌تر |

---

## نیازمندی‌های سیستم

| نیازمندی | جزئیات |
|---|---|
| **سیستم عامل** | ویندوز 7، 8، 10 یا 11 |
| **PowerShell** | نسخه 5.1 یا جدیدتر |
| **winget** (اختیاری) | برای نصب رسمی خودکار |
| **اینترنت** | اتصال اینترنت فعال |
| **فضای دیسک** | حدود 50 مگابایت برای وابستگی‌ها |

---

## راهنمای استفاده

### استفاده پایه

1. **اجرای UVD** - روی `uvd.bat` دوبار کلیک کنید یا از میانبر دسکتاپ استفاده کنید
2. **وارد کردن لینک** - آدرس هر ویدیویی را وارد کنید
3. **انتخاب فرمت** - فرمت دانلود مورد نظر خود را انتخاب کنید
4. **دانلود چندگانه** - چند کیفیت به صف اضافه کنید، `done` تایپ کنید
5. **صبر کنید** - UVD فایل‌ها را دانلود و سازماندهی می‌کند

### دستورات موجود

| دستور | توضیح |
|---|---|
| `help` یا `-h` | نمایش راهنمای کامل |
| `exit` | خروج از برنامه |
| `restart` | راه‌اندازی مجدد برنامه |
| `clear-cache` | پاک کردن کش متادیتا |
| `folder` | باز کردن پوشه برنامه |
| `downloads` | باز کردن پوشه دانلودها |
| `settings` | باز کردن فایل تنظیمات |

### صف دانلود چندگانه

1. یک گزینه کیفیت انتخاب کنید (مثلاً `2`)
2. گزینه‌های بیشتری اضافه کنید (مثلاً `4`، `22`)
3. `done` تایپ کنید وقتی آماده شدید
4. همه دانلودها با پیشرفت شروع می‌شوند
5. خلاصه در انتها نمایش داده می‌شود

---

## تنظیمات

### ساختار فایل‌ها

```
UVD/
├── uvd.ps1              # اسکریپت اصلی
├── settings.json        # فایل پیکربندی
├── cookies.txt          # کوکی‌های مرورگر (اختیاری)
├── yt-dlp.exe           # موتور دانلود ویدیو
├── ffmpeg.exe           # ابزار پردازش رسانه
├── video_cache.json     # کش متادیتا ویدیو
├── Temp/                # فایل‌های موقت
└── Downloaded/          # دانلودهای شما
    ├── Video/
    ├── Audio/
    └── Covers/
```

### راهنمای تنظیمات

#### تنظیمات عمومی

| تنظیم | پیش‌فرض | توضیح |
|---|---|---|
| `request_timeout_seconds` | `20` | مهلت زمانی درخواست‌ها به سرور |
| `max_retries` | `3` | تعداد تلاش‌های مجدد |
| `show_processing_messages` | `true` | نمایش پیشرفت تفصیلی |
| `use_database_cache` | `true` | کش متادیتا ویدیو |

#### تنظیمات بهینه‌سازی (ضدبات)

| تنظیم | پیش‌فرض | توضیح |
|---|---|---|
| `enable_optimization` | `true` | فعال کردن تمام ویژگی‌های بهینه‌سازی |
| `concurrent_fragments` | `4` | فرگمنت‌های همزمان |
| `fragment_retries` | `10` | تلاش مجدد فرگمنت‌های ناموفق |
| `sleep_requests` | `1` | تاخیر بین درخواست‌ها |
| `sleep_interval` | `3` | حداقل تصادفی تاخیر |
| `max_sleep_interval` | `7` | حداکثر تصادفی تاخیر |
| `extractor_args` | `"youtube:player_client=web,android_vr,tv_downgraded"` | آرگومان‌های ضدبات |
| `extractor_retries` | `3` | تلاش مجدد خطای اکسترکتور |

#### تنظیمات پروکسی

| تنظیم | پیش‌فرض | توضیح |
|---|---|---|
| `use_system_proxy` | `true` | تشخیص خودکار پروکسی سیستم |
| `custom_proxy_enabled` | `false` | استفاده از پروکسی سفارشی |
| `custom_proxy_host` | `""` | آدرس سرور پروکسی |
| `custom_proxy_port` | `""` | پورت سرور پروکسی |

#### تنظیمات کوکی

| تنظیم | پیش‌فرض | توضیح |
|---|---|---|
| `use_cookies` | `false` | فعال کردن احراز هویت کوکی |
| `cookie_file_path` | `"cookies.txt"` | نام فایل کوکی |
| `cookie_file_directory` | `""` | پوشه سفارشی کوکی |
| `cookie_source` | `""` | مرورگر برای `--cookies-from-browser` (chrome/edge/firefox) |

---

## عیب‌یابی

| خطا | دلیل | راه حل |
|---|---|---|
| **Sign in to confirm you're not a bot** | تشخیص بات یوتیوب | استفاده از ورود مرورگر (گزینه 2 در منوی خطا) |
| **403 Forbidden** | ویدیوی محدود سنی یا خصوصی | استفاده از کوکی مرورگر |
| **429 Too Many Requests** | محدودیت نرخ درخواست | 15-30 دقیقه صبر کنید |
| **404 Not Found** | ویدیو حذف شده یا آدرس اشتباه | آدرس را بررسی کنید |
| **Permission Denied** | دسترسی نوشتن رد شده | به عنوان مدیر اجرا کنید |
| **Missing Codec** | مشکل ffmpeg | پوشه Temp را پاک کنید |

### حالت دیباگ

ثبت لاگ دیباگ را در `settings.json` فعال کنید:
```json
{
  "advanced": {
    "enable_debug_logging": true
  }
}
```

فایل `debug.txt` را برای اطلاعات تفصیلی خطا بررسی کنید.

---

## مشارکت

### گزارش باگ

[مشکلی را گزارش کنید](https://github.com/MBNpro-ir/UVD/issues) با اطلاعات:
- پیام خطا
- مراحل بازتولید
- اطلاعات سیستم

### درخواست امکانات

[مشکلی ایجاد کنید](https://github.com/MBNpro-ir/UVD/issues) با برچسب `enhancement`.

---

## مجوز

این پروژه تحت مجوز MIT است - جزئیات را در فایل [LICENSE](LICENSE) ببینید.

---

## سپاسگزاری

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - موتور اصلی دانلود (پشتیبانی از ۱۸۰۰+ سایت)
- [ffmpeg](https://ffmpeg.org/) - چارچوب پردازش رسانه
- [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) - نسخه‌های ویندوز ffmpeg

---

<div align="center">
  <strong>ساخته شده با ❤️ توسط MBNPRO</strong>
  <br/>
  <a href="https://t.me/mbnproo">تلگرام: @mbnproo</a>
  <br/>
  <br/>
  <a href="README.md">Read this in English</a>
</div>
</div>
