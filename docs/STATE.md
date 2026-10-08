# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-09 00:10 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5h:** **dừng bước 0 (r2)** — file BPF trên máy vẫn sha256 `7618d9c1…` (R022), chưa bản `14d065a6…` (R023); **chưa** tag `m5h`.
- **M5f:** đã đóng — R021, tag `m5f`.

## Bước đã xong (M5h)

- Bước 0: commit BPF `25c66cb`.
- Bước 1: Go + header `539a171`; `make build` OK.

## Bước đang làm

- (không — chờ BPF)

## Bước tiếp theo

- **Người dùng** chép BPF M5h-r2 (`14d065a6…`) vào `bpf/sys_enter.bpf.c`.
- Agent: commit M5h-r2 → `make build` → M5h bước 2–4 (`docs/tasks/M5h.md`).

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- **M5h:** R022 verifier (bản cũ); R023 chờ file BPF r2 trên máy.
- O5 không làm.
