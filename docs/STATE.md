# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-09 00:45 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5h:** **dừng trước G3** — G7b/G7b-nho zstd0 OK; G7-cap zstd mặc định `mat`≠0 (R025); **chưa** tag `m5h`.
- **M5f:** đã đóng — R021, tag `m5f`.

## Bước đã xong (M5h)

- Bước 0 r2: BPF `5beaace` (sha256 `14d065a6…`).
- Bước 1: Go `539a171`; build OK.
- Bước 2: G7a/fentry; G7b/G7b-nho zstd0; G7-cap fail (`validation/m5h-20261009/step2/`).

## Bước đang làm

- (không — chờ BPF)

## Bước tiếp theo

- Kiến trúc sư: G7-cap `mat`=0 (R025; M5f cùng script đã `mat`=0).
- Sau đó: G3, bước 3–4 M5h.

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- **M5h:** R025 G7-cap; R024/R022/R023 lịch sử.
- O5 không làm.
