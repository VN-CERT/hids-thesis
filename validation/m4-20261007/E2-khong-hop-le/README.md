# E2 — dữ liệu không hợp lệ (loại khỏi M4)

Thu thập ngày 2026-10-07 khi **chưa** đặt CPU Limit trên vCenter.

Agent đã chạy `e2-collect` với biến môi trường `M4_E2_SKIP_PROMPT=1`, bỏ qua bước chờ người dùng xác nhận limit. Kết quả: `steal_median_us` ≈ 0 ở mọi mức (Unlimited, 36000, 24000, 12000 MHz) — không phản ánh steal do giới hạn CPU.

**Không dùng** các file `.bin` / `.csv` trong thư mục này cho báo cáo M4. E2 hợp lệ sẽ được thu lại sau M4.2 (`scripts/m4.sh e2`, người dùng thao tác vCenter).

Báo cáo R009 ghi nhận E2 cũ; thay thế bằng R010 và dữ liệu E2 mới khi có.
