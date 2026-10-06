# R004 — M3 mục A–E: trạng thái theo thread, bộ cộng dồn irq, kiểm tra fail-closed

## 1. Thông tin chung
- Số báo cáo: **R004**
- Ngày giờ: **2026-10-06 (chạy thử lúc 00:04 ngày 2026-10-07 giờ máy)**
- Mốc: **M3 mục A–E** (phạm vi phiên bị người dùng thu hẹp, xem mục 2)
- Git commit: **`b8e75d1`** — cây git sạch lúc chạy thử, header dữ liệu ghi `git_commit: b8e75d1` không có dấu `dirty`.
- Máy: Ubuntu 24.04, kernel 6.8.0-142-generic, VM VMware, 24 CPU.

## 2. Mục tiêu

Nhiệm vụ M3 do kiến trúc sư giao gồm 10 mục A–J. Người dùng đã thu hẹp phạm vi
phiên này: **chỉ làm mục A, B, C, D, E**.

Mục tiêu của phiên:

- **A.** Ghi định nghĩa 5 thành phần của Δt vào `.cursor/rules/hids.mdc`.
- **B.** Trạng thái theo từng thread trong `BPF_MAP_TYPE_TASK_STORAGE`, mở rộng từ M2.
- **C.** Bộ cộng dồn irq per-CPU: `irq_handler_*`, `softirq_*`, và mọi cặp
  `*_entry`/`*_exit` trong `/sys/kernel/tracing/events/irq_vectors/`.
- **D.** Bảng flags thêm bit6 CLAMPED.
- **E.** Kiểm tra fail-closed lúc khởi động và các dòng header mới.

Trước đó, trong cùng phiên, đã làm xong phần phản hồi của kiến trúc sư cho R003
(G7d, file `.periodic` + dòng `LOSS`, ghi nhận GĐ4) — đã báo và đã commit ở
`cc610ea`.

### KHÔNG làm trong phiên này

**Mục F, G, H, I, J của M3 chưa viết và chưa chạy.** Cụ thể:

| Mục | Nội dung | Trạng thái |
|---|---|---|
| F | `tools/wl.c` (ba lần `read()`, chế độ cpu/sleep/mixed/io) | **Chưa viết, chưa chạy.** Không có file nào được tạo. |
| G | `bin/rec-check` (phần dư G5, tổng thành phần theo tid) | **Chưa viết, chưa chạy.** Không có file nào được tạo. |
| H | `scripts/g3.sh` (S1–S5, G-real trên qdrant, G-irq so với bcc) | **Chưa viết, chưa chạy.** Không có file nào được tạo. |
| I | Kỳ vọng vật lý để tự gỡ lỗi | **Chưa dùng.** Chưa có phép đo nào đối chiếu với kỳ vọng vật lý. |
| J | Lưu `validation/g3-<ngày>/`, tag `m3`, viết báo cáo cho toàn bộ M3 | **Chưa làm.** Không gắn tag `m3`. |

Hệ quả quan trọng: **các con số trong báo cáo này chưa được đối chiếu với bất kỳ
nguồn tham chiếu nào của kernel.** Việc đó thuộc mục G và H. Báo cáo này chỉ
chứng minh chương trình nạp được, chạy được, và các bản ghi không tự mâu thuẫn.

## 3. Đã làm gì

### 3.1 Mục A — định nghĩa 5 thành phần (`.cursor/rules/hids.mdc`)

Đã ghi vào quy tắc dự án, nguyên văn theo kiến trúc sư: khoảng ON-CPU chia thành
`cpu + steal + irq`; `steal` lấy từ `vmw_steal_time` quy đổi trong BPF; `irq` lấy
từ bộ cộng dồn per-CPU; `cpu` = độ dài khoảng − steal − irq, nếu âm thì đặt 0 và
bật cờ CLAMPED. Khoảng OFF-CPU chia thành `rq` (chờ hàng đợi chạy) và `vol`
(ngủ/chờ tự nguyện) theo mốc `sched_wakeup`. Steal lúc OFF-CPU không tính.

### 3.2 Mục B — trạng thái theo thread

Viết lại `bpf/sys_enter.bpf.c` (606 dòng). Trạng thái mỗi thread nằm trong
`BPF_MAP_TYPE_TASK_STORAGE` (`BPF_F_NO_PREALLOC`), chỉ tạo mới ở `sys_enter`,
còn `sched_switch`/`sched_wakeup` chỉ tra cứu.

Máy trạng thái ON-CPU / OFF-CPU:

- `sys_enter`: đóng khoảng ON-CPU đang mở, cộng vào các biến tích luỹ, ghi bản
  ghi 48 byte, xoá biến tích luỹ, mở khoảng ON-CPU mới.
- `sched_switch` (phía `prev`): đóng khoảng ON-CPU, ghi mốc OFF-CPU, phân loại
  `RUNNABLE` (bị chiếm quyền) hay `SLEEP` (ngủ), bật D_SLEEP khi
  `prev_state & 0x2`.
- `sched_switch` (phía `next`): cộng `rq` hoặc `vol`+`rq` dựa trên mốc
  `sched_wakeup`, bật MIGRATED nếu đổi CPU, mở lại khoảng ON-CPU.
- `sched_wakeup` / `sched_wakeup_new`: ghi mốc đánh thức bằng
  `__sync_val_compare_and_swap` để chỉ mốc đầu tiên được giữ.

Khi `bpf_ringbuf_reserve` thất bại: tăng bộ đếm mất, bật cờ chờ GAP_BEFORE,
**giữ nguyên các biến tích luỹ và mốc `sys_enter` trước**, mở lại khoảng ON-CPU.
Nhờ vậy bản ghi tiếp theo gộp đúng cả khoảng bị mất, đẳng thức
`Δt = cpu+steal+irq+rq+vol` vẫn giữ.

### 3.3 Mục C — bộ cộng dồn irq per-CPU

`BPF_MAP_TYPE_PERCPU_ARRAY` một phần tử, mỗi CPU giữ: mốc vào, tổng theo 3 loại
(hard / soft / vector), độ sâu lồng nhau, loại của mức ngoài cùng.

Đã gắn **13 cặp** tracepoint (26 chương trình BPF), đếm từ
`/sys/kernel/tracing/events/`, không đoán:

- `irq:irq_handler_entry` / `irq_handler_exit` → loại hard
- `irq:softirq_entry` / `softirq_exit` → loại soft
- 11 cặp trong `irq_vectors/`: `local_timer`, `reschedule`, `call_function`,
  `call_function_single`, `irq_work`, `x86_platform_ipi`, `error_apic`,
  `spurious_apic`, `thermal_apic`, `threshold_apic`, `deferred_error_apic`
  → loại vector

Xử lý irq đang chạy: khi `sched_switch` xảy ra ngay trong đường thoát irq
(`preempt_schedule_irq`), phần irq đã chạy chưa được cộng vào tổng. Hàm
`irq_total_at()` cộng thêm `now - start_ns` khi độ sâu > 0, để phần đó không bị
tính sang `cpu`.

### 3.4 Mục D — bảng flags

Đã ghi vào `.cursor/rules/hids.mdc`: bit0 FIRST, bit1 GAP_BEFORE, bit2 D_SLEEP,
bit3 MIGRATED, bit4 OVERFLOW, bit5 STEAL_FALLBACK, **bit6 CLAMPED**, bit7 = 0,
bit8–15 = số CPU lúc `sys_enter`.

### 3.5 Mục E — kiểm tra fail-closed và header mới

Thêm `internal/stealcheck/stealcheck.go` (174 dòng), gọi từ `hids-collect`
**trước khi** nạp chương trình thu thập:

1. **Đếm dòng `vmware-stealtime`** trong `dmesg`, nếu không đọc được thì
   `journalctl -k -b`. Số dòng phải bằng số CPU. Không bằng thì **từ chối chạy**,
   trừ khi có cờ `-allow-no-stealclock` (khi đó steal = 0 trên mọi bản ghi).
2. **So `vmw_steal_time` với `rq->prev_steal_time`** trên từng CPU trong 3 giây:
   lấy hai lần chụp cách nhau 3 giây, so mức tăng của hai đường. Ngưỡng
   `max(2 ms, 1%)`. Lệch quá ngưỡng thì **từ chối chạy** và in bảng từng CPU bị
   lệch, trừ khi có cờ `-steal-fallback` (khi đó dùng `rq->prev_steal_time` và
   mọi bản ghi mang cờ STEAL_FALLBACK).

Thêm 8 dòng header mới (xem nguyên văn ở mục 5.1): `stealclock`, `steal_mode`,
`tsc_khz`, `tsc_source`, `preempt`, `config_hz`, `kernel.sched_schedstats`,
`irq_tracepoints`. Thêm `PreemptMode()`, `ConfigHZ()`, `SchedSchedstats()` vào
`internal/hostinfo`.

### 3.6 Dọn dẹp mã

Cách nạp typed ksym bằng `BPF_PSEUDO_BTF_ID` (kiến trúc sư đã duyệt ở M1) được
tách ra `internal/percpuksym/percpuksym.go` (132 dòng) để cả `stealbpf` và
`syscallbpf` dùng chung. `syscallbpf` phải vá trên **toàn bộ collection** vì hàm
đọc ksym là `__always_inline` nên bị nhân vào nhiều chương trình.

### 3.7 Một lỗi đã tìm ra và sửa

Lần chạy thử đầu cho `irq_vec_delta_ns = 660450908689` (660 giây irq vector
trong một cửa sổ 6,7 ms) — vô lý.

Nguyên nhân: **thứ tự gắn tracepoint**. Ban đầu gắn theo thứ tự tên nên
`*_entry` được gắn trước `*_exit`. Một irq rơi đúng khe giữa hai lần gắn sẽ được
ghi `entry` (độ sâu 0 → 1, đặt mốc) nhưng không có `exit` để hạ độ sâu, nên CPU
đó kẹt ở độ sâu 1 với một mốc rất cũ; lần `exit` sau đó cộng cả khoảng thời gian
từ lúc gắn vào bộ cộng dồn. 24 CPU × ~30 giây ≈ 660 giây, khớp con số thấy được.

Sửa: gắn toàn bộ `*_exit` **trước** `*_entry`, và gỡ theo thứ tự **ngược** với
lúc gắn (nên trong mỗi cặp thì `*_entry` được gỡ trước `*_exit`). Hai đầu đều
đúng: lúc gắn chỉ có thể thấy `exit` không có `entry` (đã chặn, độ sâu 0 thì bỏ
qua), lúc gỡ irq đang chạy vẫn còn `exit` để đóng.

Chặn thêm cho hướng nguy hiểm còn lại: xem mục 7.

## 4. Lệnh build, lệnh chạy

### Build

    cd /root/hids
    make clean && make build

### Chạy thử 30 giây

Tạo tải thử (file này nằm trong `out/`, không commit, nội dung ở
`validation/m3ae-20261006/README.md`):

    cat > out/target.py <<'EOF'
    import time, os
    print(os.getpid(), flush=True)
    end = time.time() + 45
    while time.time() < end:
        t = time.monotonic() + 0.005
        while time.monotonic() < t:
            pass
        time.sleep(0.005)
        os.getppid()
    EOF

Chạy:

    rm -f out/target.pid
    (setsid python3 out/target.py > out/target.pid 2>&1 &)
    sleep 2
    ./bin/hids-collect -pid $(cat out/target.pid) -duration 30s -out out/m3-thu.bin

Kiểm kernel đã sạch:

    for k in prog link map; do printf "%s: %s\n" "$k" "$(bpftool $k list | grep -c hids_)"; done
    ls -A /sys/fs/bpf | wc -l

Soi cheo tự nhất quán (script dùng một lần, đã lưu ở
`validation/m3ae-20261006/soicheo.py`):

    python3 validation/m3ae-20261006/soicheo.py out/m3-thu.bin

### Hai cờ mới

    ./bin/hids-collect -allow-no-stealclock ...   # chay voi steal = 0
    ./bin/hids-collect -steal-fallback ...        # dung rq->prev_steal_time

## 5. Kết quả (nguyên văn output)

### 5.1 `make clean && make build` và cây git

```
go build -ldflags "-X hids/internal/buildinfo.Commit=b8e75d1" -o bin/hids-collect ./cmd/hids-collect
go build -ldflags "-X hids/internal/buildinfo.Commit=b8e75d1" -o bin/rec-stat ./cmd/rec-stat
--- git status ---
(trong nghia la cay sach)
```

### 5.2 Chạy thử 30 giây — nguyên văn stderr

File: `validation/m3ae-20261006/chay-thu-30s.txt`

```
stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
doi chieu vmw_steal_time voi rq->prev_steal_time trong 3s...
doi chieu xong: lech lon nhat 19933 ns tren 24 CPU, nguong max(2000000 ns, 1%)
ghi vao out/m3-thu.bin
loc pid: 444102 | loc cgroup: khong co | ring buffer: 64 MiB
READY
ban ghi doc duoc: 5958 | so lan dinh ghi: 5958 | mat: 0
irq cong don (ns): hard 1104809 | soft 134842591 | vector 761834462
irq bat thuong: 0 khoang, 0 ns | CPU con do sau khac 0: 0
thoi gian chay: 30.017 s | CPU collector: user 0.235 s, sys 0.218 s (getrusage RUSAGE_SELF)
kich thuoc file: 286792 byte
du lieu: out/m3-thu.bin | thong ke: out/m3-thu.bin.stats | theo doi: out/m3-thu.bin.periodic
```

### 5.3 Header mới và file theo dõi `.periodic` — nguyên văn

File: `validation/m3ae-20261006/chay-thu-30s.bin.periodic`

```
# hids-collect
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# nr_cpus_possible: 24
# git_commit: b8e75d1
# record_size: 48
# filter_pid: 444102
# filter_cgroup: khong co
# ringbuf_bytes: 67108864
# stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
# steal_mode: vmw_steal_time
# tsc_khz: 1995312
# tsc_source: dmesg | [    0.000000] vmware: TSC freq read from hypervisor : 1995.312 MHz
# preempt: voluntary (nguyen van: "none (voluntary) full")
# config_hz: 1000
# kernel.sched_schedstats: 0
# irq_tracepoints (13 cap): call_function call_function_single deferred_error_apic error_apic irq_handler irq_work local_timer reschedule softirq spurious_apic thermal_apic threshold_apic x86_platform_ipi
# start_mono_ns: 18272472840328
# start_wall: 2026-10-07T00:04:12.177952525+07:00
# duration: 30s
# moi dong cach nhau 10s
mono_ns,wall,dinh_ghi_delta,mat_delta,dinh_ghi_tong,mat_tong,irq_hard_delta_ns,irq_soft_delta_ns,irq_vec_delta_ns,irq_hard_tong_ns,irq_soft_tong_ns,irq_vec_tong_ns
18272473191189,2026-10-07T00:04:12.178302788+07:00,0,0,0,0,0,58726,1462373,0,58726,1462373
18282473403697,2026-10-07T00:04:22.178515268+07:00,1985,0,1985,0,372170,45022780,253067637,372170,45081506,254530010
18292482444894,2026-10-07T00:04:32.187556386+07:00,1988,0,3973,0,360289,42950845,249767598,732459,88032351,504297608
18302482530162,2026-10-07T00:04:42.187641678+07:00,1985,0,5958,0,372350,46787556,256196522,1104809,134819907,760494130
18302489409003,2026-10-07T00:04:42.194520561+07:00,0,0,5958,0,0,22684,1340332,1104809,134842591,761834462
```

### 5.4 Soi cheo tự nhất quán — nguyên văn

File: `validation/m3ae-20261006/tu-nhat-quan.txt`

```
so ban ghi: 5958
so khoang so sanh duoc: 5957
lech |dt - (cpu+steal+irq+rq+vol)| lon nhat: 500 ns
so khoang lech > 1000 ns: 0
tong dt   : 30006082242 ns
tong cong : 30006107229 ns
  cpu         14885017359 ns   49.61%
  steal            234600 ns    0.00%
  irq            63259958 ns    0.21%
  rq             18512312 ns    0.06%
  vol         15039083000 ns   50.12%
flags: {'FIRST': 1, 'MIGRATED': 5}
CPU xuat hien (bit8-15): [7, 8]
```

Lưu ý về chữ "tự nhất quán": đây **không phải** phép kiểm chứng. Nó chỉ so bản
ghi với chính nó (Δt có bằng tổng 5 thành phần không), **không** so với nguồn
tham chiếu nào của kernel. Mốc 500 ns là đúng bằng sai số làm tròn của
`vol_us = (vol_ns+500)/1000`.

### 5.5 Kernel sau khi thoát — nguyên văn

```
prog: 0
link: 0
map: 0
/sys/fs/bpf: 0 muc
```

### 5.6 Bộ đếm mất theo từng CPU

File: `validation/m3ae-20261006/chay-thu-30s.bin.stats`, 24 dòng, định dạng
`cpu,seq_cuoi,mat`. Ba dòng cuối:

```
21,0,0
22,0,0
23,0,0
```

## 6. File dữ liệu đã tạo

Đã commit:

- `/root/hids/validation/m3ae-20261006/README.md`
- `/root/hids/validation/m3ae-20261006/chay-thu-30s.txt`
- `/root/hids/validation/m3ae-20261006/chay-thu-30s.bin.periodic`
- `/root/hids/validation/m3ae-20261006/chay-thu-30s.bin.stats`
- `/root/hids/validation/m3ae-20261006/tu-nhat-quan.txt`
- `/root/hids/validation/m3ae-20261006/soicheo.py`

Không commit (theo quy tắc, file lớn):

- `/root/hids/out/m3-thu.bin` — 286.792 byte
- `/root/hids/out/target.py`, `/root/hids/out/target.pid`

## 7. Quyết định đã tự đưa ra và lý do

1. **Gắn `*_exit` trước `*_entry`, gỡ theo thứ tự ngược.** Đây là cách duy nhất
   đúng ở cả hai đầu; đã chứng minh bằng lỗi thật ở mục 3.7. Đảo ngược được.
2. **Chặn an toàn `HIDS_IRQ_MAX_NS = 1 giây`.** `is->depth += 1` không nguyên tử;
   một hardirq lồng vào giữa phép đọc-sửa-ghi có thể làm mất một lần tăng, khiến
   một `exit` sau này đóng số với mốc cũ và sinh ra khoảng rất dài. Khoảng dài
   hơn 1 giây bị **loại ra và đếm vào `odd_cnt`**, in ra lúc kết thúc
   (`irq bat thuong`). Đây **không phải hằng số vật lý** và không dùng để làm
   tròn số liệu: nó là bộ phát hiện hỏng dữ liệu, phải luôn bằng 0; khác 0 là có
   lỗi cần báo. Đã ghi rõ trong mã nguồn.
3. **In thêm `CPU con do sau khac 0` lúc kết thúc.** Để nhìn thấy hướng hỏng còn
   lại (độ sâu kẹt ở ≥ 1 thì irq bị đếm thiếu, im lặng). Hiện bằng 0.
4. **Tách `internal/percpuksym`.** Chỉ là dọn mã, không đổi hành vi; cách nạp
   ksym vẫn đúng như kiến trúc sư đã duyệt ở M1.
5. **Ngưỡng so hai đường steal là `max(2 ms, 1%)` trong 3 giây.** Cần một ngưỡng
   để fail-closed hoạt động được. Chọn con số rộng rãi để không báo động sai; số
   đo thật trong 3 lần chạy là 19.933 ns, 36.590 ns và 155.385 ns, cách ngưỡng
   hơn một bậc. Nếu kiến trúc sư muốn ngưỡng khác thì sửa hai hằng số
   `ToleranceNs` và `ToleranceRel` trong `internal/stealcheck/stealcheck.go`.
6. **Dùng một script python dùng một lần để soi cheo tự nhất quán** thay vì viết
   `bin/rec-check`, vì `rec-check` là mục G, ngoài phạm vi phiên. Script đã lưu
   vào `validation/` để tái lập được, nhưng **không phải công cụ của dự án**.
7. **Tải thử là một tiến trình python 5 ms đốt CPU + 5 ms ngủ.** Chỉ để có bản
   ghi mà kiểm tra, không phải tải kiểm chứng; tải kiểm chứng thật là `tools/wl.c`
   (mục F, chưa làm).

## 8. Cần kiến trúc sư quyết định

1. **Ngưỡng của phép so hai đường steal lúc khởi động.** Hiện tự chọn
   `max(2 ms, 1%)` trong 3 giây (mục 7.5). Số đo thật cách ngưỡng hơn một bậc.
   Xin xác nhận hoặc cho con số khác.

2. **Đua đọc-sửa-ghi trên độ sâu irq.** `is->depth += 1` và `is->depth -= 1`
   trên map per-CPU không nguyên tử, mà hardirq có thể lồng vào giữa (hardirq
   chen vào một softirq handler). Ba phương án:

   - **(a) Giữ như hiện tại.** Hướng nguy hiểm (cộng thừa) đã bị chặn và đếm
     (`odd_cnt`, hiện 0). Hướng còn lại (cộng thiếu vì độ sâu kẹt) chỉ nhìn thấy
     qua dòng `CPU con do sau khac 0` lúc kết thúc, hiện 0. Hệ quả: nếu đua xảy
     ra thật thì có thể mất một phần irq mà không biết mất bao nhiêu.
   - **(b) Dùng `__sync_fetch_and_add` cho độ sâu.** Nguyên tử nên không mất lần
     tăng/giảm, nhưng cặp (độ sâu, mốc) vẫn không nguyên tử với nhau, nên chỉ
     giảm xác suất, không khử hẳn. Thêm một chút chi phí mỗi irq.
   - **(c) Không dùng độ sâu, mà giữ một mảng mốc theo từng loại
     (hard/soft/vector).** Ba loại không bao giờ lồng vào chính nó trên cùng CPU,
     nên bỏ được biến độ sâu dùng chung. Đúng hơn về nguyên tắc nhưng phải viết
     lại mục C và phải đo lại.

   Tôi **không tự quyết** vì việc này ảnh hưởng trực tiếp tới phép đo thành phần
   `irq`. Chờ kiến trúc sư chọn.

3. **Có cần dòng header ghi `CONFIG_IRQ_TIME_ACCOUNTING` và
   `CONFIG_PARAVIRT_TIME_ACCOUNTING` không?** Trên máy này cả hai **không** được
   bật (đọc từ `/boot/config-6.8.0-142-generic`), nên `sum_exec_runtime` của
   kernel bao gồm cả steal và irq — điều này quan trọng khi mục G/H đối chiếu với
   `/proc/<tid>/schedstat`. Hiện chưa ghi vào header.

4. **Hai vướng mắc cũ chưa có quyết định**, nhắc lại: biên cửa sổ của G7c (mục 8
   của R003, hiện chấp nhận chênh lệch theo lựa chọn (c)), và ngưỡng cảnh báo khi
   tỉ lệ bản ghi mất vượt bao nhiêu thì coi là bất thường.

## 9. Việc người dùng cần làm tay

Không có. Phiên này không cần thao tác vCenter, không cần đổi cấu hình máy.

Ghi chú: `kernel.sched_schedstats` hiện là `0`. Mục H của M3 (`scripts/g3.sh`)
sẽ cần bật nó lên `1` rồi đặt lại như cũ, vì `/proc/<tid>/sched` chỉ có các
trường `wait_sum`, `sum_sleep_runtime`, `sum_block_runtime`, `iowait_sum` khi nó
bằng `1`. Việc đó để phiên sau, và `g3.sh` sẽ tự lưu rồi tự đặt lại giá trị.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất

### Lỗi và hạn chế còn tồn tại

1. **Chưa có phép kiểm chứng nào.** Mọi số trong báo cáo này chỉ là số do chính
   collector sinh ra, chưa đặt cạnh nguồn tham chiếu của kernel. Chưa thể nói
   `cpu`, `steal`, `irq`, `rq`, `vol` đo **đúng**; chỉ có thể nói chúng **không
   tự mâu thuẫn** và tổng khớp Δt trong sai số làm tròn 500 ns.
2. **Đua trên độ sâu irq** — mục 8.2.
3. **Mục F, G, H, I, J của M3 chưa làm**, chưa có file nào.
4. **Chưa đo trên tải thật.** Tải thử chỉ có hai trạng thái CPU và ngủ; chưa có
   bản ghi nào mang cờ OVERFLOW, GAP_BEFORE, D_SLEEP hay STEAL_FALLBACK trong
   lần chạy này (chỉ thấy FIRST và MIGRATED). Nhánh mã xử lý các cờ đó chưa được
   chạy qua với dữ liệu thật ở M3.
5. **Chưa đo chi phí của collector khi tải cao.** Lần này collector dùng
   0,235 s user + 0,218 s sys cho 30 giây với 5.958 bản ghi — tải rất nhẹ. Số
   này không nói gì về chi phí của 26 chương trình irq khi có hàng triệu irq.

### Việc tiếp theo đề xuất

1. Kiến trúc sư duyệt mục 8, trước hết là 8.2 (đua trên độ sâu irq), vì nó có
   thể làm phải viết lại mục C.
2. Làm mục F và G của M3 (`tools/wl.c`, `bin/rec-check`).
3. Làm mục H (`scripts/g3.sh`: S1–S5, G-real, G-irq), chạy, rồi mới gắn tag `m3`.

### Tag git

**Không gắn tag `m3`** (M3 chưa xong trọn vẹn). Gắn tag **`m3-ae`** cho mốc A–E.
