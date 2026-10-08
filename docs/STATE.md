# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-08 23:45 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5h:** **dừng** — verifier từ chối `hids_sched_switch` (R022); chờ BPF sửa từ kiến trúc sư; **chưa** tag `m5h`.
- **M5f:** đã đóng — R021, tag `m5f`.

## Bước đã xong (M5h)

- Bước 0: commit BPF `25c66cb`.
- Bước 1: Go + header `539a171`; `make build` OK.

## Bước đang làm

- (không — chờ BPF)

## Bước tiếp theo

- Kiến trúc sư sửa `bpf/sys_enter.bpf.c` (verifier pass).
- Chạy lại M5h từ bước 2 (`docs/tasks/M5h.md`).

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- **M5h:** `R1 pointer |= pointer prohibited` trong `hids_sched_switch` (chi tiết R022).
- O5 không làm.
