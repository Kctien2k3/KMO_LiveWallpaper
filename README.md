# 🎬 KMO_LiveWallpaper (macOS & Windows Native Live Wallpaper)

Ứng dụng **`KMO_LiveWallpaper`** siêu nhẹ, tối ưu phần cứng độc quyền dành cho cả **macOS** (100% Native Swift `AVFoundation` + `VideoToolbox`) và **Windows 10/11** (100% Native C# WPF `Media Foundation` + `WorkerW`).

---

## ✨ Điểm nổi bật & Cam kết hiệu năng (macOS & Windows)

| Tính năng | Chi tiết kỹ thuật & Lợi ích thực tế |
| :--- | :--- |
| **🛡️ An toàn tuyệt đối cho màn hình** | Đồng bộ nhịp quét VSync (`60Hz` / `120Hz` ProMotion), khóa dải màu SDR chuẩn, không gây chớp hình hay kích xung nhiệt đèn nền màn hình. |
| **⚡ Siêu nhẹ All-in-One (`≤ 5% CPU & ≤ 80MB RAM`)** | Giải mã phần cứng trực tiếp qua chip Media Engine (Apple Silicon) hoặc DXVA2/D3D11 GPU Video Engine (NVIDIA/Intel/AMD trên Windows), không sinh tiến trình rác. |
| **🧠 Tự động dừng thông minh (`0.0% CPU`)** | Tự ngắt giải mã về `0.0% CPU` khi cửa sổ làm việc chiếm **trên 90% màn hình**, khi mở phần mềm Edit chuyên nghiệp (Adobe Premiere, After Effects, Photoshop, DaVinci Resolve, Final Cut, CapCut...), hoặc khi **Khóa màn hình (Lock Screen) / Sleep / Gập máy**. |
| **🌊 Chuyển cảnh mượt mà 0% khựng hình** | Phát lại tức thì (`0ms`) khi về Desktop và dừng mượt (`0.45s` debounce) sau khi hiệu ứng thu/phóng cửa sổ hoặc chuyển Desktop hoàn tất. |
| **📺 Tự động Fit màn hình TV / Multi-Monitor** | Tự động nhận diện thay đổi tỷ lệ khi cắm cáp HDMI hoặc chiếu không dây (AirPlay / Miracast) lên TV, lấp đầy tràn viền 100% không để dải đen. |
| **🎛️ Giao diện Cài đặt trực quan** | Tuỳ chỉnh độ phân giải (`1080p`, `2K QHD`, `4K Gốc`), tỷ lệ khung hình (`Lấp đầy`, `Vừa khít`, `Kéo giãn`), thu phóng (`Zoom`) và dịch chuyển ngang/dọc trực quan. |

---

## 🍎 Dành cho macOS (MacBook, Mac mini, Mac Studio, iMac)

Đã đóng gói sẵn **`KMO_LiveWallpaper.app`** (Universal Binary chạy được trên cả Mac chip M và Intel):

### Cách 1: Cài đặt tự động bằng 1 cú nhấp đúp (Khuyên dùng)
1. Tải thư mục này về máy (bấm **Code -> Download ZIP** trên GitHub rồi giải nén, hoặc `git clone`).
2. Nhấp đúp chuột vào file **`CaiDat.command`** (nếu Mac hỏi quyền mở lần đầu, bấm **Chuột phải vào `CaiDat.command` -> chọn Open / Mở**).
3. Ứng dụng sẽ tự động được chép vào thư mục `/Applications`, gỡ cảnh báo tải mạng và mở lên ngay!

### Cách 2: Kéo thả thủ công
1. Kéo trực tiếp biểu tượng **`KMO_LiveWallpaper.app`** (hoặc giải nén từ `KMO_LiveWallpaper-macOS-Universal.zip`) vào thư mục **`Applications` (Ứng dụng)** của Mac.
2. Mở ứng dụng từ Launchpad hoặc `/Applications`, bấm **`Chọn...`** để chọn video yêu thích!

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
