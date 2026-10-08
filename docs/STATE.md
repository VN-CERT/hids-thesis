# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-08 23:10 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, `m3`, `m4`, `m5`, `m5b`, `m5c`, `m5d`, `m5e`, `m5f`, `m6a`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore` — không bao giờ commit file đo/thu thập vào repo.

## Mốc hiện tại và mục tiêu

- **M5f:** đã đóng — R021, tag `m5f`.
- **M5e:** đã đóng — R020, tag `m5e`.
- **M5d:** đã đóng — R019, tag `m5d`.

## Bước đã xong

- Rewrite git loại `*.bin`; `.gitignore` bổ sung `*.bin` / `*.bin.zst`.
- M5f: G7 step2 (trước resume), case A bước 1, job `hids-m5f-resume` exit 0, validation `m5f-20261008`, R021.
- M5e: G7 zstd, T3-R/T4-R, T4 kịch trần, nhiễu git push, R020.

## Bước đang làm

- (không)

## Bước tiếp theo

- Chờ nhiệm vụ mới từ kiến trúc sư / người dùng.

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- O5 không làm (R019/R020/R021).
- `m5f_parse.tsv` rỗng do bug đọc `meta.txt` trong `m5f_resume.sh` (chi tiết R021 mục 8).
