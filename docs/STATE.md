# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-20 17:50 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin`. Hash cũ: `docs/commit-map-loc-bin.txt`.
- Tham chiếu bằng **TAG mốc**; dữ liệu `*.bin` / `*.bin.zst` không vào git.

## Mốc hiện tại và mục tiêu

- **M5:** đóng (`m5h`).
- **M6b-1:** đóng (`m6b1`, R028).
- **M6b-1.1:** đang làm — chẩn đoán CPU collector ~9,7% lõi, sửa `records_per_sec`, chạy lại cổng, tag `m6b1.1`, R029 (`docs/tasks/M6b-1.1.md`).

## Bước đã xong (M6b-1.1)

- Lưu nhiệm vụ nguyên văn `docs/tasks/M6b-1.1.md`.

## Bước đang làm

- A1: chạy collector đúng cấu hình 24 giờ trong 5 phút, ghi `top -H` và `perf record/report`.
- Sau đó A2 (biến thể a–d), A3 (tối ưu việc định kỳ user-space), B, C, D.

## Bước tiếp theo

- Theo đúng thứ tự A → B → C → D trong task. Mục nào không đạt: dừng, dán nguyên văn.

## Việc đang chạy

- (sắp chạy A1 bằng systemd-run)

## Vướng mắc / chờ kiến trúc sư

- (không)
