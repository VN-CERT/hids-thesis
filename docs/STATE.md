# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 00:25 (giờ máy)

## Mốc hiện tại và mục tiêu
- Mốc: **M3 PHẦN 1** (nguyên văn nhiệm vụ: `docs/tasks/M3-phan2.md`). PHẦN 1 = mục 8.2 + 8.3 trong phản hồi của kiến trúc sư cho R004.
- PHẦN 1 gồm: viết lại mục C (bộ cộng dồn irq per-CPU) theo phương án (c), in `recursion_misses` của từng chương trình BPF, thêm cột `soft_raw_delta_ns` vào `.periodic`, thêm 4 dòng header `CONFIG_*`.
- Điều kiện kết thúc PHẦN 1: build sạch, chạy lại phép chạy thử 30 giây của R004 và phép soi chéo tự nhất quán, commit, in `XONG PHẦN 1` rồi **CHỜ** người dùng đổi model và bảo làm tiếp.
- **PHẦN 2 = M3 mục F–J.** Chưa bắt đầu. KHÔNG làm cho tới khi người dùng bảo làm tiếp.
- Mốc M3 mục A–E: đã xong (commit `9139688`, tag `m3-ae`, báo cáo R004).

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
| Báo cáo R003 | `cc610ea` |
| M3 mục A: định nghĩa 5 thành phần vào `hids.mdc` | `cc610ea` |
| M3 mục D: bảng flags thêm bit6 CLAMPED | `cc610ea` |
| M3 mục B: trạng thái theo thread, máy trạng thái ON-CPU/OFF-CPU | `b8e75d1` |
| M3 mục C: bộ cộng dồn irq per-CPU, 13 cặp tracepoint | `b8e75d1` |
| M3 mục E: kiểm tra fail-closed lúc khởi động, header mới | `b8e75d1` |
| Sửa thứ tự gắn/gỡ cặp tracepoint irq (lỗi irq vector 660 giây) | `b8e75d1` |
| Chạy thử 30 giây, lưu `validation/m3ae-20261006/` | `9139688` |
| Báo cáo R004, tag `m3-ae` | `9139688` |
| Lưu nguyên văn nhiệm vụ vào `docs/tasks/M3-phan2.md` | `015c83a` |
| PHẦN 1 / 8.2: viết lại mục C theo phương án (c), trạng thái irq riêng từng loại | `015c83a` |
| PHẦN 1 / 8.2: in `recursion_misses` từng chương trình, cột `soft_raw_delta_ns` | `015c83a` |
| PHẦN 1 / 8.3: 4 dòng header `CONFIG_*` đọc từ `/boot/config-$(uname -r)` | `015c83a` |
| PHẦN 1: chạy lại 30 giây + soi chéo, lưu `validation/m3p1-20261007/` | `015c83a` |
| PHẦN 1: chạy lại lần hai với binary từ cây git sạch | `6b4a050` |

## Bước đang làm
Không có. PHẦN 1 đã xong và đã commit. Đang **CHỜ** người dùng đổi model và bảo làm PHẦN 2.

## Bước tiếp theo
1. **DỪNG, chờ người dùng.** Không bắt đầu PHẦN 2 khi chưa được bảo.
2. PHẦN 2 = M3 mục F–J (nguyên văn trong `docs/tasks/M3-phan2.md`): `tools/wl.c`, `bin/rec-check`, `scripts/g3.sh` (S1–S5, G-real, G-irq, chạy lại G7d), lưu `validation/g3-<ngày>/`, commit, tag `m3`, viết R005, rồi DỪNG (không làm M4).
3. Chỉ gắn tag `m3` sau khi mục H đã chạy xong.

## Kết quả chạy thử M3 mục A–E (2026-10-06, `validation/m3ae-20261006/`)
- Verifier nạp được toàn bộ: 1 chương trình `tp_btf/sys_enter`, 3 chương trình sched, 26 chương trình irq (13 cặp).
- Kiểm tra fail-closed lúc khởi động đều qua: 24/24 dòng `vmware-stealtime`; lệch `vmw_ns` so với `rq->prev_steal_time` lớn nhất 155.385 ns, ngưỡng `max(2.000.000 ns, 1%)`.
- 30 giây, tải thử 5 ms đốt CPU + 5 ms ngủ: 5.958 bản ghi, mất 0, file `.periodic` có 5 dòng.
- Tự nhất quán: `|Δt − (cpu+steal+irq+rq+vol)|` lớn nhất 5.853 ns trên 5.957 khoảng; chỉ 1 khoảng lệch > 1.000 ns và đúng khoảng đó mang cờ CLAMPED.
- Phân rã: cpu 49,61%, vol 50,12%, irq 0,20%, rq 0,06%, steal 0,00% — khớp thiết kế của tải thử.
- `irq bat thuong: 0 khoang` và `CPU con do sau khac 0: 0`.
- Sau khi thoát: `bpftool prog/link/map list` không còn dòng `hids_` nào, `/sys/fs/bpf` rỗng.

## Việc đang chạy
Không có. Việc `hids-g7` xong lúc 23:21:06 (mã thoát 0), `hids-g7c` xong lúc 23:23:40 (mã thoát 0), `hids-g7d` xong lúc 23:43:25 (mã thoát 0).

(Định dạng khi có việc: tên | lệnh | giờ bắt đầu | dự kiến xong | log `out/jobs/<tên>.log` | trạng thái `out/jobs/<tên>.status`)

## Ghi nhận cho GĐ4 (CHƯA làm bây giờ)
- **Tấn công làm mù collector.** Kẻ tấn công có thể bơm thật nhiều syscall để ring buffer đầy, làm collector mất bản ghi và không nhìn thấy hành vi thật. Vì vậy số liệu mất bản ghi không phải chỉ là chỉ số sức khoẻ: nó là **tín hiệu phát hiện**. Giai đoạn 4 phải coi một đợt mất bản ghi bất thường là dấu hiệu đáng ngờ, không phải nhiễu cần bỏ qua.
- Chính sách hiện tại của collector (kiến trúc sư chốt ở R003): **không bao giờ im lặng, không bao giờ tự dừng**. Mỗi 10 giây ghi một dòng vào `<out>.bin.periodic` (số lần định ghi và số mất, cả delta lẫn cộng dồn, cộng tổng irq theo loại từ M3); khi delta mất > 0 thì in dòng `LOSS ...` ra stderr và ghi vào log rồi chạy tiếp. Không dừng thu thập vì mất bản ghi.

## Ghi nhận cho M3 (đã làm ở mục E)
- Khi khởi động, collector tự so `vmw_ns` với `rq_steal_ns` trên từng CPU trong 3 giây đầu. Lệch quá `max(2 ms, 1%)` thì **từ chối chạy (fail-closed)** và in bảng từng CPU bị lệch. Cờ `-steal-fallback` để chuyển sang `rq->prev_steal_time`, cờ `-allow-no-stealclock` để chạy với steal = 0.

## Quyết định của kiến trúc sư cho R004 (đã áp dụng ở PHẦN 1)
- Mọi quyết định tự đưa ra ở mục 7 của R004: **chấp nhận**.
- 8.1 Ngưỡng so hai đường steal `max(2 ms, 1%)` trong 3 giây: **giữ nguyên**, không đổi.
- 8.2 Đua trên độ sâu irq: **chọn phương án (c)**. Đã viết lại mục C: bỏ biến độ sâu dùng chung; mỗi CPU giữ trạng thái riêng cho hard, soft, vector (mốc vào, 0 = không hoạt động, và tổng); mỗi trường chỉ do chương trình của đúng loại đó ghi. Soft chụp `hard+vector` lúc vào, trừ phần lồng lúc ra; giữ thêm `soft_raw` chỉ để đối chiếu với `softirqs-bpfcc`. Thành phần irq của thread = hard + vector + soft_excl.
- 8.3 Header thêm 4 dòng `CONFIG_IRQ_TIME_ACCOUNTING`, `CONFIG_PARAVIRT_TIME_ACCOUNTING`, `CONFIG_SCHEDSTATS`, `CONFIG_SCHED_INFO` đọc từ `/boot/config-$(uname -r)`: **đã thêm**.

## Vướng mắc đã được kiến trúc sư ĐÓNG (R004 mục 8.4)
1. **Biên cửa sổ của G7c: theo phương án (c).** Đóng, không cần làm gì thêm.
2. **Đua đọc-sửa-ghi trên độ sâu irq: theo phương án (c).** Đóng. Đã viết lại mục C, không còn biến độ sâu dùng chung.
3. **Ngưỡng cảnh báo khi mất bản ghi.** Đóng ở tầng collector: collector **luôn in dòng `LOSS`** và **không bao giờ tự dừng**. Ngưỡng "bất thường" thuộc **tầng phát hiện (GĐ3)**: ở đó khoảng nào mang cờ `GAP_BEFORE` bị loại khỏi chấm điểm và cộng vào **"thời gian mù"**; ngưỡng cảnh báo sẽ đặt theo ngân sách báo động của fleet, không đặt trong collector.

## Vướng mắc / chờ kiến trúc sư quyết định
Không có.
