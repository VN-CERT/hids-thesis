# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-19 17:40 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin`. Hash cũ: `docs/commit-map-loc-bin.txt`.
- Tham chiếu bằng **TAG mốc**; dữ liệu `*.bin` / `*.bin.zst` không vào git.

## Mốc hiện tại và mục tiêu

- **M5:** đóng (`m5h`).
- **M6b-1:** cổng + pre24h **ĐẠT** (R028); **đang thu 24h**; chưa tag `m6b1`.

## Bước đã xong (M6b-1)

- Xoá `M6B1_SKIP_*` khỏi `scripts/m6b1_gate.sh`.
- Pre24h (`1a88508`): G7a, G7b-nho, G3 S1–S5, G9b, host 10 phút — exit=0.
- G8 / G9a / G10 đã duyệt kiến trúc sư.
- R028 viết (bảng 24h còn trống — chờ job).

## Bước đang làm

- Chờ `hidsrun-24h` xong → điền bảng 24 giờ vào R028 → tag `m6b1`.

## Bước tiếp theo

- M6b-2 sau khi đóng m6b1.

## Việc đang chạy

- **hidsrun-24h** — `bash scripts/m6b1_24h_run.sh`; bắt đầu 2026-10-19T17:38:14+07:00; dự kiến xong ~2026-10-20T17:38; đích `/srv/hids-data/uni-lms-app/` (cgroup `hscd_redis` + `qdrant`); log `out/jobs/m6b1-24h.log`; status `out/jobs/m6b1-24h.status`; hourly `out/jobs/m6b1-24h.hourly.tsv`.

## Vướng mắc / chờ kiến trúc sư

- (không)
