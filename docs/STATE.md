# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 03:50 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M3.2:** xong. Tag `m3` → `31144f5` (G3 v3).
- **M4-ab:** xong E1, E3, E4; tag `m4-ab` → `7ec2409` (sau commit validation). **E2** chờ người dùng (vCenter).

## Bước đang làm
Không có.

## Bước tiếp theo
Người dùng chạy E2 (`scripts/m4.sh e2`); sau đó tag `m4` và báo cáo bổ sung.

## Ghi nhận kiến trúc sư (R006 §8 → STATE)
- bpftrace `@rq_sau_wakeup_ns` khớp **rq** collector (~0,2–2,4%), không khớp `run_delay` (~6 µs/wakeup thiếu trên CPU rảnh).
- S5 tổng kernel = exec + run_delay + sleep (block trong sleep); lệch ~1 µs.
- G-irq vs bcc 4–9%: gắn chung tracepoint, chỉ tham chiếu.

## Các bước đã xong (M3.2 + M4-ab)
| Việc | Commit / dữ liệu |
|---|---|
| wl, g3 m32, rec-export, m4 | `6a07fb0` … `7ec2409` |
| G3 v3 | `validation/g3-20261007-v3/`, tag `m3` |
| M4 E1/E3/E4 | `validation/m4-20261007/` |
| R007 | `reports/R007-m3.2-m4-ab.md` |

## Việc đang chạy
Không có.

## Vướng mắc / chờ kiến trúc sư
Không có mới.
