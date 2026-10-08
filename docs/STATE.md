# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-08 20:30 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, `m3`, `m4`, `m5`, `m5b`, `m5c`, `m5d`, `m5e`, `m6a`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore` — không bao giờ commit file đo/thu thập vào repo.

## Mốc hiện tại và mục tiêu

- **M5e:** đã đóng — R020, tag `m5e` (xem báo cáo; dữ liệu trong `validation/m5e-20261008/`).
- **M5d:** đã đóng — R019, tag `m5d`.
- **M5f:** chưa bắt đầu — đặc tả `docs/tasks/M5f.md` (bước 1: checkout Go ghi/nén từ tag `m5d`).

## Bước đã xong

- Rewrite git loại `*.bin`; `.gitignore` bổ sung `*.bin` / `*.bin.zst`.
- M5e: G7 zstd, T3-R/T4-R, T4 kịch trần, xử lý nhiễu git push, R020.

## Bước đang làm

- (không)

## Bước tiếp theo

- Thực hiện **M5f** theo `docs/tasks/M5f.md`.

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- O5 không làm (R019/R020).
