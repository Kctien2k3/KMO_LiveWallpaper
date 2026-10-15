# 🎬 KMO_LiveWallpaper (macOS Native Live Wallpaper)

Ứng dụng **`KMO_LiveWallpaper` (`KMO_LiveWallpaper.app`)** siêu nhẹ, viết hoàn toàn bằng **100% Native Swift (`AVFoundation` + `VideoToolbox` + `IOSurface`)** dành riêng cho macOS (tối ưu đặc biệt cho màn hình **Liquid Retina XDR 120Hz ProMotion** và chip **Apple Silicon M1/M2/M3/M4** lẫn Intel).

---

## ✨ Điểm nổi bật & Cam kết an toàn màn hình

| Tính năng | Chi tiết kỹ thuật & Lợi ích thực tế |
| :--- | :--- |
| **🛡️ Bảo vệ tuyệt đối màn hình 120Hz ProMotion & mini-LED** | Khóa tốc độ chuẩn `1.0x`, đồng bộ nhịp quét VSync nguyên lần (`30fps` / `60fps`), khóa dải màu `.sRGB` ổn định và tắt kích sáng HDR/EDR đột ngột. |
| **⚡ Siêu nhẹ All-in-One (`≤ 5% CPU & ≤ 80MB RAM`)** | Giải mã phần cứng trực tiếp qua chip Media Engine của Apple, không gọi `ffmpeg` ngoài, không sinh tiến trình rác. |
| **🧠 Tự động dừng thông minh (`0.0% CPU`)** | Tự ngắt giải mã về `0.0% CPU` khi cửa sổ làm việc chiếm **trên 90% màn hình**, khi mở phần mềm Edit chuyên nghiệp (Adobe Premiere, After Effects, Photoshop, DaVinci Resolve, Final Cut, CapCut...), hoặc khi **Khóa màn hình / Screen Saver / Gập máy**. |
| **🌊 Chuyển cảnh mượt mà 0% khựng hình** | Phát lại tức thì (`0ms`) từ bộ đệm phần cứng khi về Desktop và dừng mượt (`0.45s` debounce) sau khi hiệu ứng thu/phóng cửa sổ hoặc vuốt chuyển Desktop hoàn tất. |
| **🎛️ Giao diện chuẩn macOS System Settings** | Tuỳ chỉnh độ phân giải (`1080p`, `2K QHD`, `4K Gốc`), tỷ lệ khung hình (`Lấp đầy`, `Vừa khít`, `Kéo giãn`), thu phóng (`Zoom`) và dịch chuyển ngang/dọc trực quan. |

---

## 🚀 Cách tải về và cài đặt trên máy Mac mới (Dành cho mọi người)

Trong kho lưu trữ này đã đóng gói sẵn ứng dụng **`KMO_LiveWallpaper.app`** (Universal Binary chạy được trên cả Mac chip M và chip Intel). Khi tải về máy mới, bạn chỉ cần làm **1 trong 2 cách** cực dễ sau:

### Cách 1: Cài đặt tự động bằng 1 cú nhấp đúp (Khuyên dùng)
1. Tải thư mục này về máy (bấm **Code -> Download ZIP** trên GitHub rồi giải nén, hoặc `git clone`).
2. Nhấp đúp chuột vào file **`CaiDat.command`** (nếu Mac hỏi quyền mở lần đầu, bấm **Chuột phải vào `CaiDat.command` -> chọn Open / Mở**).
3. Trình cài đặt sẽ tự động chép **`KMO_LiveWallpaper.app`** vào thư mục `/Applications`, gỡ cảnh báo tải mạng của macOS và mở sẵn ứng dụng lên cho bạn!

### Cách 2: Kéo thả thủ công
1. Kéo trực tiếp biểu tượng **`KMO_LiveWallpaper.app`** (hoặc giải nén từ `KMO_LiveWallpaper-macOS-Universal.zip`) vào thư mục **`Applications` (Ứng dụng)** của máy Mac.
2. Mở ứng dụng từ Launchpad hoặc thư mục `Applications`, bấm nút **`Chọn...`** để chọn bất kỳ video `.mp4` / `.mov` nào bạn thích làm hình nền!

---

## 🛠️ Biên dịch lại từ mã nguồn (Dành cho lập trình viên)

Nếu muốn tự biên dịch lại từ tệp mã nguồn duy nhất `main.swift`:

```bash
chmod +x build.sh
./build.sh
```
