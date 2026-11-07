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
