# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-08 13:10 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M5d:** O1 ringbuf wakeup + poll 10 ms; stealclock journal/runtime; đang chạy `hids-m5d`.

## Bước đã xong
- M5c R018, tag `m5c`
- M5d: `docs/tasks/M5d.md`, stealclock, O1 BPF/user-space, G7a mat=0 (commit `86be9ef`)

## Bước đang làm
- `systemd-run` unit **hids-m5d** → `scripts/m5d.sh` → `validation/m5d-20261008/`

## Bước tiếp theo
- Khi job xong: R019, tag `m5d`, O5 chỉ nếu bpf-delta ≥1,5× idle

## Việc đang chạy
- **hids-m5d** — `bash scripts/m5d.sh` — log `out/jobs/m5d.log` — dự kiến nhiều giờ (G7b 24M + ma trận M5)

## Vướng mắc / chờ kiến trúc sư
- O5 (ring buffer per-CPU) chỉ khi điều kiện BPF stats đạt.
