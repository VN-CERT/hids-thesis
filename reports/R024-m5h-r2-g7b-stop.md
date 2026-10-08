# R024 — M5h-r2: dừng bước 2 (G7b mat ≠ 0)

1. **Số báo cáo:** R024  
   **Ngày giờ:** 2026-10-09 00:35 (UTC+7)  
   **Mốc:** M5h-r2  
   **Git commit:** `5beaace` (BPF r2); Go `539a171` / `49b9a16`; **không** tag `m5h`  
   *(R023 giữ nguyên — sha256 lần trước; không ghi đè R022.)*

2. **Mục tiêu**  
   Tiếp `docs/tasks/M5h.md`: BPF verifier pass → G7/G3 → đo overhead → tag `m5h`.

3. **Đã làm gì**  
   - Bước 0: sha256 `14d065a601787645b911b7a743e4d6d323757aff0b02bf3487a58fee5fed9d7d` — khớp. Commit `5beaace` «M5h-r2: sua loi verifier (kien truc su)».  
   - Bước 1: `make build` thành công (`5beaace`, không `-dirty`).  
   - Bước 2: G7a (tracepoint) **đạt**; G7a (fentry) **đạt**; G7b (24×1 000 000, 64 MiB) **không đạt** (`mat` = 13 238 390 ≠ 0). **Dừng** — không chạy G3, bước 3–4.  
   - *(Đã chạy G7b-nho trước khi chốt dừng; ghi trong mục 5 — không đạt tiêu chí G7b.)*

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids
   sha256sum bpf/sys_enter.bpf.c
   make build
   bash scripts/g7.sh a 1000000
   HIDS_COLLECT_EXTRA="-sys-enter-hook fentry" bash scripts/g7.sh a 1000000
   bash scripts/g7.sh b 1000000
   # log: validation/m5h-20261009/step2/
   ```

5. **Kết quả**

   **G7a tracepoint (tóm tắt):**  
   ```
   so ban ghi collector doc duoc             : 1000001
   tong bo dem mat (ring buffer day)         : 0
   dinh ghi - ban ghi trong file             : 0
   recursion_misses (bpf_prog_info), tong 0 tren 31 chuong trinh:
   ```

   **G7a fentry (tóm tắt):** cùng mức — `mat` = 0, `recursion_misses` tổng 0 (log: `validation/m5h-20261009/step2/g7a-fentry.log`).

   **G7b — nguyên văn đối chiếu toàn cục (không đạt):**  
   ```
   ban ghi doc duoc: 10761634 | so lan dinh ghi: 24000024 | mat: 13238390
   recursion_misses (bpf_prog_info), tong 0 tren 31 chuong trinh:
   tong ban ghi doc duoc:                        10761634
   tong bo dem mat:                              13238390
   tong (perf - ban ghi):                        13238390
   doi chieu seq (toan cuc)
     so lan dinh ghi (tong seq_cuoi cua moi CPU): 24000024
     so ban ghi collector doc duoc             : 10761634
     so ban ghi dem duoc trong file            : 10761634
     tong bo dem mat (ring buffer day)         : 13238390
     tong so seq bi thieu theo CPU             : 13238390
     dinh ghi - ban ghi trong file             : 13238390
   ```
   File: `out/g7b-20261009-003119.bin.stats`, log `validation/m5h-20261009/step2/g7b.log`.

   **G7b-nho (đã chạy, không thay thế G7b):** `mat` = 14 791 086; `perf − bản ghi` = 14 791 086 (khớp tuyệt đối mất, như R019) — nhưng G7b 64 MiB đã fail trước đó.

   **G3 S1–S5, bước 3 đo, tag `m5h`:** chưa chạy.

6. **File dữ liệu**  
   - `/root/hids/validation/m5h-20261009/step2/g7a-tp.log`  
   - `/root/hids/validation/m5h-20261009/step2/g7a-fentry.log`  
   - `/root/hids/validation/m5h-20261009/step2/g7b.log`  
   - `/root/hids/validation/m5h-20261009/step2/g7b-nho.log`  
   - `/root/hids/out/g7b-20261009-003119.bin.stats`

7. **Quyết định đã tự đưa ra**  
   - Áp tiêu chí R019/M5h: G7b 24×1 000 000 yêu cầu `mat` = 0 (không chỉ khớp perf).  
   - Báo cáo số **R024** vì R023 đã dùng cho lần dừng sha256.

8. **Cần kiến trúc sư quyết định**  
   - BPF M5h-r2 + reader user space: tại sao G7b 64 MiB mất ~55% bản ghi (`mat` = perf diff) trong khi G7a đạt `mat` = 0? Có chấp nhận tiêu chí khác, giảm tải G7b, hay sửa BPF/Go trước khi đo overhead?

9. **Việc người dùng cần làm tay**  
   - (Không) — chờ hướng kiến trúc sư.

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Hoàn thành G7b `mat` = 0 rồi chạy G7b-nho + G3 + bước 3–4; báo cáo mới (R025).
