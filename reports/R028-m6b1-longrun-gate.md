# R028 — M6b-1: tính năng thu dài ngày + cổng kiểm

1. **Số báo cáo:** R028  
   **Ngày giờ:** 2026-10-19 17:40 (UTC+7)  
   **Mốc:** M6b-1  
   **Git:** HEAD `e8ad30b` (binary 24h); pre24h đo bằng `1a88508` — `git diff --stat 1a88508 e8ad30b -- bpf cmd internal go.mod go.sum Makefile` **rỗng** (chỉ thêm script/STATE).  
   **Tag `m6b1`:** chưa gắn — chờ xong job 24h rồi gắn.

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

### Bảng 24 giờ

**CHƯA XONG.** Job `hidsrun-24h` bắt đầu 2026-10-19T17:38:14+07:00, đích `/srv/hids-data/uni-lms-app/`, container **hscd_redis** + **qdrant**, binary `e8ad30b`, READY.

Bảng từng giờ sẽ ghi vào `out/jobs/m6b1-24h.hourly.tsv` (cột: wall, bin_bytes, proc_bytes, host_bytes, recs_per_s, kernel_drops, disk_skipped, free_gb, rss_bytes, cpu_seconds, proc_drops).  
**Tiến độ:** 0/24 — dự kiến xong ~2026-10-20 17:38. Log: `out/jobs/m6b1-24h.log`.

| giờ (wall) | bin sau nén | proc sau nén | host sau nén | tỉ lệ nén | rec/s | mất | RSS | CPU collector |
|---|---|---|---|---|---|---|---|---|
| (chờ dữ liệu hourly) | | | | | | | | |

6. **File dữ liệu**  
   - `/root/hids/validation/m6b1-pre24h-20261019/`  
   - `/root/hids/validation/m6b1-20261019/` (G8, G9a, G10)  
   - `/srv/hids-data/uni-lms-app/` (24h đang ghi)  
   - `/root/hids/out/jobs/m6b1-pre24h.log`, `m6b1-24h.log`, `m6b1-24h.status`

7. **Quyết định đã tự đưa ra**  
   - Pre24h dùng `g3.sh m5d` (chỉ S1–S5) đúng yêu cầu mục 1.  
   - G9b chọn 2 container theo `docker stats` CPU cao nhất tại thời điểm chạy.  
   - Binary 24h = HEAD sau khi thêm script chạy 24h; mã collector/BPF không đổi so với pre24h (`1a88508`).  
   - Chưa gắn tag `m6b1` cho đến khi bảng 24 giờ đủ.

8. **Cần kiến trúc sư quyết định**  
   - (Không — chờ đủ bảng 24 giờ rồi gắn tag / bổ sung R028 nếu cần.)

9. **Việc người dùng cần làm tay**  
   - (Không)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Hoàn tất `hidsrun-24h`, điền bảng 24 giờ vào R028 (hoặc R029 nếu không sửa R028), gắn tag `m6b1`.  
    - Gate cũ `m6b1_gate.sh` còn lỗi `set -u` khi biến `lines` (đã ghi nhận; chưa sửa trong lần này để tránh đụng script cổng ngoài yêu cầu xoá SKIP).

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
