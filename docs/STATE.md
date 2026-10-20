# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-20 17:45 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin`. Hash cũ: `docs/commit-map-loc-bin.txt`.
- Tham chiếu bằng **TAG mốc**; dữ liệu `*.bin` / `*.bin.zst` không vào git.

## Mốc hiện tại và mục tiêu

- **M5:** đóng (`m5h`).
- **M6b-1:** **đóng** — R028, tag `m6b1`.

## Bước đã xong (M6b-1)

- Xoá `M6B1_SKIP_*` khỏi `scripts/m6b1_gate.sh`.
- Pre24h (`1a88508`): G7a, G7b-nho, G3 S1–S5, G9b, host 10 phút — exit=0.
- G8 / G9a / G10 đã duyệt kiến trúc sư.
- Thu 24 giờ `hidsrun-24h` xong 2026-10-20T17:38:14+07:00: 34.192.008 bản ghi, mất kernel 0, dữ liệu `/srv/hids-data/uni-lms-app/`.
- R028 đã điền bảng 24 giờ.

## Bước đang làm

- (không)

## Bước tiếp theo

- M6b-2 (chờ nhiệm vụ từ kiến trúc sư).

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- `status.tsv`: 24 dòng `records_per_sec` âm tại mỗi lần xoay file (ghi nhận ở R028 mục 10).
