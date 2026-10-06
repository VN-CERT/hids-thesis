# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 01:50 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M3.2 + M4:** đang chạy (wl, g3 v3, rec-export, m4.sh).
- Tag `m3` sẽ gắn lại sau G3 v3; tag `m4-ab` sau E1/E3/E4 (E2 chờ người dùng).

## Bước đang làm
- Chạy `scripts/g3.sh m32` → `validation/g3-*-v3/`.
- Chạy `scripts/m4.sh all` → `validation/m4-*`.

## Bước tiếp theo
- Báo cáo R007; commit; tag `m4-ab`; retag `m3` trên commit đo v3.

## Ghi nhận kiến trúc sư (từ R006 mục 8)
- bpftrace `@rq_sau_wakeup_ns` khớp **rq** collector (lệch 0,2–2,4%), **không** khớp `run_delay`. `run_delay` kernel thiếu ~6 µs mỗi wakeup trên CPU rảnh; collector đúng đặc tả.
- **S5:** tổng kernel = exec + run_delay + sleep (block trong sleep, không cộng thêm). Lệch thật ~1 µs.
- **G-irq:** lệch 4–9% so với bcc do gắn chung tracepoint; chỉ tham chiếu.

## Các bước đã xong (phiên này)
| Việc | Ghi chú |
|---|---|
| `tools/wl.c` M3.2 + mixed/mem M4 | hiệu chỉnh, tự kiểm 5×10 ms, `-loops` |
| `scripts/g3.sh` m32, G-real 30s, S5 tổng kernel | OUTROOT v3 mặc định |
| `cmd/rec-export`, `analysis/m4.py`, `scripts/m4.sh` | |

## Việc đang chạy
(xem `out/jobs/` sau khi khởi động systemd)

## Vướng mắc / chờ kiến trúc sư
Không có mới.
