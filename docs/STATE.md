# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-09 16:00 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5:** **đóng** — tag `m5h`.
- **M6b-1:** **đang làm** — tính năng thu dài ngày trên máy test (task `docs/tasks/M6b-1.md`).

## Bước đã xong (M6b-1)

- `bpf/proc_events.bpf.c` đã commit (sha256 theo task).
- Go: `internal/procbpf` (loader, parse), `internal/hostsample`, `internal/recseq`.
- `cmd/hids-collect/longrun.go` + cờ `-datadir`, `-rotate`, `-min-free-gb`.
- `cmd/rec-chain`, `deploy/hids-collect.service`, `scripts/m6b1_gate.sh`, Makefile `rec-chain`.
- `make build` thành công.

## Bước đang làm

- Chạy `scripts/m6b1_gate.sh` từ cây git sạch; sửa G8/G9 nếu gate lệch.
- Commit các chunk còn lại (nếu chưa gom hết).
- Bước 9 task: chạy thử 24h (systemd-run), báo cáo R028 — **chưa bắt đầu**.

## Bước tiếp theo

- Hoàn tất cổng M6b-1, tag `m6b1`, R028.
- M6b-2 thu production.

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- (không)
