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

- A1 xong (commit e445f59, unit hids-m6b11-a1, exit=0): 5 phút đúng cấu hình 24h; CPU delta status 6.04/5.94/6.09 giây mỗi ~60 giây (≈10% một lõi); output `validation/m6b11-20261020/A1/` (top-H.txt, perf-report.txt, cpu-status-summary.txt, cpu-proc.tsv).
- A2: đã thêm cờ thử nghiệm `-no-proc`, `-no-host`, `-cgroup-refresh` (mặc định giữ nguyên hành vi). Chuẩn bị chạy các biến thể 5 phút.

## Bước tiếp theo

- Theo đúng thứ tự A → B → C → D trong task. Mục nào không đạt: dừng, dán nguyên văn.

## Việc đang chạy

- **hids-m6b11-a2** — 4 biến thể A2, mỗi biến thể 5 phút: a2-baseline, b-no-proc (`-no-proc`), c-no-host (`-no-host`), d-cgroup10s (`-cgroup-refresh 10s`); `DIAG_PERF=0`; bắt đầu 2026-10-20 ~18:05 (+07), dự kiến ~21 phút; log `out/jobs/m6b11-a2.log`, trạng thái `out/jobs/m6b11-a2.status`; output `validation/m6b11-20261020/{A2a,A2b,A2c,A2d}/`.

## Vướng mắc / chờ kiến trúc sư

- (không)
