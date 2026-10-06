# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 00:43 (giờ máy)

## Mốc hiện tại và mục tiêu
- Mốc **M3 PHẦN 2 (F–J):** đã xong. Tag `m3`, báo cáo R005.
- **M4:** chưa bắt đầu (cố ý dừng sau R005).

## Bước đang làm
Không có.

## Bước tiếp theo
1. Chờ kiến trúc sư duyệt R005 (G-real, G-irq, wl/`clock_gettime`).
2. Có thể chạy lại S1–S5 với `wl` spin 262144 và G-irq với parse bcc đã sửa trong `g3.sh`.

## Các bước đã xong (PHẦN 2)
| Bước | Commit |
|---|---|
| `tools/wl.c`, `bin/rec-check`, `scripts/g3.sh` | `e93f01b` |
| Sửa g3 wchan + wl clock_gettime | `c3d371b` |
| Tự chạy G3, `validation/g3-20261007/` | (commit tag `m3`) |
| Báo cáo R005 | (commit tag `m3`) |

## Việc đang chạy
Không có. `hids-g3` đã chạy xong (~00:36); log `out/jobs/g3-driver.log`.

## Kết quả G3 (2026-10-07, `validation/g3-20261007/`)
- S1–S5: bảng trong `*-ketqua.txt`; S5 có 300 bản ghi `D_SLEEP`.
- G7d: perf 1.000.001 = collector 1.000.001.
- `recursion_misses` = 0 trên 30 chương trình BPF.
- G-real: tham chiếu schedstat tổng = 0 (PID không khớp hai mốc — xem R005 mục 8).
- G-irq: bảng lần chạy parse lỗi; sửa `g3.sh` sau lần chạy.

## Vướng mắc / chờ kiến trúc sư quyết định
Xem R005 mục 8 (G-real, G-irq, wl nr 228 trong S1/S3/S4).
