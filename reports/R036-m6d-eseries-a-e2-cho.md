# R036 — M6d phần A (E1/E3/E4-cache); E2 chờ

1. Số báo cáo: R036  
   Ngày giờ: 2026-10-24 22:35 (giờ máy; bổ sung E2)  
   Mốc: M6d  
   Git commit: (gắn sau commit E2 + tag `m6d`); binary mốc `m6c.3` = `455970a`

2. Mục tiêu  
   Chốt bảng tranh chấp Bài 1: lặp E1, E3, E4-cache ≥ 3 lần/mức với binary cuối (m6c.3) + dấu tần số; E2 (`--cpu-method int64`) với người dùng vCenter. Không sửa BPF, không sửa m4.sh.

3. Đã làm gì  
   - Lưu nguyên văn `docs/tasks/M6d.md`.  
   - Kiểm sha256 5 file kiến trúc sư: khớp (trước build và lúc viết báo cáo).  
   - `make build` đạt; không sửa BPF.  
   - Script mới: `scripts/m6d_eseries.sh`, `scripts/m6d_a_driver.sh`, `scripts/m6d_e2.sh` (gọi đúng mức m4.sh; không sửa m4.sh).  
   - Phần A: unit `hids-m6d-a`, 20:08→21:29 (+07), exit=0. 12 container dừng lúc đo, `docker start` lại khi xong.  
   - READY phần A: mọi lượt `so_attempt=1` (30/30); không có KHONG_READY.  
   - Phần B: `scripts/m6d_e2.sh`, 22:00→22:30 (+07), status=done; stress-ng `--cpu-method int64`; 12/12 attempt=1; Unlimited cuối vm_steal_pct=0.021%.  
   - Kiến trúc sư duyệt phần A: CHẤP NHẬN, không chạy lại (phụ lục cuối báo cáo). Tag `m6d`.

4. Lệnh build, lệnh chạy  
```bash
cd /root/hids
make build
# Phần A (đã chạy):
systemd-run --unit=hids-m6d-a --collect bash -c 'cd /root/hids && bash scripts/m6d_a_driver.sh'
# Phần B (người dùng, khi ngồi vCenter):
sudo bash scripts/m6d_e2.sh
# (script tự dừng 12 container, hướng dẫn Enter từng mức, đặt lại Unlimited cuối)
```

5. Kết quả

### Mức dùng (nguyên văn từ `scripts/m4.sh`)

```
e1: for L in 0 1 2 3; stress-ng --cpu 1 --taskset $WL_CPU; run_wl_mixed loops 500
e3: e3_once idle 0; e3_once stress2 2
e4: for n in 0 4 12 22; e4_workers n cache
     stress-ng --cache 1 --taskset 0-19,21-23; run_wl_mem loops 500
e2 (m4.sh gốc): Unlimited, 36000, 24000, 12000 MHz
     stress-ng --cpu 22 --taskset 0-19,22-23   # KHÔNG có --cpu-method
e2 (m6d): cùng mức; stress-ng thêm --cpu-method int64
```

File đầy đủ: `validation/m6d-20261024/muc-m4-nguyen-van.txt`.

### Hiệu chuẩn

```
calibrate xong: burn_loops=2586241 mem_steps=506088
```

### READY / KHONG_READY

```
so_attempt=1: 30/30 lượt (E1 12 + E3 6 + E4-cache 12)
KHONG_READY: 0
```

### Dấu tần số (trước/sau mỗi mức)

```
freq E1-L0: truoc=1.9345 sau=1.9353 lech=0.04%
freq E1-L1: truoc=1.9345 sau=2.5258 lech=30.57% LECH_>2%
freq E1-L2: truoc=1.9397 sau=2.5263 lech=30.24% LECH_>2%
freq E1-L3: truoc=2.5260 sau=2.5252 lech=0.03%
freq E3-idle: truoc=1.9389 sau=1.9258 lech=0.68%
freq E3-stress2: truoc=1.9327 sau=1.9345 lech=0.09%
freq E4c-L0: truoc=1.9368 sau=1.9285 lech=0.43%
freq E4c-L4: truoc=1.9262 sau=1.9311 lech=0.25%
freq E4c-L12: truoc=1.9347 sau=1.9260 lech=0.45%
freq E4c-L22: truoc=1.9326 sau=1.9359 lech=0.17%
```

### E1 (co-runner cùng CPU; `-pmu on`; khoảng đốt)

Kỳ vọng (không phải tiêu chí): rq tăng theo mức; cpu và CPI gần như không đổi; steal ≈ 0.

```
muc	run	cpu_ns	rq_ns	steal_ns	irq_ns	vol_us	CPI	inst	GHz	GHz_wall_truoc	GHz_wall_sau
0	1	9839296.0	0.0	0.0	107450.5	0.0	1.2461	15517538.0	1.9681	1.9345	1.9353
0	2	9837781.5	0.0	0.0	102114.0	0.0	1.2487	15517538.0	1.9723	1.9345	1.9353
0	3	9846364.0	0.0	0.0	104581.0	0.0	1.2468	15517538.0	1.9674	1.9345	1.9353
0	trung_vi	9839296.0000	0.0000	0.0000	104581.0000	0.0000	1.2468	15517538.0000	1.9681	1.9345	1.9353
1	1	9574852.0	8961276.5	0.0	57682.0	0.0	1.2481	15517537.0	1.9812	1.9345	2.5258
1	2	7555544.0	7995713.0	0.0	50299.5	0.0	1.2485	15517536.0	2.5727	1.9345	2.5258
1	3	9737436.5	8994935.5	0.0	58880.0	0.0	1.2483	15517537.0	1.9801	1.9345	2.5258
1	trung_vi	9574852.0000	8961276.5000	0.0000	57682.0000	0.0000	1.2483	15517537.0000	1.9812	1.9345	2.5258
2	1	7547062.0	12004871.5	0.0	43461.0	0.0	1.2477	15517535.0	2.5736	1.9397	2.5263
2	2	7516554.0	12000810.0	0.0	41619.5	0.0	1.2456	15517535.0	2.5759	1.9397	2.5263
2	3	7542614.0	12004694.0	0.0	42841.0	0.0	1.2489	15517535.0	2.5750	1.9397	2.5263
2	trung_vi	7542614.0000	12004694.0000	0.0000	42841.0000	0.0000	1.2477	15517535.0000	2.5750	1.9397	2.5263
3	1	7554730.0	18008887.5	0.0	45092.0	0.0	1.2498	15517535.0	2.5739	2.5260	2.5252
3	2	9726067.5	26031536.5	0.0	64190.0	0.0	1.2478	15517537.0	1.9770	2.5260	2.5252
3	3	9658101.0	26004065.0	0.0	60877.5	0.0	1.2472	15517537.0	1.9779	2.5260	2.5252
3	trung_vi	9658101.0000	26004065.0000	0.0000	60877.5000	0.0000	1.2478	15517537.0000	1.9779	2.5260	2.5252
```

Tỉ lệ trung vị so mức 0:

```
muc	cpu_ns	rq_ns	steal_ns	irq_ns	vol_us	CPI	ratio_cpu	ratio_rq	ratio_CPI
0	9839296.0	0.0	0.0	104581.0	0.0	1.2468	1.0000	—	1.0000
1	9574852.0	8961276.5	0.0	57682.0	0.0	1.2483	0.9731	∞	1.0012
2	7542614.0	12004694.0	0.0	42841.0	0.0	1.2477	0.7666	∞	1.0007
3	9658101.0	26004065.0	0.0	60877.5	0.0	1.2478	0.9816	∞	1.0008
```

(rq mức 0 = 0 → tỉ lệ rq ghi ∞; giá trị tuyệt đối rq trung vị: L1=8961276.5, L2=12004694.0, L3=26004065.0)

### E3 (mạng/ngủ 300s; `-pmu host`; CPI = na)

Kỳ vọng (không phải tiêu chí): vol tăng; cpu/rq/steal không đổi.

```
muc	run	cpu_ns	rq_ns	steal_ns	irq_ns	vol_us	CPI	inst	GHz	GHz_wall_truoc	GHz_wall_sau
idle	1	37154	18985	0	26648	300000113	na	0	na	1.9389	1.9258
idle	2	30383	26074	0	0	300000142	na	0	na	1.9389	1.9258
idle	3	51079	25275	0	0	300000235	na	0	na	1.9389	1.9258
idle	trung_vi	37154.0000	25275.0000	0.0000	0.0000	300000142.0000	na	0.0000	na	1.9389	1.9258
stress2	1	32486	12502	0	0	300000122	na	0	na	1.9327	1.9345
stress2	2	25469	25379	0	0	300000130	na	0	na	1.9327	1.9345
stress2	3	22965	23064	0	0	300000132	na	0	na	1.9327	1.9345
stress2	trung_vi	25469.0000	23064.0000	0.0000	0.0000	300000130.0000	na	0.0000	na	1.9327	1.9345
```

### E4-cache (`stress-ng --cache`; `-pmu on`)

Kỳ vọng (không phải tiêu chí): inst không đổi; CPI tăng; GHz hiệu dụng ghi kèm.  
E4-stream không chạy lại (đã có R034).

```
muc	run	cpu_ns	rq_ns	steal_ns	irq_ns	vol_us	CPI	inst	GHz	GHz_wall_truoc	GHz_wall_sau
0	1	14437899.0	0.0	0.0	201939.0	0.0	1.8971	14170548.0	1.9618	1.9368	1.9285
0	2	14490946.0	0.0	0.0	206800.5	0.0	1.9178	14170548.0	1.9619	1.9368	1.9285
0	3	14590766.5	0.0	0.0	212379.0	0.0	1.9295	14170548.0	1.9619	1.9368	1.9285
0	trung_vi	14490946.0000	0.0000	0.0000	206800.5000	0.0000	1.9178	14170548.0000	1.9619	1.9368	1.9285
4	1	13560381.0	0.0	0.0	125278.0	0.0	1.7410	14170547.0	1.9544	1.9262	1.9311
4	2	13531093.5	0.0	8259.0	118025.0	0.0	1.7222	14170547.0	1.9530	1.9262	1.9311
4	3	13425287.0	0.0	8829.5	120994.5	0.0	1.7208	14170547.0	1.9529	1.9262	1.9311
4	trung_vi	13531093.5000	0.0000	8259.0000	120994.5000	0.0000	1.7222	14170547.0000	1.9530	1.9262	1.9311
12	1	13538405.0	0.0	0.0	118416.5	0.0	1.6890	14170547.0	1.9501	1.9347	1.9260
12	2	13503656.0	0.0	21670.0	119323.5	0.0	1.7144	14170547.0	1.9482	1.9347	1.9260
12	3	13663529.0	0.0	10183.5	114452.5	0.0	1.7083	14170547.0	1.9411	1.9347	1.9260
12	trung_vi	13538405.0000	0.0000	10183.5000	118416.5000	0.0000	1.7083	14170547.0000	1.9482	1.9347	1.9260
22	1	13897588.5	0.0	0.0	128476.0	0.0	1.7337	14170547.0	1.9549	1.9326	1.9359
22	2	13128348.5	0.0	0.0	124060.0	0.0	1.6504	14170546.0	1.9401	1.9326	1.9359
22	3	14178968.0	0.0	0.0	149324.0	0.0	1.7757	14170548.0	1.9490	1.9326	1.9359
22	trung_vi	13897588.5000	0.0000	0.0000	128476.0000	0.0000	1.7337	14170547.0000	1.9490	1.9326	1.9359
```

### E2 (steal; `--cpu-method int64`; `-pmu on`; 3 lần/mức)

Mức limit (m4.sh): Unlimited, 36000, 24000, 12000 MHz.  
stress-ng: `--cpu 22 --cpu-method int64 --taskset 0-19,22-23` (KHÁC m4.sh gốc).  
Kỳ vọng (không phải tiêu chí): steal tăng theo mức; cpu/CPI không đổi.

vm_steal_pct (/proc/stat, 10 s, trước mỗi mức):

```
Unlimited	0.025%
36000	17.794%
24000	45.757%
12000	68.333%
Unlimited-cuoi (sau khi đặt lại)	0.021%
```

Dấu tần số E2:

```
freq E2-Unlimited: truoc=1.9346 sau=1.9329 lech=0.09%
freq E2-36000: truoc=1.6156 sau=1.6516 lech=2.23% LECH_>2%
freq E2-24000: truoc=0.9891 sau=1.2165 lech=22.99% LECH_>2%
freq E2-12000: truoc=0.5161 sau=0.4965 lech=3.80% LECH_>2%
```

```
muc	run	vm_steal_pct	cpu_ns	steal_ns	rq_ns	steal_off_ns	CPI	inst	cyc	GHz_hieu_dung	GHz_wall_truoc	GHz_wall_sau
Unlimited	1	0.025	9858542.5	72813.5	15240.5	0.0	1.2485	15517539.0	19373114.5	1.9651	1.9346	1.9329
Unlimited	2	0.025	9849657.5	69138.5	35716.5	0.0	1.2472	15517539.0	19354124.5	1.9650	1.9346	1.9329
Unlimited	3	0.025	9789286.5	60761.0	57216.0	0.0	1.2484	15517539.0	19372580.0	1.9790	1.9346	1.9329
Unlimited	trung_vi	0.025	9849657.5000	69138.5000	35716.5000	0.0000	1.2484	15517539.0000	19372580.0000	1.9651	1.9346	1.9329
36000	1	17.794	9875389.0	87547.5	25037.5	0.0	1.2478	15517539.0	19363374.0	1.9608	1.6156	1.6516
36000	2	17.794	9865210.0	79280.5	26313.0	0.0	1.2456	15517539.0	19328410.0	1.9592	1.6156	1.6516
36000	3	17.794	9844791.5	77993.0	20336.0	0.0	1.2467	15517539.0	19345251.5	1.9650	1.6156	1.6516
36000	trung_vi	17.794	9865210.0000	79280.5000	25037.5000	0.0000	1.2467	15517539.0000	19345251.5000	1.9608	1.6156	1.6516
24000	1	45.757	9870713.5	15216.5	0.0	0.0	1.2528	15517539.0	19440420.5	1.9695	0.9891	1.2165
24000	2	45.757	9926188.0	86249.5	23062.5	0.0	1.2420	15517539.0	19272367.5	1.9416	0.9891	1.2165
24000	3	45.757	9896448.5	66246.5	0.0	0.0	1.2465	15517539.0	19342900.0	1.9545	0.9891	1.2165
24000	trung_vi	45.757	9896448.5000	66246.5000	0.0000	0.0000	1.2465	15517539.0000	19342900.0000	1.9545	0.9891	1.2165
12000	1	68.333	9993109.0	87347.0	0.0	0.0	1.2473	15517539.0	19355293.5	1.9369	0.5161	0.4965
12000	2	68.333	9923010.0	70746.0	22750.0	0.0	1.2468	15517539.0	19346600.0	1.9497	0.5161	0.4965
12000	3	68.333	9931545.0	55190.0	12124.5	0.0	1.2479	15517540.0	19364793.5	1.9498	0.5161	0.4965
12000	trung_vi	68.333	9931545.0000	70746.0000	12124.5000	0.0000	1.2473	15517539.0000	19355293.5000	1.9497	0.5161	0.4965
```

READY E2: 12/12 attempt=1. File: `validation/m6d-20261024/E2/`.

### Chốt READY

READY phần A (30/30) và E2 (12/12). Không chạy lại phần A (kiến trúc sư chấp nhận).

6. File dữ liệu đã tạo  
   - `validation/m6d-20261024/` (E1, E2, E3, E4-cache; mỗi lượt `collect.bin` + `export.csv` + `ketqua.txt`)  
   - `validation/m6d-20261024/bang-tong-hop.tsv`, `E2/bang-tong-hop.tsv`  
   - `validation/m6d-20261024/freq-lech.txt`, `E2/freq-lech.txt`  
   - `out/jobs/m6d-a.log`, `out/jobs/m6d-e2.log`  
   - `out/m6d-build.log`

7. Quyết định đã tự đưa ra và lý do  
   - Script E-series/E2 tách khỏi m4.sh (không source/sửa m4.sh); copy đúng mức và cơ chế (calibrate → e1 → e3 → e4-cache; E2 Enter + đo steal 10s).  
   - E1/E4: `-pmu on`; E3: `-pmu host` (theo nhiệm vụ).  
   - Phân tích khoảng đốt: nr=35 hoặc 230 (như m4/m6c); E3: bản ghi vol_ns lớn nhất (như m4.sh).  
   - Driver phần A dừng/khởi động lại container trong `m6d_a_driver.sh`.

8. Cần kiến trúc sư quyết định  
   (Đã trả lời — xem phụ lục. Không còn câu hỏi mở về phần A.)

9. Việc người dùng cần làm tay  
   (Không còn — E2 đã chạy xong.)

10. Lỗi còn tồn tại, việc tiếp theo  
    - M6d đóng: tag `m6d`, push.  
    - Không còn lỗi mở trong phạm vi M6d.

### Thay đổi ngoài phạm vi (`git diff --stat m6c.3..HEAD -- scripts analysis internal cmd tools`)

```
 scripts/m6d_a_driver.sh |  48 +++++
 scripts/m6d_e2.sh       | 379 ++++++++++++++++++++++++++++++++++++++++
 scripts/m6d_eseries.sh  | 449 ++++++++++++++++++++++++++++++++++++++++++++++++
 3 files changed, 876 insertions(+)
```

(analysis / internal / cmd / tools: không đổi)

### sha256 5 file (lúc viết báo cáo)

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
```

---

## Phụ lục — Trả lời kiến trúc sư về R036 phần A (nhận 2026-10-24)

**CHẤP NHẬN, không chạy lại.**

1. **E4-cache:** inst không đổi, CPI giảm ~10 %, cpu_ns giảm 7 % — ghi là quan sát: `--cache` ở các mức này không bão hoà băng thông; CPI giảm phù hợp giả thuyết tần số uncore/mesh tăng khi lõi khác bận; E4-stream (R034) là ca tranh chấp bộ nhớ chính.

2. **E1:** cpu_ns chỉ so tuyệt đối trong cùng dải GHz; bảng bài dùng rq và cyc; ghi tần số nhảy 1,93↔2,53; rq 9/12/26 ms nhất quán với CFS chia đều.

3. **E3** là kiểm không gán nhầm: vol = 300 s, cpu/rq vài chục µs, steal 0 — đạt.
