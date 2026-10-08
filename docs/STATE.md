# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-09 00:35 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5h:** **dừng bước 2 (r2)** — BPF `5beaace`; G7a/fentry OK; G7b `mat`≠0 (R024); **chưa** tag `m5h`.
- **M5f:** đã đóng — R021, tag `m5f`.

## Bước đã xong (M5h)

- Bước 0 r2: BPF `5beaace` (sha256 `14d065a6…`).
- Bước 1: Go `539a171`; build OK.
- Bước 2 một phần: G7a + G7a fentry (`validation/m5h-20261009/step2/`).

## Bước đang làm

- (không — chờ BPF)

## Bước tiếp theo

- Kiến trúc sư: G7b `mat`=0 với BPF r2 (R024).
- Sau đó: G7b-nho, G3, bước 3–4 M5h.

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- **M5h:** R024 G7b mất bản ghi; R022/R023 lịch sử.
- O5 không làm.
