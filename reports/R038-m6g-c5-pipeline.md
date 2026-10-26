# R038 — M6g đường ống phân tích C5

1. Số báo cáo: **R038**. Ngày giờ: **2026-10-26 09:34 +07**. Mốc: **M6g**. Git commit: `91bf83e` (tag `m6g`).

2. Mục tiêu

Đường ống C5 trên máy 195: `c5_extract` streaming khớp `detector_c5.py` v1.1, `c5_pipeline.sh`, thử ≥ 50 triệu bản ghi tổng hợp (không LAB-1/production), R038, tag `m6g`, push, dừng.

3. Đã làm gì

- Lưu `docs/tasks/M6g.md`. Commit trước: `d0305de` — `analysis/detector_c5.py` v1.1 + `analysis/c5_score.py` (kiến trúc sư); sha khớp nhiệm vụ.
- `scripts/c5_extract.py`: streaming theo tid, cửa sổ 300 s / bước 30 s, ≥ 5 bản ghi; nhánh BASELINE_dt_tho, PHANRA_5tp (kèm ctx_*), AGG_cgroup_giay (syscall/cpu/own rate + tids_mean).
- `scripts/c5_equiv_test.py`: 2 file tổng hợp nhỏ + `out/g3-S1-002949.bin` → TAT_CA_KHOP (max lệch tương đối 0).
- `cmd/rec-export`: thêm cột theo tên `cgroup_id`, `seq`, `vol_us` (giữ `vol_ns`, `dt_ns`).
- `scripts/c5_pipeline.sh`, `scripts/c5_plot_svg.py`, `scripts/c5_gen_synthetic.py`, `scripts/c5_m6g_large.sh`.
- Chạy đường ống trên 50.000.000 bản ghi tổng hợp + nhãn giả (unit `hids-c5-m6g-large`, exit 0).

4. Lệnh build, lệnh chạy

```bash
cd /root/hids
make build

# Tuong duong (bat buoc)
python3 scripts/c5_equiv_test.py 2>&1 | tee out/c5-equiv/equiv.log

# Sinh tong hop lon + duong ong (hoac tach buoc)
python3 scripts/c5_gen_synthetic.py --out out/c5-syn-50m --records 50000000 --tids 20
bash scripts/c5_pipeline.sh /root/hids/out/c5-syn-50m /root/hids/out/c5-pipe-50m

# Hoac ca khoi:
systemd-run --unit=hids-c5-m6g-large --collect \
  bash -c 'cd /root/hids && bash scripts/c5_m6g_large.sh'
```

5. Kết quả

### 5.1 Sha kiến trúc sư (không sửa)

```
7bce6a15feb7879e16f511ac88ec555e35ba11a67b34acda1f0886e6004f879e  analysis/detector_c5.py
66d46ebad78e980e7aa41085ed38de4c7a02e8e96e96180739bc8bdc071baf92  analysis/c5_score.py
```

### 5.2 Diff rec-export (tóm tắt)

Cột CSV đổi thứ tự/thêm tên: `ts_enter,cgroup_id,tid,seq,syscall_nr,flags,cpu_ns,steal_ns,irq_ns,rq_ns,vol_us,steal_off_ns,inst,cyc,pmu_ok,vol_ns,dt_ns`.

### 5.3 Kiểm tương đương (nguyên văn `out/c5-equiv/equiv.log`)

```
# rec-export /root/hids/out/g3-S1-002949.bin
=== syn1 ===
file: /tmp/c5equiv-dvdkr_i4/syn1.tsv
so_cua_so ref=56 got=56  so_chieu~=13
thieu_tren_ref=0 thieu_tren_got=0
sai_lech_tuong_doi_max=0.000000e+00
ket_qua: KHOP
=== syn2 ===
file: /tmp/c5equiv-dvdkr_i4/syn2.tsv
so_cua_so ref=60 got=60  so_chieu~=13
thieu_tren_ref=0 thieu_tren_got=0
sai_lech_tuong_doi_max=0.000000e+00
ket_qua: KHOP
=== g3 ===
file: /tmp/c5equiv-dvdkr_i4/g3.csv
so_cua_so ref=2 got=2  so_chieu~=13
thieu_tren_ref=0 thieu_tren_got=0
sai_lech_tuong_doi_max=0.000000e+00
ket_qua: KHOP

TAT_CA_KHOP tol=1e-06
equiv_sec=67.36 rss_kb=1637344
```

### 5.4 Thời gian / RAM — bộ 50 triệu (nguyên văn các dòng TIME_)

```
TIME_gen real=133.82 sec maxrss_kb=27008
TIME_extract real=368.47 sec maxrss_kb=162768   # day01
TIME_extract real=376.14 sec maxrss_kb=162324   # day02
TIME_extract real=367.25 sec maxrss_kb=162440   # day03
TIME_extract real=375.54 sec maxrss_kb=162420   # day04
TIME_extract real=380.69 sec maxrss_kb=162404   # day05
TIME_extract real=382.56 sec maxrss_kb=164604   # day06
TIME_extract real=444.09 sec maxrss_kb=162508   # day07
merged_rows 197841 cols 29
TIME_score real=28.43 sec maxrss_kb=419320
TIME_pipe real=2752.74 sec maxrss_kb=419320
```

Tường: gen 08:40:53 → xong 09:28:59 (+07); tổng wall ≈ 48,1 phút (gen 134 s + pipe 2753 s).

Đỉnh RSS pipeline: **419320 KB ≈ 410 MB** (bước score). Extract đỉnh ~161 MB / ngày. Equiv (detector nạp hết): ~1,6 GB.

Ngoại suy thô ×18 (≈ 900 triệu bản ghi / 7 ngày nền): pipe ≈ **13,8 giờ**, gen+pipe ≈ **14,4 giờ** — trong một đêm trên 195 nếu I/O và số tid tương tự.

### 5.5 tom_tat.tsv (50M, nguyên văn)

```
branch	muc_phat_hien	nguong	bao_dong_gia
AGG_cgroup_giay	0.50	822.1226	0.3438
AGG_cgroup_giay	0.80	446.2131	0.3438
AGG_cgroup_giay	0.90	446.0782	0.3438
AGG_cgroup_giay	0.95	379.5964	0.3438
AGG_cgroup_giay	1.00	6.7807	0.3438
BASELINE_dt_tho	0.50	1807.7741	0.0000
BASELINE_dt_tho	0.80	1473.3991	0.0000
BASELINE_dt_tho	0.90	616.2142	0.0000
BASELINE_dt_tho	0.95	521.5850	0.0000
BASELINE_dt_tho	1.00	351.4480	0.0000
PHANRA_5tp	0.50	1807.0111	0.0000
PHANRA_5tp	0.80	1476.7844	0.0000
PHANRA_5tp	0.90	616.0709	0.0000
PHANRA_5tp	0.95	521.4556	0.0000
PHANRA_5tp	1.00	47.1366	0.0000
```

(Số liệu tổng hợp giả — chỉ để chứng minh đường ống, không phải kết luận C5 trên LAB-1.)

### 5.6 Cách chạy ngày 1/11 — kéo dữ liệu từ 201

SSH key đã dùng được: `root@10.70.55.201 -p 22022` (BatchMode OK). Trên 201 repo nằm ở `/root/collector` (không phải `hids-collector`).

Kích thước quan sát 2026-10-26:

| Đường dẫn trên 201 | Dung lượng |
|---|---|
| `/root/collector/validation/lab1-20261024/bn` | 220M |
| `/root/collector/validation/lab1-20261024/benign-lieu` | 421M |
| `/root/collector/validation/lab1-20261024/slow` | 72K |
| `/root/collector/lab` | 20K |
| `/srv/hids-data/lab1-benign` | 2.6G |
| `/root/collector/validation/lab1-20261024/benign-khoi-dong.txt` | 4K |

Lệnh kéo về 195 (chưa chạy trong M6g — chỉ chuẩn bị):

```bash
mkdir -p /root/hids/validation/lab1-20261024 /root/hids/lab /srv/hids-data
rsync -avP -e 'ssh -p 22022' \
  root@10.70.55.201:/root/collector/validation/lab1-20261024/bn \
  root@10.70.55.201:/root/collector/validation/lab1-20261024/benign-lieu \
  root@10.70.55.201:/root/collector/validation/lab1-20261024/slow \
  root@10.70.55.201:/root/collector/validation/lab1-20261024/benign-khoi-dong.txt \
  /root/hids/validation/lab1-20261024/
rsync -avP -e 'ssh -p 22022' \
  root@10.70.55.201:/root/collector/lab/ \
  /root/hids/lab/
rsync -avP -e 'ssh -p 22022' \
  root@10.70.55.201:/srv/hids-data/lab1-benign/ \
  /srv/hids-data/lab1-benign/
# Dat symlink/copy benign-khoi-dong.txt dung cho pipeline:
# /root/hids/validation/lab1-20261024/benign-khoi-dong.txt
# Chay (khi kien truc su giao ngay 1/11):
# bash scripts/c5_pipeline.sh /root/hids/validation/lab1-20261024 /root/hids/out/c5-lab1
```

`benign-khoi-dong.txt` trên 201 có `start_mono_ns=401189871480814`, `datadir=/srv/hids-data/lab1-benign`.

6. File dữ liệu đã tạo

- `/root/hids/out/c5-equiv/equiv.log`, `g3.csv`
- `/root/hids/out/c5-syn-50m/` (CSV 7 ngày + nhãn; ~4.0G)
- `/root/hids/out/c5-pipe-50m/` — `features_all.tsv`, `muc.tsv`, `score/tom_tat.tsv`, `score/tradeoff_*.tsv`, `bao_dong_gia_muc_det90.svg`, `pipeline.log`
- `/root/hids/out/jobs/c5-m6g-large.log`, `.status`

7. Quyết định đã tự đưa ra và lý do

- Đặt `c5_extract.py` đúng `scripts/` theo nhiệm vụ; không sửa detector/c5_score.
- AGG theo định nghĩa M6g (rate 1 Hz → mean/cv), không theo mô tả PSI tạm trong docstring c5_score — c5_score chỉ chấm các cột số có trong TSV (bỏ ctx_*).
- Bộ tổng hợp xuất CSV kiểu rec-export (không sinh .bin) để thử extract+score; pipeline vẫn hỗ trợ `.bin` qua `rec-export`.
- SVG bằng XML thuần (stdlib), không thêm thư viện vẽ.

8. Cần kiến trúc sư quyết định

- Không (trong phạm vi M6g). Ngày 1/11 chạy LAB-1 khi được giao.

9. Việc người dùng cần làm tay

- Không bắt buộc cho M6g. Khi chạy ngày 1/11: xác nhận còn đủ chỗ đĩa trên 195 (~3G+ cho rsync lab1-benign).

10. Lỗi còn tồn tại, việc tiếp theo đề xuất

- Không chạy LAB-1 trong M6g (đúng nhiệm vụ).
- Đường ống sẵn sàng; đề xuất bước sau: rsync từ 201 rồi `c5_pipeline.sh` trên `validation/lab1-20261024` khi kiến trúc sư giao ngày 1/11.
- Tag `m6g`, push, **DỪNG**.
