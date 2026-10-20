# R028 — M6b-1: tính năng thu dài ngày + cổng kiểm

1. **Số báo cáo:** R028  
   **Ngày giờ:** 2026-10-19 17:40 (UTC+7); bổ sung bảng 24 giờ 2026-10-20 17:45  
   **Mốc:** M6b-1  
   **Git:** HEAD `e8ad30b` (binary 24h); pre24h đo bằng `1a88508` — `git diff --stat 1a88508 e8ad30b -- bpf cmd internal go.mod go.sum Makefile` **rỗng** (chỉ thêm script/STATE).  
   **Tag `m6b1`:** gắn trên commit chứa bản R028 này (sau khi điền bảng 24 giờ).

2. **Mục tiêu**  
   Siết cổng (xoá SKIP); chạy lại G7a / G7b-nho / G3 S1–S5 / G9b / host-stats trên binary có sửa SIGTERM; khởi động thu 24h; báo cáo.

3. **Đã làm gì**  
   - Xoá hẳn `M6B1_SKIP_G7A` / `M6B1_SKIP_G3` khỏi `scripts/m6b1_gate.sh` (commit `1a88508`).  
   - `scripts/m6b1_pre24h.sh`: mục 1–3 bắt buộc; exit=0.  
   - Kiến trúc sư đã duyệt G8, G9a, G10 trước đó.  
   - Unit `hidsrun-24h` đang chạy → `/srv/hids-data/uni-lms-app/`, container `hscd_redis` + `qdrant`.

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids
   sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py
   make build   # git_commit trong ldflags = HEAD sạch
   # Muc 1-3:
   M6B1_PRE24H_OUT=validation/m6b1-pre24h-20261019 bash scripts/m6b1_pre24h.sh
   # 24h:
   sudo systemd-run --unit=hidsrun-24h --collect bash -c 'cd /root/hids && bash scripts/m6b1_24h_run.sh'
   ```

5. **Kết quả**

### sha256 ba file kiến trúc sư (trước build + trong status 24h)

```
14d065a601787645b911b7a743e4d6d323757aff0b02bf3487a58fee5fed9d7d  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
```

### Mục 1 — G7a / G7b-nho / G3 (binary `1a88508`, `-zstd-level 0` cho G7)

**G7a** (`validation/m6b1-pre24h-20261019/g7a-summary.txt`):

```
G7a ban_ghi=1000001 mat=0 (perf-ban_ghi)=0
PASS: G7a perf=ban_ghi=1000001 mat=0
```

**G7b-nho:**

```
G7b-nho ban_ghi=22022103 mat=1977921 seq_thieu=1977921 (perf-ban_ghi)=1977921
PASS: G7b-nho (perf-ban_ghi)=mat=seq_thieu=1977921
```

**G3 S1–S5** — G5 phần dư `|tất cả (trừ FIRST)|` max (ns); mọi chương trình trong log collector kết thúc với giá trị recursion 0:

```
S1 max=0
S2 max=498
S3 max=500
S4 max=0
S5 max=496
PASS: G3 recursion_misses=0
PASS: G3 S1-S5 phan du max <= 500 ns
```

**Bảng đối chiếu collector | kernel** (cùng kiểu R026; nguyên văn từ `*-ketqua.txt`):

| Scenario | thành phần | collector | tham chiếu | nguồn |
|---|---|---:|---:|---|
| S1 | cpu+steal+irq | 2962670562 | 2962712249 | Delta schedstat sum_exec_runtime |
| S1 | rq | 23260 | 14630 | Delta schedstat run_delay |
| S1 | vol | 91227000 | 91239700 | Delta sum_sleep_runtime |
| S2 | cpu+steal+irq | 13924440 | 28742161 | Delta schedstat sum_exec_runtime |
| S2 | rq | 17423637 | 3932225 | Delta schedstat run_delay |
| S2 | vol | 3059398000 | 3058120000 | Delta sum_sleep_runtime |
| S2 | tong | 3090746077 | 3090794386 | collector \| kernel |
| S3 | cpu+steal+irq | 1237240360 | 1247920357 | Delta schedstat sum_exec_runtime |
| S3 | rq | 9702421 | 84363 | Delta schedstat run_delay |
| S3 | vol | 1996560000 | 1995550000 | Delta sum_sleep_runtime |
| S3 | tong | 3243502781 | 3243554720 | collector \| kernel |
| S4 | cpu+steal+irq | 2959399249 | 2959593402 | Delta schedstat sum_exec_runtime |
| S4 | rq | 2957679686 | 2957579151 | Delta schedstat run_delay |
| S4 | vol | 91514000 | 91505500 | Delta sum_sleep_runtime |
| S5 | cpu+steal+irq | 69443067 | 74294679 | Delta schedstat sum_exec_runtime |
| S5 | rq | 6453941 | 843990 | Delta schedstat run_delay |
| S5 | vol | 744297000 | 745070000 | Delta sum_sleep_runtime |
| S5 | vol (D_SLEEP) | 303779000 | 304550000 | Delta sum_block_runtime |
| S5 | tong | 820194008 | 820208669 | collector \| kernel |

### G8 (đã duyệt; `validation/m6b1-20261019/g8/`)

```
perf exec=501 fork=501 exit=502
collector exec=501 fork=501 exit=502
exec filename ket thuc /true: 500
PASS: G8 exec/fork/exit khớp perf; exec "/true" = 500
```

### G9a (đã duyệt; rotate 2m, zstd0, G7-cap 1 tiến trình)

```
tong lo hong ranh gioi: 0 | tong seq thieu ranh gioi: 0
PASS: G9 rec-chain seq_thieu=0 lo_hong=0 mat=0
```

Ghi chú kiến trúc sư: cột `seq_thieu` trong bảng **từng file** của file đầu (bản ghi đang trên đường lúc xoay) không tính là mất; tiêu chí là **bảng ranh giới** + bộ đếm mất kernel.

### Mục 2 — G9b (zstd mặc định, 2 container thật: `postgres` rồi khi đo CPU là cặp trong targets; run dùng `postgres`+|`hscd_redis` theo log targets lúc chạy — xem `g9b-targets.txt`: **postgres | hscd_redis**)

Giải nén toàn bộ (`files-inventory.txt`):

```
so file .bin: 5
so file proc: 5
so file host: 5
FILE bin .../202610191014.bin bytes=203945 tong_ban_ghi=16510 decompress_read_ok=1
FILE bin .../202610191016.bin bytes=578797 tong_ban_ghi=47799 decompress_read_ok=1
FILE bin .../202610191018.bin bytes=552859 tong_ban_ghi=45625 decompress_read_ok=1
FILE bin .../202610191020.bin bytes=577162 tong_ban_ghi=47685 decompress_read_ok=1
FILE bin .../202610191022.bin bytes=76992 tong_ban_ghi=6372 decompress_read_ok=1
FILE proc ... (5 file) zstdcat_ok=1
FILE host ... (5 file) zstdcat_ok=1
```

**rec-chain ranh giới:**

```
tong lo hong ranh gioi: 0 | tong seq thieu ranh gioi: 0
G9b ranh_gioi lo_hong=0 seq_thieu=0 kernel_mat_file_cuoi=0
PASS: G9b rec-chain ranh_gioi seq_thieu=0 lo_hong=0 mat=0
```

### G10 (đã duyệt)

```
PASS: G10 PAUSE_DISK
PASS: G10 RESUME_DISK
PASS: G10 bo vi dia=17965099
PASS: G10 kernel mat=0
```

### Mục 3 — Host-stats 10 phút

```
PASS: host ~600 dong (600)
PASS: host bo dem tich luy khong giam
```

(Dữ liệu: `validation/m6b1-pre24h-20261019/host10m/`. Lần gate cũ cũng có 600 dòng MONOTONIC_OK; script gate exit=1 vì lỗi bash `lines` unbound — không đổi tiêu chí.)

### Bảng 24 giờ — ĐÃ XONG

Job `hidsrun-24h`: bắt đầu 2026-10-19T17:38:14+07:00, kết thúc 2026-10-20T17:38:14+07:00; đích `/srv/hids-data/uni-lms-app/`; container **hscd_redis** + **qdrant**; binary `e8ad30b`; READY lúc bắt đầu. Kết thúc bằng `timeout --signal=TERM 86400` nên mã thoát của job là `124`; log collector có dòng `ket thuc longrun end_mono_ns=960041797041342 disk_skipped=0` (dừng sạch). Sau khi thoát: `bpftool prog list | grep -ci hids` = 0, map = 0, `/sys/fs/bpf` = 0.

**Tổng 24 giờ (đo từ file đích):**

```
tong ban ghi .bin (cong so_ban_ghi_doc_duoc cua 25 segment): 34192008
bin:  537065050 byte sau nen | payload chua nen 34192008 x 56 = 1914752448 byte | ti le 1914752448/537065050 = 3.57
proc: 1187266 byte sau nen | 7925565 byte chua nen (119918 dong ke ca 25 dong header) | ti le 6.68
host: 5201114 byte sau nen | 20575521 byte chua nen (86421 dong ke ca 25 dong header) | ti le 3.96
status.tsv: 1426 dong du lieu | tong kernel_drops_delta = 0 | tong proc_drops_delta = 0 | disk_skipped cuoi = 0
RSS cuoi: 202956800 byte (193.6 MiB) | CPU collector cuoi: 8361.764 s
```

Bảng dưới lấy từ `out/jobs/m6b1-24h.hourly.tsv` (23 dòng) cộng dòng cuối lúc kết thúc job (dòng 24). Dung lượng là **luỹ kế**, số trong ngoặc là **delta của giờ đó**. `rec/s` là giá trị ở phút cuối của giờ đó trong `status.tsv`. Cột “mất kernel” là delta 60 giây cuối của giờ; tổng cả 24 giờ bằng 0 (xem tổng trên).

| # | wall (+07) | bin nén luỹ kế (delta) MB | proc nén luỹ kế (delta) KB | host nén luỹ kế (delta) KB | tỉ lệ nén bin (ước tính*) | rec/s | mất kernel | RSS MiB | CPU collector luỹ kế (delta) s |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026-10-19T18:38:16+07:00 | 22.2 (22.2) | 45.9 (45.9) | 211.1 (211.1) | 3.58 | 390.8 | 0 | 188.0 | 350.2 (350.2) |
| 2 | 2026-10-19T19:38:16+07:00 | 44.6 (22.4) | 96.2 (50.3) | 429.0 (217.9) | 3.53 | 393.1 | 0 | 188.0 | 694.7 (344.5) |
| 3 | 2026-10-19T20:38:16+07:00 | 67.0 (22.4) | 145.8 (49.5) | 647.9 (218.9) | 3.60 | 397.6 | 0 | 188.0 | 1045.8 (351.1) |
| 4 | 2026-10-19T21:38:16+07:00 | 89.4 (22.4) | 195.7 (49.9) | 866.8 (218.9) | 3.53 | 396.9 | 0 | 188.0 | 1390.7 (344.9) |
| 5 | 2026-10-19T22:38:16+07:00 | 111.8 (22.4) | 245.8 (50.1) | 1085.0 (218.3) | 3.54 | 395.6 | 0 | 188.0 | 1735.8 (345.0) |
| 6 | 2026-10-19T23:38:16+07:00 | 134.2 (22.4) | 295.2 (49.4) | 1302.9 (217.9) | 3.60 | 390.7 | 0 | 192.6 | 2085.6 (349.8) |
| 7 | 2026-10-20T00:38:16+07:00 | 156.6 (22.4) | 344.8 (49.6) | 1519.2 (216.2) | 3.54 | 393.7 | 0 | 192.6 | 2430.8 (345.2) |
| 8 | 2026-10-20T01:38:16+07:00 | 178.9 (22.4) | 394.9 (50.1) | 1735.4 (216.2) | 3.59 | 397.6 | 0 | 192.6 | 2782.7 (351.8) |
| 9 | 2026-10-20T02:38:16+07:00 | 201.3 (22.4) | 444.4 (49.5) | 1951.7 (216.3) | 3.54 | 397.4 | 0 | 192.6 | 3127.6 (345.0) |
| 10 | 2026-10-20T03:38:16+07:00 | 223.7 (22.4) | 494.2 (49.8) | 2164.6 (212.9) | 3.60 | 396.0 | 0 | 192.6 | 3478.7 (351.0) |
| 11 | 2026-10-20T04:38:16+07:00 | 246.1 (22.4) | 543.1 (48.9) | 2378.8 (214.2) | 3.55 | 397.7 | 0 | 193.0 | 3825.4 (346.7) |
| 12 | 2026-10-20T05:38:17+07:00 | 268.5 (22.4) | 592.6 (49.5) | 2594.9 (216.1) | 3.54 | 394.2 | 0 | 193.0 | 4171.6 (346.2) |
| 13 | 2026-10-20T06:38:17+07:00 | 290.9 (22.4) | 642.2 (49.5) | 2809.1 (214.2) | 3.61 | 395.1 | 0 | 193.0 | 4523.7 (352.1) |
| 14 | 2026-10-20T07:38:17+07:00 | 313.2 (22.4) | 691.5 (49.3) | 3024.2 (215.1) | 3.55 | 392.7 | 0 | 193.0 | 4869.6 (345.9) |
| 15 | 2026-10-20T08:38:17+07:00 | 335.6 (22.3) | 741.5 (50.1) | 3237.9 (213.8) | 3.59 | 395.7 | 0 | 193.0 | 5221.1 (351.5) |
| 16 | 2026-10-20T09:38:17+07:00 | 357.9 (22.4) | 790.8 (49.3) | 3456.4 (218.5) | 3.55 | 393.2 | 0 | 193.4 | 5567.4 (346.3) |
| 17 | 2026-10-20T10:38:17+07:00 | 380.3 (22.4) | 839.8 (49.0) | 3675.3 (218.9) | 3.54 | 396.2 | 0 | 193.4 | 5918.7 (351.2) |
| 18 | 2026-10-20T11:38:17+07:00 | 402.6 (22.4) | 889.8 (49.9) | 3891.8 (216.6) | 3.60 | 393.0 | 0 | 193.6 | 6264.6 (345.9) |
| 19 | 2026-10-20T12:38:17+07:00 | 425.0 (22.3) | 939.2 (49.4) | 4109.9 (218.1) | 3.55 | 392.0 | 0 | 193.6 | 6609.7 (345.1) |
| 20 | 2026-10-20T13:38:17+07:00 | 447.4 (22.4) | 989.2 (50.0) | 4327.5 (217.7) | 3.59 | 393.1 | 0 | 193.6 | 6959.7 (350.1) |
| 21 | 2026-10-20T14:38:17+07:00 | 469.8 (22.4) | 1038.4 (49.2) | 4544.2 (216.6) | 3.54 | 385.0 | 0 | 193.6 | 7306.5 (346.8) |
| 22 | 2026-10-20T15:38:17+07:00 | 492.2 (22.4) | 1079.7 (41.3) | 4761.3 (217.1) | 3.59 | 392.9 | 0 | 193.6 | 7659.5 (353.0) |
| 23 | 2026-10-20T16:38:17+07:00 | 514.5 (22.3) | 1128.1 (48.3) | 4977.8 (216.6) | 3.54 | 395.0 | 0 | 193.6 | 8008.2 (348.7) |
| 24 | 2026-10-20T17:38:14+07:00 | 537.1 (22.6) | 1187.3 (59.2) | 5201.1 (223.3) | 3.51 | 394.5 | 0 | 193.6 | 8361.8 (353.5) |

\* Tỉ lệ nén bin từng giờ là **ước tính**: (số bản ghi trong giờ suy từ `status.tsv` × 56 byte) / (delta byte `.bin` sau nén của giờ). Tỉ lệ toàn cục ở khối tổng trên tính trực tiếp từ tổng số bản ghi của 25 segment.

6. **File dữ liệu**  
   - `/root/hids/validation/m6b1-pre24h-20261019/`  
   - `/root/hids/validation/m6b1-20261019/` (G8, G9a, G10)  
   - `/srv/hids-data/uni-lms-app/` (dữ liệu 24 giờ: 25 segment mỗi luồng `.bin` / `proc-*.tsv.zst` / `host-*.tsv.zst`, kèm `status.tsv`)  
   - `/root/hids/out/jobs/m6b1-pre24h.log`, `m6b1-24h.log`, `m6b1-24h.status`, `m6b1-24h.hourly.tsv`

7. **Quyết định đã tự đưa ra**  
   - Pre24h dùng `g3.sh m5d` (chỉ S1–S5) đúng yêu cầu mục 1.  
   - G9b chọn 2 container theo `docker stats` CPU cao nhất tại thời điểm chạy.  
   - Binary 24h = HEAD sau khi thêm script chạy 24h; mã collector/BPF không đổi so với pre24h (`1a88508`).  
   - Dòng 24 của bảng giờ lấy lúc job kết thúc, vì vòng báo giờ của script chưa kịp ghi dòng thứ 24 trước khi tiến trình chính thoát.

8. **Cần kiến trúc sư quyết định**  
   - (Không.)

9. **Việc người dùng cần làm tay**  
   - (Không.)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - `status.tsv` của lần thu 24 giờ có **24 dòng `records_per_sec` âm** (một dòng tại mỗi lần xoay file): bộ đếm bản ghi của segment mới bắt đầu lại từ 0, trong khi giá trị trước vẫn là tổng của segment cũ, nên hiệu ra âm. Các dòng khác bình thường; bộ đếm mất kernel vẫn bằng 0. Cần kiến trúc sư quyết định có sửa cách tính `records_per_sec` trong `status.tsv` trước M6b-2 hay không — lần này chỉ ghi nhận, không tự sửa.  
    - Gate cũ `m6b1_gate.sh` còn lỗi `set -u` khi biến `lines` ở bước host-stats (đã ghi nhận; không đổi tiêu chí).

---

## Thay đổi ngoài phạm vi nhiệm vụ

**Tiêu chí mọi cổng kiểm (G7a/G7b-nho/G3/G8/G9/G10/host): không đổi số ngưỡng hay phép đối chiếu.** Chỉ xoá lối tắt SKIP; sửa parse số G8 (định dạng in); sửa lỗi thoát SIGTERM collector.

### 1) Sửa SIGTERM / hai vòng đọc ringbuf — `git show 2017ad6 --stat`

```
cmd/hids-collect/longrun.go | 117 +++++++++++++++++++++++++++-----------------
 1 file changed, 71 insertions(+), 46 deletions(-)
```

Tóm tắt: tách đọc syscall ringbuf và proc ringbuf thành hai goroutine; mỗi bên drain bằng `Flush`/`ErrFlushed` khi detach — hết treo `futex` khi SIGTERM (trước đó một vòng đọc xen kẽ hai reader + `SetDeadline` dễ kẹt).

### 2) Sửa đọc số trong `m6b1_gate.sh` — `git show 6fe3fa3 -- scripts/m6b1_gate.sh`

```diff
-  END{print "collector exec",e+0,"fork",f+0,"exit",x+0}
+  END{printf "collector exec=%d fork=%d exit=%d\n", e+0, f+0, x+0}
-coll_exec=$(awk '/collector exec/{print $3}' ...)
+coll_exec=$(sed -n 's/.*exec=\([0-9]*\).*/\1/p' ...)
```

Không đổi tiêu chí khớp perf; chỉ sửa cách tách số (trước đó `fork`/`exit` bị parse rỗng).

### 3) `git diff --stat` scripts/ / analysis/ (khoảng xoá SKIP + pre24h)

```
scripts/m6b1_gate.sh   |  24 ++----   (xoá M6B1_SKIP_*)
scripts/m6b1_pre24h.sh | 214 +++++  (script mới mục 1–3)
scripts/m6b1_24h_run.sh|  69 +++++  (script 24h)
analysis/              | (không đổi)
```

**Xác nhận:** không sửa `bpf/sys_enter.bpf.c`, `bpf/proc_events.bpf.c`, `analysis/m5f_parse.py`.
