# R041-c — M6i-c0 trích LAB-1c v2

1. Số: R041-c. Ngày giờ: 2026-11-08 19:33 (+07). Mốc: M6i-c0. Commit: `13197af`.

2. Mục tiêu: kéo LAB-1c từ 201, kiểm nhãn, trích features_all_v2 (không chấm).

3. Đã làm: rsync validation/lab1c-20261107 + nhãn; kiểm run_id↔tid; equiv bn nhỏ; extract unit hids-m6ic2-lab1cv2.

4. Lệnh:
```
make build  # nếu cần
systemd-run --unit=hids-m6ic2-lab1cv2 --collect --nice=10 -p MemoryMax=14G -p MemorySwapMax=0 \
  bash -c 'cd /root/hids && bash scripts/c5_m6ic2_lab1cv2_extract.sh'
```

5. Kết quả

### Equiv (file bn nhỏ N1-10s-0 …0716.bin)

```
file: /root/hids/validation/lab1c-20261107/bn/N1-10s-0-c-20261107/data/hids-collector-2026110716.bin
so_cua_so ref=174 got=174  so_chieu_cu~=13
thieu_tren_ref=0 thieu_tren_got=0
sai_lech_tuong_doi_max_cot_cu=0.000000e+00
ket_qua: KHOP
EQUIV_LAB1C OK

```

### Số cửa sổ theo nguon × branch

```
nguon	branch	n_cua_so
lab1c/bn/B1-10s-0-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B1-10s-0-c-20261107	BASELINE_dt_tho	820
lab1c/bn/B1-10s-0-c-20261107	PHANRA_5tp	820
lab1c/bn/B1-10s-D1-16-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B1-10s-D1-16-c-20261107	BASELINE_dt_tho	837
lab1c/bn/B1-10s-D1-16-c-20261107	PHANRA_5tp	837
lab1c/bn/B1-10s-D1-8-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B1-10s-D1-8-c-20261107	BASELINE_dt_tho	818
lab1c/bn/B1-10s-D1-8-c-20261107	PHANRA_5tp	818
lab1c/bn/B1-10s-D3-7-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B1-10s-D3-7-c-20261107	BASELINE_dt_tho	854
lab1c/bn/B1-10s-D3-7-c-20261107	PHANRA_5tp	854
lab1c/bn/B4-0-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B4-0-c-20261107	BASELINE_dt_tho	803
lab1c/bn/B4-0-c-20261107	PHANRA_5tp	803
lab1c/bn/B4-D1-16-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B4-D1-16-c-20261107	BASELINE_dt_tho	824
lab1c/bn/B4-D1-16-c-20261107	PHANRA_5tp	824
lab1c/bn/B4-D1-8-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B4-D1-8-c-20261107	BASELINE_dt_tho	794
lab1c/bn/B4-D1-8-c-20261107	PHANRA_5tp	794
lab1c/bn/B4-D3-7-c-20261107	AGG_cgroup_giay	62
lab1c/bn/B4-D3-7-c-20261107	BASELINE_dt_tho	844
lab1c/bn/B4-D3-7-c-20261107	PHANRA_5tp	844
lab1c/bn/N1-10s-0-c-20261107	AGG_cgroup_giay	61
lab1c/bn/N1-10s-0-c-20261107	BASELINE_dt_tho	787
lab1c/bn/N1-10s-0-c-20261107	PHANRA_5tp	787
lab1c/bn/N1-10s-D1-16-c-20261107	AGG_cgroup_giay	62
lab1c/bn/N1-10s-D1-16-c-20261107	BASELINE_dt_tho	850
lab1c/bn/N1-10s-D1-16-c-20261107	PHANRA_5tp	850
lab1c/bn/N1-10s-D1-8-c-20261107	AGG_cgroup_giay	62
lab1c/bn/N1-10s-D1-8-c-20261107	BASELINE_dt_tho	829
lab1c/bn/N1-10s-D1-8-c-20261107	PHANRA_5tp	829
lab1c/bn/N1-10s-D3-7-c-20261107	AGG_cgroup_giay	61
lab1c/bn/N1-10s-D3-7-c-20261107	BASELINE_dt_tho	832
lab1c/bn/N1-10s-D3-7-c-20261107	PHANRA_5tp	832
lab1c/bn/N4-0-c-20261107	AGG_cgroup_giay	62
lab1c/bn/N4-0-c-20261107	BASELINE_dt_tho	796
lab1c/bn/N4-0-c-20261107	PHANRA_5tp	796
lab1c/bn/N4-D1-16-c-20261107	AGG_cgroup_giay	62
lab1c/bn/N4-D1-16-c-20261107	BASELINE_dt_tho	829
lab1c/bn/N4-D1-16-c-20261107	PHANRA_5tp	829
lab1c/bn/N4-D1-8-c-20261107	AGG_cgroup_giay	62
lab1c/bn/N4-D1-8-c-20261107	BASELINE_dt_tho	793
lab1c/bn/N4-D1-8-c-20261107	PHANRA_5tp	793
lab1c/bn/N4-D3-7-c-20261107	AGG_cgroup_giay	62
lab1c/bn/N4-D3-7-c-20261107	BASELINE_dt_tho	805
lab1c/bn/N4-D3-7-c-20261107	PHANRA_5tp	805
lab1c/nen-phu	AGG_cgroup_giay	599
lab1c/nen-phu	BASELINE_dt_tho	9369
lab1c/nen-phu	PHANRA_5tp	9369
lab1c/slow/B1-300s-0-c-20261107	AGG_cgroup_giay	483
lab1c/slow/B1-300s-0-c-20261107	BASELINE_dt_tho	6192
lab1c/slow/B1-300s-0-c-20261107	PHANRA_5tp	6192
lab1c/slow/B1-60s-0-c-20261107	AGG_cgroup_giay	122
lab1c/slow/B1-60s-0-c-20261107	BASELINE_dt_tho	1740
lab1c/slow/B1-60s-0-c-20261107	PHANRA_5tp	1740
lab1c/slow/N1-60s-0-c-20261107	AGG_cgroup_giay	122
lab1c/slow/N1-60s-0-c-20261107	BASELINE_dt_tho	1728
lab1c/slow/N1-60s-0-c-20261107	PHANRA_5tp	1728
```

### Theo run_id (tid nhãn): cửa sổ n≥30 / n<30

```
run_id	lop	muc_tranh_chap	ghi_chu	n_tid	n_cua_so_n_ge_30	n_cua_so_n_lt_30
B1-10s-0-c-20261107	B	0	1.9;cgroup=nginx	1	40	2
N1-10s-0-c-20261107	N	0	1.9;cgroup=nginx	1	40	2
B4-0-c-20261107	B	0	1.9c:stress-ng	2	62	2
N4-0-c-20261107	N	0	1.9c:zlib	1	40	2
B1-10s-D1-8-c-20261107	B	D1-8	1.9;cgroup=nginx	1	40	2
N1-10s-D1-8-c-20261107	N	D1-8	1.9;cgroup=nginx	2	40	2
B4-D1-8-c-20261107	B	D1-8	1.9c:stress-ng	2	62	2
N4-D1-8-c-20261107	N	D1-8	1.9c:zlib	1	40	2
B1-10s-D1-16-c-20261107	B	D1-16	1.9;cgroup=nginx	2	40	2
N1-10s-D1-16-c-20261107	N	D1-16	1.9;cgroup=nginx	1	40	2
B4-D1-16-c-20261107	B	D1-16	1.9c:stress-ng	2	62	2
N4-D1-16-c-20261107	N	D1-16	1.9c:zlib	2	40	2
B1-10s-D3-7-c-20261107	B	D3-7	1.9;cgroup=nginx	1	40	2
N1-10s-D3-7-c-20261107	N	D3-7	1.9;cgroup=nginx	1	40	2
B4-D3-7-c-20261107	B	D3-7	1.9c:stress-ng	4	62	2
N4-D3-7-c-20261107	N	D3-7	1.9c:zlib	1	40	2
B1-60s-0-c-20261107	B	0	1.9;cgroup=nginx	2	98	8
N1-60s-0-c-20261107	N	0	1.9;cgroup=nginx	2	98	8
B1-300s-0-c-20261107	B	0	KHONG_DAT 19 chu ky (jitter TB 375 s trong 6960 s, loi tinh do dai phien cua kien truc su); chi minh hoa gioi han cua so 300 s; khong cham	2	2	338
N1-10s-nen-c-20261107	N	0	nen-phu, dung de huan luyen	1	592	2
N1-60s-nen-c-20261107	N	0	nen-phu, dung de huan luyen	1	556	30
N1-300s-nen-c-20261107	N	0	nen-phu, dung de huan luyen	1	2	536
N4-nen-c-20261107	N	0	nen-phu, dung de huan luyen	1	586	4
```

6. File: `/root/hids/out/c5-lab1c/features_all_v2.tsv`, nhãn `/root/hids/lab/nhan-*-lab1c.tsv`.

7. Quyết định tự đưa: nguon=`lab1c/bn/<run_id>|lab1c/slow/<run_id>|lab1c/nen-phu`; không trích thu/cgroup-precheck.

8. (không)

9. (không)

10. Chưa chấm. Việc tiếp: M6i-c chấm khi kiến trúc sư giao.
