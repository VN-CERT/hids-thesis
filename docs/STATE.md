# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-09 02:30 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5h:** **đóng** — R026, tag `m5h`.
- **M5f:** đã đóng — R021, tag `m5f`.

## Bước đã xong (M5h)

- Bước 0–2: BPF r2, G7a/fentry, G7b/G7b-nho zstd0, G7-cap ghi nhận throughput (R025/R026).
- G3 S1–S5: `validation/m5h-20261009/g3/` (job `hids-m5h-g3`, exit 0).
- Bước 3–4: `validation/m5h-20261009/` (job `hids-m5h-bench`, exit 0).

## Bước đang làm

- (không)

## Bước tiếp theo

- Chờ nhiệm vụ mốc mới từ kiến trúc sư.

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- O5 không làm.
