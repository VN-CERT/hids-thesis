# R039 — M6h: C5 trên lab và production

1. Số báo cáo: R039. Ngày giờ: 2026-11-07 08:17 (+07). Mốc: M6h. Git: tag `m6h` (commit chứa báo cáo này).

2. Mục tiêu

Chạy đường ống C5 trên dữ liệu lab đã có và trên production đã kéo (202 file), không rsync lại. Cửa sổ 7 ngày chỉ áp cho `nen`. Production không có `start_mono_ns`; lấy `khoi_dong_monotonic_s` (giây) × 1e9. Huấn luyện = start + 5 ngày. Kiểm tra = ngày 6–7. Áp ngưỡng lab (mức phát hiện 0,90 / 0,95 / 1,00) lên điểm production. In bảng (a)–(e). Không kết luận.

3. Đã làm gì

- `scripts/c5_pipeline.sh`: nếu không có `start_mono_ns` thì đọc `khoi_dong_monotonic_s`. Phần thập phân của giây được đổi sang nano-giây bằng số nguyên (`2858.09` → `2858090000000`). Thiếu cả hai thì báo lỗi.
- Cùng file: cột nhãn liều dùng `dose_id` khi không có cột `id`, để phiên `BEN-*` vào `muc.tsv`. Chấm lại lab từ feature đã có, không trích lại `.bin`.
- Production: `scripts/c5_m6h_prod.sh`, unit `hids-m6h-prod`, 202 file đã có trên đĩa. Không rsync.
- `scripts/c5_apply_threshold.py` đọc ngưỡng lab và đếm cửa sổ production.

4. Lệnh

```
bash scripts/c5_pipeline.sh /root/hids/validation/lab1-20261024 /root/hids/out/c5-lab1
systemd-run --unit=hids-m6h-prod --collect bash -c 'cd /root/hids && bash scripts/c5_m6h_prod.sh'
systemd-run --unit=hids-m6h-lab-rescore --collect bash -c 'cd /root/hids && bash scripts/c5_pipeline.sh /root/hids/validation/lab1-20261024 /root/hids/out/c5-lab1'
python3 scripts/c5_apply_threshold.py --tom-tat /root/hids/out/c5-lab1/score/tom_tat.tsv --prod-score /root/hids/out/c5-prod/score
```

Lab đầy đủ (trích + chấm): 2026-11-02 10:49 → 2026-11-03 11:27. `TIME_lab_pipe real=88683.13 sec maxrss_kb=7639384`.
Chấm lại lab (bỏ qua file feature đã có): `TIME_lab_rescore real=1341.47 sec maxrss_kb=2462152`. `TIME_score real=610.49 sec`.
Production: 2026-11-06 14:44:13 → 2026-11-07 01:58:01. `TIME_prod_pipe real=40421.93 sec maxrss_kb=9042232`. `TIME_score real=3470.44 sec`.

Mốc production: `nguon_moc=khoi_dong_monotonic_s`, `t_min=2858090000000`, `t_max=607658090000000`, `train_until=434858090000000`.
Mốc lab: `t_min=401189871480814`, `train_until=833189871480814`.

5. Kết quả

### Giữ / bỏ bản ghi

Production (`out/c5-prod/giu_bo.tsv`), chỉ `nen`:

```
nen files=202 giu=1668929925 bo=286262252
```

`tong_bo_qua_ngoai_7ngay 286262252`. `bang_kiem_OK` (không có nhãn tấn công).

Lab, sau lần trích phiên (2026-11-02): bn 16 file giu=16733509 bo=0; benign-lieu 15 file giu=34285851 bo=0; slow 0 file `.bin`. Nền lab nằm trong 210 file feature.

Cửa sổ lab (`out/jobs/m6h-lab-rescore.log`):

```
cua_so_theo_nguon	benign-lieu=18716	bn=15806	nen=1099625
cua_so_theo_muc	0=1105099	2=5124	4=4932	D1-16=3138	D1-2=3342	D1-4=3084	D1-8=3252	D3-4=3070	D3-7=3106
moc_cat_ngay5_ns	833189871480814
bang_kiem_OK
```

`# c5_score  cat_huan_luyen=833189871480814  cua_so=1134147  nhan_tan_cong=8  muc=43`

Production:

```
# c5_score  cat_huan_luyen=434858090000000  cua_so=4202380  nhan_tan_cong=0  muc=1
=== AGG_cgroup_giay === huan_luyen=14506 kiem_tra=5804 (nen:5804)
=== BASELINE_dt_tho === huan_luyen=1475705 kiem_tra=614336 (nen:614336)
=== PHANRA_5tp === huan_luyen=1475705 kiem_tra=614336 (nen:614336)
```

`c5_score` trên production in `nan` cho ngưỡng và báo động giả, vì không có nhãn tấn công nên không tính được mức phát hiện. Ngưỡng đem áp là ngưỡng lab.

### (a) tom_tat lab — nguyên văn `out/c5-lab1/score/tom_tat.tsv`

Đường đầy đủ: `out/c5-lab1/score/tradeoff_AGG_cgroup_giay.tsv`, `tradeoff_BASELINE_dt_tho.tsv`, `tradeoff_PHANRA_5tp.tsv`.

```
branch	muc_phat_hien	nguong	bao_dong_gia
AGG_cgroup_giay	0.50	2.8942	0.8125
AGG_cgroup_giay	0.80	0.8359	0.9288
AGG_cgroup_giay	0.90	0.7611	0.9608
AGG_cgroup_giay	0.95	0.7316	0.9875
AGG_cgroup_giay	1.00	0.7151	0.9991
BASELINE_dt_tho	0.50	1.0797	0.6942
BASELINE_dt_tho	0.80	0.6589	0.8343
BASELINE_dt_tho	0.90	0.6135	0.8844
BASELINE_dt_tho	0.95	0.5675	0.9291
BASELINE_dt_tho	1.00	0.3672	0.9757
PHANRA_5tp	0.50	1.2480	0.7470
PHANRA_5tp	0.80	0.7672	0.9443
PHANRA_5tp	0.90	0.6596	0.9665
PHANRA_5tp	0.95	0.6111	0.9728
PHANRA_5tp	1.00	0.4110	0.9884
```

So với bản `tom_tat` trước khi chấm lại (đổi `dose_id`): diff rỗng. Ngưỡng không đổi.

### (b) Báo động giả theo mức tranh chấp, mức phát hiện 0,90

Dòng `theo muc` của `c5_score` trên lab. Số trong ngoặc là số cửa sổ không phải tấn công. Khóa `0`, `2`, `4` là `D1-N=0/2/4` trong `nhan-tan-cong.tsv`. `D1-8`, `D1-16`, `D3-4`, `D3-7` là `BEN-*`. Thêm `D1-2` và `D1-4` từ `BEN-D1-2` và `BEN-D1-4`.

```
AGG_cgroup_giay 0.90	0.7611	0.9608
  theo muc: 0:0.9633(11674)  2:0.7685(108)  4:0.8646(96)  D1-16:1.0000(124)  D1-2:0.8971(136)  D1-4:0.9597(124)  D1-8:1.0000(124)  D3-4:0.9274(124)  D3-7:0.9921(126)
BASELINE_dt_tho 0.90	0.6135	0.8844
  theo muc: 0:0.8789(152788)  2:0.9403(1222)  4:0.9414(1110)  D1-16:1.0000(1507)  D1-2:0.9407(1603)  D1-4:0.8297(1480)  D1-8:1.0000(1564)  D3-4:1.0000(1473)  D3-7:1.0000(1490)
PHANRA_5tp 0.90	0.6596	0.9665
  theo muc: 0:0.9661(152788)  2:0.9591(1222)  4:0.9586(1110)  D1-16:1.0000(1507)  D1-2:0.9601(1603)  D1-4:0.8872(1480)  D1-8:1.0000(1564)  D3-4:1.0000(1473)  D3-7:1.0000(1490)
```

### (c) Cửa sổ giao từng đợt tấn công, ngưỡng lab mức phát hiện 0,90

Đếm trên `scores_<nhánh>.tsv` (cửa sổ kiểm tra). Giao nếu khoảng cửa sổ cắt khoảng trong `lab/nhan-tan-cong.tsv`. Tên đợt ghép từ `id`, `nhip_tham_so`, `muc_tranh_chap`: `period=10` + `B1` + `D1-N=k` → `B1-10s@Nk`; `period=2s/20s` + `B4` → `B4@Nk`; `period=60` → `B1-60s`; `period=300` → `B1-300s`.

Cột: đợt, số cửa sổ giao, số cửa sổ có điểm ≥ ngưỡng, tỉ lệ.

```
branch	id	n	n_diem_ge_nguong	ty_le
AGG_cgroup_giay	B1-10s@N0	54	54	1.0000
AGG_cgroup_giay	B1-10s@N2	54	46	0.8519
AGG_cgroup_giay	B1-10s@N4	54	44	0.8148
AGG_cgroup_giay	B4@N0	54	42	0.7778
AGG_cgroup_giay	B4@N2	54	54	1.0000
AGG_cgroup_giay	B4@N4	54	52	0.9630
AGG_cgroup_giay	B1-60s	0	0	nan
AGG_cgroup_giay	B1-300s	0	0	nan
BASELINE_dt_tho	B1-10s@N0	731	543	0.7428
BASELINE_dt_tho	B1-10s@N2	628	601	0.9570
BASELINE_dt_tho	B1-10s@N4	621	579	0.9324
BASELINE_dt_tho	B4@N0	629	584	0.9285
BASELINE_dt_tho	B4@N2	604	568	0.9404
BASELINE_dt_tho	B4@N4	633	587	0.9273
BASELINE_dt_tho	B1-60s	0	0	nan
BASELINE_dt_tho	B1-300s	0	0	nan
PHANRA_5tp	B1-10s@N0	731	509	0.6963
PHANRA_5tp	B1-10s@N2	628	606	0.9650
PHANRA_5tp	B1-10s@N4	621	593	0.9549
PHANRA_5tp	B4@N0	629	569	0.9046
PHANRA_5tp	B4@N2	604	581	0.9619
PHANRA_5tp	B4@N4	633	604	0.9542
PHANRA_5tp	B1-60s	0	0	nan
PHANRA_5tp	B1-300s	0	0	nan
```

Ngưỡng: AGG 0,7611; BASELINE 0,6135; PHANRA 0,6596.

`B1-60s` có `t_bat_dau_mono_ns=402498977730967`. `B1-300s` có `406099228255978`. Cả hai nhỏ hơn mốc cắt ngày 5 (`833189871480814`) và lớn hơn `start_mono_ns` lab. Thư mục `slow/` không có file `.bin`. `scores_*.tsv` chỉ chứa cửa sổ kiểm tra, nên hai đợt này có 0 dòng giao.

### (d) Production — nguyên văn `out/c5-prod/bao_dong_gia_prod.tsv`

`bao_dong_moi_host_ngay` = số cửa sổ báo động / 2. `tid_ngay` nhóm theo `start_ns // 86400e9`.

```
branch	muc_phat_hien	nguong_lab	n_cua_so	n_bao_dong	ty_le	bao_dong_moi_host_ngay	tid_ngay_bao	tid_ngay_quan_sat	ty_le_tid_ngay
AGG_cgroup_giay	0.90	0.7611	5804	4849	0.835458	2424.5000	3	3	1.000000
AGG_cgroup_giay	0.95	0.7316	5804	4952	0.853205	2476.0000	3	3	1.000000
AGG_cgroup_giay	1.00	0.7151	5804	5019	0.864748	2509.5000	3	3	1.000000
BASELINE_dt_tho	0.90	0.6135	614336	573523	0.933566	286761.5000	236855	260071	0.910732
BASELINE_dt_tho	0.95	0.5675	614336	598231	0.973785	299115.5000	258386	260071	0.993521
BASELINE_dt_tho	1.00	0.3672	614336	607884	0.989498	303942.0000	259997	260071	0.999715
PHANRA_5tp	0.90	0.6596	614336	558270	0.908737	279135.0000	210989	260071	0.811275
PHANRA_5tp	0.95	0.6111	614336	592797	0.964939	296398.5000	243513	260071	0.936333
PHANRA_5tp	1.00	0.4110	614336	613946	0.999365	306973.0000	260070	260071	0.999996
```

### (e) Overhead thực địa

Nguồn: `validation/prod1/LAB-PROD-1-FINAL.txt` và `validation/prod1/suc-khoe.tsv` (203 dòng số). Đoạn tóm tắt trong FINAL, nguyên văn:

```
cpu_seconds_delta_trung_vi=63.109
cpu_seconds_delta_p95=80.667
cpu_seconds_total_dau=1.781 cuoi=13116.599
rss_bytes_dau=187273216 cuoi=226652160
tong_kernel_drops_delta=0
tong_proc_drops_delta=0
```

```
16G	/srv/hids-data/prod1/benign
```

Journal trong cùng file:

```
Oct 24 23:08:49 Postgres-primary hids-collect[17521]: longrun datadir=/srv/hids-data/prod1/benign rotate=1h0m0s min_free_gb=50
Nov 02 08:27:02 Postgres-primary hids-collect[17521]: ket thuc longrun end_mono_ns=727562479229015 disk_skipped=0
KET LUAN: co dau hieu thieu dia / ngung ghi — xem chi tiet tren.
```

`records_per_sec` trên 203 mẫu: min 1965.2, trung vị 2521.43, max 4960.52.
`cpu_seconds_delta`: min 1.781, trung vị 63.109, max 91.03. Trung vị / 3600 = 0.017530 (1.753% của một lõi), tính từ cột `cpu_seconds_delta` của các mẫu cách nhau khoảng một giờ.

Dung lượng cộng dồn `dung_luong_GB` ở mẫu cuối mỗi ngày, và trung vị `records_per_sec` trong ngày (tính từ `suc-khoe.tsv`):

```
ngay	so_mau	rec_per_sec_median	cpu_seconds_delta_median	dung_luong_GB_cuoi	rss_cuoi
2026-10-24	2	2390.53	10.166	0.0224	199970816
2026-10-25	24	2490.34	60.893	1.7146	217894912
2026-10-26	24	2592.56	65.160	3.5474	225103872
2026-10-27	24	2637.76	65.685	5.4265	226652160
2026-10-28	24	2675.68	67.686	7.5087	226652160
2026-10-29	24	2986.47	72.761	9.7887	226652160
2026-10-30	24	2684.43	68.553	11.7652	226652160
2026-10-31	24	2492.11	61.934	13.4629	226652160
2026-11-01	24	2382.85	62.350	15.0593	226652160
2026-11-02	9	2310.18	59.724	15.6175	226652160
```

Năm tiêu chí nền trong `validation/lab1-20261024/lab1-FINAL.txt`, nguyên văn:

```
--- kiem 5 tieu chi §2 ---
doc /srv/hids-data/lab1-benign/suc-khoe.tsv
so_dong=181
1_kernel_drops_sum=0.0 proc_drops_sum=0.0 -> DAT
2_pmu_pct min=0.0 max=5.0 -> KHONG_DAT
3_cpu_seconds_total first=0.54 last=6503.54 (doi chieu thu cong <=3% loi)
4_rss first=172896256.0 last=186585088.0 change_pct=7.92 -> DAT
5_khoang_mu: can scripts/phan tich .bin (khong tu dong o day); xem gen nhip-benign.tsv
nhip_benign=/srv/hids-data/lab1-benign/gen-logs/nhip-benign.tsv
```

### SVG

- Lab: `out/c5-lab1/bao_dong_gia_muc_det90.svg` (4808 byte, 2026-11-07 08:16)
- Production: `out/c5-prod/bao_dong_gia_muc_det90.svg` (2.1K, 2026-11-07 01:57)

### Dung lượng và thời gian

- Lab `.bin` đã liệt kê lúc trích: 210 file, 34271520478 byte (34.272 GB).
- Production: `tong_file=202 tong_byte=16747044812 tong_GB=16.747`.
- `out/c5-lab1/features_all.tsv` 185 MB. `out/c5-prod/features_all.tsv` 668 MB.
- Đĩa trống trước production: khoảng 3355 GB. Sau trích: còn trên 3350 GB. Không ghi CSV đầy đủ của `.bin` (pipe `rec-export` vào `c5_extract`).

### sha256 bảy file kiến trúc sư (lúc viết báo cáo)

Năm file của M6c-3, cộng `detector_c5.py` và `c5_score.py` v1.2. `c5_score.py` khớp gói M6h (`a368c78b…`).

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
7bce6a15feb7879e16f511ac88ec555e35ba11a67b34acda1f0886e6004f879e  analysis/detector_c5.py
a368c78b69858829876c1646a17f43b659d794c6e09b8593dbdc62062ced1c1f  analysis/c5_score.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
```

6. File dữ liệu

- `out/c5-lab1/` (feature, `score/tom_tat.tsv`, `score/scores_*.tsv`, `score/tradeoff_*.tsv`, SVG)
- `out/c5-prod/` (cùng loại, thêm `bao_dong_gia_prod.tsv`)
- Log: `out/jobs/m6h-lab.log`, `out/jobs/m6h-prod.log`, `out/jobs/m6h-lab-rescore.log`
- Không commit `.bin` và `.tsv` lớn.

7. Quyết định đã tự đưa ra

- Đổi giây thập phân sang nano-giây bằng số nguyên, không dùng số thực.
- Chấm lại lab sau khi `muc.tsv` đọc `dose_id`. Feature nền và phiên giữ nguyên. Ngưỡng `tom_tat` không đổi, nên bảng production áp ngưỡng không chạy lại.
- Bảy file sha256 = năm file M6c-3 + `detector_c5.py` + `c5_score.py`. Gói M6h chỉ đưa `c5_score.py`.

### Thay đổi ngoài phạm vi

- Đĩa trống yêu cầu ≥ 90 GB (bổ sung), đo được khoảng 3,3 TB.
- Không ghi TSV đầy đủ của nền ra đĩa; pipe từng `.bin`.
- Cửa sổ 7 ngày chỉ cho `nen`. Phiên `bn` và `benign-lieu` giữ mọi bản ghi. `slow/` không có `.bin`. Không có `d2/`.
- Bỏ `payload.bin`.
- File FINAL lab trên 201 nằm ở `/root/collector/validation/lab1-FINAL.txt`.
- `benign-khoi-dong.txt` của máy 90 dùng `khoi_dong_monotonic_s`, không dùng `start_mono_ns`.

8. Cần kiến trúc sư quyết định

1. `B1-60s` và `B1-300s` có 0 cửa sổ trong `scores_*.tsv`. Mốc thời gian của hai đợt nằm trước mốc cắt ngày 5 của nền lab, và `slow/` không có `.bin`. Có tính phát hiện trên các cửa sổ nền của ngày 1–5 hay giữ 0?
2. `c5_score` trên production in `nan` vì không có nhãn tấn công. Bảng (d) dùng ngưỡng lab. Cách này có đúng bài không?
3. Khóa `theo muc` là `0/2/4` và `D1-*`/`D3-*`, không có nhãn riêng `N0/N2/N4`. `0/2/4` lấy từ `D1-N=`. Có cần tách nền bn khỏi khóa `0` không?

9. Việc người dùng cần làm tay

Không có.

10. Lỗi còn tồn tại, việc tiếp theo

Không có job đang chạy.
