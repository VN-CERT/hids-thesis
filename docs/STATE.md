# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-06 22:05 (giờ máy)

## Mốc hiện tại và mục tiêu
- Mốc: M1 — công cụ đọc bộ đếm steal theo từng CPU, để kiểm chứng trước khi xây collector.
- Trạng thái mốc: đã xong phần việc của máy, đã gắn tag `m1`. Còn một việc người dùng phải tự chạy (`scripts/g1.sh`, cần thao tác vCenter).
- Mục tiêu kế tiếp: M2 — collector đo Δt giữa hai syscall liên tiếp và phân rã thành 5 thành phần (chưa bắt đầu, chờ kiến trúc sư duyệt các câu hỏi ở mục Vướng mắc).

## Các bước đã xong
| Bước | Commit |
|---|---|
| Thêm quy tắc bắt buộc của dự án `.cursor/rules/hids.mdc` | `50a07bc` |
| M1: sinh `bpf/vmlinux.h` từ `/sys/kernel/btf/vmlinux` | `14c2ee1` |
| M1: chương trình BPF `hids_steal_snap` (`SEC("syscall")` + `BPF_PROG_RUN`, `bpf_per_cpu_ptr`) | `14c2ee1` |
| M1: `bin/steal-probe` ghi CSV kèm giá trị tham chiếu `/proc/stat` | `14c2ee1` |
| M1: `bin/steal-summary` (bảng theo CPU, `-bucket`, `-from/-to`) | `14c2ee1` |
| M1: `scripts/g1.sh` (chưa chạy, dành cho người dùng) | `14c2ee1` |
| M1: tự kiểm — build sạch, chạy 30 s, `vmw_raw` không giảm, đối chiếu `/proc/stat` | `14c2ee1` |
| M1: tag `m1` | `14c2ee1` |
| Thêm quy tắc quy trình `.cursor/rules/workflow.mdc`, dựng `docs/STATE.md` và `reports/` | (commit này) |

## Bước đang làm
Không có bước kỹ thuật nào đang dở. Vừa dựng xong bộ khung lưu trạng thái và báo cáo; báo cáo M1 là `reports/R001-m1-doc-bo-dem-steal-theo-cpu.md`.

## Bước tiếp theo
1. Người dùng chạy `scripts/g1.sh` (xem mục 9 của R001), gửi lại file `out/g1-<ngày giờ>.csv`.
2. Chạy `bin/steal-summary` ở cả hai chế độ trên file đó và viết báo cáo R002.
3. Chờ kiến trúc sư trả lời các câu hỏi ở mục Vướng mắc rồi mới bắt đầu M2.

## Việc đang chạy
Không có.

(Định dạng khi có việc: tên | lệnh | giờ bắt đầu | dự kiến xong | log `out/jobs/<tên>.log` | trạng thái `out/jobs/<tên>.status`)

## Vướng mắc / chờ kiến trúc sư quyết định
1. **Cách nạp typed ksym.** Loader bắt buộc của dự án (`github.com/cilium/ebpf` v0.22.0, không cgo) từ chối biến ksym có kiểu trong section `.ksyms`, báo nguyên văn: `load virtual .ksyms section: data section .ksyms: expected vmw_steal_time to be *Void, not *btf.Var: not supported`. Giải pháp đang dùng: khai báo extern có kiểu nhưng bỏ thuộc tính `__ksym`, rồi user space tra BTF id thật của VAR trong `/sys/kernel/btf/vmlinux` và ghi vào lệnh `ld_imm64` dưới dạng `BPF_PSEUDO_BTF_ID` (đúng việc libbpf làm). `bpf_per_cpu_ptr` vẫn được dùng, verifier vẫn kiểm kiểu theo BTF kernel. Cần duyệt cách này để dùng tiếp cho M2.
2. **Hai dòng comment thêm trong header CSV.** Ngoài danh sách đã quy định, file CSV có thêm `user_hz` (steal-summary cần để đổi tick sang ms) và `tsc_source` (dòng kernel log nguyên văn). Cần duyệt giữ hay bỏ.
