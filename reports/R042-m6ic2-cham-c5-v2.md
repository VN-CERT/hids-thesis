# R042 — M6i-c2 chấm C5 v2 (detector 1.3 + c5_score 1.4)

1. Số báo cáo: **R042**. Ngày giờ: **2026-11-08 23:27** (giờ máy). Mốc: **M6i-c2**. Git commit kiến trúc sư: `3cefc7f`. Commit báo cáo: `19fd458`. Tag: `m6i.2` (đã push `github`).

## Bối cảnh (tiền đăng ký v1.1 §1, F1–F5 — nguyên văn nhiệm vụ)

D1 hog CPU làm dịch vụ nhanh hơn 10–20 % (DVFS), rq +0,1–0,2 %; D3 mới là tranh chấp thật; nền ngày 6–7 trôi +10–15 %; 13 tid sống lâu chiếm 33 %; x_inst gần hằng số 7 ngày trong khi cpu/cpi trôi. C5 v2 dùng miền log + hồ sơ tiến trình + bộ chiều D (arr+inst+own_cv).

## 2. Mục tiêu

Chấm C5 v2 trên dữ liệu đã có (lab v2, LAB-1c, production). Không đo lại, không rsync, không ghi đè score-*/features_all*.tsv cũ. Báo cáo số/bảng/hình; không kết luận đạt/không.

## 3. Đã làm gì

- CAI `goi-195-m6ic2` → XONG; sha khớp; commit `3cefc7f`.
- (0) Hồi quy `score-v14-compat` vs `out/c5-prod/score` (R039): **KHOP** tom_tat (4 cột đầu), scores_* (7 cột đầu), tradeoff_*.
- (0) `scripts/c5_equiv_test.py` với detector v1.3: **TAT_CA_KHOP** sai lệch = 0 (syn1/syn2/g3). Log: `out/c5-lab1/equiv-v14.log`.
- (1) Lab: CH∈{A..E} `--ho-so tid_lop` + D `--ho-so lop|tat` → `out/c5-lab1/score-v14-*`.
- (2) Ghép `out/c5-lab1c/features_ghep.tsv` (lab `nguon=nen` + lab1c; `lab1c/nen-phu` → `nguon=nen`); `train-until=1006289550843307` (= max stop nền lab + 1). Chấm CH=D,A `--ho-so lop --n-toi-thieu 30` + nhãn tid.
- (3) Production CH=D,A `--ho-so tid_lop` → `out/c5-prod/score-v14-*-tid`.
- (4) `c5_apply_threshold.py` lab1c-D → prod-D-tid, `tom_tat_ngan_sach` / `ngan_sach`.
- (5) H1–H4 SVG: `out/c5-lab1/hinh-v14/`.

## 4. Lệnh build / chạy

```bash
# đã chạy (CAI + commit kiến trúc sư)
cd /root/chep_file && python3 -m zipfile -e goi-195-m6ic2.zip . && bash goi-195-m6ic2/CAI.sh

# hồi quy
python3 analysis/c5_score.py --features out/c5-prod/features_all.tsv \
  --train-until 434858090000000 --chieu-phanra A --ho-so tat --mien-tuyen-tinh \
  --n-toi-thieu 0 --dai-che-do khong --out out/c5-prod/score-v14-compat

python3 scripts/c5_equiv_test.py

# 11 bộ chấm
systemd-run --unit=hids-m6ic2-score --collect bash -c 'cd /root/hids && bash scripts/c5_m6ic2_score.sh'

python3 scripts/c5_apply_threshold.py \
  out/c5-lab1c/score-v14-D out/c5-prod/score-v14-D-tid tom_tat_ngan_sach.tsv ngan_sach

python3 scripts/c5_plot_v14.py
```

## 5. Kết quả

### (a) Hồi quy + equiv

```
KHOP tom_tat.tsv 4 cols 16 lines
KHOP scores_AGG_cgroup_giay.tsv 7cols 5805
KHOP scores_BASELINE_dt_tho.tsv 7cols 614337
KHOP scores_PHANRA_5tp.tsv 7cols 614337
KHOP tradeoff_AGG_cgroup_giay.tsv 5127
KHOP tradeoff_BASELINE_dt_tho.tsv 89014
KHOP tradeoff_PHANRA_5tp.tsv 108433
OK_ALL
```

Equiv (đuôi log):

```
=== syn1 === sai_lech_tuong_doi_max=0.000000e+00 ket_qua: KHOP
=== syn2 === sai_lech_tuong_doi_max=0.000000e+00 ket_qua: KHOP
=== g3 ===   sai_lech_tuong_doi_max=0.000000e+00 ket_qua: KHOP
TAT_CA_KHOP tol=1e-06
```

### (b) Lab — năm bộ chiều × hồ sơ

Cổng: mọi lần in `loai 56164 cua so 'thua' (n < 30)` → N=56164 > 0.

So BDG nền kiểm tra @ ngân sách 0,01 với R040 `score-v131-tocdo` (PHANRA=0,0097, BASE=0,0096):

| bộ | ho-so | PHANRA bdg_nen_kt@0.01 | BASE bdg_nen_kt@0.01 | so với v131 PHANRA |
|----|-------|------------------------:|---------------------:|--------------------|
| A | tid_lop | 0.0105 | 0.0120 | >= |
| B | tid_lop | 0.0106 | 0.0120 | >= |
| C | tid_lop | 0.0107 | 0.0120 | >= |
| D | tid_lop | 0.0183 | 0.0120 | >= |
| E | tid_lop | 0.0183 | 0.0120 | >= |
| D | lop | 0.0128 | 0.0005 | >= |
| D | tat | 0.0103 | 0.0105 | >= |

Cổng “bdg nền v14 < v131” **không đạt** (mọi bộ ≥); tiếp tục theo nhiệm vụ.

#### tom_tat_ngan_sach lab (đủ 0,001/0,01/0,05) — D-tid

```
branch	ngan_sach	nguong	bao_dong_gia	bdg_huan_luyen	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien	n_huan_luyen	n_benign	n_nen_kiem_tra	n_tan_cong
AGG_cgroup_giay	0.001	928.4715	0.0035	0.0010	0.0010	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.01	260.7706	0.0142	0.0100	0.0099	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.05	43.4780	0.0678	0.0500	0.0529	nan	nan	nan	28921	12960	11566	0
BASELINE_dt_tho	0.001	141.9943	0.0016	0.0010	0.0013	nan	nan	nan	358298	159483	143776	0
BASELINE_dt_tho	0.01	106.7068	0.0117	0.0100	0.0120	nan	nan	nan	358298	159483	143776	0
BASELINE_dt_tho	0.05	8.3947	0.0679	0.0500	0.0519	nan	nan	nan	358298	159483	143776	0
PHANRA_5tp	0.001	23538715769593.9570	0.0019	0.0010	0.0021	nan	nan	nan	358298	159483	143776	0
PHANRA_5tp	0.01	1887225145015.5132	0.0248	0.0179	0.0183	nan	nan	nan	358298	159483	143776	0
PHANRA_5tp	0.05	84.0242	0.0610	0.0500	0.0518	nan	nan	nan	358298	159483	143776	0
```

(File đủ mọi bộ: `out/c5-lab1/r042-tables/full-lab-*-ns.tsv`.)

#### theo muc PHANRA @0.01 — trích D1-16 / D3-7 (lab tid)

| CH | muc0 | D1-16 | D3-7 |
|----|-----:|------:|-----:|
| A | 0.0104 | 0.0042 | 0.0092 |
| B | 0.0105 | 0.0000 | 0.0014 |
| C | 0.0106 | 0.0042 | 0.0057 |
| D | 0.0183 | 0.0091 | 0.5667 |
| E | 0.0183 | 0.0091 | 0.5667 |

#### Bảng hồ sơ (số khóa trong `chuan_PHANRA_5tp.tsv`)

| thư mục | khoa tid: | khoa cg: | * |
|---------|----------:|---------:|--:|
| lab A..E / D-tid | 12 | 15 | 1 |
| lab D-lop | 0 | 29 | 1 |
| lab D-tat | 0 | 0 | (16 hàng chieu×band còn lại trong file) |
| lab1c D/A (lop) | 0 | 29 | 1 |
| prod D/A-tid | 25 | 17 | 1 |

### (c) LAB-1c (CH=D và A, ho-so=lop)

`train-until=1006289550843307`. `loai 58582 cua so 'thua'`. B1-300s: n cửa sổ tấn công có n≥30 rất ít (PHANRA `B1-300s` n=1 tại ngân sách) — ghi, không lỗi.

#### tom_tat (muc_phat_hien) — score-v14-D

```
branch	muc_phat_hien	nguong	bao_dong_gia	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	n_benign	n_nen_kiem_tra	n_song_sinh	n_nen_trong_tan_cong
AGG_cgroup_giay	0.50	8.7288	0.6803	nan	0.6804	nan	1220	0	1217	0
AGG_cgroup_giay	0.80	1.5738	0.8795	nan	0.8800	nan	1220	0	1217	0
AGG_cgroup_giay	0.90	1.2725	0.9238	nan	0.9244	nan	1220	0	1217	0
AGG_cgroup_giay	0.95	1.1069	0.9607	nan	0.9614	nan	1220	0	1217	0
AGG_cgroup_giay	1.00	0.4589	1.0000	nan	1.0000	nan	1220	0	1217	0
BASELINE_dt_tho	0.50	9.8165	0.1981	0.1400	0.6221	0.1862	29824	7784	1077	13143
BASELINE_dt_tho	0.80	5.6050	0.2515	0.1662	0.9898	0.2277	29824	7784	1077	13143
BASELINE_dt_tho	0.90	2.0970	0.4769	0.2671	1.0000	0.4688	29824	7784	1077	13143
BASELINE_dt_tho	0.95	2.0275	0.4961	0.2924	1.0000	0.4882	29824	7784	1077	13143
BASELINE_dt_tho	1.00	1.1532	0.8396	0.7906	1.0000	0.8382	29824	7784	1077	13143
PHANRA_5tp	0.50	20.6971	0.2168	0.2029	0.4011	0.2042	29824	7784	1077	13143
PHANRA_5tp	0.80	4.8695	0.3470	0.2884	0.9749	0.3204	29824	7784	1077	13143
PHANRA_5tp	0.90	3.4922	0.4452	0.3367	0.9935	0.4211	29824	7784	1077	13143
PHANRA_5tp	0.95	3.4922	0.4452	0.3367	0.9935	0.4211	29824	7784	1077	13143
PHANRA_5tp	1.00	2.7373	0.4883	0.3758	0.9944	0.4581	29824	7784	1077	13143
```

#### tom_tat_ngan_sach — lab1c-D

```
branch	ngan_sach	nguong	bao_dong_gia	bdg_huan_luyen	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien	n_huan_luyen	n_benign	n_nen_kiem_tra	n_tan_cong
AGG_cgroup_giay	0.001	896.3970	0.0082	0.0010	nan	0.0082	nan	0.0091	40507	1220	0	1096
AGG_cgroup_giay	0.01	247.0757	0.1287	0.0100	nan	0.1290	nan	0.1350	40507	1220	0	1096
AGG_cgroup_giay	0.05	42.0026	0.4516	0.0500	nan	0.4511	nan	0.2692	40507	1220	0	1096
BASELINE_dt_tho	0.001	56174.6252	0.0018	0.0010	0.0000	0.0000	0.0000	0.0000	502334	29824	7784	254
BASELINE_dt_tho	0.01	55820.9306	0.0028	0.0100	0.0000	0.0000	0.0009	0.0000	502334	29824	7784	254
BASELINE_dt_tho	0.05	1223.4178	0.0425	0.0500	0.0681	0.0000	0.0393	0.0000	502334	29824	7784	254
PHANRA_5tp	0.001	22804532577903.6836	0.0018	0.0010	0.0039	0.0000	0.0018	0.0000	502334	29824	7784	254
PHANRA_5tp	0.01	1887225145015.5132	0.0620	0.0127	0.0337	0.0000	0.0678	0.0000	502334	29824	7784	254
PHANRA_5tp	0.05	1045460677188.7225	0.0956	0.0514	0.0674	0.0000	0.1042	0.0000	502334	29824	7784	254
```

`phat_hien_id_ns` / `do_tre_ns` PHANRA @0.01: mọi id tấn công `ty_le=0` / `phat_hien_trong_D=khong` (ngưỡng ngân sách ~1e12). Chi tiết: `out/c5-lab1/r042-tables/lab1c-D-phat_hien_id_PHANRA_01.tsv`, `lab1c-D-do_tre_PHANRA_01.tsv`. Theo id / đợt trong D ở mức phát hiện (tom_tat) nằm trong `out/c5-lab1c/score-v14-D/log.txt` (đoạn `theo id:` / `dot trong D=300s:`).

File A: `out/c5-lab1c/score-v14-A/` + `r042-tables/full-lab1c-A-ns.tsv`.

### (d) Production

`tom_tat_ngan_sach` @0.01 — D-tid / A-tid:

```
# D-tid
AGG_cgroup_giay	0.01	4.8533	0.0098	0.0100	0.0098
BASELINE_dt_tho	0.01	39.8655	0.0052	0.0100	0.0052
PHANRA_5tp	0.01	191.1720	0.0066	0.0100	0.0066
# A-tid
AGG_cgroup_giay	0.01	4.8533	0.0098	0.0100	0.0098
BASELINE_dt_tho	0.01	39.8655	0.0052	0.0100	0.0052
PHANRA_5tp	0.01	39.8617	0.0051	0.0100	0.0051
```

(Hồ sơ prod: 25 tid riêng + 17 lop cg — bảng trên.)

Đủ ngân sách: `out/c5-lab1/r042-tables/full-prod-*-ns.tsv`.

### (e) Áp ngưỡng lab1c-D → prod-D-tid

Nguyên văn: `out/c5-prod/apply-threshold-v14-D.txt` (và `out/c5-lab1/r042-tables/apply-threshold-v14-D.txt`).

Trích ba nhánh @ 0,001 / 0,01 / 0,05 — ngưỡng lab áp lên điểm production (cột `bao_dong_moi_host_ngay`):

| branch | ngan_sach | nguong_lab | ty_le | bao_dong/host-ngày |
|--------|----------:|-----------:|------:|-------------------:|
| AGG | 0.001 | 896.397 | 0 | 0 |
| AGG | 0.01 | 247.076 | 0 | 0 |
| AGG | 0.05 | 42.0026 | 0 | 0 |
| BASE | 0.001 | 56174.6 | 0.000122 | 30.5 |
| BASE | 0.01 | 55820.9 | 0.000122 | 30.5 |
| BASE | 0.05 | 1223.42 | 0.000784 | 196.5 |
| PHANRA | 0.001 | 2.28e13 | 0 | 0 |
| PHANRA | 0.01 | 1.89e12 | 0 | 0 |
| PHANRA | 0.05 | 1.05e12 | 0 | 0 |

Nhánh `prod_tu_hoc` cùng file (ngưỡng tự học ngày 1–5 trên production).

### (f) Hình H1–H4

| file | mô tả |
|------|--------|
| `out/c5-lab1/hinh-v14/H1_lab1c_phat_hien.svg` | lab1c score-v14-D, phát hiện @ BDG 1 %, B1/N1/B4/N4 × muc |
| `out/c5-lab1/hinh-v14/H2_duong_tranh_chap.svg` | lab score-v14-D-tid, BASE vs PHANRA × D1-16/D3-7 |
| `out/c5-lab1/hinh-v14/H3_bo_chieu_A_E.svg` | bdg nền kt lab @ 1 % theo A..E |
| `out/c5-lab1/hinh-v14/H4_ho_so_D.svg` | bdg nền kt bộ D: tid_lop / lop / tat |

### (g) Thời gian / RSS (`/usr/bin/time -v`)

| bộ | elapsed | RSS_kB |
|----|---------|-------:|
| lab A-tid | 0:56.95 | 1119232 |
| lab B-tid | 0:52.27 | 1119160 |
| lab C-tid | 0:52.94 | 1119376 |
| lab D-tid | 0:47.80 | 1119112 |
| lab E-tid | 0:46.18 | 1119224 |
| lab D-lop | 0:47.19 | 1120204 |
| lab D-tat | 0:47.32 | 1049436 |
| lab1c D | 1:07.54 | 1158760 |
| lab1c A | 1:03.53 | 1158788 |
| prod D-tid | 2:29.04 | 3800072 |
| prod A-tid | 2:33.19 | 3800152 |
| prod compat | 2:13.24 | 3076820 |

Unit `hids-m6ic2-score`: 23:10 → 23:23, exit=0.

### (h) sha256 (7 file)

```
bb1c74c507324b6c2f3f863b585f571bfe6983515d700415c313abe8ebbd9bcf  analysis/c5_score.py
5b106f59840b0361f163f896b08bb24ca4781caea8cd374fa6eb379d885d8fd9  analysis/detector_c5.py
67092ef43d9bb78c1db7bd84af1df9e76e97e6e7dac966cf2301e9d20cd6ab22  scripts/c5_plot_v14.py
6df30be24a938979ed91c024e887e48d35f411f353ae14abf622705456de9c18  scripts/c5_m6ic2_score.sh
ae87301976b1117359c8755861831776937ce88242de8fc0bdc92fed1ae95887  scripts/c5_apply_threshold.py
e09575339fc7afc899482d518be16889795aae175aa8d75c564cc2d5a614546f  scripts/c5_equiv_test.py
4a39ebb4293835ca9eed20af8a2cacd25cd431ee8bfe50e15b84e06f08603e21  docs/tasks/M6i.md
```

## 6. File dữ liệu đã tạo

- `out/c5-prod/score-v14-compat/`
- `out/c5-lab1/score-v14-{A,B,C,D,E}-tid/`, `score-v14-D-lop/`, `score-v14-D-tat/`
- `out/c5-lab1c/features_ghep.tsv` (~376 MB, không commit), `features_ghep.cut`
- `out/c5-lab1c/score-v14-D/`, `score-v14-A/`
- `out/c5-prod/score-v14-D-tid/`, `score-v14-A-tid/`
- `out/c5-prod/apply-threshold-v14-D.txt`
- `out/c5-lab1/hinh-v14/H1..H4.svg`
- `out/c5-lab1/r042-tables/`
- `out/jobs/m6ic2-score.{log,status}`
- Không đụng: `out/c5-prod/score`, `score-v13-khong`, `features_all.tsv`, `out/c5-lab1/score`, `score-v131-*`, `score-v132-*`.

## 7. Quyết định đã tự đưa ra và lý do

1. `train-until` lab1c ghep = **max(stop) nền lab + 1** (không phải max(start)+1): tránh orphan 554 cửa sổ có start≤max_start nhưng stop>max_start+1; vẫn < min start lab1c.
2. Đổi `lab1c/nen-phu` → `nguon=nen` khi ghép để `bdg_nen_kiem_tra` đếm được nền phiên lab1c (công thức score yêu cầu `nguon=="nen"`).
3. Script `scripts/c5_m6ic2_score.sh` + `c5_plot_v14.py` (thư viện chuẩn, tham số hoá H1–H4).
4. Bảng hồ sơ lấy từ khóa `tid:`/`cg:` trong `chuan_PHANRA_*.tsv` (score không ghi file `bang_ho_so.tsv` riêng).

## 8. Cần kiến trúc sư quyết định

1. **Bộ chiều nào tách D3 tốt nhất mà bdg nền thấp nhất?** Trên lab @0.01 PHANRA: D và E có `theo_muc D3-7 = 0,5667` (tách mạnh) nhưng `bdg_nen_kt = 0,0183`; A/B/C có bdg nền ~0,0105–0,0107 nhưng D3-7 chỉ 0,001–0,009. Có chấp nhận bdg nền cao hơn để giữ bộ D/E, hay ưu tiên A/B/C?
2. **Hồ sơ tid_lop có cần cho lab1c xuyên phiên không?** Đã chấm chính bằng `--ho-so lop` (29 khóa cg). Tid lab ≠ tid lab1c → tid_lop trên ghep chỉ gắn được tid sống lâu của **lab** (nền huấn luyện), không khớp tid tấn công lab1c. Có cần thêm mẻ `--ho-so tid_lop` chỉ để đối chiếu không?
3. Ngưỡng ngân sách PHANRA trên lab/lab1c ~1e12–1e13 (MAD=0 / EPS trên chiều log?) → `phat_hien=0` @ 0,01 trên lab1c và 0 báo động khi áp ngưỡng lab→prod. Có giữ ngân sách trên miền log như vậy, hay cần chỉnh (ví dụ bỏ chiều MAD=0 khỏi bộ D khi chấm ngân sách)?
4. Cổng “bdg nền v14 < v131” không đạt trên lab — có siết thêm (đổi mặc định ho-so / bộ chiều) trước khi đóng C5 v2 không?

## 9. Việc người dùng cần làm tay

Không.

## 10. Lỗi còn tồn tại / việc tiếp theo

- Cổng so v131 (bdg nền thấp hơn) chưa đạt trên lab.
- `features_ghep.tsv` lớn, không vào git.
- Đề xuất: kiến trúc sư trả lời mục 8; sau đó có thể gắn cấu hình production mặc định (CH + ho-so) và đóng mốc.

## Thay đổi ngoài phạm vi

```
 docs/STATE.md, reports/INDEX.md, reports/R041-c-*.md, reports/R042-*.md,
 scripts/c5_m6ic2_score.sh, scripts/c5_plot_v14.py,
 out/c5-lab1/hinh-v14/*.svg, out/c5-lab1/r042-tables/*, out/c5-lab1/equiv-v14.log,
 out/c5-prod/apply-threshold-v14-D.txt
 → 47 files, +1312 lines (git diff --cached --stat lúc commit R042).
 Không sửa analysis/detector_c5.py / c5_score.py sau commit kiến trúc sư.
 Không commit features_ghep.tsv / scores_*.tsv lớn.
```
