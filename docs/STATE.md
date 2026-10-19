# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-19 16:45 (giờ máy)

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

- G7a PASS (2026-10-10). G3 S1–S5 đã chạy xong. G8 lần 1 FAIL (`-duration 120`). G8 lần 2: proc BPF tgid read-only. G8 lần 3: collector không thoát SIGTERM. Đang sửa vòng đọc + chạy lại cổng.

## Bước tiếp theo

- Hoàn tất cổng M6b-1, tag `m6b1`, R028.
- M6b-2 thu production.

## Việc đang chạy

- **hids-m6b1-gate** — chạy lại sau sửa `hids_proc_self_tgid` trên spec; G8–G10 + host 10 phút; log `out/jobs/m6b1-gate.log`.

## Vướng mắc / chờ kiến trúc sư

- (không)
