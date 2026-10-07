# E2 lần 1 — limit đã được đặt nhưng bước kiểm steal bị lỗi

Người dùng đã thao tác vCenter và bấm Enter đúng quy trình (2026-10-07).

Lỗi khi chạy `scripts/m4.sh e2` (M4.2):
- Gọi `e2_one_level 36000 36000 MHz 1` khiến tham số `need_limit` = `MHz` → lỗi `MHz: unbound variable` tại bước kiểm steal; kiểm tra 5% và đo steal **không** chạy đúng.
- `stress-ng` chỉ bật trong từng mức, không giữ tải suốt 4 mức; không có `steal-probe`.

Dữ liệu collector (`.bin`/`.csv`) vẫn lưu để phân tích thống kê mới (R011). Không dùng làm E2 chính thức cho M4 cho đến khi chạy lại `m4.sh e2` sau M4.3.
