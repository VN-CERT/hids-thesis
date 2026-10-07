# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 22:15 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M5b:** Xong báo cáo R017, tag `m5b` trên `255ef53`. O4 chưa làm (C2 đạt ngưỡng).

## Bước đã xong
- M5b O2/O3, sửa đọc ring buffer, ma trận `validation/m5b-20261007/`, G3 v3, G7a/d/b-nho (lượt sau sửa)
- R017, tag `m5b`

## Bước đang làm
Không.

## Bước tiếp theo
Chạy lại chẩn đoán + T4-R nếu kiến trúc sư yêu cầu; quyết O1/O4.

## Việc đang chạy
Không.

## Vướng mắc / chờ kiến trúc sư
- O1 `BPF_RB_NO_WAKEUP` + poll: hoãn sau lỗi 100% mất bản ghi.
- T3/T4-C1 vẫn >10% suy giảm — có thử O4 fentry?
