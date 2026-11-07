# R041 — M6i-c1: chẩn đoán điểm số và trích đặc trưng siêu tập C5 v2

1. Số báo cáo: R041. Ngày giờ: 2026-11-07 12:26 (+07). Mốc: M6i-c1. Git: `c5_score.py` v1.3.2 ở commit `d59d0ac`. Tag `m6i.1` gắn trên commit báo cáo này.

2. Mục tiêu

Chẩn đoán điểm số (không kết luận). Viết `c5_extract_v2` và bắt đầu trích `features_all_v2`. Không đo lại, không rsync, không ghi đè `features_all.tsv` / `score-*` cũ.

## Bối cảnh (nguyên văn)

"R040/M6i-b: ngưỡng tại ngân sách ≤ 0,05 là 1e5–4e7 ở cả ba cách chuẩn hoá, nên điểm của các cửa sổ vượt ngưỡng đến từ một chiều có MAD quá nhỏ (MAD = 0 thay bằng 1e-9, hoặc quần thể trộn loại tiến trình chênh nhau nhiều bậc). Ở ngân sách 0,1/0,2 không nhánh nào đổi báo động giả dưới D1/D3. Hai dịch vụ nền chạy vòng hở (wrk2 −R, pgbench −R) nên Δt bị neo vào nhịp đến; tranh chấp thế chỗ phần ngủ bằng rq chứ không kéo dài Δt. M6i-c1 chỉ đo để kiến trúc sư thiết kế C5 v2 trên bản lặp r1 của các phiên liều; r2, LAB-1c, production giữ làm tập kiểm."

3. Đã làm gì

- CAI `goi-195-m6ic1` in `XONG`. sha256 `c5_score.py` = `cd90de2ab97ecebd56cf177fa53acc40d2b4d0c8e0cc725edf87c16371e8472b`. Commit `d59d0ac` đúng câu kiến trúc sư.
- Chấm lại bốn bộ v1.3.2 → `score-v132-{tocdo,nhip,khong}` và `out/c5-prod/score-v132-tocdo`. `cmp` `tom_tat_ngan_sach.tsv`, `tradeoff_*.tsv`, `duong_tranh_chap_*.tsv` với bộ v131: cả bốn **KHOP**.
- Viết `scripts/c5_extract_v2.py` (bản sao v1 + cột siêu tập). Equiv cột cũ = 0; known-answer cột mới KHOP.
- Đo 10M tổng hợp M6g-b; ước lượng lab < 40 giờ → chạy trích.
- Hai unit `hids-m6ic1-labv2` và `hids-m6ic1-prodv2` (nice 10) đang chạy song song.
- `scripts/c5_dap_ung.py` và watcher `scripts/c5_m6ic1_r041b.sh` sẵn; phụ lục R041-b khi lab xong.

4. Lệnh

```
python3 analysis/c5_score.py ... # bon lan, xem scripts/c5_m6ic1_score.sh
python3 scripts/c5_equiv_test_v2.py
# perf 10M: cat CSV c5-syn-10m | c5_extract_v2
systemd-run --unit=hids-m6ic1-labv2 --collect bash -c 'cd /root/hids && nice -n 10 bash scripts/c5_pipeline_v2_extract.sh validation/lab1-20261024 out/c5-lab1 m6ic1-labv2'
systemd-run --unit=hids-m6ic1-prodv2 --collect bash -c 'cd /root/hids && nice -n 10 bash scripts/c5_pipeline_v2_extract.sh validation/prod1 out/c5-prod m6ic1-prodv2'
```

5. Kết quả

### (1) Chẩn đoán bước 1 — hồi quy v1.3.2

```
CMP_OK lab-tocdo
CMP_OK lab-nhip
CMP_OK lab-khong
CMP_OK prod-tocdo
```

Thời gian/RSS chấm: lab toc_do 0:37.25 / 796400 kB; nhip 0:35.53 / 813740; khong 0:31.22 / 791800; prod toc_do 2:01.55 / 2890308.

#### (a)(b)(c) MAD=0, chieu_max 1%, chieu_max vượt ngưỡng

```
======== lab-tocdo ========
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== AGG_cgroup_giay === huan_luyen=28921 kiem_tra=12960 (benign-lieu:746 bn:648 nen:11566) chieu=syscall_rate_mean,syscall_rate_cv,cpu_rate_mean,cpu_rate_cv,own_rate_mean,own_rate_cv,tids_mean
chieu_max cua 1 % diem huan luyen cao nhat (>= 20.1050): own_rate_cv:255  cpu_rate_mean:26  cpu_rate_cv:4  syscall_rate_mean:3  syscall_rate_cv:1
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: cpu_rate_cv:4  cpu_rate_mean:3
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_rate_cv:139  cpu_rate_cv:4  cpu_rate_mean:4
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_rate_cv:595  cpu_rate_mean:5  cpu_rate_cv:4  own_rate_mean:1
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== BASELINE_dt_tho === huan_luyen=377766 kiem_tra=168083 (benign-lieu:8985 bn:7579 nen:151519) chieu=dt_med,dt_p90,dt_iqr,dt_cv
chieu_max cua 1 % diem huan luyen cao nhat (>= 39940472.7985): dt_p90:3779
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: dt_p90:181
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: dt_p90:1526
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: dt_med:4499  dt_p90:3974  dt_iqr:44
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== PHANRA_5tp === huan_luyen=377766 kiem_tra=168083 (benign-lieu:8985 bn:7579 nen:151519) chieu=own_med,own_p90,own_iqr,own_cv,cpu_med,cpu_p90,cpi_med
chieu_max cua 1 % diem huan luyen cao nhat (>= 40799402.9821): own_p90:3779
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: own_p90:180
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_p90:1530
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_med:5258  own_p90:3971  own_iqr:44
======== lab-nhip ========
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== AGG_cgroup_giay === huan_luyen=28921 kiem_tra=12960 (benign-lieu:746 bn:648 nen:11566) chieu=syscall_rate_mean,syscall_rate_cv,cpu_rate_mean,cpu_rate_cv,own_rate_mean,own_rate_cv,tids_mean
chieu_max cua 1 % diem huan luyen cao nhat (>= 20.8675): own_rate_cv:202  cpu_rate_cv:87
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: own_rate_cv:12
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_rate_cv:98  cpu_rate_cv:23  cpu_rate_mean:1
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_rate_cv:565  cpu_rate_cv:28  cpu_rate_mean:2
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== BASELINE_dt_tho === huan_luyen=377766 kiem_tra=168083 (benign-lieu:8985 bn:7579 nen:151519) chieu=dt_med,dt_p90,dt_iqr,dt_cv
chieu_max cua 1 % diem huan luyen cao nhat (>= 37960736.4606): dt_p90:3780
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: dt_p90:153
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: dt_p90:1576
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: dt_med:4609  dt_p90:3971  dt_iqr:44
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== PHANRA_5tp === huan_luyen=377766 kiem_tra=168083 (benign-lieu:8985 bn:7579 nen:151519) chieu=own_med,own_p90,own_iqr,own_cv,cpu_med,cpu_p90,cpi_med
chieu_max cua 1 % diem huan luyen cao nhat (>= 38674010.0871): own_p90:3780
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: own_p90:153
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_p90:1576
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_med:4668  own_p90:3971  own_iqr:44
======== lab-khong ========
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== AGG_cgroup_giay === huan_luyen=28921 kiem_tra=12960 (benign-lieu:746 bn:648 nen:11566) chieu=syscall_rate_mean,syscall_rate_cv,cpu_rate_mean,cpu_rate_cv,own_rate_mean,own_rate_cv,tids_mean
chieu_max cua 1 % diem huan luyen cao nhat (>= 19.1183): own_rate_cv:289
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: own_rate_cv:40
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_rate_cv:88
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_rate_cv:586
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== BASELINE_dt_tho === huan_luyen=377766 kiem_tra=168083 (benign-lieu:8985 bn:7579 nen:151519) chieu=dt_med,dt_p90,dt_iqr,dt_cv
chieu_max cua 1 % diem huan luyen cao nhat (>= 16783966.9016): dt_p90:3777
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: dt_p90:251
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: dt_p90:1574
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: dt_med:4933  dt_p90:4419
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== PHANRA_5tp === huan_luyen=377766 kiem_tra=168083 (benign-lieu:8985 bn:7579 nen:151519) chieu=own_med,own_p90,own_iqr,own_cv,cpu_med,cpu_p90,cpi_med
chieu_max cua 1 % diem huan luyen cao nhat (>= 16914853.5638): own_p90:3777
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: own_p90:258
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_p90:1574
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_med:4906  own_p90:4419
======== prod-tocdo ========
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== AGG_cgroup_giay === huan_luyen=14506 kiem_tra=5804 (nen:5804) chieu=syscall_rate_mean,syscall_rate_cv,cpu_rate_mean,cpu_rate_cv,own_rate_mean,own_rate_cv,tids_mean
chieu_max cua 1 % diem huan luyen cao nhat (>= 5.2642): own_rate_cv:49  own_rate_mean:38  cpu_rate_mean:34  syscall_rate_mean:14  cpu_rate_cv:9  syscall_rate_cv:1
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: cpu_rate_mean:2  own_rate_cv:1  syscall_rate_mean:1  syscall_rate_cv:1
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_rate_cv:39  own_rate_mean:8  cpu_rate_mean:7  cpu_rate_cv:1  syscall_rate_mean:1  tids_mean:1  syscall_rate_cv:1
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_rate_cv:261  own_rate_mean:22  cpu_rate_mean:21  cpu_rate_cv:19  tids_mean:10  syscall_rate_mean:9  syscall_rate_cv:2
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== BASELINE_dt_tho === huan_luyen=1475705 kiem_tra=614336 (nen:614336) chieu=dt_med,dt_p90,dt_iqr,dt_cv
chieu_max cua 1 % diem huan luyen cao nhat (>= 116573.4457): dt_iqr:7531  dt_p90:7227
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: dt_p90:565  dt_iqr:36  dt_med:1
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: dt_iqr:4235  dt_p90:3899  dt_med:1
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: dt_p90:29937  dt_iqr:4358  dt_med:1
chieu co MAD=0 (dung EPS=1e-9) theo dai: 0
=== PHANRA_5tp === huan_luyen=1475705 kiem_tra=614336 (nen:614336) chieu=own_med,own_p90,own_iqr,own_cv,cpu_med,cpu_p90
chieu_max cua 1 % diem huan luyen cao nhat (>= 120420.3407): own_iqr:7559  own_p90:7198
  [ngan_sach=0.001] chieu_max cua cua so benign vuot nguong: own_p90:565  own_iqr:36  own_med:1
  [ngan_sach=0.01] chieu_max cua cua so benign vuot nguong: own_iqr:4243  own_p90:3906  own_med:1
  [ngan_sach=0.05] chieu_max cua cua so benign vuot nguong: own_p90:29940  own_iqr:4363  own_med:1
```

#### (d) chuan_* — dải có ≥ 1000 cửa sổ huấn luyện

Lab `toc_do` BASELINE (đầy đủ). Các nhánh/bộ khác: `out/jobs/m6ic1-diag/chuan_ge1000_*.tsv`.

```
dai	chieu	n	median	MAD	MAD_over_median	mad0
*	dt_med	377766	21137.5	2153.5	0.101881	0
*	dt_p90	377766	80898	7237	0.0894583	0
*	dt_iqr	377766	42201	11245	0.266463	0
*	dt_cv	377766	7.04212926	0.104614758	0.0148556	0
r7	dt_med	1598	22861.75	803.5	0.035146	0
r7	dt_p90	1598	86307	5037.5	0.0583672	0
r7	dt_iqr	1598	50007.5	4686.5	0.0937159	0
r7	dt_cv	1598	6.97315829	0.171776999	0.024634	0
r8	dt_med	2149	22893	973.5	0.0425239	0
r8	dt_p90	2149	87887	5445	0.0619546	0
r8	dt_iqr	2149	50357	4663	0.0925988	0
r8	dt_cv	2149	6.95546617	0.158923673	0.0228487	0
r9	dt_med	11847	23039	1433	0.0621989	0
r9	dt_p90	11847	88298	6987	0.0791298	0
r9	dt_iqr	11847	50219	5101	0.101575	0
r9	dt_cv	11847	6.97909023	0.143363242	0.0205418	0
r10	dt_med	83302	23233	977	0.0420523	0
r10	dt_p90	83302	89974	5777	0.0642074	0
r10	dt_iqr	83302	53127	2455	0.04621	0
r10	dt_cv	83302	6.95587011	0.138036512	0.0198446	0
r11	dt_med	90526	22269	934	0.0419417	0
r11	dt_p90	90526	82697.5	4770.5	0.0576861	0
r11	dt_iqr	90526	46723	3343	0.0715493	0
r11	dt_cv	90526	7.05050623	0.0820272335	0.0116342	0
r12	dt_med	187221	20731	730	0.035213	0
r12	dt_p90	187221	76638	3040	0.039667	0
r12	dt_iqr	187221	41220	2341	0.0567928	0
r12	dt_cv	187221	7.05588434	0.065861552	0.00933427	0
```

Lab `toc_do` PHANRA (rút vài dải; file đủ ở diag):

```
dai	chieu	n	median	MAD	MAD_over_median	mad0
*	own_med	377766	18363	1952	0.106301	0
*	own_p90	377766	78781	7181	0.0911514	0
*	own_iqr	377766	41811	10732	0.256679	0
*	own_cv	377766	7.04630679	0.10607562	0.0150541	0
*	cpu_med	377766	7353	346	0.0470556	0
*	cpu_p90	377766	43649	9804	0.22461	0
*	cpi_med	363408	4.148	0.3	0.072324	0
r7	own_med	1598	19979.5	775.75	0.0388273	0
r7	own_p90	1598	84335.5	4963	0.0588483	0
r7	own_iqr	1598	49621.5	4011	0.0808319	0
r7	own_cv	1598	6.97488067	0.171968155	0.0246554	0
r7	cpu_med	1598	7592.5	229.5	0.0302272	0
r7	cpu_p90	1598	50779	5574	0.10977	0
r7	cpi_med	1530	4.33974522	0.348302396	0.0802587	0
r8	own_med	2149	19999	870	0.0435022	0
r8	own_p90	2149	85986	5299	0.0616263	0
r8	own_iqr	2149	49879	4049	0.0811764	0
r8	own_cv	2149	6.95651185	0.159207595	0.0228861	0
r8	cpu_med	2149	7634	251	0.0328792	0
...
```

Lab `toc_do` AGG:

```
dai	chieu	n	median	MAD	MAD_over_median	mad0
*	syscall_rate_mean	28921	925.126667	725.233333	0.783929	0
*	syscall_rate_cv	28921	1.20052985	0.996844514	0.830337	0
*	cpu_rate_mean	28921	12446780	10676275	0.857754	0
*	cpu_rate_cv	28921	0.864817447	0.657699405	0.760507	0
*	own_rate_mean	28921	1.14399258e+10	8.59069793e+09	0.75094	0
*	own_rate_cv	28921	1.07892977	0.482675903	0.447365	0
*	tids_mean	28921	2.91	2.37	0.814433	0
r10	syscall_rate_mean	6636	650.628333	441.86	0.679128	0
r10	syscall_rate_cv	6636	1.54009457	1.22808825	0.797411	0
r10	cpu_rate_mean	6636	7667886.27	6453376.08	0.841611	0
r10	cpu_rate_cv	6636	1.53871392	1.21741908	0.791193	0
r10	own_rate_mean	6636	1.30576137e+10	7.53760326e+09	0.577257	0
r10	own_rate_cv	6636	1.15318051	0.482893318	0.418749	0
r10	tids_mean	6636	3.575	2.825	0.79021	0
r11	syscall_rate_mean	7149	960.173333	771.49	0.80349	0
r11	syscall_rate_cv	7149	1.22720537	1.02414949	0.834538	0
r11	cpu_rate_mean	7149	7787793.89	7784020.57	0.999515	0
r11	cpu_rate_cv	7149	1.22642027	0.685121865	0.558635	0
r11	own_rate_mean	7149	1.27055673e+10	7.89966896e+09	0.621749	0
r11	own_rate_cv	7149	1.02437923	0.431654824	0.421382	0
r11	tids_mean	7149	3.88	3.07666667	0.792955	0
r12	syscall_rate_mean	13566	1546.32833	1544.52	0.998831	0
r12	syscall_rate_cv	13566	0.708749921	0.519555202	0.733059	0
r12	cpu_rate_mean	13566	13839665	13824347.1	0.998893	0
r12	cpu_rate_cv	13566	0.711885941	0.32237189	0.452842	0
r12	own_rate_mean	13566	1.09143289e+10	8.68711881e+09	0.795937	0
r12	own_rate_cv	13566	0.947830429	0.375140178	0.395788	0
r12	tids_mean	13566	3.18333333	3.17666667	0.997906	0
```

#### (e) 30 cửa sổ điểm cao nhất — lab toc_do, nền kiểm tra

BASELINE (cột cgroup bỏ vì chưa có ở features_all v1):

```
start_ns	tid	dai	diem	chieu_max	toc_do	n_cua_so_tid	ts_dau	ts_cuoi
994599005043624	360862	r12	39959145.802049	dt_p90	5861.8	12487	317822417034541	1005972988498793
994629005043624	360862	r12	39959145.802049	dt_p90	5845.8	12487	317822417034541	1005972988498793
994659005043624	360862	r12	39959145.802049	dt_p90	5852.5	12487	317822417034541	1005972988498793
994689005043624	360862	r12	39959145.802049	dt_p90	5862.7	12487	317822417034541	1005972988498793
1005582988498793	360862	r12	39959145.283535	dt_p90	5801.2	12487	317822417034541	1005972988498793
1005612988498793	360862	r12	39959145.283535	dt_p90	5805.3	12487	317822417034541	1005972988498793
1005642988498793	360862	r12	39959145.283535	dt_p90	5787.1	12487	317822417034541	1005972988498793
1005672988498793	360862	r12	39959145.283535	dt_p90	5752.4	12487	317822417034541	1005972988498793
1000001464094763	360862	r12	39959143.952968	dt_p90	5881.8	12487	317822417034541	1005972988498793
1000031464094763	360862	r12	39959143.952968	dt_p90	5898.7	12487	317822417034541	1005972988498793
1000061464094763	360862	r12	39959143.952968	dt_p90	5896.2	12487	317822417034541	1005972988498793
1000091464094763	360862	r12	39959143.952968	dt_p90	5905.6	12487	317822417034541	1005972988498793
929055569092960	360862	r12	39959143.470841	dt_p90	6477.6	12487	317822417034541	1005972988498793
929085569092960	360862	r12	39959143.470841	dt_p90	6471.1	12487	317822417034541	1005972988498793
929115569092960	360862	r12	39959143.470841	dt_p90	6473.2	12487	317822417034541	1005972988498793
929145569092960	360862	r12	39959143.470841	dt_p90	6475.0	12487	317822417034541	1005972988498793
995319005043624	360862	r12	39959143.075243	dt_p90	5919.1	12487	317822417034541	1005972988498793
995349005043624	360862	r12	39959143.075243	dt_p90	5907.0	12487	317822417034541	1005972988498793
995379005043624	360862	r12	39959143.075243	dt_p90	5908.7	12487	317822417034541	1005972988498793
995409005043624	360862	r12	39959143.075243	dt_p90	5893.2	12487	317822417034541	1005972988498793
931756964048225	360862	r12	39959141.827657	dt_p90	6419.2	12487	317822417034541	1005972988498793
931786964048225	360862	r12	39959141.827657	dt_p90	6423.0	12487	317822417034541	1005972988498793
931816964048225	360862	r12	39959141.827657	dt_p90	6425.8	12487	317822417034541	1005972988498793
931846964048225	360862	r12	39959141.827657	dt_p90	6428.2	12487	317822417034541	1005972988498793
944720577514805	360862	r12	39959141.531458	dt_p90	6441.3	12487	317822417034541	1005972988498793
944750577514805	360862	r12	39959141.531458	dt_p90	6444.2	12487	317822417034541	1005972988498793
944780577514805	360862	r12	39959141.531458	dt_p90	6471.7	12487	317822417034541	1005972988498793
944810577514805	360862	r12	39959141.531458	dt_p90	6460.4	12487	317822417034541	1005972988498793
1003602988498793	360862	r12	39959140.351987	dt_p90	5873.1	12487	317822417034541	1005972988498793
1003632988498793	360862	r12	39959140.351987	dt_p90	5862.9	12487	317822417034541	1005972988498793
```

AGG:

```
start_ns	tid	dai	diem	chieu_max	toc_do	n_cua_so_tid	ts_dau	ts_cuoi
851934000000000	75979	r-2	83.709314	cpu_rate_mean	0.3	0		
841134000000000	75979	r-3	77.451561	cpu_rate_mean	0.2	0		
895134000000000	75979	r-2	40.431925	cpu_rate_mean	0.5	0		
927534000000000	76058	r12	34.749811	cpu_rate_cv	4882.5	0		
941933000000000	76058	r12	34.749811	cpu_rate_cv	4976.5	0		
833934000000000	75979	r-1	30.492147	cpu_rate_mean	0.7	0		
984894000000000	76058	r11	21.561237	own_rate_cv	2064.2	0		
905334000000000	76058	r11	21.464840	own_rate_cv	2541.1	0		
905454000000000	76058	r11	21.464804	own_rate_cv	2542.2	0		
905364000000000	76058	r11	21.464647	own_rate_cv	2540.7	0		
905484000000000	76058	r11	21.464623	own_rate_cv	2544.4	0		
891144000000000	76058	r11	21.463087	own_rate_cv	2552.4	0		
891024000000000	76058	r11	21.463062	own_rate_cv	2534.4	0		
890904000000000	76058	r11	21.463032	own_rate_cv	2536.0	0		
905304000000000	76058	r11	21.461262	own_rate_cv	2539.0	0		
905424000000000	76058	r11	21.461248	own_rate_cv	2544.5	0		
905544000000000	76058	r11	21.461213	own_rate_cv	2535.0	0		
905274000000000	76058	r11	21.461052	own_rate_cv	2392.6	0		
905394000000000	76058	r11	21.461034	own_rate_cv	2538.5	0		
905514000000000	76058	r11	21.460999	own_rate_cv	2541.0	0		
891114000000000	76058	r11	21.459449	own_rate_cv	2544.8	0		
891054000000000	76058	r11	21.459441	own_rate_cv	2536.1	0		
891084000000000	76058	r11	21.459440	own_rate_cv	2535.6	0		
890994000000000	76058	r11	21.459415	own_rate_cv	2539.7	0		
890964000000000	76058	r11	21.459409	own_rate_cv	2532.9	0		
890934000000000	76058	r11	21.459393	own_rate_cv	2527.4	0		
890874000000000	76058	r11	21.459380	own_rate_cv	2534.2	0		
901194000000000	76058	r11	21.452378	own_rate_cv	2531.0	0		
901074000000000	76058	r11	21.452372	own_rate_cv	2556.2	0		
901314000000000	76058	r11	21.452370	own_rate_cv	2546.1	0
```

PHANRA:

```
start_ns	tid	dai	diem	chieu_max	toc_do	n_cua_so_tid	ts_dau	ts_cuoi
994599005043624	360862	r12	40818479.377354	own_p90	5861.8	12487	317822417034541	1005972988498793
994629005043624	360862	r12	40818479.377354	own_p90	5845.8	12487	317822417034541	1005972988498793
994659005043624	360862	r12	40818479.377354	own_p90	5852.5	12487	317822417034541	1005972988498793
994689005043624	360862	r12	40818479.377354	own_p90	5862.7	12487	317822417034541	1005972988498793
1000001464094763	360862	r12	40818478.634644	own_p90	5881.8	12487	317822417034541	1005972988498793
1000031464094763	360862	r12	40818478.634644	own_p90	5898.7	12487	317822417034541	1005972988498793
1000061464094763	360862	r12	40818478.634644	own_p90	5896.2	12487	317822417034541	1005972988498793
1000091464094763	360862	r12	40818478.634644	own_p90	5905.6	12487	317822417034541	1005972988498793
929055569092960	360862	r12	40818477.820088	own_p90	6477.6	12487	317822417034541	1005972988498793
929085569092960	360862	r12	40818477.820088	own_p90	6471.1	12487	317822417034541	1005972988498793
929115569092960	360862	r12	40818477.820088	own_p90	6473.2	12487	317822417034541	1005972988498793
929145569092960	360862	r12	40818477.820088	own_p90	6475.0	12487	317822417034541	1005972988498793
995319005043624	360862	r12	40818477.131998	own_p90	5919.1	12487	317822417034541	1005972988498793
995349005043624	360862	r12	40818477.131998	own_p90	5907.0	12487	317822417034541	1005972988498793
995379005043624	360862	r12	40818477.131998	own_p90	5908.7	12487	317822417034541	1005972988498793
995409005043624	360862	r12	40818477.131998	own_p90	5893.2	12487	317822417034541	1005972988498793
1005582988498793	360862	r12	40818476.123888	own_p90	5801.2	12487	317822417034541	1005972988498793
1005612988498793	360862	r12	40818476.123888	own_p90	5805.3	12487	317822417034541	1005972988498793
1005642988498793	360862	r12	40818476.123888	own_p90	5787.1	12487	317822417034541	1005972988498793
1005672988498793	360862	r12	40818476.123888	own_p90	5752.4	12487	317822417034541	1005972988498793
944720577514805	360862	r12	40818475.817466	own_p90	6441.3	12487	317822417034541	1005972988498793
944750577514805	360862	r12	40818475.817466	own_p90	6444.2	12487	317822417034541	1005972988498793
944780577514805	360862	r12	40818475.817466	own_p90	6471.7	12487	317822417034541	1005972988498793
944810577514805	360862	r12	40818475.817466	own_p90	6460.4	12487	317822417034541	1005972988498793
842084888043792	360862	r12	40818475.203943	own_p90	6510.4	12487	317822417034541	1005972988498793
842114888043792	360862	r12	40818475.203943	own_p90	6510.9	12487	317822417034541	1005972988498793
842144888043792	360862	r12	40818475.203943	own_p90	6513.9	12487	317822417034541	1005972988498793
842174888043792	360862	r12	40818475.203943	own_p90	6509.8	12487	317822417034541	1005972988498793
940039169059500	360862	r12	40818474.504295	own_p90	6533.5	12487	317822417034541	1005972988498793
940069169059500	360862	r12	40818474.504295	own_p90	6506.1	12487	317822417034541	1005972988498793
```

### (2) Kiểm tương đương v2 + hiệu năng

`out/jobs/m6ic1-equiv-v2.log`:

```
sai_lech_v1_v2_max=0.000000e+00 n_ref=56 n_got=56
ket_qua: KHOP
=== syn1 === ... sai_lech_tuong_doi_max_cot_cu=0.000000e+00 ket_qua: KHOP
=== syn2 === ... KHOP
=== g3 === ... KHOP
=== known_answer cot moi ===
tid2000 n_rec=900 n_cua_so_BASE=15
start_ns	n	cgroup_id	x_vol_med	x_blk	x_arr_med	x_dt_sum	x_vol_sum	x_n_pmu	got_ok
5000000000000	600.0	500.0	100000000	0.5008347245409015	1000000000	299500000000.0	30000000000.0	150.0	KHOP
5030000000000	600.0	500.0	100000000	0.5008347245409015	1000000000	299500000000.0	30000000000.0	150.0	KHOP
5060000000000	600.0	500.0	100000000	0.5008347245409015	1000000000	299500000000.0	30000000000.0	150.0	KHOP
known_answer: KHOP
TAT_CA_KHOP tol=1e-06
```

Hiệu năng 10M (`out/c5-syn-10m`, giu=10000000):

| | |
|---|---|
| Thời gian | 4:20.64 (260,64 s) |
| RSS đỉnh | 5307988 kB |
| so_cua_so | 133088 |

Ước lượng theo số bản ghi `giu` thực tế (M6h `giu_bo.tsv`):

| | bản ghi | ước thời gian |
|---|---|---|
| Lab | 2455631066 | 64004 s ≈ **17,8 giờ** |
| Production | 1668929925 | 43499 s ≈ **12,1 giờ** |

Lab ước < 40 giờ → chạy trích thật.

### (3) Trạng thái hai unit trích

Lúc viết báo cáo:

- `hids-m6ic1-labv2`: running từ 2026-11-07 12:23:56. Log `out/jobs/m6ic1-labv2.log`, status `out/jobs/m6ic1-labv2.status`. 210 file.
- `hids-m6ic1-prodv2`: running song song. Log/status `out/jobs/m6ic1-prodv2.*`. 202 file.

**Phần 4 chờ** — bảng đáp ứng viết vào phụ lục `reports/R041-b-m6ic1-dap-ung.md` khi lab xong (watcher `scripts/c5_m6ic1_r041b.sh`, không chờ người). Sau lab: kiểm số dòng + 1000 dòng ngẫu nhiên khớp cột cũ với `features_all.tsv`; lệch → dừng.

### (4) Bốn bảng đáp ứng

Chờ lab. Xem R041-b.

### (5) Thời gian / RSS (tóm tắt)

| Việc | Thời gian | RSS (kB) |
|---|---|---|
| Chấm lab toc_do v1.3.2 | 0:37.25 | 796400 |
| Chấm lab nhip | 0:35.53 | 813740 |
| Chấm lab khong | 0:31.22 | 791800 |
| Chấm prod toc_do | 2:01.55 | 2890308 |
| extract_v2 10M | 4:20.64 | 5307988 |
| Equiv v2 | ~80 s | (xem log) |

### sha256 bảy file

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
a70c0a20b3f45ad86459b27ca1002cb2f0d124650e2ed50c5853d7ba99e28292  analysis/detector_c5.py
cd90de2ab97ecebd56cf177fa53acc40d2b4d0c8e0cc725edf87c16371e8472b  analysis/c5_score.py
```

6. File

- `out/c5-lab1/score-v132-tocdo|nhip|khong/`, `out/c5-prod/score-v132-tocdo/`
- `out/jobs/m6ic1-diag/` (chuan_ge1000_*, top30_*, diag_log_snippets.txt)
- `out/jobs/m6ic1-equiv-v2.log`, `out/jobs/m6ic1-perf10m/`
- `scripts/c5_extract_v2.py`, `c5_equiv_test_v2.py`, `c5_pipeline_v2_extract.sh`, `c5_dap_ung.py`, `c5_m6ic1_score.sh`, `c5_m6ic1_r041b.sh`
- Unit đang chạy: labv2, prodv2

7. Quyết định đã tự đưa ra

- Equiv v2 chỉ so cột cũ với detector/v1 (cột mới có kiểm known-answer riêng).
- Ước lượng dùng `giu` thực tế từ M6h (2,46 tỷ lab), không dùng số ~0,9 tỷ trong bối cảnh.
- Watcher R041-b chạy tách unit để không chết khi mất phiên.

### Thay đổi ngoài phạm vi nhiệm vụ

Không sửa `analysis/c5_score.py` sau commit kiến trúc sư. Diff hiện tại (chưa commit báo cáo):

```
?? scripts/c5_dap_ung.py
?? scripts/c5_equiv_test_v2.py
?? scripts/c5_extract_v2.py
?? scripts/c5_m6ic1_r041b.sh
?? scripts/c5_m6ic1_score.sh
?? scripts/c5_pipeline_v2_extract.sh

```

8. Cần kiến trúc sư quyết định

Không có câu hỏi mới. Chẩn đoán: mọi bộ in `chieu co MAD=0 ... theo dai: 0`; điểm cao nền lab tập trung tid `360862`, chiều `dt_p90`/`own_p90`, dải `r12`.

9. Việc người dùng cần làm tay

Không có.

10. Lỗi còn tồn tại, việc tiếp theo

Hai unit trích còn chạy. R041-b khi lab xong. Không chạy LAB-1c.
