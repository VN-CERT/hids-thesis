# R037 — M6f: so overhead Falco / Tetragon / HIDS trên T1/T3/T4

1. Số báo cáo: **R037**  
   Ngày giờ: **2026-10-25 02:47 (+07)**  
   Mốc: **M6f**  
   Git commit: `3ee5460` (du lieu + R037); tag `m6f` = HEAD tai luc push.

2. Mục tiêu  
   So overhead của Falco, Tetragon (mặc định và sys_enter), HIDS-host (production), HIDS-all (toàn máy) với mốc C0 trên cùng benchmark T1/T3/T4 (máy 195), 10 lượt xen kẽ. Không sửa BPF, không sửa file kiến trúc sư, không sửa `analysis/`.

3. Đã làm gì  
   - Lưu nguyên văn `docs/tasks/M6f.md`.  
   - Kiểm sha256 5 file kiến trúc sư: khớp.  
   - Pull ảnh: `falcosecurity/falco:latest` (= **0.45.1**); `quay.io/cilium/tetragon:latest` **không tồn tại** → dùng **v1.7.0** (phiên bản ổn định trong tài liệu chính thức tại thời điểm làm).  
   - Script `scripts/m6f_overhead.sh`, `scripts/m6f_driver.sh`, TracingPolicy `scripts/m6f-tetragon-sysenter.yaml`.  
   - Vệ sinh: `user.slice AllowedCPUs=0-11,21-23` suốt phiên; dừng 12 container khi đo; `freq_stamp` trước/sau mỗi khối T; gỡ AllowedCPUs và bật lại container khi xong.  
   - Unit `hids-m6f`: bắt đầu 2026-10-24 23:47, xong 2026-10-25 02:45 (+07), **exit=0**; lần 1 (23:44) exit=2 do `-v` relative path (đã sửa, chạy lại từ đầu).  
   - Kernel sạch sau khi xong (`bpf_leftover_match=0`); 12 container chạy lại.

4. Lệnh build, lệnh chạy  
```bash
cd /root/hids
# Không make build (không đổi BPF); binary hiện tại.
systemd-run --unit=hids-m6f --collect bash -c 'cd /root/hids && bash scripts/m6f_driver.sh'
# Dữ liệu: validation/m6f-20261024/
# Thống kê:
python3 analysis/m6c_stats.py validation/m6f-20261024/T1.tsv
python3 analysis/m6c_stats.py validation/m6f-20261024/T3.tsv
python3 analysis/m6c_stats.py validation/m6f-20261024/T4.tsv
```

5. Kết quả

### Phiên bản công cụ

| Công cụ | Ảnh | Digest | Phiên bản |
|---------|-----|--------|-----------|
| Falco | `falcosecurity/falco:latest` | `sha256:69e957f91b3a6beb5c82e2afae33ec3e4479dab2d4421475d288d0cd113cedf6` | Falco **0.45.1**, Libs 0.26.1, Engine 0.65.0, Driver API 11.0.0 / Schema 4.3.0 |
| Tetragon | `quay.io/cilium/tetragon:v1.7.0` | `sha256:deda51c3f88e4d26b4d76c99ea207f2b05f9e40c210e0f04a37ca632ab7bf527` | CLI / image **v1.7.0** |

### Lệnh chạy container (nguyên văn tài liệu + cấu hình M6f)

**Falco — Fully Privileged / Modern eBPF** (nguồn: https://falco.org/docs/setup/container/ ; docs ghi `0.45.0`, M6f pull `latest` = 0.45.1):

```shell
docker pull falcosecurity/falco:0.45.0
docker run --rm -it \
           --privileged \
           -v /sys/kernel/tracing:/sys/kernel/tracing:ro \
           -v /var/run/docker.sock:/host/var/run/docker.sock \
           -v /proc:/host/proc:ro \
           -v /etc:/host/etc:ro \
           falcosecurity/falco:0.45.0
```

Cấu hình M6f thêm (cùng mount privileged ở trên, `-d --name m6f-falco`, mount metrics host dir):

```text
falco \
  -o engine.kind=modern_ebpf \
  -o stdout_output.enabled=false \
  -o syslog_output.enabled=false \
  -o file_output.enabled=true \
  -o file_output.filename=/dev/null \
  -o metrics.enabled=true \
  -o metrics.interval=5s \
  -o metrics.output_rule=false \
  -o metrics.output_file=/metrics/falco_metrics.jsonl \
  -o metrics.kernel_event_counters_enabled=true \
  -o log_syslog=false
```

Bộ luật: mặc định trong ảnh (`/etc/falco/falco_rules.yaml`). Sẵn sàng khi log có `Opening 'syscall' source with modern BPF probe`; kiểm `bpftool prog show` tăng trước khi chạy tải. Drop: `scap.n_drops` trong metrics JSONL.

**Tetragon — Stable** (nguồn: https://tetragon.io/docs/installation/container/):

```shell
docker run --name tetragon --rm -d                   \
    --pid=host --cgroupns=host --privileged          \
    -v /sys/kernel/btf/vmlinux:/var/lib/tetragon/btf \
    quay.io/cilium/tetragon:v1.7.0
```

M6f thêm: `-p 127.0.0.1:2112:2112`, lệnh  
`/usr/bin/tetragon --export-filename /dev/null --metrics-server :2112`  
(và với TETRA-sysenter: `--tracing-policy` gắn `raw_syscalls/sys_enter` không lọc — file `scripts/m6f-tetragon-sysenter.yaml`).  
Sẵn sàng khi log có `Listening for events...`. Drop: Prometheus `:2112` — `tetragon_observer_ringbuf_events_lost_total` + `tetragon_observer_ringbuf_queue_events_lost_total` (cột drop = tổng hai số này).

**HIDS-host:** `./bin/hids-collect -pmu host` + lọc cgroup/pid tải (như M6c-1).  
**HIDS-all:** `./bin/hids-collect -pmu host -cgroup /sys/fs/cgroup`.

### Dấu tần số (CPU 12, trung vị GHz_wall)

| Khối | Trước | Sau | |Δ| ≤ 2%? |
|------|-------|-----|---------|
| T1 | 1.9398 | 1.9400 | có |
| T4 | 1.9401 | 1.9399 | có |
| T3 | **2.0717** | **1.9380** | **không** (~6,9%) |

### Overhead — nguyên văn `m6c_stats.py` (mốc C0)

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T1	C0	10	184.9300	1.9936	183.5040	186.3560	0.0000	-	-	-
T1	FALCO	10	216.5040	1.4042	215.4996	217.5084	17.0735	16.2086	17.9413	0.0001
T1	HIDS-all	10	768.5130	25.5840	750.2126	786.8134	315.5697	307.3839	324.3609	0.0001
T1	HIDS-host	10	772.6190	31.1118	750.3645	794.8735	317.7900	307.2820	327.6276	0.0001
T1	TETRA-def	10	185.7210	3.3862	183.2988	188.1432	0.4277	-0.6878	1.8241	0.5871
T1	TETRA-sysenter	10	1590.5890	95.3800	1522.3630	1658.8150	760.1033	731.5546	792.8581	0.0002
```

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T3	C0	10	3548.3341	238.4655	3377.7581	3718.9102	0.0000	-	-	-
T3	FALCO	10	3324.5322	251.1323	3144.8954	3504.1689	-6.3072	-11.7092	-0.6532	0.0562
T3	HIDS-all	10	2040.6054	191.9740	1903.2850	2177.9258	-42.4912	-46.2017	-38.5060	0.0001
T3	HIDS-host	10	2817.6600	241.8824	2644.6398	2990.6802	-20.5920	-25.4680	-15.4034	0.0001
T3	TETRA-def	10	3510.5278	213.3188	3357.9394	3663.1163	-1.0655	-6.1679	4.3353	0.6998
T3	TETRA-sysenter	10	1495.2554	180.8972	1365.8584	1624.6525	-57.8604	-61.1641	-54.3283	0.0002
```

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T4	C0	10	109653.2480	3972.5516	106811.6532	112494.8428	0.0000	-	-	-
T4	FALCO	10	97068.7700	5081.5887	93433.8730	100703.6670	-11.4766	-14.9045	-8.2071	0.0001
T4	HIDS-all	10	62873.5660	1819.9752	61571.7246	64175.4074	-42.6615	-44.1741	-41.0414	0.0001
T4	HIDS-host	10	94097.2260	5822.6495	89932.2429	98262.2091	-14.1866	-17.6370	-10.3807	0.0001
T4	TETRA-def	10	109977.8460	5951.9533	105720.3709	114235.3211	0.2960	-3.5312	4.2422	0.8894
T4	TETRA-sysenter	10	58094.8530	1492.9225	57026.9548	59162.7512	-47.0195	-48.3075	-45.5824	0.0002
```

(T1: ns/syscall — cao hơn = chậm hơn. T3: TPS, T4: req/s — thấp hơn = chậm hơn.)

### CPU công cụ (trung vị `cpu.stat usage_usec` của cgroup container / scope collector) cạnh overhead

| load | cond | median cpu_usec | ghi chú drop (median) |
|------|------|-----------------|------------------------|
| T1 | FALCO | 1.22e5 | scap.n_drops=0 |
| T1 | TETRA-def | 4.42e4 | ringbuf+queue lost=0 |
| T1 | TETRA-sysenter | 7.10e7 | lost≈1.45e7 |
| T1 | HIDS-host | 1.67e7 | mat=0; ~1.29e6 bản ghi/s |
| T1 | HIDS-all | 1.63e7 | mat=0; ~1.31e6 bản ghi/s |
| T3 | FALCO | 1.99e7 | drops=0 |
| T3 | TETRA-def | 7.87e5 | lost=0 |
| T3 | TETRA-sysenter | 2.27e8 | lost≈6.13e7 |
| T3 | HIDS-host | 5.15e7 | mat=0; ~5.22e5 bản ghi/s |
| T3 | HIDS-all | 1.20e8 | mat≈6.43e5; ~1.11e6 bản ghi/s |
| T4 | FALCO | 3.87e7 | drops=0 |
| T4 | TETRA-def | 2.89e5 | lost=0 |
| T4 | TETRA-sysenter | 2.38e8 | lost≈1.06e8 |
| T4 | HIDS-host | 5.06e7 | mat=0; ~6.71e5 bản ghi/s |
| T4 | HIDS-all | 1.19e8 | mat≈2.71e7; ~1.38e6 bản ghi/s |

TSV đầy đủ: `validation/m6f-20261024/tool-cpu.tsv`, `tool-drop.tsv`, `tool-summary.txt`.

6. File dữ liệu đã tạo  
   - `validation/m6f-20261024/` (T1/T3/T4 × 6 điều kiện × 10; `*.tsv`, `*.stats.txt`, `freq/`, `versions.txt`, `overhead.log`)  
   - `out/jobs/m6f.log`, `out/jobs/m6f.status`  
   - `docs/tasks/M6f.md`, `scripts/m6f_overhead.sh`, `scripts/m6f_driver.sh`, `scripts/m6f-tetragon-sysenter.yaml`

7. Quyết định đã tự đưa ra và lý do  
   - `quay.io/cilium/tetragon:latest` không có → dùng **v1.7.0** đúng tài liệu “latest stable”.  
   - Falco: `falco:latest` = 0.45.1 (docs ví dụ 0.45.0); cấu hình qua `-o` thay file YAML (tránh lỗi schema `program_output`).  
   - Drop Tetragon: tổng `ringbuf_events_lost` + `queue_events_lost` (cả hai có trên `:2112`).  
   - Drop Falco: `scap.n_drops` từ metrics JSONL.  
   - Lần chạy 1 fail vì Docker hiểu relative `-v` là tên volume → sửa absolute path, chạy lại toàn bộ từ đầu (không ghép dữ liệu cũ).

### Thay đổi ngoài phạm vi

```
git diff --stat m6c.3..HEAD -- scripts analysis internal cmd tools
 scripts/m6d_a_driver.sh            |  48 +++
 scripts/m6d_e2.sh                  | 379 ++++++++++++++++++++++
 scripts/m6d_eseries.sh             | 449 ++++++++++++++++++++++++++
 scripts/m6e_e2b.sh                 | 514 +++++++++++++++++++++++++++++
 scripts/m6f-tetragon-sysenter.yaml |  11 +
 scripts/m6f_driver.sh              |  28 ++
 scripts/m6f_overhead.sh            | 645 +++++++++++++++++++++++++++++++++++++
 7 files changed, 2074 insertions(+)
```

Không đụng `analysis/`, `internal/`, `cmd/`, `tools/`, BPF trong diff này. File kiến trúc sư không đổi (sha256 khớp).

### sha256 5 file (lúc viết báo cáo)

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
```

8. Cần kiến trúc sư quyết định  
   1. **T3 freq trước/sau lệch > 2%** (2.0717 → 1.9380 GHz): có được so tuyệt đối overhead T3 giữa các điều kiện trong đợt này không, hay chỉ dùng tỉ lệ % vs C0 trong cùng xen kẽ?  
   2. **HIDS-all vs Falco/Tetragon “công bằng”:** HIDS-all mất nhiều bản ghi ở T3/T4 (median mat ~6e5 / ~2.7e7) trong khi Falco `scap.n_drops=0` và TETRA-def lost=0 — có cần cấu hình HIDS-all tăng ring buffer / giảm phạm vi, hay giữ như production-all-machine để báo cáo?  
   3. Bảng bài: ưu tiên hàng nào làm “đối thủ gần production” — **Falco (rules mặc định)** và **TETRA-def**, còn TETRA-sysenter / HIDS-all chỉ phụ lục “cùng lớp quan sát mọi sys_enter”?  
   4. T1: HIDS-host ~+318% ns/syscall vs Falco ~+17% — có chấp nhận giải thích “Falco lọc theo rules/state set, HIDS ghi mọi sys_enter trong cgroup”, hay cần thêm cấu hình Falco/Tetragon quan sát mọi syscall để so trực tiếp với HIDS-host?

9. Việc người dùng cần làm tay  
   - Không có.

10. Lỗi còn tồn tại, việc tiếp theo đề xuất  
   - Không lỗi chặn: unit exit=0, BPF sạch, container bật lại, AllowedCPUs gỡ.  
   - Đề xuất: kiến trúc sư trả lời mục 8; không chạy lại trừ khi yêu cầu (T3 freq).  
   - Tag `m6f`, push; **DỪNG**.


---

## Phụ lục — Trả lời kiến trúc sư về R037 mục 8 (nhận 2026-10-25)

**ĐẠT.**

**(8.1)** T3 lệch tần số 6,9 % giữa đầu/cuối khối: chỉ dùng **% so C0 trong cùng xen kẽ**, không so tuyệt đối TPS giữa khối; ghi chú trong bảng.

**(8.2)** HIDS-all giữ nguyên, nhãn *"ngoài cấu hình production; vượt công suất ~0,95 M bản ghi/giây đã biết; mất được đếm chính xác"* — mục đích là công bằng phạm vi với TETRA-sysenter (6,4×10⁵ vs 6,1×10⁷ mất ở T3; 2,7×10⁷ vs 1,06×10⁸ ở T4).

**(8.3)** Bảng chính của bài: **C0, Falco mặc định, TETRA-def, HIDS-host**; phụ lục *"cùng lớp quan sát mọi sys_enter"*: **TETRA-sysenter, HIDS-all**. Khác lớp: Falco mặc định lọc syscall theo rules ngay trong BPF và không phân rã thời gian; TETRA-def chỉ exec/exit.

**(8.4)** Chấp nhận giải thích. Chạy thêm **M6f-b**: FALCO-all = Falco modern_ebpf với `-o base_syscalls.all=true` (T1/T3/T4 × 10, xen kẽ C0 và HIDS-host); nối kết quả ở mục **M6f-b** dưới đây; tag `m6f.1`.

### Ghi chú bảng chính (theo 8.1 / 8.3)

- T3: chỉ đọc cột `pct_vs_C0` (và CI); **không** so mean TPS tuyệt đối giữa đầu/cuối khối vì GHz lệch 6,9 %.
- Bảng chính bài: C0 | FALCO (mặc định) | TETRA-def | HIDS-host.
- Phụ lục cùng lớp mọi sys_enter: TETRA-sysenter | HIDS-all (HIDS-all: ngoài production; vượt ~0,95 M bản ghi/s; mất đếm chính xác).

### M6f-b

Unit `hids-m6fb`: 2026-10-25 09:39 → 11:02 (+07), **exit=0**.  
Điều kiện xen kẽ ×10: **C0**, **FALCO-all** (`-o base_syscalls.all=true`), **HIDS-host**.  
Falco 0.45.1 **nhận** `base_syscalls.all` (schema ok; không lỗi). Dữ liệu: `validation/m6f-b-20261025/`.

Lệnh (bổ sung so M6f Falco):

```text
falco -o engine.kind=modern_ebpf -o base_syscalls.all=true \
  -o stdout_output.enabled=false -o syslog_output.enabled=false \
  -o file_output.enabled=true -o file_output.filename=/dev/null \
  -o metrics.enabled=true -o metrics.interval=5s \
  -o metrics.output_rule=false -o metrics.output_file=/metrics/falco_metrics.jsonl \
  -o metrics.kernel_event_counters_enabled=true -o log_syslog=false
```

```bash
systemd-run --unit=hids-m6fb --collect bash -c 'cd /root/hids && bash scripts/m6fb_driver.sh'
```

**freq_stamp CPU12 (trung vị GHz_wall):** T1 1.9402→1.9384; T4 1.9410→1.9391; T3 1.9394→1.9392 (mọi khối |Δ|≤2%).

**Overhead — nguyên văn `m6c_stats.py`:**

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T1	C0	10	183.8870	3.3434	181.4955	186.2785	0.0000	-	-	-
T1	FALCO-all	10	216.9250	2.6921	214.9993	218.8507	17.9665	16.3618	19.4348	0.0001
T1	HIDS-host	10	778.1620	25.5039	759.9189	796.4051	323.1740	313.7873	332.1207	0.0001
```

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T3	C0	10	3466.0272	242.3413	3292.6787	3639.3756	0.0000	-	-	-
T3	FALCO-all	10	3344.4555	218.3204	3188.2893	3500.6217	-3.5075	-8.7734	1.9857	0.2511
T3	HIDS-host	10	2749.1436	254.6779	2566.9707	2931.3166	-20.6831	-25.9470	-15.1797	0.0001
```

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T4	C0	10	113783.6120	3647.8680	111174.2657	116392.9583	0.0000	-	-	-
T4	FALCO-all	10	97789.0950	6776.4440	92941.8557	102636.3343	-14.0570	-17.8863	-10.2794	0.0001
T4	HIDS-host	10	98908.0720	5382.3105	95058.0665	102758.0775	-13.0735	-16.3152	-9.9652	0.0001
```

**CPU công cụ (median usage_usec) và drop:**

| load | cond | median cpu_usec | scap.n_drops / mat (median) |
|------|------|-----------------|------------------------------|
| T1 | FALCO-all | 1.22e5 | 0 |
| T1 | HIDS-host | 1.67e7 | mat=0 (~1.28e6 bản ghi/s) |
| T3 | FALCO-all | 2.00e7 | 0 |
| T3 | HIDS-host | 5.12e7 | mat=0 (~5.21e5 bản ghi/s) |
| T4 | FALCO-all | 3.75e7 | 0 |
| T4 | HIDS-host | 5.43e7 | mat=0 (~7.09e5 bản ghi/s) |

Quan sát (không tự kết luận đạt): FALCO-all gần với FALCO mặc định ở M6f (T1 ~+18% vs ~+17%; T4 ~−14% vs ~−11%); HIDS-host cùng bậc với M6f (T1 ~+323%, T3 ~−21%, T4 ~−13%).

sha256 5 file lúc viết M6f-b: khớp (cùng giá trị như mục trên).

Tag: `m6f.1`.

### M6f-c

Ngày: 2026-10-25. Nhiệm vụ: `docs/tasks/M6f-c.md`. Không sửa BPF / analysis / file kiến trúc sư.

#### (1) scap.n_evts / scap.n_drops từ metrics JSONL đã ghi (M6f FALCO, M6f-b FALCO-all)

Nguồn: dòng metrics cuối mỗi lượt (`falco_metrics.jsonl`).  
`load_syscalls`: T1 = 10 000 000; T3/T4 = `ban_ghi` của **HIDS-host cùng lượt** (cùng suite).  
TSV đầy đủ: `validation/m6f-c-20261025/falco_nevts_compare.tsv`.

**Trung vị (10 lượt):**

| suite | load | cond | median scap.n_evts | median scap.n_drops | median load_syscalls |
|-------|------|------|--------------------:|--------------------:|---------------------:|
| M6f | T1 | FALCO | 1 | 0 | 10000000 |
| M6f | T3 | FALCO | 8165600 | 0 | 31498010 |
| M6f | T4 | FALCO | 22735130 | 0 | 40297252 |
| M6f-b | T1 | FALCO-all | 1 | 0 | 10000000 |
| M6f-b | T3 | FALCO-all | 8271183 | 0 | 31468557 |
| M6f-b | T4 | FALCO-all | 22524746 | 0 | 42601171 |

**Từng lượt (nguyên văn TSV):** xem `validation/m6f-c-20261025/falco_nevts_compare.tsv` và `part1-table.txt`.

#### (2) T1 × 10 — C0 / FALCO-A / HIDS-host — **không chạy được**

Lệnh yêu cầu: `falco -A -o base_syscalls.all=true` (+ cấu hình còn lại như M6f-b).

Falco **0.45.1** từ chối `-A`. Lỗi nguyên văn:

```
Error: Option ‘A’ does not exist
```

File: `validation/m6f-c-20261025/falco-A-error.txt`.  
Không có m6c_stats / n_evts / CPU cho FALCO-A (không gắn được). Không thay bằng cấu hình khác.

Tag: `m6f.2`.

---

## Phụ lục — Trả lời kiến trúc sư về M6f-c (nhận 2026-10-25)

**ĐẠT**, đóng chuỗi M6f (tag `m6f.2`), không chạy thêm.

(1) Phạm vi quan sát của Falco (modern_ebpf, rules mặc định, cả base_syscalls.all) theo scap.n_evts/so syscall của tải: T1 0 % (n_evts=1 trên 10 triệu getppid), T3 26 %, T4 56 %; Falco 0.45 không còn -A; vậy Falco không thể cấu hình để quan sát mọi syscall — khác lớp với HIDS và Tetragon-sysenter.

(2) Chi phí trên mỗi sự kiện THỰC QUAN SÁT: T4 Falco 1,67 µs/sự kiện vs HIDS-host 1,27 µs/bản ghi (gồm phân rã + nén), T3 2,4 µs vs 1,63 µs.

(3) Bảng chính bài thêm cột "độ phủ syscall": Falco 0/26/56 %, TETRA-def ~0 (exec/exit), TETRA-sysenter 100 % (mất 1,45×10⁷/6,1×10⁷/1,06×10⁸), HIDS-host 100 % (mất 0).

(4) Câu kết luận so sánh: ở tải Falco phủ nhiều nhất (T4), overhead hai bên bằng nhau (−14 % vs −13 %) dù Falco chỉ thấy một nửa syscall; công cụ cùng phạm vi duy nhất đắt gấp 2 và mất sự kiện.

