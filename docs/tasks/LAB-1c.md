NHIỆM VỤ GỘP LAB-1c (máy 201, repo /root/collector, nhánh lab-collector) — gồm ba phần: PHẦN A (LAB-1c bản 1) nhưng B4/N4 theo PHẦN B (1.9c) ngay từ đầu; PHẦN C (LAB-1c-phụ) đặt unit tự xếp sau driver. Đọc hết cả ba phần trước khi làm. Kết thúc lượt sau khi: Phụ lục 1.9+1.9b+1.9c đã commit, phiên thử rút gọn đạt, driver đã bật và phiên đầu (15 phút) đạt, unit LAB-1c-phụ đã đặt; in tên hai unit, giờ dự kiến xong, và dòng kiểm trạng thái. Không kết luận.

## 1.9c
LAB-1c — SỬA ĐỔI 1.9c (áp cho B4/N4 của PHẦN A và nền nén log của PHẦN C). B4/N4 là MỘT tiến trình sống suốt cửa sổ nhãn, chu kỳ bật 2 s / nghỉ 20 s. B4 = stress-ng --cpu 1 --cpu-load 10 --cpu-load-slice 2000 (hoặc lab1c_b4_burner.py). N4 = lab1c_n4_zlib.py. LAB-1c-phụ dùng lab1c_n4_zlib.py.

## phụ
LAB-1c-phụ — nền lớp tiến trình chu kỳ lành trong cgroup lab0-nginx (1.9b + N4 zlib theo 1.9c). Unit hids-lab1c-nenphu chờ hids-lab1c-driver xong rồi chạy 150 phút.

(Nội dung đầy đủ PHẦN A/B/C đã được người dùng dán trong phiên Cursor 2026-11-07; thực hiện theo đúng đặc tả đó.)
