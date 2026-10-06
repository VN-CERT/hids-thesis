# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-06 23:32 (giờ máy)

## Mốc hiện tại và mục tiêu
- Mốc: **M3 mục A–E** (người dùng thu hẹp phạm vi phiên này). Chỉ làm A, B, C, D, E.
- Mục F (`tools/wl.c`), G (`bin/rec-check`), H (`scripts/g3.sh`), I, J để phiên sau. **Chưa viết, chưa chạy.**
- Điều kiện kết thúc phiên: build sạch, cây git sạch, chạy thử `hids-collect` 30 giây không lỗi, viết R004, không gắn tag `m3` (chỉ `m3-ae`).
- Phần phản hồi của kiến trúc sư cho R003 (G7d, file `.periodic` + dòng LOSS, ghi nhận GĐ4): đã xong, đã commit.

## Kết quả G1 (kiến trúc sư kết luận: ĐẠT)
- Dữ liệu: `validation/g1-20261006/` (giữ lâu dài, không nằm trong `.gitignore`).
- Kết luận: `vmw_steal_time` = `/proc/stat` = (Ready + Co-stop của vCenter), lệch ≤ 0,001%.
- **Đường đo steal chính thức của dự án là `vmw_steal_time`.** `runqueues.prev_steal_time` chỉ dùng để đối chiếu.

## Kết quả G7 (số liệu, chưa có kết luận của kiến trúc sư)
- Dữ liệu: `validation/g7-20261006/` (giữ lâu dài). Báo cáo: `reports/R003-m2.1-cpu-trong-flags-va-do-g7.md`.
- G7a (1 tiến trình, 1 triệu syscall): perf 1.000.001, collector 1.000.001, mất 0.
- G7b (24 tiến trình × 1 triệu, có stress-ng, ring buffer 64 MiB): perf 24.000.024, collector 24.000.024, mất 0 trên cả 24 PID.
- G7b-nho (giống G7b, ring buffer 1 MiB): mất 1.205.210 bản ghi. Ba nguồn độc lập cho cùng con số: hiệu (perf − bản ghi), bộ đếm `mat` của kernel, và số seq bị thiếu đếm từ dữ liệu. Trên từng CPU, `seq_thieu` bằng đúng `mat`.
- G7c (lọc cgroup container caddy, 60 giây): perf 459.095, collector trong cửa sổ 459.865. Chênh lệch do biên cửa sổ (xem mục 8 của R003); bộ đếm mất = 0, seq thiếu = 0.

## Quyết định của kiến trúc sư cho M1 (đã áp dụng)
1. Chấp nhận cách nạp typed ksym bằng `BPF_PSEUDO_BTF_ID` tự gán (`assignPerCPUKsyms`).
2. Giữ hai dòng header `user_hz` và `tsc_source`.
3. Đã đặt `git config --local user.name "hids-bot"`, `user.email "hids-bot@localhost"`.
4. Mọi binary ghi dữ liệu ghi git commit vào header; cây dirty thì in cảnh báo ra stderr và ghi `dirty` vào header.
5. Báo cáo M1 là `reports/R001-m1-steal-probe.md`.
6. Bảng flags đã chốt và ghi vào `.cursor/rules/hids.mdc`.

## Quyết định của kiến trúc sư cho R002 (đã áp dụng)
1. **Phương án B cho mục 8 của R002**: `flags` bit 8–15 = số CPU lúc `sys_enter` (`bpf_get_smp_processor_id() & 0xff`). Bảng flags trong `hids.mdc` đã sửa: bit0 FIRST, bit1 GAP_BEFORE, bit2 D_SLEEP, bit3 MIGRATED, bit4 OVERFLOW, bit5 STEAL_FALLBACK, bit6–7 = 0, bit8–15 = CPU.
2. `hids-collect` từ chối chạy nếu số CPU possible > 256.
3. `rec-stat` in theo từng CPU: seq nhỏ nhất, seq lớn nhất, số lỗ hổng, tổng số seq bị thiếu (xử lý quay vòng modulo 2^32), cạnh bộ đếm mất; có dòng TỔNG.
4. Đã đổi tên `validation/g1-20261006/vcenter-ready-costop-run.csv.csv` thành `vcenter-ready-costop-run.csv`.
5. `sysinj` chờ bằng một lệnh `read()` chặn trên stdin, không vòng lặp kiểm tra file, không sleep.
6. `g7.sh` theo trình tự FIFO → collector (chờ `READY`) → perf → chờ 2 giây → mở khoá → chờ thoát → chờ 2 giây → dừng collector.

## Các bước đã xong
| Bước | Commit |
|---|---|
| Quy tắc bắt buộc `.cursor/rules/hids.mdc` | `50a07bc` |
| M1: toàn bộ | `14c2ee1` (tag `m1`) |
| Quy tắc quy trình `.cursor/rules/workflow.mdc`, `docs/STATE.md`, `reports/` | `e10bb50`, `dfc863b` |
| Người dùng chạy G1 600 giây có thao tác vCenter | dữ liệu `validation/g1-20261006/` |
| Áp dụng phản hồi kiến trúc sư cho M1, chốt bảng flags | `5e0fea8` |
| M2: `hids_sys_enter`, `hids-collect`, `rec-stat`, `tools/sysinj.c`, `scripts/g7.sh` | `8456905` |
| Sửa cách tính dấu `dirty` trong Makefile | `5573cf7` |
| M2: tự kiểm và báo cáo R002 | `122b502` (tag `m2`) |
| M2.1: số CPU vào flags, `rec-stat` phân tích seq theo CPU, `sysinj` chờ bằng `read()`, `g7.sh` trình tự mới | `fc26d21` |
| Sửa chỗ đếm tải nền của G7c | `acbcb92` |
| Lưu dữ liệu kiểm chứng G7 | `e0b36fd` |
| Báo cáo R003 | (commit này) |

## Bước đang làm
M3 mục B và C: mở rộng trạng thái theo thread trong task storage, thêm bộ cộng dồn irq per-CPU, gắn `sched_switch`/`sched_wakeup`/`sched_wakeup_new` và 13 cặp tracepoint irq.

## Bước tiếp theo
1. M3 mục E: kiểm tra fail-closed lúc khởi động và các dòng header mới.
2. `make clean && make build` sạch, chạy thử `hids-collect` 30 giây.
3. Viết R004, cập nhật INDEX, commit, gắn tag `m3-ae`, dừng.

## Việc đang chạy
Không có. Việc `hids-g7` xong lúc 23:21:06 (mã thoát 0), `hids-g7c` xong lúc 23:23:40 (mã thoát 0), `hids-g7d` xong lúc 23:43:25 (mã thoát 0).

(Định dạng khi có việc: tên | lệnh | giờ bắt đầu | dự kiến xong | log `out/jobs/<tên>.log` | trạng thái `out/jobs/<tên>.status`)

## Ghi nhận cho GĐ4 (CHƯA làm bây giờ)
- **Tấn công làm mù collector.** Kẻ tấn công có thể bơm thật nhiều syscall để ring buffer đầy, làm collector mất bản ghi và không nhìn thấy hành vi thật. Vì vậy số liệu mất bản ghi không phải chỉ là chỉ số sức khoẻ: nó là **tín hiệu phát hiện**. Giai đoạn 4 phải coi một đợt mất bản ghi bất thường là dấu hiệu đáng ngờ, không phải nhiễu cần bỏ qua.
- Chính sách hiện tại của collector (kiến trúc sư chốt ở R003): **không bao giờ im lặng, không bao giờ tự dừng**. Mỗi 10 giây ghi một dòng vào `<out>.bin.periodic` (số lần định ghi và số mất, cả delta lẫn cộng dồn, cộng tổng irq theo loại từ M3); khi delta mất > 0 thì in dòng `LOSS ...` ra stderr và ghi vào log rồi chạy tiếp. Không dừng thu thập vì mất bản ghi.

## Ghi nhận cho M3 (CHƯA làm bây giờ)
- Khi khởi động, collector tự so `vmw_ns` với `rq_steal_ns` trên từng CPU trong vài giây đầu. Lệch quá ngưỡng thì **từ chối chạy (fail-closed)** và báo lỗi rõ ràng.

## Vướng mắc / chờ kiến trúc sư quyết định
1. **Biên cửa sổ của G7c.** `perf stat -a -G <cgroup> -- sleep 60` không cho biết hai mốc thời gian nó bắt đầu và kết thúc đếm, nên cửa sổ lọc bản ghi rộng hơn cửa sổ thật của perf 58–79 ms, gây chênh 115 và 770 bản ghi trong hai lần chạy. Ba phương án ở mục 8 của R003. Hiện chấp nhận chênh lệch biên.
2. **Ngưỡng cảnh báo khi ring buffer đầy.** Chưa có quy định collector phải làm gì khi tỉ lệ bản ghi mất vượt một ngưỡng nào đó. Hiện chỉ ghi số vào `.stats` và in ra stderr lúc kết thúc.
