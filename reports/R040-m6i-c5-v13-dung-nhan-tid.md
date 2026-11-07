# R040 — M6i-b: ngân sách báo động giả (viết lại bản đầy đủ)

1. Số báo cáo: R040. Ngày giờ: 2026-11-07 10:20 (+07). Mốc: M6i-b. Git: `c5_score.py` v1.3.1 ở commit `17250c4`. Tag `m6i` = `d806f16`. Commit báo cáo (kể cả sửa đóng khối mã): xem `git log -1`.

2. Mục tiêu

Làm nửa «báo động giả ổn định dưới tranh chấp» trên dữ liệu đã có, ở điểm đánh đổi cùng ngân sách báo động giả. Không đo lại, không rsync, không ghi đè `out/c5-lab1/score`, `out/c5-prod/score`, `out/c5-prod/score-v13-khong`. Không dùng nhãn tấn công.

## Mục đầu — dừng ở nhãn theo tid (nguyên văn bản 09:43)

# R040 — M6i: dừng ở nhãn theo tid

1. Số báo cáo: R040. Ngày giờ: 2026-11-07 09:43 (+07). Mốc: M6i. Git: commit detector v1.2 + c5_score v1.3 là `113cf6a`. Chưa gắn tag `m6i`.

2. Mục tiêu

Chấm lại C5 bằng `detector_c5.py` v1.2 và `c5_score.py` v1.3 trên dữ liệu đã có. Không đo lại, không rsync, không ghi đè `out/c5-lab1/score` và `out/c5-prod/score`.

### Thay đổi phương pháp sau R039

(1) nền lab và production có nhịp ngày/đêm; median/MAD học tĩnh trên 5 ngày → ban đêm mọi cửa sổ thành bất thường → báo động giả nền 0,88–0,97; v1.3 học median/MAD riêng theo dải tải (tốc độ bản ghi tổng, hệ số 2; lab kiểm chéo bằng mức generator trong nhip-benign.tsv). (2) B1-60s/B1-300s nằm trên nền ngày 1–5 → 0 cửa sổ kiểm tra; v1.3: cửa sổ giao nhãn luôn là kiểm tra. (3) R039 coi MỌI (tid, cửa sổ) giao khoảng thời gian tấn công là "cửa sổ tấn công" (kể cả các tid dịch vụ benign đang chạy) nên mức phát hiện 0,90 ép ngưỡng về ~0; v1.3 chấm cửa sổ tấn công = cửa sổ của CHÍNH tid tấn công (nhãn theo tid), cửa sổ tid khác trong khoảng đó là benign ("nền trong lúc tấn công"). Toán chấm điểm giữ nguyên; --dai-che-do khong + không --nhan-tid = đúng hành vi R039.

3. Đã làm gì

- CAI.sh in `XONG`. sha256 hai file mới khớp gói.
- Commit `113cf6a`, thông điệp đúng câu kiến trúc sư.
- Bước 0a và 0b xong.
- Bước 1: tên tiến trình lấy từ `lab1_driver.sh` và `lab1_slow.sh` trên 201 (chỉ đọc). Quét `proc-*.tsv.zst` của từng phiên và giờ nền của đợt slow. Mọi đợt lớp B có `n_tid_co_ban_ghi = 0`. Dừng theo câu 1d. Không viết `lab/nhan-tid.tsv`. Không chấm lab/production v1.3.

4. Lệnh

```
python3 scripts/c5_equiv_test.py
python3 analysis/c5_score.py --features /root/hids/out/c5-prod/features_all.tsv --train-until 434858090000000 --dai-che-do khong --out /root/hids/out/c5-prod/score-v13-khong
ssh -p 22022 root@10.70.55.201 'cat /root/collector/scripts/lab1_driver.sh; ls /root/collector/scripts/'
ssh -p 22022 root@10.70.55.201 'cat /root/collector/scripts/lab1_slow.sh'
```

`TIME_reg real=83.87 sec maxrss_kb=2518988`.

5. Kết quả

### (a) Tương đương và hồi quy

`out/c5-equiv/equiv-m6i.log`:

```
=== syn1 ===
so_cua_so ref=56 got=56  so_chieu~=13
sai_lech_tuong_doi_max=0.000000e+00
ket_qua: KHOP
=== syn2 ===
so_cua_so ref=60 got=60  so_chieu~=13
sai_lech_tuong_doi_max=0.000000e+00
ket_qua: KHOP
=== g3 ===
so_cua_so ref=2 got=2  so_chieu~=13
sai_lech_tuong_doi_max=0.000000e+00
ket_qua: KHOP
TAT_CA_KHOP tol=1e-06
```

Bảng đặc trưng production: `/root/hids/out/c5-prod/features_all.tsv`, 668 MB, 4202381 dòng (kể cả tiêu đề). Tiêu đề bắt đầu `branch	tid	start_ns	stop_ns`. Mốc cắt production của M6h: `434858090000000`.

So 4 cột đầu `tom_tat.tsv` và 7 cột đầu `scores_<branch>.tsv` với `out/c5-prod/score/` của R039:

```
tom_tat dong_chung=16 lech=0 thua_cu=0 thua_moi=0
scores_AGG_cgroup_giay dong_chung=5805 lech=0
scores_BASELINE_dt_tho dong_chung=614337 lech=0
scores_PHANRA_5tp dong_chung=614337 lech=0
HOI_QUY KHOP
```

Thư mục `out/c5-lab1/score` và `out/c5-prod/score` không bị ghi đè. Bản hồi quy nằm ở `out/c5-prod/score-v13-khong/`.

### (b) Nhãn theo tid — dừng

Tên công cụ, từ driver trên 201:

- B1: `python3 scripts/lab1_http_client.py --name xcfgd-beacon`
- N1: cùng script, `--name nginx-healthcheck`
- B4: `stress-ng --cpu 1 --timeout 2s` (bật 2 giây, nghỉ 20 giây)
- N4: `gzip -f` trên `payload.work`
- B1-60s / B1-300s / N1-60s / N1-300s: cùng tên `xcfgd-beacon` / `nginx-healthcheck` trong `lab1_slow.sh`

Collector của phiên ghi trong `collect.log`: chỉ lọc hai cgroup Docker (nginx, postgres). `proc-*.tsv.zst` của phiên và của giờ nền slow chỉ có `postgres`, `psql`, `runc:[2:INIT]`. Không có `xcfgd-beacon`, `nginx-healthcheck`, `stress-ng`, `gzip`, `python`.

```
run_id	id	lop	cong_cu	n_tid	n_tid_co_ban_ghi	n_ban_ghi
B1-D1N0-20261024	B1	B	xcfgd-beacon	0	0	0
N1-D1N0-20261024	N1	N	nginx-healthcheck	0	0	0
B1-D1N2-20261024	B1	B	xcfgd-beacon	0	0	0
N1-D1N2-20261024	N1	N	nginx-healthcheck	0	0	0
B1-D1N4-20261024	B1	B	xcfgd-beacon	0	0	0
N1-D1N4-20261024	N1	N	nginx-healthcheck	0	0	0
B4-D1N0-20261024	B4	B	stress-ng	0	0	0
N4-D1N0-20261024	N4	N	gzip	0	0	0
B4-D1N2-20261024	B4	B	stress-ng	0	0	0
N4-D1N2-20261024	N4	N	gzip	0	0	0
B4-D1N4-20261024	B4	B	stress-ng	0	0	0
N4-D1N4-20261024	N4	N	gzip	0	0	0
B1-60s-20261024	B1	B	xcfgd-beacon	0	0	0
N1-60s-20261024	N1	N	nginx-healthcheck	0	0	0
B1-300s-20261024	B1	B	xcfgd-beacon	0	0	0
N1-300s-20261024	N1	N	nginx-healthcheck	0	0	0
```

`ts_dau` và `ts_cuoi` trống vì không có tid.

File `proc-2026102416.tsv.zst` của `bn/B1-D1N0` có 8 dòng `exec`, không đủ 20. Mốc đợt `t_bat_dau_mono_ns=317934743404711`. Cả 8 dòng:

```
318046521350697	exec	367193	367193	360718	75979	psql	/usr/bin/psql
318046547973497	exec	367193	367193	360718	75979	psql	/usr/lib/postgresql/16/bin/psql
318047801081167	exec	367257	367257	367245	75979	psql	/usr/bin/psql
318047826723336	exec	367257	367257	360718	75979	psql	/usr/lib/postgresql/16/bin/psql
318347622393623	exec	370454	370454	370442	75979	psql	/usr/bin/psql
318347648264261	exec	370454	370454	360718	75979	psql	/usr/lib/postgresql/16/bin/psql
318348883108473	exec	370520	370520	360718	75979	psql	/usr/bin/psql
318348908953970	exec	370520	370520	360718	75979	psql	/usr/lib/postgresql/16/bin/psql
```

### sha256 bảy file

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
a70c0a20b3f45ad86459b27ca1002cb2f0d124650e2ed50c5853d7ba99e28292  analysis/detector_c5.py
ffa579fc5b9aae05a5fd10023f4c843998177c3a2a9173aa8486b239490002a0  analysis/c5_score.py
```

6. File

- `out/c5-equiv/equiv-m6i.log`
- `out/c5-prod/score-v13-khong/` (không đè `out/c5-prod/score/`)
- `out/jobs/m6i-reg.log`
- Driver đã đọc: `/tmp/lab1_driver_201.txt`, `/tmp/lab1_slow.sh` (bản sao lúc đọc, không nằm trong repo)

7. Quyết định đã tự đưa ra

- Hồi quy dùng đúng lệnh trong nhiệm vụ: không `--nhan`, `--dai-che-do khong`, mốc cắt production `434858090000000`.
- Đợt slow quét `proc-*.tsv.zst` của giờ tường ứng trong `/srv/hids-data/lab1-benign` vì phiên slow không có file proc.

### Thay đổi ngoài phạm vi nhiệm vụ

Không sửa script. `git diff --stat scripts/ analysis/` sau commit kiến trúc sư: không có diff chưa commit trong hai thư mục đó.

8. Cần kiến trúc sư quyết định

Đợt lớp B có 0 tid trong luồng proc. Công cụ chạy trên host (driver), còn collector chỉ ghi hai cgroup Docker. Có lấy tid từ nguồn khác không, hay dừng M6i tại đây?

9. Việc người dùng cần làm tay

Không có.

10. Lỗi còn tồn tại, việc tiếp theo

Chưa làm bước 2–7. Chưa tag `m6i`, chưa push commit `113cf6a` và báo cáo này.

## Quyết định sau bước 1d

Quyết định kiến trúc sư 07/11 (nguyên văn):

"Bước 1d dừng đúng. Các tiến trình B1/N1/B4/N4 của LAB-1 chạy trên host, ngoài hai cgroup collector lọc, nên LAB-1 KHÔNG có bản ghi syscall của tiến trình tấn công; 'cửa sổ tấn công' trong R039 chỉ là cửa sổ của nginx/postgres trong khoảng thời gian đó (beacon từ host thêm 1 request/10 s giữa 20–200 rps của wrk2 → vô hình; B4/N4 trên host với nạn nhân chỉ là tranh chấp CPU xung). Đây là lỗi giao thức LAB-1 §5 (kiến trúc sư), không phải lỗi dữ liệu hay detector. Hệ quả: (1) nửa 'phát hiện' của C5 chưa có dữ liệu → chạy lại B/N trên 201 với tiến trình tấn công trong cgroup lab0-nginx (LAB-1c, Phụ lục 1.9), rồi M6i-c; (2) nửa 'báo động giả ổn định dưới tranh chấp' làm NGAY trên dữ liệu đã có ở điểm đánh đổi 'cùng ngân sách báo động giả' (giao thức đánh giá mục 2, ngưỡng chọn trên tập huấn luyện theo mục 4) = M6i-b này; (3) các khoảng B4/N4 cũ được xếp thành mức tranh chấp riêng 'B4cu-*/N4cu-*' (tranh chấp CPU xung, không có trong thư viện liều), các khoảng B1/N1 cũ là benign thường (không ảnh hưởng nạn nhân). Không có nhãn tấn công nào được dùng trong M6i-b."

3. Đã làm gì (M6i-b)

- CAI `goi-195-m6ib` in `XONG`. sha256 `analysis/c5_score.py` = `c51885701e1d911a6d023631bda509269193b16eda370bbd33d904bde19d40f9`. Commit `17250c4`, thông điệp đúng câu kiến trúc sư.
- Hồi quy v1.3.1 `--dai-che-do khong` khớp R039 (4 cột `tom_tat`, 7 cột `scores_*`, nguyên file `tradeoff_*`).
- Viết `out/c5-lab1/muc-v2.tsv` (6 dòng B4cu/N4cu đứng trước muc.tsv của M6h) và `out/c5-lab1/nhip-benign-gop.tsv`.
- Chấm lab ba cách và production một cách. Cổng KIEM KHOP của `toc_do` đạt rồi mới chấm tiếp.
- Sửa `scripts/c5_apply_threshold.py` thêm đường hai thư mục. Áp ngưỡng lab `toc_do` và ngưỡng tự học production.
- Vẽ H1×3, H2, H3 bằng `scripts/c5_plot_v131.py`.

4. Lệnh

```
python3 analysis/c5_score.py --features out/c5-prod/features_all.tsv --train-until 434858090000000 --dai-che-do khong --out out/c5-prod/score-v131-khong
bash scripts/c5_m6ib_score.sh
python3 scripts/c5_apply_threshold.py out/c5-lab1/score-v131-tocdo out/c5-prod/score-v131-tocdo tom_tat_ngan_sach.tsv ngan_sach
python3 scripts/c5_plot_v131.py /root/hids/out/c5-lab1
```

`scripts/c5_m6ib_score.sh` chạy bốn lần `c5_score.py` (lab `toc_do`, lab `nhip`, lab `khong`, production `toc_do`) với `--ngan-sach 0.001,0.01,0.05`, không `--nhan`, không `--nhan-tid`. Lab: `--train-until 833189871480814 --muc out/c5-lab1/muc-v2.tsv --dai-nhip out/c5-lab1/nhip-benign-gop.tsv`. Production: `--train-until 434858090000000 --dai-che-do toc_do`. Stdout mỗi lần ở `<out>/log.txt`, `/usr/bin/time -v` ở `<out>/time.txt`. Unit: `systemd-run --unit=hids-m6ib-score`.

5. Kết quả

### (b) Hồi quy v1.3.1

`TIME_reg real=109.76 sec maxrss_kb=2598844`.

```
tom_tat dong=16 lech=0 thua_cu=0 thua_moi=0
scores_AGG_cgroup_giay dong=5805 lech=0
tradeoff_AGG_cgroup_giay dong=5127 lech=0
scores_BASELINE_dt_tho dong=614337 lech=0
tradeoff_BASELINE_dt_tho dong=89014 lech=0
scores_PHANRA_5tp dong=614337 lech=0
tradeoff_PHANRA_5tp dong=108433 lech=0
HOI_QUY KHOP
```

Thư mục hồi quy: `out/c5-prod/score-v131-khong/`. Ba thư mục cấm ghi đè giữ nguyên mốc thời gian: `out/c5-lab1/score` 2026-11-03 11:16:59, `out/c5-prod/score` 2026-11-07 00:57:10, `out/c5-prod/score-v13-khong` 2026-11-07 09:42:43.

### (c) muc-v2 và nhịp

Thêm 6 dòng. Sáu dòng đầu của `out/c5-lab1/muc-v2.tsv` (rồi 43 dòng dữ liệu của `muc.tsv` M6h, file 50 dòng kể cả tiêu đề):

```
start_ns	stop_ns	muc
357514341430516	358114365905299	B4cu-0
358421009700231	359021051356565	N4cu-0
359329708562237	359929732614274	B4cu-2
360238398481339	360838440650847	N4cu-2
361147094207607	361747117838638	B4cu-4
362055785483588	362655827525278	N4cu-4
```

Nhịp gom từ hai file (không có file thứ ba dưới `lab/`):

- `/srv/hids-data/lab1-benign/gen-logs/nhip-benign.tsv`
- `/root/hids/validation/lab1-20261024/gen-test/nhip-benign.tsv`

`out/c5-lab1/nhip-benign-gop.tsv`: 4639 dòng (1 tiêu đề + 4638 dòng dữ liệu). Ba dòng đầu:

```
nhip_id	dich_vu	muc	t_bat_dau_mono_ns	t_ket_thuc_mono_ns
1	nginx	120	317746265237692	318036292435195
1	postgres	100	317746286709298	318037286330643
```

Số nhịp theo (dich_vu, muc): nginx 20=594, nginx 50=516, nginx 120=568, nginx 200=641, postgres 15=594, postgres 40=516, postgres 100=1209.

Khoảng mono_ns của nhịp: 305104742901036 .. 1041310200202533. Cửa sổ nền lab nhánh BASELINE_dt_tho: n=529559, start_ns 401193603650926 .. stop_ns 1006289550843306.

Bảng đặc trưng lab: `/root/hids/out/c5-lab1/features_all.tsv`, 193193332 byte, 1134148 dòng. Mốc cắt ngày 5: `833189871480814`.

Cổng trên log `score-v131-tocdo` (và cùng bảng trung vị trong `nhip_kiem.tsv`):

```
# KIEM KHOP nhip-benign <-> toc do tong (ban ghi/giay) trong tung nhip: 4176/4638 nhip co du lieu; ky vong toc do tang theo muc cua moi dich vu
dich_vu	muc	n_nhip	toc_do_trung_vi	toc_do_p10	toc_do_p90
nginx	20	545	1049.4	896.6	1068.0
nginx	50	516	2538.6	2350.1	2566.8
nginx	120	529	5861.8	5606.8	5902.0
nginx	200	498	6475.2	6284.9	6513.9
postgres	15	545	1049.4	896.6	1068.0
postgres	40	516	2538.6	2350.1	2566.8
postgres	100	1027	5902.1	5673.8	6502.6
```

4176/4638 = 0,9004. Trung vị tăng theo muc trong từng dich_vu. «theo dai (nen kiem tra)» tại ngân sách 0,01 có 15 dải có mẫu trên mỗi nhánh (mục (d) toc_do).

### (d) Lab ba cách

`tom_tat.tsv` toàn `nan` ở ngưỡng và phát hiện vì không truyền `--nhan`. `n_tan_cong` trong `tom_tat_ngan_sach.tsv` = 0.

#### Lab `toc_do` — `tom_tat_ngan_sach.tsv`

```
branch	ngan_sach	nguong	bao_dong_gia	bdg_huan_luyen	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien	n_huan_luyen	n_benign	n_nen_kiem_tra	n_tan_cong
AGG_cgroup_giay	0.001	30.5359	0.0005	0.0010	0.0004	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.01	20.1050	0.0113	0.0100	0.0125	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.05	17.0353	0.0467	0.0500	0.0519	nan	nan	nan	28921	12960	11566	0
BASELINE_dt_tho	0.001	39959129.4829	0.0011	0.0010	0.0012	nan	nan	nan	377766	168083	151519	0
BASELINE_dt_tho	0.01	39940472.7985	0.0091	0.0100	0.0096	nan	nan	nan	377766	168083	151519	0
BASELINE_dt_tho	0.05	144584.0114	0.0507	0.0500	0.0519	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.001	40818462.3653	0.0011	0.0010	0.0012	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.01	40799402.9821	0.0091	0.0100	0.0097	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.05	209532.2755	0.0552	0.0500	0.0580	nan	nan	nan	377766	168083	151519	0
```

#### Bảng dải

`dai_AGG_cgroup_giay.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
r-3	[0.125,0.25)	4	4	4	0	khong
r-2	[0.25,0.5)	12	8	8	0	co
r-1	[0.5,1)	52	10	8	0	co
r0	[1,2)	64	2	2	0	co
r1	[2,4)	36	16	16	0	co
r2	[4,8)	6	19	1	0	khong
r3	[8,16)	5	9	1	0	khong
r4	[16,32)	8	16	6	0	co
r5	[32,64)	0	16	0	0	khong
r6	[64,128)	54	56	24	0	co
r7	[128,256)	168	152	84	0	co
r8	[256,512)	200	186	84	0	co
r9	[512,1024)	961	510	350	0	co
r10	[1024,2048)	6636	3170	2678	0	co
r11	[2048,4096)	7149	3094	2860	0	co
r12	[4096,8192)	13566	5692	5440	0	co
```

`dai_BASELINE_dt_tho.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
r-3	[0.125,0.25)	17	18	18	0	co
r-2	[0.25,0.5)	53	32	32	0	co
r-1	[0.5,1)	89	24	6	0	co
r0	[1,2)	93	18	18	0	co
r1	[2,4)	118	49	49	0	co
r2	[4,8)	20	90	0	0	co
r3	[8,16)	50	95	32	0	co
r4	[16,32)	68	103	18	0	co
r5	[32,64)	0	181	16	0	khong
r6	[64,128)	615	595	252	0	co
r7	[128,256)	1598	1603	859	0	co
r8	[256,512)	2149	1987	872	0	co
r9	[512,1024)	11847	6409	4331	0	co
r10	[1024,2048)	83302	39643	33838	0	co
r11	[2048,4096)	90526	39175	36287	0	co
r12	[4096,8192)	187221	78061	74891	0	co
```

`dai_PHANRA_5tp.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
r-3	[0.125,0.25)	17	18	18	0	co
r-2	[0.25,0.5)	53	32	32	0	co
r-1	[0.5,1)	89	24	6	0	co
r0	[1,2)	93	18	18	0	co
r1	[2,4)	118	49	49	0	co
r2	[4,8)	20	90	0	0	co
r3	[8,16)	50	95	32	0	co
r4	[16,32)	68	103	18	0	co
r5	[32,64)	0	181	16	0	khong
r6	[64,128)	615	595	252	0	co
r7	[128,256)	1598	1603	859	0	co
r8	[256,512)	2149	1987	872	0	co
r9	[512,1024)	11847	6409	4331	0	co
r10	[1024,2048)	83302	39643	33838	0	co
r11	[2048,4096)	90526	39175	36287	0	co
r12	[4096,8192)	187221	78061	74891	0	co
```

#### theo muc / theo dai tại ngân sách 0,001, 0,01, 0,05 (đúng thứ tự AGG, BASELINE, PHANRA trong log)

```
# AGG_cgroup_giay
ngan_sach	nguong	bdg_huan_luyen(n=28921)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	30.5359	0.0010	0.0005	0.0004	nan	nan	nan
  theo muc: 0:0.0006(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0000(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0000(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0000(124)  D3-7:0.0000(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
  theo dai (nen kiem tra): r-3:0.2500(4)  r-2:0.2500(8)  r-1:0.0000(8)  r0:0.0000(2)  r1:0.0000(16)  r2:0.0000(1)  r3:0.0000(1)  r4:0.0000(6)  r6:0.0000(24)  r7:0.0000(84)  r8:0.0000(84)  r9:0.0000(350)  r10:0.0000(2678)  r11:0.0000(2860)  r12:0.0004(5440)
0.01	20.1050	0.0100	0.0113	0.0125	nan	nan	nan
  theo muc: 0:0.0125(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0000(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0081(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0000(124)  D3-7:0.0000(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
  theo dai (nen kiem tra): r-3:0.2500(4)  r-2:0.2500(8)  r-1:0.1250(8)  r0:0.0000(2)  r1:0.0000(16)  r2:0.0000(1)  r3:0.0000(1)  r4:0.0000(6)  r6:0.0000(24)  r7:0.0000(84)  r8:0.0000(84)  r9:0.0000(350)  r10:0.0019(2678)  r11:0.0465(2860)  r12:0.0004(5440)
0.05	17.0353	0.0500	0.0467	0.0519	nan	nan	nan
  theo muc: 0:0.0517(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0000(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0081(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0000(124)  D3-7:0.0000(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0185(54)
  theo dai (nen kiem tra): r-3:0.2500(4)  r-2:0.2500(8)  r-1:0.2500(8)  r0:0.0000(2)  r1:0.0000(16)  r2:0.0000(1)  r3:0.0000(1)  r4:0.0000(6)  r6:0.0000(24)  r7:0.0000(84)  r8:0.0000(84)  r9:0.0000(350)  r10:0.0762(2678)  r11:0.1301(2860)  r12:0.0035(5440)

# BASELINE_dt_tho
ngan_sach	nguong	bdg_huan_luyen(n=377766)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	39959129.4829	0.0010	0.0011	0.0012	nan	nan	nan
  theo muc: 0:0.0012(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0007(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0000(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): r-3:0.0000(18)  r-2:0.0000(32)  r-1:0.0000(6)  r0:0.0000(18)  r1:0.0000(49)  r3:0.0000(32)  r4:0.0000(18)  r5:0.0000(16)  r6:0.0000(252)  r7:0.0000(859)  r8:0.0000(872)  r9:0.0000(4331)  r10:0.0000(33838)  r11:0.0000(36287)  r12:0.0024(74891)
0.01	39940472.7985	0.0100	0.0091	0.0096	nan	nan	nan
  theo muc: 0:0.0096(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0166(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0166(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): r-3:0.0000(18)  r-2:0.0000(32)  r-1:0.0000(6)  r0:0.0000(18)  r1:0.0000(49)  r3:0.0000(32)  r4:0.0000(18)  r5:0.0000(16)  r6:0.0000(252)  r7:0.0000(859)  r8:0.0000(872)  r9:0.0000(4331)  r10:0.0000(33838)  r11:0.0000(36287)  r12:0.0195(74891)
0.05	144584.0114	0.0500	0.0507	0.0519	nan	nan	nan
  theo muc: 0:0.0519(152898)  2:0.0362(1243)  4:0.0330(1243)  B4cu-0:0.0302(629)  B4cu-2:0.0331(604)  B4cu-4:0.0363(633)  D1-16:0.0531(1507)  D1-2:0.0258(1471)  D1-4:0.0257(1480)  D1-8:0.0473(1564)  D3-4:0.0516(1473)  D3-7:0.0403(1490)  N4cu-0:0.0370(621)  N4cu-2:0.0346(607)  N4cu-4:0.0371(620)
  theo dai (nen kiem tra): r-3:0.0000(18)  r-2:0.0000(32)  r-1:0.0000(6)  r0:0.0000(18)  r1:0.0000(49)  r3:0.0000(32)  r4:0.0000(18)  r5:0.0000(16)  r6:0.0952(252)  r7:0.0827(859)  r8:0.0218(872)  r9:0.0201(4331)  r10:0.0252(33838)  r11:0.0638(36287)  r12:0.0600(74891)

# PHANRA_5tp
ngan_sach	nguong	bdg_huan_luyen(n=377766)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	40818462.3653	0.0010	0.0011	0.0012	nan	nan	nan
  theo muc: 0:0.0012(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0000(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0000(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): r-3:0.0000(18)  r-2:0.0000(32)  r-1:0.0000(6)  r0:0.0000(18)  r1:0.0000(49)  r3:0.0000(32)  r4:0.0000(18)  r5:0.0000(16)  r6:0.0000(252)  r7:0.0000(859)  r8:0.0000(872)  r9:0.0000(4331)  r10:0.0000(33838)  r11:0.0000(36287)  r12:0.0024(74891)
0.01	40799402.9821	0.0100	0.0091	0.0097	nan	nan	nan
  theo muc: 0:0.0097(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0166(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0166(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): r-3:0.0000(18)  r-2:0.0000(32)  r-1:0.0000(6)  r0:0.0000(18)  r1:0.0000(49)  r3:0.0000(32)  r4:0.0000(18)  r5:0.0000(16)  r6:0.0000(252)  r7:0.0000(859)  r8:0.0000(872)  r9:0.0000(4331)  r10:0.0000(33838)  r11:0.0000(36287)  r12:0.0196(74891)
0.05	209532.2755	0.0500	0.0552	0.0580	nan	nan	nan
  theo muc: 0:0.0580(152898)  2:0.0249(1243)  4:0.0233(1243)  B4cu-0:0.0207(629)  B4cu-2:0.0232(604)  B4cu-4:0.0269(633)  D1-16:0.0531(1507)  D1-2:0.0224(1471)  D1-4:0.0162(1480)  D1-8:0.0473(1564)  D3-4:0.0177(1473)  D3-7:0.0181(1490)  N4cu-0:0.0209(621)  N4cu-2:0.0247(607)  N4cu-4:0.0242(620)
  theo dai (nen kiem tra): r-3:0.0000(18)  r-2:0.0000(32)  r-1:0.0000(6)  r0:0.0000(18)  r1:0.0000(49)  r3:0.0000(32)  r4:0.0000(18)  r5:0.0000(16)  r6:0.0000(252)  r7:0.0058(859)  r8:0.0218(872)  r9:0.0201(4331)  r10:0.0957(33838)  r11:0.0261(36287)  r12:0.0600(74891)
```

#### duong_tranh_chap

`duong_tranh_chap_AGG_cgroup_giay.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	34.7498	0.0004	0.0006	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	21.4646	0.0010	0.0011	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.002	21.4594	0.0020	0.0021	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.005	21.4315	0.0049	0.0051	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.01	20.6256	0.0099	0.0100	0.0000	0.0000	0.0000	0.0000	0.0000	0.0081	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.02	18.9241	0.0200	0.0200	0.0000	0.0000	0.0000	0.0000	0.0000	0.0081	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.05	17.1792	0.0500	0.0498	0.0000	0.0000	0.0000	0.0000	0.0000	0.0081	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0185
0.1	15.6300	0.0999	0.0993	0.0000	0.0000	0.0000	0.0000	0.0000	0.0081	0.0000	0.0000	0.0484	0.0000	0.0000	0.0000	0.0000	0.0185
0.2	12.6748	0.2000	0.1987	0.0185	0.0000	0.0000	0.0000	0.0000	0.1048	0.0000	0.0000	0.1774	0.0000	0.0000	0.0741	0.0000	0.0741
```

`duong_tranh_chap_BASELINE_dt_tho.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	39959137.0834	0.0005	0.0005	0.0000	0.0000	0.0000	0.0000	0.0000	0.0007	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	39959134.0320	0.0010	0.0010	0.0000	0.0000	0.0000	0.0000	0.0000	0.0007	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.002	39959086.1986	0.0020	0.0020	0.0000	0.0000	0.0000	0.0000	0.0000	0.0139	0.0000	0.0000	0.0160	0.0000	0.0000	0.0000	0.0000	0.0000
0.005	39955783.9218	0.0050	0.0051	0.0000	0.0000	0.0000	0.0000	0.0000	0.0166	0.0000	0.0000	0.0166	0.0000	0.0000	0.0000	0.0000	0.0000
0.01	39939378.1872	0.0100	0.0100	0.0000	0.0000	0.0000	0.0000	0.0000	0.0166	0.0000	0.0000	0.0166	0.0000	0.0000	0.0000	0.0000	0.0000
0.02	21024425.5791	0.0200	0.0199	0.0072	0.0129	0.0064	0.0149	0.0063	0.0173	0.0122	0.0034	0.0166	0.0177	0.0128	0.0000	0.0066	0.0032
0.05	144588.6383	0.0500	0.0500	0.0362	0.0330	0.0302	0.0331	0.0363	0.0531	0.0258	0.0257	0.0473	0.0204	0.0201	0.0370	0.0346	0.0371
0.1	814.8201	0.1000	0.1001	0.1110	0.1150	0.1161	0.1093	0.1137	0.0790	0.1196	0.0993	0.0729	0.0991	0.0973	0.1337	0.1104	0.1258
0.2	63.9763	0.2000	0.1999	0.1577	0.1738	0.1590	0.1424	0.2101	0.2303	0.1543	0.1527	0.2257	0.1908	0.1993	0.1594	0.2109	0.1629
```

`duong_tranh_chap_PHANRA_5tp.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	40818471.8104	0.0005	0.0005	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	40818468.8115	0.0010	0.0010	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.002	40818419.0664	0.0020	0.0020	0.0000	0.0000	0.0000	0.0000	0.0000	0.0139	0.0000	0.0000	0.0160	0.0000	0.0000	0.0000	0.0000	0.0000
0.005	40815045.6825	0.0050	0.0051	0.0000	0.0000	0.0000	0.0000	0.0000	0.0166	0.0000	0.0000	0.0166	0.0000	0.0000	0.0000	0.0000	0.0000
0.01	40798282.3717	0.0100	0.0100	0.0000	0.0000	0.0000	0.0000	0.0000	0.0166	0.0000	0.0000	0.0166	0.0000	0.0000	0.0000	0.0000	0.0000
0.02	22204406.1643	0.0200	0.0199	0.0072	0.0129	0.0064	0.0149	0.0063	0.0173	0.0122	0.0034	0.0166	0.0177	0.0128	0.0000	0.0066	0.0032
0.05	209542.4854	0.0500	0.0500	0.0249	0.0233	0.0207	0.0232	0.0269	0.0531	0.0204	0.0162	0.0473	0.0177	0.0181	0.0209	0.0247	0.0242
0.1	870.8160	0.1000	0.1001	0.1110	0.1150	0.1161	0.1093	0.1137	0.0776	0.1196	0.0993	0.0703	0.0998	0.0980	0.1337	0.1104	0.1258
0.2	68.5622	0.2000	0.1999	0.1593	0.1746	0.1590	0.1424	0.2085	0.2123	0.1564	0.1554	0.2129	0.1677	0.2000	0.1610	0.2109	0.1677
```

#### tom_tat.tsv

```
branch	muc_phat_hien	nguong	bao_dong_gia	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	n_benign	n_nen_kiem_tra	n_song_sinh	n_nen_trong_tan_cong
AGG_cgroup_giay	0.50	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.80	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.90	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.95	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	1.00	nan	nan	nan	nan	nan	12960	11566	0	0
BASELINE_dt_tho	0.50	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.80	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.90	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.95	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	1.00	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.50	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.80	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.90	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.95	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	1.00	nan	nan	nan	nan	nan	168083	151519	0	0
```

#### Lab `nhip` — `tom_tat_ngan_sach.tsv`

```
branch	ngan_sach	nguong	bao_dong_gia	bdg_huan_luyen	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien	n_huan_luyen	n_benign	n_nen_kiem_tra	n_tan_cong
AGG_cgroup_giay	0.001	24.3062	0.0009	0.0010	0.0009	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.01	20.8675	0.0094	0.0100	0.0100	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.05	17.2241	0.0459	0.0500	0.0504	nan	nan	nan	28921	12960	11566	0
BASELINE_dt_tho	0.001	45926472.5046	0.0009	0.0010	0.0010	nan	nan	nan	377766	168083	151519	0
BASELINE_dt_tho	0.01	37960736.4606	0.0094	0.0100	0.0100	nan	nan	nan	377766	168083	151519	0
BASELINE_dt_tho	0.05	175950.3179	0.0513	0.0500	0.0528	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.001	46847481.2174	0.0009	0.0010	0.0010	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.01	38674010.0871	0.0094	0.0100	0.0100	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.05	228485.2096	0.0517	0.0500	0.0528	nan	nan	nan	377766	168083	151519	0
```

#### Bảng dải

`dai_AGG_cgroup_giay.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
nginx120|postgres100	-	7260	3313	2957	0	co
nginx120|postgres40	-	2	0	0	0	khong
nginx200|postgres100	-	7226	2821	2821	0	co
nginx20|postgres15	-	7212	3644	2894	0	co
nginx50|postgres40	-	7221	3182	2894	0	co
```

`dai_BASELINE_dt_tho.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
nginx120|postgres100	-	97193	44241	39791	0	co
nginx120|postgres40	-	1	2	2	0	khong
nginx200|postgres100	-	99629	38922	38922	0	co
nginx20|postgres100	-	1	0	0	0	khong
nginx20|postgres15	-	90356	45076	36400	0	co
nginx50|postgres15	-	5	14	14	0	khong
nginx50|postgres40	-	90581	39828	36390	0	co
```

`dai_PHANRA_5tp.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
nginx120|postgres100	-	97193	44241	39791	0	co
nginx120|postgres40	-	1	2	2	0	khong
nginx200|postgres100	-	99629	38922	38922	0	co
nginx20|postgres100	-	1	0	0	0	khong
nginx20|postgres15	-	90356	45076	36400	0	co
nginx50|postgres15	-	5	14	14	0	khong
nginx50|postgres40	-	90581	39828	36390	0	co
```

#### theo muc / theo dai tại ngân sách 0,001, 0,01, 0,05 (đúng thứ tự AGG, BASELINE, PHANRA trong log)

```
# AGG_cgroup_giay
ngan_sach	nguong	bdg_huan_luyen(n=28921)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	24.3062	0.0010	0.0009	0.0009	nan	nan	nan
  theo muc: 0:0.0009(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0000(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0000(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0000(124)  D3-7:0.0159(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
  theo dai (nen kiem tra): nginx120|postgres100:0.0000(2957)  nginx200|postgres100:0.0000(2821)  nginx20|postgres15:0.0000(2894)  nginx50|postgres40:0.0035(2894)
0.01	20.8675	0.0100	0.0094	0.0100	nan	nan	nan
  theo muc: 0:0.0101(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0370(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0000(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0000(124)  D3-7:0.0159(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
  theo dai (nen kiem tra): nginx120|postgres100:0.0034(2957)  nginx200|postgres100:0.0039(2821)  nginx20|postgres15:0.0028(2894)  nginx50|postgres40:0.0301(2894)
0.05	17.2241	0.0500	0.0459	0.0504	nan	nan	nan
  theo muc: 0:0.0501(11674)  2:0.0000(108)  4:0.0093(108)  B4cu-0:0.0370(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0000(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0161(124)  D3-7:0.0397(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
  theo dai (nen kiem tra): nginx120|postgres100:0.0044(2957)  nginx200|postgres100:0.0046(2821)  nginx20|postgres15:0.0643(2894)  nginx50|postgres40:0.1282(2894)

# BASELINE_dt_tho
ngan_sach	nguong	bdg_huan_luyen(n=377766)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	45926472.5046	0.0010	0.0009	0.0010	nan	nan	nan
  theo muc: 0:0.0010(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0000(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0000(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): nginx120|postgres100:0.0000(39791)  nginx120|postgres40:0.0000(2)  nginx200|postgres100:0.0039(38922)  nginx20|postgres15:0.0000(36400)  nginx50|postgres15:0.0000(14)  nginx50|postgres40:0.0000(36390)
0.01	37960736.4606	0.0100	0.0094	0.0100	nan	nan	nan
  theo muc: 0:0.0100(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0173(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0166(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): nginx120|postgres100:0.0165(39791)  nginx120|postgres40:0.0000(2)  nginx200|postgres100:0.0219(38922)  nginx20|postgres15:0.0000(36400)  nginx50|postgres15:0.0000(14)  nginx50|postgres40:0.0000(36390)
0.05	175950.3179	0.0500	0.0513	0.0528	nan	nan	nan
  theo muc: 0:0.0529(152898)  2:0.0233(1243)  4:0.0209(1243)  B4cu-0:0.0207(629)  B4cu-2:0.0215(604)  B4cu-4:0.0237(633)  D1-16:0.0644(1507)  D1-2:0.0177(1471)  D1-4:0.0216(1480)  D1-8:0.0556(1564)  D3-4:0.0550(1473)  D3-7:0.0477(1490)  N4cu-0:0.0209(621)  N4cu-2:0.0214(607)  N4cu-4:0.0242(620)
  theo dai (nen kiem tra): nginx120|postgres100:0.0605(39791)  nginx120|postgres40:0.0000(2)  nginx200|postgres100:0.0601(38922)  nginx20|postgres15:0.0248(36400)  nginx50|postgres15:0.0000(14)  nginx50|postgres40:0.0646(36390)

# PHANRA_5tp
ngan_sach	nguong	bdg_huan_luyen(n=377766)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	46847481.2174	0.0010	0.0009	0.0010	nan	nan	nan
  theo muc: 0:0.0010(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0000(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0000(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): nginx120|postgres100:0.0000(39791)  nginx120|postgres40:0.0000(2)  nginx200|postgres100:0.0039(38922)  nginx20|postgres15:0.0000(36400)  nginx50|postgres15:0.0000(14)  nginx50|postgres40:0.0000(36390)
0.01	38674010.0871	0.0100	0.0094	0.0100	nan	nan	nan
  theo muc: 0:0.0100(152898)  2:0.0000(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0173(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0166(1564)  D3-4:0.0000(1473)  D3-7:0.0000(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
  theo dai (nen kiem tra): nginx120|postgres100:0.0165(39791)  nginx120|postgres40:0.0000(2)  nginx200|postgres100:0.0219(38922)  nginx20|postgres15:0.0000(36400)  nginx50|postgres15:0.0000(14)  nginx50|postgres40:0.0000(36390)
0.05	228485.2096	0.0500	0.0517	0.0528	nan	nan	nan
  theo muc: 0:0.0530(152898)  2:0.0233(1243)  4:0.0209(1243)  B4cu-0:0.0207(629)  B4cu-2:0.0215(604)  B4cu-4:0.0237(633)  D1-16:0.0644(1507)  D1-2:0.0177(1471)  D1-4:0.0324(1480)  D1-8:0.0556(1564)  D3-4:0.0659(1473)  D3-7:0.0638(1490)  N4cu-0:0.0209(621)  N4cu-2:0.0214(607)  N4cu-4:0.0242(620)
  theo dai (nen kiem tra): nginx120|postgres100:0.0605(39791)  nginx120|postgres40:0.0000(2)  nginx200|postgres100:0.0601(38922)  nginx20|postgres15:0.0248(36400)  nginx50|postgres15:0.0000(14)  nginx50|postgres40:0.0647(36390)
```

#### duong_tranh_chap

`duong_tranh_chap_AGG_cgroup_giay.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	25.1228	0.0009	0.0009	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	23.9864	0.0010	0.0009	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0159	0.0000	0.0000	0.0000
0.002	22.7007	0.0020	0.0021	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0159	0.0000	0.0000	0.0000
0.005	21.1720	0.0049	0.0051	0.0000	0.0000	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0159	0.0000	0.0000	0.0000
0.01	20.9106	0.0099	0.0100	0.0000	0.0000	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0159	0.0000	0.0000	0.0000
0.02	19.2397	0.0200	0.0200	0.0000	0.0000	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0317	0.0000	0.0000	0.0000
0.05	17.2477	0.0500	0.0497	0.0000	0.0093	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0161	0.0397	0.0000	0.0000	0.0000
0.1	15.2446	0.0999	0.0992	0.0000	0.0185	0.0370	0.0185	0.0000	0.0000	0.0161	0.0000	0.0161	0.0242	0.0397	0.0000	0.0000	0.0000
0.2	7.8123	0.2000	0.1988	0.0185	0.0370	0.0370	0.0370	0.0370	0.0887	0.0323	0.0323	0.1613	0.3710	0.3333	0.0000	0.0370	0.0000
```

`duong_tranh_chap_BASELINE_dt_tho.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	45926566.3269	0.0005	0.0005	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	45926490.0230	0.0010	0.0010	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.002	45924499.7887	0.0020	0.0020	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.005	45903492.7297	0.0050	0.0050	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.01	37960219.0699	0.0100	0.0100	0.0000	0.0000	0.0000	0.0000	0.0000	0.0173	0.0000	0.0000	0.0166	0.0000	0.0000	0.0000	0.0000	0.0000
0.02	21778751.2919	0.0200	0.0199	0.0105	0.0137	0.0064	0.0083	0.0063	0.0173	0.0122	0.0034	0.0166	0.0177	0.0128	0.0000	0.0066	0.0081
0.05	175955.7323	0.0500	0.0501	0.0233	0.0209	0.0207	0.0215	0.0237	0.0644	0.0177	0.0169	0.0556	0.0204	0.0188	0.0209	0.0214	0.0242
0.1	849.4303	0.1000	0.1000	0.1102	0.1150	0.1161	0.1093	0.1090	0.0829	0.1196	0.0993	0.0831	0.1045	0.1054	0.1337	0.1104	0.1242
0.2	68.6533	0.2000	0.1999	0.1537	0.1689	0.1574	0.1440	0.2070	0.2230	0.1557	0.1534	0.2238	0.1921	0.2101	0.1594	0.2109	0.1597
```

`duong_tranh_chap_PHANRA_5tp.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	46847575.8597	0.0005	0.0005	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	46847498.8655	0.0010	0.0010	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.002	46845467.0072	0.0020	0.0020	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.005	46824036.8764	0.0050	0.0050	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.01	38673481.8394	0.0100	0.0100	0.0000	0.0000	0.0000	0.0000	0.0000	0.0173	0.0000	0.0000	0.0166	0.0000	0.0000	0.0000	0.0000	0.0000
0.02	23091272.3500	0.0200	0.0199	0.0105	0.0137	0.0064	0.0083	0.0063	0.0173	0.0122	0.0034	0.0166	0.0177	0.0128	0.0000	0.0066	0.0081
0.05	228489.0015	0.0500	0.0501	0.0233	0.0209	0.0207	0.0215	0.0237	0.0644	0.0177	0.0324	0.0556	0.0659	0.0638	0.0209	0.0214	0.0242
0.1	872.3745	0.1000	0.1000	0.1102	0.1150	0.1161	0.1093	0.1090	0.0829	0.1196	0.0993	0.0825	0.1052	0.1060	0.1337	0.1104	0.1242
0.2	73.1918	0.2000	0.1999	0.1569	0.1714	0.1574	0.1424	0.2117	0.2050	0.1584	0.1554	0.2110	0.1704	0.2094	0.1610	0.2109	0.1645
```

#### tom_tat.tsv

```
branch	muc_phat_hien	nguong	bao_dong_gia	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	n_benign	n_nen_kiem_tra	n_song_sinh	n_nen_trong_tan_cong
AGG_cgroup_giay	0.50	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.80	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.90	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.95	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	1.00	nan	nan	nan	nan	nan	12960	11566	0	0
BASELINE_dt_tho	0.50	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.80	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.90	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.95	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	1.00	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.50	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.80	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.90	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.95	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	1.00	nan	nan	nan	nan	nan	168083	151519	0	0
```

#### Lab `khong` — `tom_tat_ngan_sach.tsv`

```
branch	ngan_sach	nguong	bao_dong_gia	bdg_huan_luyen	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien	n_huan_luyen	n_benign	n_nen_kiem_tra	n_tan_cong
AGG_cgroup_giay	0.001	22.6960	0.0031	0.0043	0.0031	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.01	19.1183	0.0068	0.0100	0.0068	nan	nan	nan	28921	12960	11566	0
AGG_cgroup_giay	0.05	16.2148	0.0452	0.0500	0.0493	nan	nan	nan	28921	12960	11566	0
BASELINE_dt_tho	0.001	16785377.3047	0.0015	0.0010	0.0015	nan	nan	nan	377766	168083	151519	0
BASELINE_dt_tho	0.01	16783966.9016	0.0094	0.0100	0.0093	nan	nan	nan	377766	168083	151519	0
BASELINE_dt_tho	0.05	62708.4973	0.0556	0.0500	0.0556	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.001	16916274.9774	0.0015	0.0010	0.0016	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.01	16914853.5638	0.0094	0.0100	0.0093	nan	nan	nan	377766	168083	151519	0
PHANRA_5tp	0.05	69179.9879	0.0555	0.0500	0.0555	nan	nan	nan	377766	168083	151519	0
```

#### Bảng dải

`dai_AGG_cgroup_giay.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
-	-	28921	12960	11566	0	co
```

`dai_BASELINE_dt_tho.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
-	-	377766	168083	151519	0	co
```

`dai_PHANRA_5tp.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
-	-	377766	168083	151519	0	co
```

#### theo muc / theo dai tại ngân sách 0,001, 0,01, 0,05 (đúng thứ tự AGG, BASELINE, PHANRA trong log)

```
# AGG_cgroup_giay
ngan_sach	nguong	bdg_huan_luyen(n=28921)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	22.6960	0.0043	0.0031	0.0031	nan	nan	nan
  theo muc: 0:0.0033(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0370(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0000(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0000(124)  D3-4:0.0000(124)  D3-7:0.0000(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
0.01	19.1183	0.0100	0.0068	0.0068	nan	nan	nan
  theo muc: 0:0.0069(11674)  2:0.0000(108)  4:0.0000(108)  B4cu-0:0.0370(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0081(124)  D1-2:0.0000(124)  D1-4:0.0000(124)  D1-8:0.0161(124)  D3-4:0.0000(124)  D3-7:0.0159(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)
0.05	16.2148	0.0500	0.0452	0.0493	nan	nan	nan
  theo muc: 0:0.0491(11674)  2:0.0000(108)  4:0.0185(108)  B4cu-0:0.0370(54)  B4cu-2:0.0000(54)  B4cu-4:0.0000(54)  D1-16:0.0081(124)  D1-2:0.0161(124)  D1-4:0.0000(124)  D1-8:0.0161(124)  D3-4:0.0000(124)  D3-7:0.0317(126)  N4cu-0:0.0000(54)  N4cu-2:0.0000(54)  N4cu-4:0.0000(54)

# BASELINE_dt_tho
ngan_sach	nguong	bdg_huan_luyen(n=377766)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	16785377.3047	0.0010	0.0015	0.0015	nan	nan	nan
  theo muc: 0:0.0015(152898)  2:0.0040(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0007(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0000(1564)  D3-4:0.0027(1473)  D3-7:0.0087(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
0.01	16783966.9016	0.0100	0.0094	0.0093	nan	nan	nan
  theo muc: 0:0.0093(152898)  2:0.0105(1243)  4:0.0105(1243)  B4cu-0:0.0064(629)  B4cu-2:0.0083(604)  B4cu-4:0.0063(633)  D1-16:0.0173(1507)  D1-2:0.0095(1471)  D1-4:0.0007(1480)  D1-8:0.0166(1564)  D3-4:0.0095(1473)  D3-7:0.0128(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0066(607)  N4cu-4:0.0081(620)
0.05	62708.4973	0.0500	0.0556	0.0556	nan	nan	nan
  theo muc: 0:0.0554(152898)  2:0.0732(1243)  4:0.0716(1243)  B4cu-0:0.0747(629)  B4cu-2:0.0679(604)  B4cu-4:0.0774(633)  D1-16:0.0246(1507)  D1-2:0.0823(1471)  D1-4:0.0568(1480)  D1-8:0.0173(1564)  D3-4:0.0550(1473)  D3-7:0.0470(1490)  N4cu-0:0.0934(621)  N4cu-2:0.0741(607)  N4cu-4:0.0790(620)

# PHANRA_5tp
ngan_sach	nguong	bdg_huan_luyen(n=377766)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	16916274.9774	0.0010	0.0015	0.0016	nan	nan	nan
  theo muc: 0:0.0015(152898)  2:0.0040(1243)  4:0.0000(1243)  B4cu-0:0.0000(629)  B4cu-2:0.0000(604)  B4cu-4:0.0000(633)  D1-16:0.0000(1507)  D1-2:0.0000(1471)  D1-4:0.0000(1480)  D1-8:0.0000(1564)  D3-4:0.0027(1473)  D3-7:0.0087(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0000(607)  N4cu-4:0.0000(620)
0.01	16914853.5638	0.0100	0.0094	0.0093	nan	nan	nan
  theo muc: 0:0.0093(152898)  2:0.0105(1243)  4:0.0105(1243)  B4cu-0:0.0064(629)  B4cu-2:0.0083(604)  B4cu-4:0.0063(633)  D1-16:0.0173(1507)  D1-2:0.0095(1471)  D1-4:0.0007(1480)  D1-8:0.0166(1564)  D3-4:0.0095(1473)  D3-7:0.0128(1490)  N4cu-0:0.0000(621)  N4cu-2:0.0066(607)  N4cu-4:0.0081(620)
0.05	69179.9879	0.0500	0.0555	0.0555	nan	nan	nan
  theo muc: 0:0.0552(152898)  2:0.0740(1243)  4:0.0748(1243)  B4cu-0:0.0763(629)  B4cu-2:0.0679(604)  B4cu-4:0.0806(633)  D1-16:0.0252(1507)  D1-2:0.0816(1471)  D1-4:0.0595(1480)  D1-8:0.0173(1564)  D3-4:0.0570(1473)  D3-7:0.0302(1490)  N4cu-0:0.0950(621)  N4cu-2:0.0741(607)  N4cu-4:0.0839(620)
```

#### duong_tranh_chap

`duong_tranh_chap_AGG_cgroup_giay.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	22.6960	0.0031	0.0033	0.0000	0.0000	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	22.6960	0.0031	0.0033	0.0000	0.0000	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.002	22.6960	0.0031	0.0033	0.0000	0.0000	0.0370	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.005	19.9941	0.0049	0.0051	0.0000	0.0000	0.0370	0.0000	0.0000	0.0081	0.0000	0.0000	0.0161	0.0000	0.0159	0.0000	0.0000	0.0000
0.01	19.1085	0.0099	0.0100	0.0000	0.0000	0.0370	0.0000	0.0000	0.0081	0.0000	0.0000	0.0161	0.0000	0.0159	0.0000	0.0000	0.0000
0.02	18.4614	0.0200	0.0200	0.0000	0.0000	0.0370	0.0000	0.0000	0.0081	0.0000	0.0000	0.0161	0.0000	0.0159	0.0000	0.0000	0.0000
0.05	16.1586	0.0500	0.0498	0.0000	0.0185	0.0370	0.0000	0.0000	0.0081	0.0161	0.0000	0.0161	0.0000	0.0317	0.0000	0.0000	0.0000
0.1	13.9300	0.0999	0.0994	0.0000	0.0185	0.0370	0.0185	0.0185	0.0161	0.0242	0.0000	0.0645	0.0242	0.0397	0.0000	0.0000	0.0000
0.2	9.8884	0.2000	0.1989	0.0185	0.0370	0.0370	0.0370	0.0370	0.1371	0.0323	0.0161	0.2339	0.0323	0.0476	0.0000	0.0370	0.0000
```

`duong_tranh_chap_BASELINE_dt_tho.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	16785380.9733	0.0005	0.0005	0.0000	0.0000	0.0000	0.0000	0.0000	0.0007	0.0000	0.0000	0.0000	0.0000	0.0027	0.0000	0.0000	0.0000
0.001	16785379.5876	0.0010	0.0010	0.0032	0.0000	0.0000	0.0000	0.0000	0.0007	0.0000	0.0000	0.0000	0.0000	0.0034	0.0000	0.0000	0.0000
0.002	16785376.3948	0.0020	0.0020	0.0040	0.0000	0.0000	0.0000	0.0000	0.0007	0.0027	0.0000	0.0000	0.0027	0.0087	0.0000	0.0000	0.0065
0.005	16785126.9381	0.0050	0.0050	0.0072	0.0032	0.0000	0.0000	0.0000	0.0173	0.0027	0.0000	0.0166	0.0034	0.0101	0.0000	0.0066	0.0065
0.01	16783733.0630	0.0100	0.0100	0.0105	0.0105	0.0064	0.0083	0.0063	0.0173	0.0095	0.0007	0.0166	0.0095	0.0128	0.0000	0.0066	0.0081
0.02	16777444.3907	0.0200	0.0199	0.0105	0.0137	0.0143	0.0149	0.0142	0.0173	0.0150	0.0122	0.0166	0.0177	0.0128	0.0081	0.0148	0.0081
0.05	62710.7784	0.0500	0.0498	0.0314	0.0241	0.0334	0.0298	0.0253	0.0239	0.0571	0.0209	0.0166	0.0197	0.0188	0.0467	0.0247	0.0339
0.1	489.7569	0.1000	0.1000	0.1102	0.1150	0.1161	0.1093	0.1090	0.0889	0.1196	0.1020	0.0761	0.1045	0.1060	0.1337	0.1104	0.1242
0.2	37.4880	0.2000	0.2000	0.1874	0.2124	0.1987	0.1705	0.2338	0.2044	0.1747	0.1838	0.2148	0.2077	0.2268	0.1723	0.2208	0.1919
```

`duong_tranh_chap_PHANRA_5tp.tsv`:

```
bdg_nen_dat	nguong	bdg_nen_thuc	bdg_muc_0	bdg_muc_2	bdg_muc_4	bdg_muc_B4cu-0	bdg_muc_B4cu-2	bdg_muc_B4cu-4	bdg_muc_D1-16	bdg_muc_D1-2	bdg_muc_D1-4	bdg_muc_D1-8	bdg_muc_D3-4	bdg_muc_D3-7	bdg_muc_N4cu-0	bdg_muc_N4cu-2	bdg_muc_N4cu-4
0.0005	16916278.2700	0.0005	0.0005	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000
0.001	16916276.9919	0.0010	0.0010	0.0032	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0000	0.0027	0.0007	0.0000	0.0000	0.0000
0.002	16916274.1377	0.0020	0.0020	0.0040	0.0000	0.0000	0.0000	0.0000	0.0000	0.0027	0.0000	0.0000	0.0027	0.0087	0.0000	0.0000	0.0065
0.005	16916022.5662	0.0050	0.0050	0.0072	0.0032	0.0000	0.0000	0.0000	0.0173	0.0027	0.0000	0.0166	0.0034	0.0101	0.0000	0.0066	0.0065
0.01	16914617.7429	0.0100	0.0100	0.0105	0.0105	0.0064	0.0083	0.0063	0.0173	0.0095	0.0007	0.0166	0.0095	0.0128	0.0000	0.0066	0.0081
0.02	16908278.8424	0.0200	0.0199	0.0105	0.0137	0.0143	0.0149	0.0142	0.0173	0.0150	0.0122	0.0166	0.0177	0.0128	0.0081	0.0148	0.0081
0.05	69182.0113	0.0500	0.0498	0.0475	0.0394	0.0334	0.0596	0.0300	0.0239	0.0707	0.0331	0.0166	0.0210	0.0188	0.0467	0.0428	0.0565
0.1	484.2483	0.1000	0.1000	0.1102	0.1150	0.1161	0.1109	0.1090	0.0863	0.1203	0.1020	0.0754	0.1052	0.1067	0.1337	0.1104	0.1242
0.2	44.6958	0.2000	0.1999	0.1706	0.1907	0.1685	0.1457	0.2322	0.1944	0.1666	0.1622	0.1976	0.1779	0.2154	0.1643	0.2109	0.1694
```

#### tom_tat.tsv

```
branch	muc_phat_hien	nguong	bao_dong_gia	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	n_benign	n_nen_kiem_tra	n_song_sinh	n_nen_trong_tan_cong
AGG_cgroup_giay	0.50	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.80	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.90	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	0.95	nan	nan	nan	nan	nan	12960	11566	0	0
AGG_cgroup_giay	1.00	nan	nan	nan	nan	nan	12960	11566	0	0
BASELINE_dt_tho	0.50	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.80	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.90	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	0.95	nan	nan	nan	nan	nan	168083	151519	0	0
BASELINE_dt_tho	1.00	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.50	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.80	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.90	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	0.95	nan	nan	nan	nan	nan	168083	151519	0	0
PHANRA_5tp	1.00	nan	nan	nan	nan	nan	168083	151519	0	0
```

### (e) Production `toc_do`

`tom_tat_ngan_sach.tsv` (`out/c5-prod/score-v131-tocdo/`):

```
branch	ngan_sach	nguong	bao_dong_gia	bdg_huan_luyen	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien	n_huan_luyen	n_benign	n_nen_kiem_tra	n_tan_cong
AGG_cgroup_giay	0.001	10.7703	0.0009	0.0010	0.0009	nan	nan	nan	14506	5804	5804	0
AGG_cgroup_giay	0.01	5.2642	0.0100	0.0100	0.0100	nan	nan	nan	14506	5804	5804	0
AGG_cgroup_giay	0.05	3.4936	0.0593	0.0500	0.0593	nan	nan	nan	14506	5804	5804	0
BASELINE_dt_tho	0.001	218915.6630	0.0010	0.0010	0.0010	nan	nan	nan	1475705	614336	614336	0
BASELINE_dt_tho	0.01	116573.4457	0.0132	0.0100	0.0132	nan	nan	nan	1475705	614336	614336	0
BASELINE_dt_tho	0.05	93825.4959	0.0558	0.0500	0.0558	nan	nan	nan	1475705	614336	614336	0
PHANRA_5tp	0.001	230371.0009	0.0010	0.0010	0.0010	nan	nan	nan	1475705	614336	614336	0
PHANRA_5tp	0.01	120420.3407	0.0133	0.0100	0.0133	nan	nan	nan	1475705	614336	614336	0
PHANRA_5tp	0.05	96917.4430	0.0558	0.0500	0.0558	nan	nan	nan	1475705	614336	614336	0
```

#### Bảng dải

`dai_AGG_cgroup_giay.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
r-6	[0.015625,0.03125)	0	2	2	0	khong
r-5	[0.03125,0.0625)	6	2	2	0	khong
r-4	[0.0625,0.125)	18	6	6	0	co
r-3	[0.125,0.25)	18	4	4	0	co
r-2	[0.25,0.5)	26	4	4	0	co
r-1	[0.5,1)	52	30	30	0	co
r0	[1,2)	34	14	14	0	co
r1	[2,4)	34	10	10	0	co
r2	[4,8)	30	12	12	0	co
r3	[8,16)	4	2	2	0	khong
r4	[16,32)	2	0	0	0	khong
r5	[32,64)	6	2	2	0	khong
r6	[64,128)	1	1	1	0	khong
r7	[128,256)	56	24	24	0	co
r8	[256,512)	116	48	48	0	co
r9	[512,1024)	230	96	96	0	co
r10	[1024,2048)	455	190	190	0	co
r11	[2048,4096)	12876	5320	5320	0	co
r12	[4096,8192)	505	37	37	0	co
r13	[8192,16384)	37	0	0	0	co
```

`dai_BASELINE_dt_tho.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
r-6	[0.015625,0.03125)	0	30	30	0	khong
r-5	[0.03125,0.0625)	74	27	27	0	co
r-4	[0.0625,0.125)	234	111	111	0	co
r-3	[0.125,0.25)	308	52	52	0	co
r-2	[0.25,0.5)	340	55	55	0	co
r-1	[0.5,1)	930	513	513	0	co
r0	[1,2)	562	226	226	0	co
r1	[2,4)	568	186	186	0	co
r2	[4,8)	485	224	224	0	co
r3	[8,16)	74	76	76	0	co
r4	[16,32)	51	0	0	0	co
r5	[32,64)	112	44	44	0	co
r6	[64,128)	38	36	36	0	co
r7	[128,256)	3808	1584	1584	0	co
r8	[256,512)	9842	4484	4484	0	co
r9	[512,1024)	21708	9361	9361	0	co
r10	[1024,2048)	44047	19402	19402	0	co
r11	[2048,4096)	1309811	571208	571208	0	co
r12	[4096,8192)	77125	6717	6717	0	co
r13	[8192,16384)	5588	0	0	0	co
```

`dai_PHANRA_5tp.tsv`:

```
dai	khoang_toc_do	huan_luyen	kiem_tra	kt_nen	kt_tan_cong	du_mau
r-6	[0.015625,0.03125)	0	30	30	0	khong
r-5	[0.03125,0.0625)	74	27	27	0	co
r-4	[0.0625,0.125)	234	111	111	0	co
r-3	[0.125,0.25)	308	52	52	0	co
r-2	[0.25,0.5)	340	55	55	0	co
r-1	[0.5,1)	930	513	513	0	co
r0	[1,2)	562	226	226	0	co
r1	[2,4)	568	186	186	0	co
r2	[4,8)	485	224	224	0	co
r3	[8,16)	74	76	76	0	co
r4	[16,32)	51	0	0	0	co
r5	[32,64)	112	44	44	0	co
r6	[64,128)	38	36	36	0	co
r7	[128,256)	3808	1584	1584	0	co
r8	[256,512)	9842	4484	4484	0	co
r9	[512,1024)	21708	9361	9361	0	co
r10	[1024,2048)	44047	19402	19402	0	co
r11	[2048,4096)	1309811	571208	571208	0	co
r12	[4096,8192)	77125	6717	6717	0	co
r13	[8192,16384)	5588	0	0	0	co
```

#### theo muc / theo dai tại 0,001, 0,01, 0,05

```
# AGG_cgroup_giay
ngan_sach	nguong	bdg_huan_luyen(n=14506)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	10.7703	0.0010	0.0009	0.0009	nan	nan	nan
  theo muc: 0:0.0009(5804)
  theo dai (nen kiem tra): r-6:0.0000(2)  r-5:0.0000(2)  r-4:0.0000(6)  r-3:0.0000(4)  r-2:0.0000(4)  r-1:0.0333(30)  r0:0.0000(14)  r1:0.0000(10)  r2:0.0000(12)  r3:0.0000(2)  r5:1.0000(2)  r6:1.0000(1)  r7:0.0000(24)  r8:0.0208(48)  r9:0.0000(96)  r10:0.0000(190)  r11:0.0000(5320)  r12:0.0000(37)
0.01	5.2642	0.0100	0.0100	0.0100	nan	nan	nan
  theo muc: 0:0.0100(5804)
  theo dai (nen kiem tra): r-6:0.0000(2)  r-5:0.0000(2)  r-4:0.0000(6)  r-3:0.2500(4)  r-2:0.0000(4)  r-1:0.0667(30)  r0:0.0000(14)  r1:0.1000(10)  r2:0.0000(12)  r3:0.0000(2)  r5:1.0000(2)  r6:1.0000(1)  r7:0.1667(24)  r8:0.1667(48)  r9:0.0312(96)  r10:0.0158(190)  r11:0.0062(5320)  r12:0.0000(37)
0.05	3.4936	0.0500	0.0593	0.0593	nan	nan	nan
  theo muc: 0:0.0593(5804)
  theo dai (nen kiem tra): r-6:0.0000(2)  r-5:0.5000(2)  r-4:0.1667(6)  r-3:0.2500(4)  r-2:0.2500(4)  r-1:0.1667(30)  r0:0.1429(14)  r1:0.2000(10)  r2:0.0833(12)  r3:0.0000(2)  r5:1.0000(2)  r6:1.0000(1)  r7:0.1667(24)  r8:0.2292(48)  r9:0.0833(96)  r10:0.0737(190)  r11:0.0532(5320)  r12:0.1892(37)

# BASELINE_dt_tho
ngan_sach	nguong	bdg_huan_luyen(n=1475705)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	218915.6630	0.0010	0.0010	0.0010	nan	nan	nan
  theo muc: 0:0.0010(614336)
  theo dai (nen kiem tra): r-6:0.0000(30)  r-5:0.0000(27)  r-4:0.0000(111)  r-3:0.0000(52)  r-2:0.0000(55)  r-1:0.0000(513)  r0:0.0000(226)  r1:0.0000(186)  r2:0.0000(224)  r3:0.0000(76)  r5:0.0000(44)  r6:0.0000(36)  r7:0.0076(1584)  r8:0.0056(4484)  r9:0.0020(9361)  r10:0.0277(19402)  r11:0.0000(571208)  r12:0.0013(6717)
0.01	116573.4457	0.0100	0.0132	0.0132	nan	nan	nan
  theo muc: 0:0.0132(614336)
  theo dai (nen kiem tra): r-6:0.0000(30)  r-5:0.0000(27)  r-4:0.0000(111)  r-3:0.0000(52)  r-2:0.0000(55)  r-1:0.0019(513)  r0:0.0000(226)  r1:0.0000(186)  r2:0.0000(224)  r3:0.0000(76)  r5:0.0000(44)  r6:0.0000(36)  r7:0.0076(1584)  r8:0.0062(4484)  r9:0.0090(9361)  r10:0.0432(19402)  r11:0.0123(571208)  r12:0.0197(6717)
0.05	93825.4959	0.0500	0.0558	0.0558	nan	nan	nan
  theo muc: 0:0.0558(614336)
  theo dai (nen kiem tra): r-6:0.0000(30)  r-5:0.0000(27)  r-4:0.0000(111)  r-3:0.0000(52)  r-2:0.0000(55)  r-1:0.0039(513)  r0:0.0000(226)  r1:0.0000(186)  r2:0.0000(224)  r3:0.0000(76)  r5:0.0000(44)  r6:0.0000(36)  r7:0.0076(1584)  r8:0.0065(4484)  r9:0.0096(9361)  r10:0.0450(19402)  r11:0.0580(571208)  r12:0.0201(6717)

# PHANRA_5tp
ngan_sach	nguong	bdg_huan_luyen(n=1475705)	bdg_kiem_tra_benign	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	phat_hien
0.001	230371.0009	0.0010	0.0010	0.0010	nan	nan	nan
  theo muc: 0:0.0010(614336)
  theo dai (nen kiem tra): r-6:0.0000(30)  r-5:0.0000(27)  r-4:0.0000(111)  r-3:0.0000(52)  r-2:0.0000(55)  r-1:0.0000(513)  r0:0.0000(226)  r1:0.0000(186)  r2:0.0000(224)  r3:0.0000(76)  r5:0.0000(44)  r6:0.0000(36)  r7:0.0076(1584)  r8:0.0056(4484)  r9:0.0020(9361)  r10:0.0277(19402)  r11:0.0000(571208)  r12:0.0013(6717)
0.01	120420.3407	0.0100	0.0133	0.0133	nan	nan	nan
  theo muc: 0:0.0133(614336)
  theo dai (nen kiem tra): r-6:0.0000(30)  r-5:0.0000(27)  r-4:0.0000(111)  r-3:0.0000(52)  r-2:0.0000(55)  r-1:0.0019(513)  r0:0.0000(226)  r1:0.0000(186)  r2:0.0000(224)  r3:0.0000(76)  r5:0.0000(44)  r6:0.0000(36)  r7:0.0076(1584)  r8:0.0062(4484)  r9:0.0090(9361)  r10:0.0436(19402)  r11:0.0123(571208)  r12:0.0197(6717)
0.05	96917.4430	0.0500	0.0558	0.0558	nan	nan	nan
  theo muc: 0:0.0558(614336)
  theo dai (nen kiem tra): r-6:0.0000(30)  r-5:0.0000(27)  r-4:0.0000(111)  r-3:0.0000(52)  r-2:0.0000(55)  r-1:0.0039(513)  r0:0.0000(226)  r1:0.0000(186)  r2:0.0000(224)  r3:0.0000(76)  r5:0.0000(44)  r6:0.0000(36)  r7:0.0076(1584)  r8:0.0065(4484)  r9:0.0097(9361)  r10:0.0451(19402)  r11:0.0581(571208)  r12:0.0201(6717)
```

`tom_tat.tsv` production (nan, không có nhãn):

```
branch	muc_phat_hien	nguong	bao_dong_gia	bdg_nen_kiem_tra	bdg_song_sinh	bdg_nen_trong_tan_cong	n_benign	n_nen_kiem_tra	n_song_sinh	n_nen_trong_tan_cong
AGG_cgroup_giay	0.50	nan	nan	nan	nan	nan	5804	5804	0	0
AGG_cgroup_giay	0.80	nan	nan	nan	nan	nan	5804	5804	0	0
AGG_cgroup_giay	0.90	nan	nan	nan	nan	nan	5804	5804	0	0
AGG_cgroup_giay	0.95	nan	nan	nan	nan	nan	5804	5804	0	0
AGG_cgroup_giay	1.00	nan	nan	nan	nan	nan	5804	5804	0	0
BASELINE_dt_tho	0.50	nan	nan	nan	nan	nan	614336	614336	0	0
BASELINE_dt_tho	0.80	nan	nan	nan	nan	nan	614336	614336	0	0
BASELINE_dt_tho	0.90	nan	nan	nan	nan	nan	614336	614336	0	0
BASELINE_dt_tho	0.95	nan	nan	nan	nan	nan	614336	614336	0	0
BASELINE_dt_tho	1.00	nan	nan	nan	nan	nan	614336	614336	0	0
PHANRA_5tp	0.50	nan	nan	nan	nan	nan	614336	614336	0	0
PHANRA_5tp	0.80	nan	nan	nan	nan	nan	614336	614336	0	0
PHANRA_5tp	0.90	nan	nan	nan	nan	nan	614336	614336	0	0
PHANRA_5tp	0.95	nan	nan	nan	nan	nan	614336	614336	0	0
PHANRA_5tp	1.00	nan	nan	nan	nan	nan	614336	614336	0	0
```

#### Áp ngưỡng

Lệnh: `python3 scripts/c5_apply_threshold.py out/c5-lab1/score-v131-tocdo out/c5-prod/score-v131-tocdo tom_tat_ngan_sach.tsv ngan_sach`

Cột `bao_dong_moi_host_ngay` = số báo động / 2. `theo_dai` là tỉ lệ cửa sổ ngày 6–7 trong từng dải.

```
=== nguong lab ===
branch	ngan_sach	nguon_nguong	nguong	n_cua_so	n_bao_dong	ty_le	bao_dong_moi_host_ngay	tid_ngay_bao	tid_ngay_quan_sat	ty_le_tid_ngay	theo_dai
AGG_cgroup_giay	0.001	lab	30.5359	5804	1	0.000172	0.5000	1	3	0.333333	r-1:0.0000(30) r-2:0.0000(4) r-3:0.0000(4) r-4:0.0000(6) r-5:0.0000(2) r-6:0.0000(2) r0:0.0000(14) r1:0.0000(10) r10:0.0000(190) r11:0.0000(5320) r12:0.0000(37) r2:0.0000(12) r3:0.0000(2) r5:0.5000(2) r6:0.0000(1) r7:0.0000(24) r8:0.0000(48) r9:0.0000(96)
AGG_cgroup_giay	0.01	lab	20.105	5804	1	0.000172	0.5000	1	3	0.333333	r-1:0.0000(30) r-2:0.0000(4) r-3:0.0000(4) r-4:0.0000(6) r-5:0.0000(2) r-6:0.0000(2) r0:0.0000(14) r1:0.0000(10) r10:0.0000(190) r11:0.0000(5320) r12:0.0000(37) r2:0.0000(12) r3:0.0000(2) r5:0.5000(2) r6:0.0000(1) r7:0.0000(24) r8:0.0000(48) r9:0.0000(96)
AGG_cgroup_giay	0.05	lab	17.0353	5804	2	0.000345	1.0000	1	3	0.333333	r-1:0.0000(30) r-2:0.0000(4) r-3:0.0000(4) r-4:0.0000(6) r-5:0.0000(2) r-6:0.0000(2) r0:0.0000(14) r1:0.0000(10) r10:0.0000(190) r11:0.0000(5320) r12:0.0000(37) r2:0.0000(12) r3:0.0000(2) r5:1.0000(2) r6:0.0000(1) r7:0.0000(24) r8:0.0000(48) r9:0.0000(96)
BASELINE_dt_tho	0.001	lab	3.99591e+07	614336	0	0.000000	0.0000	0	260071	0.000000	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0000(19402) r11:0.0000(571208) r12:0.0000(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0000(1584) r8:0.0000(4484) r9:0.0000(9361)
BASELINE_dt_tho	0.01	lab	3.99405e+07	614336	0	0.000000	0.0000	0	260071	0.000000	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0000(19402) r11:0.0000(571208) r12:0.0000(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0000(1584) r8:0.0000(4484) r9:0.0000(9361)
BASELINE_dt_tho	0.05	lab	144584	614336	7398	0.012042	3699.0000	289	260071	0.001111	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0424(19402) r11:0.0111(571208) r12:0.0192(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0060(4484) r9:0.0089(9361)
PHANRA_5tp	0.001	lab	4.08185e+07	614336	0	0.000000	0.0000	0	260071	0.000000	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0000(19402) r11:0.0000(571208) r12:0.0000(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0000(1584) r8:0.0000(4484) r9:0.0000(9361)
PHANRA_5tp	0.01	lab	4.07994e+07	614336	0	0.000000	0.0000	0	260071	0.000000	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0000(19402) r11:0.0000(571208) r12:0.0000(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0000(1584) r8:0.0000(4484) r9:0.0000(9361)
PHANRA_5tp	0.05	lab	209532	614336	754	0.001227	377.0000	264	260071	0.001015	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0355(19402) r11:0.0000(571208) r12:0.0013(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0058(4484) r9:0.0020(9361)
=== nguong tu hoc production ===
branch	ngan_sach	nguon_nguong	nguong	n_cua_so	n_bao_dong	ty_le	bao_dong_moi_host_ngay	tid_ngay_bao	tid_ngay_quan_sat	ty_le_tid_ngay	theo_dai
AGG_cgroup_giay	0.001	prod_tu_hoc	10.7703	5804	5	0.000861	2.5000	2	3	0.666667	r-1:0.0333(30) r-2:0.0000(4) r-3:0.0000(4) r-4:0.0000(6) r-5:0.0000(2) r-6:0.0000(2) r0:0.0000(14) r1:0.0000(10) r10:0.0000(190) r11:0.0000(5320) r12:0.0000(37) r2:0.0000(12) r3:0.0000(2) r5:1.0000(2) r6:1.0000(1) r7:0.0000(24) r8:0.0208(48) r9:0.0000(96)
AGG_cgroup_giay	0.01	prod_tu_hoc	5.2642	5804	58	0.009993	29.0000	3	3	1.000000	r-1:0.0667(30) r-2:0.0000(4) r-3:0.2500(4) r-4:0.0000(6) r-5:0.0000(2) r-6:0.0000(2) r0:0.0000(14) r1:0.1000(10) r10:0.0158(190) r11:0.0062(5320) r12:0.0000(37) r2:0.0000(12) r3:0.0000(2) r5:1.0000(2) r6:1.0000(1) r7:0.1667(24) r8:0.1667(48) r9:0.0312(96)
AGG_cgroup_giay	0.05	prod_tu_hoc	3.4936	5804	344	0.059269	172.0000	3	3	1.000000	r-1:0.1667(30) r-2:0.2500(4) r-3:0.2500(4) r-4:0.1667(6) r-5:0.5000(2) r-6:0.0000(2) r0:0.1429(14) r1:0.2000(10) r10:0.0737(190) r11:0.0532(5320) r12:0.1892(37) r2:0.0833(12) r3:0.0000(2) r5:1.0000(2) r6:1.0000(1) r7:0.1667(24) r8:0.2292(48) r9:0.0833(96)
BASELINE_dt_tho	0.001	prod_tu_hoc	218916	614336	602	0.000980	301.0000	217	260071	0.000834	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0277(19402) r11:0.0000(571208) r12:0.0013(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0056(4484) r9:0.0020(9361)
BASELINE_dt_tho	0.01	prod_tu_hoc	116573	614336	8135	0.013242	4067.5000	320	260071	0.001230	r-1:0.0019(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0432(19402) r11:0.0123(571208) r12:0.0197(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0062(4484) r9:0.0090(9361)
BASELINE_dt_tho	0.05	prod_tu_hoc	93825.5	614336	34296	0.055826	17148.0000	1141	260071	0.004387	r-1:0.0039(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0450(19402) r11:0.0580(571208) r12:0.0201(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0065(4484) r9:0.0096(9361)
PHANRA_5tp	0.001	prod_tu_hoc	230371	614336	602	0.000980	301.0000	217	260071	0.000834	r-1:0.0000(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0277(19402) r11:0.0000(571208) r12:0.0013(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0056(4484) r9:0.0020(9361)
PHANRA_5tp	0.01	prod_tu_hoc	120420	614336	8150	0.013266	4075.0000	322	260071	0.001238	r-1:0.0019(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0436(19402) r11:0.0123(571208) r12:0.0197(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0062(4484) r9:0.0090(9361)
PHANRA_5tp	0.05	prod_tu_hoc	96917.4	614336	34304	0.055839	17152.0000	1141	260071	0.004387	r-1:0.0039(513) r-2:0.0000(55) r-3:0.0000(52) r-4:0.0000(111) r-5:0.0000(27) r-6:0.0000(30) r0:0.0000(226) r1:0.0000(186) r10:0.0451(19402) r11:0.0581(571208) r12:0.0201(6717) r2:0.0000(224) r3:0.0000(76) r5:0.0000(44) r6:0.0000(36) r7:0.0076(1584) r8:0.0065(4484) r9:0.0097(9361)
```

### (f) Hình

| File | byte |
|---|---|
| `out/c5-lab1/hinh/H1_tocdo.svg` | 5843 |
| `out/c5-lab1/hinh/H1_nhip.svg` | 5844 |
| `out/c5-lab1/hinh/H1_khong.svg` | 5844 |
| `out/c5-lab1/hinh/H2_duong_tranh_chap.svg` | 1840 |
| `out/c5-lab1/hinh/H3_dai_tocdo_vs_khong.svg` | 5324 |

H1: báo động giả theo mức tại ngân sách 0,01, ba nhánh, một hình cho mỗi cách chấm lab. H2: `score-v131-tocdo`, trục hoành `bdg_nen_thuc` (log), trục tung D1-16 và D3-7. H3: báo động giả nền kiểm tra theo dải tại 0,01, `toc_do` so với `khong`.

### (g) Thời gian và RSS

| Lần chạy | Thời gian | RSS đỉnh (kB) |
|---|---|---|
| Hồi quy production `khong` | 109,76 s | 2598844 |
| Lab `toc_do` | 0:36.11 | 776524 |
| Lab `nhip` | 0:36.99 | 795808 |
| Lab `khong` | 0:34.00 | 717952 |
| Production `toc_do` | 1:59.86 | 2811716 |

### (h) sha256 bảy file

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
a70c0a20b3f45ad86459b27ca1002cb2f0d124650e2ed50c5853d7ba99e28292  analysis/detector_c5.py
c51885701e1d911a6d023631bda509269193b16eda370bbd33d904bde19d40f9  analysis/c5_score.py
```

6. File

- `out/c5-prod/score-v131-khong/` (hồi quy)
- `out/c5-lab1/muc-v2.tsv`, `out/c5-lab1/nhip-benign-gop.tsv`
- `out/c5-lab1/score-v131-tocdo/`, `score-v131-nhip/`, `score-v131-khong/`
- `out/c5-prod/score-v131-tocdo/`
- `out/c5-lab1/hinh/H1_tocdo.svg`, `H1_nhip.svg`, `H1_khong.svg`, `H2_duong_tranh_chap.svg`, `H3_dai_tocdo_vs_khong.svg`
- `out/jobs/m6ib-reg.log`, `out/jobs/m6ib-apply.txt`

7. Quyết định đã tự đưa ra

- Bốn lần chấm chạy trong unit `hids-m6ib-score` để không chết khi mất phiên. Cổng KIEM KHOP nằm trong script, trước lần chấm `nhip`.
- Hình dùng script mới `scripts/c5_plot_v131.py` (chỉ thư viện chuẩn, đọc TSV đã chấm). Không sửa script vẽ cũ của pipeline.
- `c5_apply_threshold.py` giữ đường cũ `--tom-tat` và `--prod-score` (mức 0,90/0,95/1,00) để R039 chạy lại được. Đường mới in hai khối: ngưỡng lab và ngưỡng tự học production.

### Thay đổi ngoài phạm vi nhiệm vụ

Không sửa `analysis/c5_score.py` sau commit `17250c4`. Không sửa `analysis/detector_c5.py`. Diff so với `17250c4` trong `scripts/` và `analysis/`:

```
 scripts/c5_apply_threshold.py | sửa (đường hai thư mục)
 scripts/c5_plot_v131.py       | file mới
 scripts/c5_m6ib_score.sh      | file mới
```

`analysis/`: không có diff.

8. Cần kiến trúc sư quyết định

Không có câu hỏi mới. Nửa phát hiện chờ LAB-1c rồi M6i-c, theo quyết định 07/11 ở trên.

9. Việc người dùng cần làm tay

Không có.

10. Lỗi còn tồn tại, việc tiếp theo

Tag `m6i` = `d806f16` đã push lên `github` (`master`). Không chạy LAB-1c.
