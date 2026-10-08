# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-08 13:10 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M5d:** đóng mốc — **dừng tại bước 1** (G7b chưa đạt mat=0). Ma trận `validation/m5d-20261008/` **không dùng** cho báo cáo cho đến khi O1 qua G7b.

## Bước đã xong
- Ma trận overhead + tải cố định (job `hids-m5d` 15:41)
- Chính sách dọn dữ liệu (`0e52a32`)
- Kiểm chứng đóng mốc: `scripts/m5d_close_step1_verify.sh` — **G7a PASS**, G7b **FAIL** (`verify-close/`, 16:17–16:22)

## Bước đang làm
- Chờ kiến trúc sư: O1 chưa đủ cho G7b 24×24M (mat ≈ 1,5×10⁸); có LOSS ~26–38%/10s trong `out/g7b-20261008-161727-collect.log`

## Bước tiếp theo
- Sau khi O1 (hoặc O5) đạt G7b mat=0: chạy lại bước 1 đầy đủ → bước 2 BPF → dọn mini-t1 → R019 + tag `m5d`

## Việc đang chạy
- (không)

## Vướng mắc / chờ kiến trúc sư
- G7b với O1 hiện tại: ring buffer 64 MiB vẫn đầy dù FORCE_WAKEUP khi avail≥ring/8; user-space không kịp đọc.
- O5 chỉ sau khi BPF stats + điều kiện 1,5×; chưa chạy bước 2 đóng mốc.
