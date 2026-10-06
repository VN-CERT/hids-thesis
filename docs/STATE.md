# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-06 22:50 (giờ máy)

## Mốc hiện tại và mục tiêu
- Mốc: M2 — bản ghi syscall 48 byte, lọc theo pid/cgroup, ring buffer dùng chung, đếm bản ghi mất.
- Phần việc của máy ở M2 đã xong và đã tự kiểm. Còn chờ người dùng chạy ba phép đo G7 và kiến trúc sư quyết định một việc (xem mục Vướng mắc).
- Mốc kế tiếp: M3 — đo thật năm thành phần của Δt.

## Kết quả G1 (kiến trúc sư kết luận: ĐẠT)
- Dữ liệu: `validation/g1-20261006/` (giữ lâu dài, không nằm trong `.gitignore`).
- Kết luận: `vmw_steal_time` = `/proc/stat` = (Ready + Co-stop của vCenter), lệch ≤ 0,001%.
- **Đường đo steal chính thức của dự án là `vmw_steal_time`.** `runqueues.prev_steal_time` chỉ dùng để đối chiếu.

## Quyết định của kiến trúc sư cho M1 (đã áp dụng)
1. Chấp nhận cách nạp typed ksym bằng `BPF_PSEUDO_BTF_ID` tự gán (`assignPerCPUKsyms`). Giữ nguyên, dùng tiếp cho M2.
2. Giữ hai dòng header `user_hz` và `tsc_source`.
3. Đã đặt `git config --local user.name "hids-bot"`, `user.email "hids-bot@localhost"`.
4. Mọi binary ghi dữ liệu ghi git commit vào header; cây dirty thì in cảnh báo ra stderr và ghi `dirty` vào header (`internal/buildinfo.WarnIfDirty`).
5. Báo cáo M1 là `reports/R001-m1-steal-probe.md`. `reports/INDEX.md` và `docs/STATE.md` đã có.
6. Bảng flags đã chốt và ghi vào `.cursor/rules/hids.mdc`.

## Các bước đã xong
| Bước | Commit |
|---|---|
| Quy tắc bắt buộc `.cursor/rules/hids.mdc` | `50a07bc` |
| M1: toàn bộ (`bpf/vmlinux.h`, `hids_steal_snap`, `steal-probe`, `steal-summary`, `scripts/g1.sh`, tự kiểm) | `14c2ee1` (tag `m1`) |
| Quy tắc quy trình `.cursor/rules/workflow.mdc`, `docs/STATE.md`, `reports/`, `out/jobs/` | `e10bb50`, `dfc863b` |
| Người dùng chạy G1 600 giây có thao tác vCenter | dữ liệu `validation/g1-20261006/` |
| Áp dụng phản hồi kiến trúc sư cho M1, lưu `validation/g1-20261006/`, chốt bảng flags | `5e0fea8` |
| M2: `hids_sys_enter`, `hids-collect`, `rec-stat`, `tools/sysinj.c`, `scripts/g7.sh` | `8456905` |
| Sửa cách tính dấu `dirty` trong Makefile | `5573cf7` |
| M2: tự kiểm (build sạch, G7a N=10000, lọc cgroup, kernel sạch) và báo cáo R002 | (commit này) |

## Bước đang làm
Không có bước kỹ thuật nào đang dở. Báo cáo M2 là `reports/R002-m2-ban-ghi-syscall.md`.

## Bước tiếp theo
1. Người dùng chạy `scripts/g7.sh a`, `b`, `c` (xem mục 9 của R002), gửi lại kết quả.
2. Phân tích kết quả G7 và viết báo cáo R003.
3. Chờ kiến trúc sư quyết định về trường CPU trong bản ghi, rồi bắt đầu M3.

## Việc đang chạy
Không có.

(Định dạng khi có việc: tên | lệnh | giờ bắt đầu | dự kiến xong | log `out/jobs/<tên>.log` | trạng thái `out/jobs/<tên>.status`)

## Ghi nhận cho M3 (CHƯA làm bây giờ)
- Khi khởi động, collector tự so `vmw_ns` với `rq_steal_ns` trên từng CPU trong vài giây đầu. Lệch quá ngưỡng thì **từ chối chạy (fail-closed)** và báo lỗi rõ ràng.

## Vướng mắc / chờ kiến trúc sư quyết định
1. **Bản ghi 48 byte không có trường CPU** nên `rec-stat` không tách được bản ghi theo CPU, do đó không in được seq nhỏ nhất/lớn nhất và số lỗ hổng seq của từng CPU. Bốn phương án (nhét CPU vào bit cao của `seq`; dùng bit 8..15 của `flags`; mỗi CPU một ring buffer; giữ nguyên) kèm hệ quả đã ghi ở mục 8 của R002. Hiện chạy theo phương án giữ nguyên: chỉ có bảng `seq_cuoi`/`mat` theo CPU lấy từ file `.stats` và đối chiếu tổng toàn cục.
