# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-06 22:35 (giờ máy)

## Mốc hiện tại và mục tiêu
- Mốc: M2 — bản ghi syscall 48 byte, lọc theo pid/cgroup, ring buffer dùng chung, đếm bản ghi mất.
- M1 đã xong và được kiểm chứng bằng phép đo G1. Kiến trúc sư kết luận **G1 ĐẠT**.
- Mục tiêu M2: `hids_sys_enter` (tp_btf/sys_enter) ghi bản ghi 48 byte vào ring buffer; `bin/hids-collect` thu thập; `bin/rec-stat` thống kê; `tools/sysinj.c` và `scripts/g7.sh` để kiểm chứng.

## Kết quả G1 (kiến trúc sư kết luận: ĐẠT)
- Dữ liệu: `validation/g1-20261006/` (giữ lâu dài, không nằm trong `.gitignore`).
- Kết luận: `vmw_steal_time` = `/proc/stat` = (Ready + Co-stop của vCenter), lệch ≤ 0,001%.
- **Đường đo steal chính thức của dự án là `vmw_steal_time`.** `runqueues.prev_steal_time` chỉ dùng để đối chiếu.

## Quyết định của kiến trúc sư cho M1 (đã áp dụng)
1. Chấp nhận cách nạp typed ksym bằng `BPF_PSEUDO_BTF_ID` tự gán (`assignPerCPUKsyms`). Giữ nguyên, dùng tiếp cho M2.
2. Giữ hai dòng header `user_hz` và `tsc_source`.
3. Đã đặt `git config --local user.name "hids-bot"`, `user.email "hids-bot@localhost"`.
4. Mọi binary ghi dữ liệu phải ghi git commit vào header; nếu cây làm việc dirty thì in cảnh báo ra stderr và ghi `dirty` vào header. Đã làm trong `internal/buildinfo` (`WarnIfDirty`).
5. Báo cáo M1 đổi tên thành `reports/R001-m1-steal-probe.md`. `reports/INDEX.md` và `docs/STATE.md` đã có.
6. Bảng flags đã chốt và ghi vào `.cursor/rules/hids.mdc`.

## Các bước đã xong
| Bước | Commit |
|---|---|
| Quy tắc bắt buộc `.cursor/rules/hids.mdc` | `50a07bc` |
| M1: toàn bộ (`bpf/vmlinux.h`, `hids_steal_snap`, `steal-probe`, `steal-summary`, `scripts/g1.sh`, tự kiểm) | `14c2ee1` (tag `m1`) |
| Quy tắc quy trình `.cursor/rules/workflow.mdc`, `docs/STATE.md`, `reports/`, `out/jobs/` | `e10bb50`, `dfc863b` |
| Người dùng chạy G1 600 giây có thao tác vCenter | dữ liệu `validation/g1-20261006/` |
| Áp dụng phản hồi kiến trúc sư cho M1, lưu `validation/g1-20261006/`, chốt bảng flags | `5e0fea8` |
| M2: `hids_sys_enter`, `hids-collect`, `rec-stat`, `tools/sysinj.c`, `scripts/g7.sh` | (commit kế tiếp) |

## Bước đang làm
M2 — đã viết xong mã và thử nghiệm tay, đang chạy tự kiểm và viết báo cáo R002.

## Bước tiếp theo
1. Chạy tự kiểm G7a với N=10000 trên cây sạch, kiểm tra kernel sạch sau khi thoát.
2. Viết báo cáo R002.
3. Người dùng chạy `scripts/g7.sh a|b|c` với N=1000000.

## Việc đang chạy
Không có.

(Định dạng khi có việc: tên | lệnh | giờ bắt đầu | dự kiến xong | log `out/jobs/<tên>.log` | trạng thái `out/jobs/<tên>.status`)

## Ghi nhận cho M3 (CHƯA làm bây giờ)
- Khi khởi động, collector tự so `vmw_ns` với `rq_steal_ns` trên từng CPU trong vài giây đầu. Lệch quá ngưỡng thì **từ chối chạy (fail-closed)** và báo lỗi rõ ràng.

## Vướng mắc / chờ kiến trúc sư quyết định
(Ghi tại mục 8 của báo cáo R002 khi M2 xong.)
