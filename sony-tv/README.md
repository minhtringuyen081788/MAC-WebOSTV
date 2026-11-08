# Tối ưu TV Sony ở nhà khách

TV Sony đời mới chạy **Android TV / Google TV**. Có thể làm TV nhẹ hơn mà **không cần root**:

- **Không root, không flash ROM.** Sony khoá bootloader. Cố can thiệp dễ làm hỏng TV và mất bảo hành.
- **Dùng ADB** (công cụ chính thức của Android) để tắt app thừa và giảm hiệu ứng. Mọi thay đổi đều hoàn tác được.
- **TV không chung mạng với máy chủ** thì dùng **Tailscale**: một mạng riêng ảo miễn phí. Cài trên máy chủ và TV, đăng nhập cùng tài khoản là hai bên thấy nhau như đang chung mạng, dù ở hai nơi khác nhau.

```
 [Máy chủ / máy tính văn phòng]                  [TV Sony ở nhà khách]
   Tailscale: 100.x.x.1   ◄──── internet ────►      Tailscale: 100.x.x.2
   - phát nội dung cho TV                            - mở nội dung từ máy chủ
   - quản lý TV từ xa bằng ADB                       - không cần mở cổng router
```

---

## Bước 1: Chỉnh tay trên TV (5 phút, có hiệu quả rõ nhất)

| Việc | Đường dẫn trên TV |
|---|---|
| Tắt gợi ý/quảng cáo ở màn hình chính | **Google TV:** Cài đặt → Tài khoản và hồ sơ → bật **Chế độ chỉ dùng ứng dụng** (Apps only mode)<br>**Android TV đời cũ:** Cài đặt → Màn hình chính → tắt xem trước video và âm thanh |
| Không cho app tự cập nhật ngầm | Google Play → Cài đặt → Tự động cập nhật ứng dụng → **Không tự động cập nhật** |
| Gỡ app không dùng | Cài đặt → Ứng dụng → chọn app → Gỡ cài đặt |
| Tắt theo dõi nội dung (nếu TV có mục này) | Cài đặt → **Samba Interactive TV** → Tắt |
| Cập nhật phần mềm TV một lần lên bản mới nhất | Cài đặt → Hệ thống → Giới thiệu → Cập nhật phần mềm hệ thống |
| Khởi động lại định kỳ (mỗi tuần) | Giữ nút nguồn trên remote → **Khởi động lại** |

> Tên mục có thể khác chút tuỳ đời TV.

## Bước 2: Bật ADB trên TV (làm tại chỗ, một lần)

1. Cài đặt → Hệ thống → Giới thiệu (đời cũ: Cài đặt → Tuỳ chọn thiết bị → Giới thiệu).
2. Bấm **7 lần** vào dòng **Bản dựng** (Build) đến khi TV báo đã bật chế độ nhà phát triển.
3. Quay lại → **Tuỳ chọn nhà phát triển** → bật **Gỡ lỗi USB** (USB debugging). Trên TV Sony, mục này mở luôn ADB qua mạng.
4. Lần đầu máy tính kết nối, TV hiện hộp thoại **"Cho phép gỡ lỗi?"**. Tick **Luôn cho phép từ máy tính này** rồi bấm OK.
   Vì phải có người bấm trên TV nên **lần kết nối đầu tiên cần làm tại nhà khách**. Từ lần sau mới quản lý từ xa được.

## Bước 3: Cài Tailscale (xử lý chuyện không chung mạng)

1. **Máy chủ:** tải Tailscale tại tailscale.com/download (có bản cho Mac, Windows, Linux) và đăng nhập bằng tài khoản Google của công ty.
2. **TV:** mở Google Play trên TV → tìm **Tailscale** → cài đặt. Mở app, TV hiện mã QR hoặc đường link → dùng điện thoại mở ra và đăng nhập **cùng tài khoản**. Bấm đồng ý khi TV hỏi quyền VPN.
3. **Máy tính dùng để quản lý TV:** cũng cài Tailscale và đăng nhập cùng tài khoản.
4. Vào trang quản trị Tailscale (login.tailscale.com) để xem IP dạng `100.x.x.x` của TV và máy chủ.
5. Trên TV, mở nội dung từ máy chủ bằng IP Tailscale của máy chủ (ví dụ `http://100.x.x.1:8080`) thay cho IP mạng nội bộ cũ.
6. Để nhà khách cúp điện hay rút điện TV xong Tailscale vẫn tự kết nối lại, chạy (sau khi làm Bước 4):
   ```bash
   ./tv-optimize.sh 100.x.x.2 vpn-always-on
   ./tv-optimize.sh 100.x.x.2 reboot
   ```

## Bước 4: Chạy script tối ưu

Cài `adb` trên máy tính:

- **Mac:** `brew install android-platform-tools`
- **Windows / Linux:** tải *SDK Platform-Tools* của Google, giải nén rồi thêm vào PATH. Trên Windows, chạy script bằng Git Bash.

```bash
cd sony-tv

# 1. Xem TV có gì, app nào ngốn RAM, gói nào sẽ bị tắt (chưa thay đổi gì cả)
./tv-optimize.sh 100.x.x.2 scan

# 2. (Tuỳ chọn) sửa packages-disable.txt: bỏ dấu # trước những app khách không cần

# 3. Áp dụng: tắt app thừa, giảm hiệu ứng chuyển cảnh còn 0.5x, dọn cache
./tv-optimize.sh 100.x.x.2 apply
./tv-optimize.sh 100.x.x.2 reboot
```

Nếu TV ở cùng mạng với máy tính thì dùng IP mạng nội bộ (ví dụ `192.168.1.50`) thay cho IP Tailscale.

**Hoàn tác toàn bộ:** `./tv-optimize.sh <IP> restore`

### Script làm gì, và không làm gì

- **Có làm:** tắt các app trong `packages-disable.txt` (app vẫn nằm trên máy, chỉ không chạy), giảm hiệu ứng chuyển cảnh, dọn cache, đóng app chạy nền.
- **Không làm:** không root, không xoá file hệ thống, không đụng tới firmware.
- **Tự chặn:** script không bao giờ tắt màn hình chính (launcher), trình cài đặt ban đầu, Google Play, dịch vụ Google, ứng dụng xem truyền hình của Sony và Tailscale, kể cả khi lỡ ghi các gói này vào danh sách. Tắt nhầm những gói đó có thể làm TV mất màn hình chính hoặc mất kết nối tới máy chủ.

## Lưu ý an toàn

- **Không mở cổng 5555 trên router nhà khách ra internet.** ADB không có mật khẩu, ai dò ra cổng này là chiếm được TV. Chỉ quản lý TV qua Tailscale.
- **Không dùng link công khai** (tunnel hay chia sẻ public) cho nội dung trên máy chủ nếu trong đó có số liệu nội bộ như giá vốn hay doanh thu. Tailscale giữ kết nối riêng tư giữa các thiết bị của công ty.
- Khi nhân viên nghỉ việc hoặc thôi dùng một máy nào đó, gỡ thiết bị đó khỏi trang quản trị Tailscale.

## Nếu TV chỉ để chiếu nội dung từ máy chủ

- Video: xuất **1080p, H.264**. TV phổ thông giải mã nhẹ hơn nhiều so với 4K hoặc HEVC 10-bit, nhất là khi đường truyền về nhà khách yếu.
- Trang web hiển thị: hạn chế hiệu ứng động và video nền. TV Sony đời phổ thông chỉ có khoảng 1,5–2 GB RAM.
