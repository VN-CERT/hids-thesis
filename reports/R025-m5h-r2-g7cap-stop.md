# R025 — M5h-r2: G7b zstd0 đạt; dừng G7-cap (mat ≠ 0)

1. **Số báo cáo:** R025  
   **Ngày giờ:** 2026-10-09 00:45 (UTC+7)  
   **Mốc:** M5h-r2 (tiếp sau quyết định R024)  
   **Git commit:** `75b162b` / BPF `5beaace`; **không** tag `m5h`

2. **Mục tiêu**  
   Theo kiến trúc sư: G7b/G7b-nho với `-zstd-level 0`; G7-cap zstd mặc định `mat`=0; G3 S1–S5; nếu đạt → M5h bước 3–4 + tag `m5h`.

3. **Đã làm gì**  
   - G7b + G7b-nho lại với `HIDS_COLLECT_EXTRA="-zstd-level 0"` — **đạt**.  
   - G7-cap 2 tiến trình / 60 s / zstd mặc định (`scripts/m5f_g7cap2.sh`) — **không đạt** (`mat` 7–8 triệu). **Dừng**; không G3, không bước 3–4 M5h.

4. **Lệnh chạy**  
   ```bash
   cd /root/hids
   HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh b 1000000
   HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh b-nho 1000000
   G7_CAP_OUT=validation/m5h-20261009/step2/g7-cap bash scripts/m5f_g7cap2.sh
   ```

5. **Kết quả**

   **Quyết định kiến trúc sư (R024):** G7b lần trước mất do zstd mặc định (~2,4M bản ghi/s > ~1,3M khi nén); đếm khớp tuyệt đối. G7b/G7b-nho regression dùng `-zstd-level 0`.

   **G7b `-zstd-level 0` (nguyên văn đối chiếu):**  
   ```
     tong bo dem mat (ring buffer day)         : 0
     tong so seq bi thieu theo CPU             : 0
     dinh ghi - ban ghi trong file             : 0
   ```
   Log: `validation/m5h-20261009/step2/g7b-zstd0.log`

   **G7b-nho `-zstd-level 0`:**  
   ```
   ban ghi doc duoc: 20697818 | so lan dinh ghi: 24000024 | mat: 3302206
   tong bo dem mat:                              3302206
   tong (perf - ban ghi):                        3302206
     tong so seq bi thieu theo CPU             : 3302206
     dinh ghi - ban ghi trong file             : 3302206
   ```
   Log: `validation/m5h-20261009/step2/g7b-nho-zstd0.log`

   **G7-cap zstd mặc định — lượt 1 (nguyên văn collector):**  
   ```
   LOSS mono_ns=36673025095384 mat=1512341 dinh_ghi=12887964 ti_le=11.735% mat_tong=1512341 dinh_ghi_tong=50422162 (ring buffer day, van thu thap tiep)
   LOSS mono_ns=36683022162193 mat=4857952 dinh_ghi=15617543 ti_le=31.106% mat_tong=6370293 dinh_ghi_tong=66039705 (ring buffer day, van thu thap tiep)
   LOSS mono_ns=36693022088875 mat=2088099 dinh_ghi=13883842 ti_le=15.040% mat_tong=8458392 dinh_ghi_tong=79923547 (ring buffer day, van thu thap tiep)
   ban ghi doc duoc: 72618011 | so lan dinh ghi: 81076403 | mat: 8458392
   recursion_misses (bpf_prog_info), tong 0 tren 31 chuong trinh:
   ```
   File: `validation/m5h-20261009/step2/g7-cap/zstd-default-p2-20261009-003827-collect.log`  
   Script: `recs=72618011 mat=8458392` → exit 1

   **G7-cap — lượt 2 (xác nhận):**  
   ```
   LOSS mono_ns=36744146022178 mat=1016535 dinh_ghi=12504875 ti_le=8.129% mat_tong=1016535 dinh_ghi_tong=47730624 (ring buffer day, van thu thap tiep)
   LOSS mono_ns=36754152047295 mat=5783901 dinh_ghi=16161905 ti_le=35.787% mat_tong=6800436 dinh_ghi_tong=63892529 (ring buffer day, van thu thap tiep)
   LOSS mono_ns=36764148089338 mat=672887 dinh_ghi=11620351 ti_le=5.791% mat_tong=7473323 dinh_ghi_tong=75512880 (ring buffer day, van thu thap tiep)
   ban ghi doc duoc: 69091435 | so lan dinh ghi: 76564758 | mat: 7473323
   ```
   File: `validation/m5h-20261009/step2/g7-cap/zstd-default-p2-20261009-003938-collect.log`

   **Tham chiếu M5f (cùng script):** R021 G7-cap2 `recs=74442243 mat=0` (trước BPF r2).

   **G3 S1–S5, M5h bước 3–4:** chưa chạy.

6. **File dữ liệu**  
   - `/root/hids/validation/m5h-20261009/step2/g7b-zstd0.log`  
   - `/root/hids/validation/m5h-20261009/step2/g7b-nho-zstd0.log`  
   - `/root/hids/validation/m5h-20261009/step2/g7-cap/`  
   - `/root/hids/docs/tasks/M5h.md`

7. **Quyết định đã tự đưa ra**  
   - Chạy G7-cap hai lần vì lần 1 exit 1 trong pipeline `tee` dễ bị hiểu nhầm; cả hai lần `mat` > 0.

8. **Cần kiến trúc sư quyết định**  
   - G7-cap `mat`=0 là bắt buộc để tiếp M5h hay chấp nhận mất ~10% khi zstd+stress 24 CPU sau BPF r2?  
   - Có điều chỉnh tải (1 tiến trình, thời gian ngắn hơn, ring lớn hơn) hay sửa đường nén/đọc user space?

9. **Việc người dùng cần làm tay**  
   - (Không)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Sau G7-cap `mat`=0: G3 → `scripts/m5h.sh` (bước 3–4) → R026 + tag `m5h`.
