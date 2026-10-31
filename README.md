# 🎬 KMO_LiveWallpaper (macOS & Windows Native Live Wallpaper)

Ứng dụng **`KMO_LiveWallpaper`** siêu nhẹ, tối ưu phần cứng độc quyền dành cho cả **macOS** (100% Native Swift `AVFoundation` + `VideoToolbox`) và **Windows 10/11** (100% Native C# WPF `Media Foundation` + `WorkerW`).

---

## ✨ Điểm nổi bật & Cam kết hiệu năng (macOS & Windows)

| Tính năng | Chi tiết kỹ thuật & Lợi ích thực tế |
| :--- | :--- |
| **🛡️ An toàn tuyệt đối cho màn hình** | Đồng bộ nhịp quét VSync (`60Hz` / `120Hz` ProMotion), khóa dải màu SDR chuẩn, không gây chớp hình hay kích xung nhiệt đèn nền màn hình. |
| **⚡ Siêu nhẹ All-in-One (`≤ 8% CPU & ≤ 80MB RAM`)** | Giải mã phần cứng trực tiếp qua Media Engine (Apple Silicon) hoặc DXVA2/D3D11 GPU Video Engine (Windows). Vùng đệm giảm tải mềm `5% - 8%` chống giật khựng. |
| **🧠 Tự động dừng thông minh (`0.0% CPU`)** | Tự ngắt giải mã về `0.0% CPU` khi cửa sổ làm việc chiếm **trên 90% màn hình**, khi mở phần mềm Edit chuyên nghiệp (Adobe Premiere, After Effects, Photoshop, DaVinci Resolve, Final Cut, CapCut...), hoặc khi **Khóa màn hình (Lock Screen) / Sleep / Gập máy**. |
| **🌊 Chuyển cảnh mượt mà 0% khựng hình** | Phát lại tức thì (`0ms`) khi về Desktop và dừng mượt (`0.45s` debounce) sau khi hiệu ứng thu/phóng cửa sổ hoặc chuyển Desktop hoàn tất. |
| **📺 Tự động Fit màn hình TV / Multi-Monitor** | Tự động nhận diện thay đổi tỷ lệ khi cắm cáp HDMI hoặc chiếu không dây (AirPlay / Miracast) lên TV, lấp đầy tràn viền 100% không để dải đen. |
| **🔒 Khóa màn hình (Lock Screen) & Screen Saver** | Hỗ trợ phát video trên Trình bảo vệ màn hình (Screen Saver) và cập nhật hình nền Màn hình khóa (Lock Screen). Hỗ trợ tuỳ chỉnh khung hình và màu sắc riêng biệt hoặc đồng bộ với màn hình chính. |
| **🎨 Bộ lọc màu sắc phần cứng (Direct Scanout)** | Tuỳ chỉnh Tương phản (Contrast: 80% - 130%) và Độ rực rỡ (Saturation: 50% - 150%). Tự động kích hoạt Zero-Copy Direct Scanout khi ở 100% để triệt tiêu toàn bộ gánh nặng GPU shader. |
| **🎛️ Giao diện Cài đặt trực quan** | Tuỳ chỉnh độ phân giải (`1080p`, `2K QHD`, `4K Gốc`), tốc độ khung hình (`30 FPS`, `60 FPS`, `120 FPS`), phạm vi (`🖥️ Màn chính` / `🔒 Khóa & Chờ`), tỷ lệ (`Lấp đầy`, `Vừa khít`, `Kéo giãn`), thu phóng (`Zoom`) và dịch chuyển ngang/dọc trực quan. |

---

## 🍎 Dành cho macOS (MacBook, Mac mini, Mac Studio, iMac)

Ứng dụng hỗ trợ Universal Binary chạy mượt trên cả chip Apple Silicon (M1/M2/M3/M4) lẫn Intel:

### Cách 1: Cài đặt tự động 1-Click bằng file `.pkg` (Khuyên dùng nhất - Tiện nhất)
1. Tải file **`KMO_LiveWallpaper-macOS-Installer.pkg`**.
2. Nhấp đúp chuột vào file `.pkg` và bấm **"Tiếp tục" ➔ "Cài đặt"**.
3. Hệ thống sẽ tự động chép vào `/Applications`, tự gỡ chặn Gatekeeper và tự khởi động ứng dụng ngay lập tức!

### Cách 2: Kéo thả trực quan bằng file `.dmg`
1. Tải file **`KMO_LiveWallpaper.dmg`**.
2. Nhấp đúp chuột để mở ổ đĩa ảo, kéo biểu tượng **`KMO_LiveWallpaper`** vào thư mục **`Applications`**.

### Cách 3: Chạy script `CaiDat.command` hoặc giải nén file `.zip`
- Giải nén `KMO_LiveWallpaper-macOS-Universal.zip` hoặc nhấp đúp file **`CaiDat.command`** trong thư mục mã nguồn.

---

## 🪟 Dành cho Windows (Windows 10 / Windows 11)

Mã nguồn nằm trong thư mục `windows/`, được xây dựng với cơ chế ghim tầng nền `WorkerW` của Windows Explorer:

### Cách 1: Chạy ngay từ file nén (Không cần cài đặt công cụ)
1. Tải file **`KMO_LiveWallpaper-Windows-x64.zip`** từ mục **Releases** / **Actions** trên GitHub.
2. Giải nén và nhấp đúp vào **`CaiDat.bat`** (hoặc chạy trực tiếp `KMO_LiveWallpaper.exe`).
3. Ứng dụng sẽ tự tạo lối tắt ngoài Desktop và xuất hiện dưới khay hệ thống (System Tray cạnh đồng hồ).

### Cách 2: Tự biên dịch từ mã nguồn
Nếu máy tính Windows của bạn đã cài đặt [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0):
```cmd
cd windows
build.bat
```
File thực thi độc lập duy nhất sẽ được tạo tại `windows\publish\KMO_LiveWallpaper.exe`.

---

## 🛠️ Biên dịch lại macOS từ mã nguồn

```bash
chmod +x build.sh
./build.sh
```
