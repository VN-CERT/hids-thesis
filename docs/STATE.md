# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 01:26 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M3.1:** xong. Tag `m3` → commit `d4c55b9`. Báo cáo **R006**; R005 giữ nhưng hỏng định dạng.
- **M4:** chưa bắt đầu.

## Bước đang làm
Không có.

## Bước tiếp theo
Chờ kiến trúc sư duyệt R006 (G-real, G-irq đơn vị, rq bpftrace vs collector).

## Các bước M3.1 đã xong
| Bước | Commit |
|---|---|
| Nhiệm vụ `docs/tasks/M3.1.md`, workflow, INDEX R005 | `a256da9` |
| Sửa build `wl` | `447d91a` |
| Makefile dirty + chạy G3 v2 | `d4c55b9` (tag `m3`) |
| g3/g7 validation path + G7d | `915de8b` |
| validation v2 + R006 | (commit hiện tại) |

## Kết quả G3 v2 (`validation/g3-20261007-v2/`)
- S1: **301** bản ghi cửa sổ; header `git_commit: d4c55b9`.
- G7d: perf 1.000.001 = collector 1.000.001.
- G-real: **103** thread giữ (`cgroup.threads`).
- `recursion_misses` = 0.

## Việc đang chạy
Không có.

## Vướng mắc / chờ kiến trúc sư
Xem R006 mục 8.
