# Báo cáo R005 — M3 PHẦN 2 (mục F–J)

1. **Số báo cáo:** R005 | **Ngày giờ:** 2026-10-07 00:42 (giờ máy) | **Mốc:** M3 PHẦN 2 | **Git commit:** c3d371b

2. **Mục tiêu**  
Hoàn thành M3 mục F–J: `tools/wl.c`, `bin/rec-check`, `scripts/g3.sh`, tự chạy G3, lưu `validation/g3-20261007/`, tag `m3`.

3. **Đã làm gì**  
- `tools/wl.c`, `bin/rec-check`, `scripts/g3.sh`, `scripts/g3_window.py`, `scripts/g3-driver.sh`.  
- Tự chạy S1–S5, G-real, G-irq, G7d.  
- Sửa chờ `wl` bằng `wchan=pipe_read`; giảm `clock_gettime` trong vòng đốt CPU của `wl`.

4. **Lệnh build, lệnh chạy**  
```
make build
sudo bash scripts/g3.sh
```

5. **Kết quả** (nguyên văn từ `validation/g3-20261007/*-ketqua.txt`):

### S1

```
=== S1: wl cpu 10000 300 (CPU 20) ===
wl pid=504102 tid=504102
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1704603 4546 3
--- moc A /proc/504102/sched ---
sum_sleep_runtime                            :          3746.992108
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.004546
iowait_sum                                   :             0.000000
--- moc B schedstat ---
3011693042 47636 10
--- moc B /proc/504102/sched ---
sum_sleep_runtime                            :          3774.178079
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.047636
iowait_sum                                   :             0.000000
cua so ts_enter: (20321720288993, 20324757513636]
--- rec-check ---
so ban ghi trong cua so: 53438
tid: 504102
cua so ts_enter: (20321720288993, 20324757513636]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 2996382992
steal 0
irq 13621362
rq 34265
vol 27186000
cpu+steal+irq 3010004354
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 53437
p50 0
p99 0
p99.9 0
max 0
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 53437
p50 0
p99 0
p99.9 0
max 0
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        3010004354      3009988439      Delta schedstat field1 sum_exec_runtime
rq                   34265           43090           Delta schedstat field2 run_delay
rq (wait_sum)        34265           43090           Delta wait_sum /proc/sched
vol                  27186000        27186000        Delta sum_sleep_runtime
vol (D_SLEEP)        0               0               Delta sum_block_runtime
--- log collector (cuoi) ---
  hids_irq_call_function_single_exit       0
  hids_irq_deferred_error_apic_entry       0
  hids_irq_deferred_error_apic_exit        0
  hids_irq_error_apic_entry                0
  hids_irq_error_apic_exit                 0
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 3.094 s | CPU collector: user 0.274 s, sys 0.288 s (getrusage RUSAGE_SELF)
kich thuoc file: 2566078 byte
du lieu: out/g3-S1-003817.bin | thong ke: out/g3-S1-003817.bin.stats | theo doi: out/g3-S1-003817.bin.periodic

```
### S2

```
=== S2: wl sleep 5000 500 (CPU 20) ===
wl pid=505664 tid=505664
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1592177 4559 3
--- moc A /proc/505664/sched ---
sum_sleep_runtime                            :          3746.268544
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.004559
iowait_sum                                   :             0.000000
--- moc B schedstat ---
10501333 354895 504
--- moc B /proc/505664/sched ---
sum_sleep_runtime                            :          6304.628056
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.354895
iowait_sum                                   :             0.000000
cua so ts_enter: (20328813370812, 20331380997125]
--- rec-check ---
so ban ghi trong cua so: 1001
tid: 505664
cua so ts_enter: (20328813370812, 20331380997125]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 5820449
steal 0
irq 8731
rq 3202679
vol 2558588000
cpu+steal+irq 5829180
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 1000
p50 0
p99 486
p99.9 499
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 1000
p50 0
p99 486
p99.9 499
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        5829180         8909156         Delta schedstat field1 sum_exec_runtime
rq                   3202679         350336          Delta schedstat field2 run_delay
rq (wait_sum)        3202679         350336          Delta wait_sum /proc/sched
vol                  2558588000      2558360000      Delta sum_sleep_runtime
vol (D_SLEEP)        0               0               Delta sum_block_runtime
--- log collector (cuoi) ---
  hids_irq_call_function_single_exit       0
  hids_irq_deferred_error_apic_entry       0
  hids_irq_deferred_error_apic_exit        0
  hids_irq_error_apic_entry                0
  hids_irq_error_apic_exit                 0
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 2.626 s | CPU collector: user 0.159 s, sys 0.118 s (getrusage RUSAGE_SELF)
kich thuoc file: 49102 byte
du lieu: out/g3-S2-003824.bin | thong ke: out/g3-S2-003824.bin.stats | theo doi: out/g3-S2-003824.bin.periodic

```
### S3

```
=== S3: wl mixed 2000 3000 500 (CPU 20) ===
wl pid=507083 tid=507083
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1634300 155305 3
--- moc A /proc/507083/sched ---
sum_sleep_runtime                            :          3739.629450
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.155305
iowait_sum                                   :             0.000000
--- moc B schedstat ---
1027003946 458173 506
--- moc B /proc/507083/sched ---
sum_sleep_runtime                            :          5296.560024
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.458173
iowait_sum                                   :             0.000000
cua so ts_enter: (20335293859442, 20337876468758]
--- rec-check ---
so ban ghi trong cua so: 19182
tid: 507083
cua so ts_enter: (20335293859442, 20337876468758]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 1017326620
steal 0
irq 4967963
rq 3347881
vol 1556968000
cpu+steal+irq 1022294583
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 19181
p50 0
p99 305
p99.9 485
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 19181
p50 0
p99 305
p99.9 485
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        1022294583      1025369646      Delta schedstat field1 sum_exec_runtime
rq                   3347881         302868          Delta schedstat field2 run_delay
rq (wait_sum)        3347881         302868          Delta wait_sum /proc/sched
vol                  1556968000      1556930000      Delta sum_sleep_runtime
vol (D_SLEEP)        0               0               Delta sum_block_runtime
--- log collector (cuoi) ---
  hids_irq_call_function_single_exit       0
  hids_irq_deferred_error_apic_entry       0
  hids_irq_deferred_error_apic_exit        0
  hids_irq_error_apic_entry                0
  hids_irq_error_apic_exit                 0
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 2.634 s | CPU collector: user 0.219 s, sys 0.183 s (getrusage RUSAGE_SELF)
kich thuoc file: 921789 byte
du lieu: out/g3-S3-003831.bin | thong ke: out/g3-S3-003831.bin.stats | theo doi: out/g3-S3-003831.bin.periodic

```
### S4

```
=== S4: wl cpu 10000 300 (CPU 20) ===
wl pid=508587 tid=508587
stress-ng pid=508591
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1718845 2621288 3
--- moc A /proc/508587/sched ---
sum_sleep_runtime                            :          3774.210805
sum_block_runtime                            :             0.000000
wait_sum                                     :             2.621288
iowait_sum                                   :             0.000000
--- moc B schedstat ---
3010227512 3008599725 952
--- moc B /proc/508587/sched ---
sum_sleep_runtime                            :          3812.310587
sum_block_runtime                            :             0.000000
wait_sum                                     :          3008.599725
iowait_sum                                   :             0.000000
cua so ts_enter: (20341873061570, 20347925663658]
--- rec-check ---
so ban ghi trong cua so: 53202
tid: 508587
cua so ts_enter: (20341873061570, 20347925663658]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 2999151308
steal 0
irq 9449403
rq 3005899252
vol 38102000
cpu+steal+irq 3008600711
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 53201
p50 0
p99 0
p99.9 0
max 0
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 53201
p50 0
p99 0
p99.9 0
max 0
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        3008600711      3008508667      Delta schedstat field1 sum_exec_runtime
rq                   3005899252      3005978437      Delta schedstat field2 run_delay
rq (wait_sum)        3005899252      3005980000      Delta wait_sum /proc/sched
vol                  38102000        38099800        Delta sum_sleep_runtime
vol (D_SLEEP)        0               0               Delta sum_block_runtime
--- log collector (cuoi) ---
  hids_irq_call_function_single_exit       0
  hids_irq_deferred_error_apic_entry       0
  hids_irq_deferred_error_apic_exit        0
  hids_irq_error_apic_entry                0
  hids_irq_error_apic_exit                 0
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 6.107 s | CPU collector: user 0.327 s, sys 0.345 s (getrusage RUSAGE_SELF)
kich thuoc file: 2554750 byte
du lieu: out/g3-S4-003837.bin | thong ke: out/g3-S4-003837.bin.stats | theo doi: out/g3-S4-003837.bin.periodic

```
### S5

```
=== S5: wl io 300 (CPU 20) ===
wl pid=510934 tid=510934
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1520729 0 2
--- moc A /proc/510934/sched ---
sum_sleep_runtime                            :          3742.692384
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.000000
iowait_sum                                   :             0.000000
--- moc B schedstat ---
27144884 2156306 603
--- moc B /proc/510934/sched ---
sum_sleep_runtime                            :          4066.858002
sum_block_runtime                            :           295.922999
wait_sum                                     :             2.156306
iowait_sum                                   :           115.555148
cua so ts_enter: (20351993920108, 20352345862504]
--- rec-check ---
so ban ghi trong cua so: 1503
tid: 510934
cua so ts_enter: (20351993920108, 20352345862504]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         300
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 24073169
steal 0
irq 141867
rq 3609394
vol 324131000
cpu+steal+irq 24215036
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 1502
p50 0
p99 481
p99.9 497
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 1502
p50 0
p99 481
p99.9 497
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        24215036        25624155        Delta schedstat field1 sum_exec_runtime
rq                   3609394         2156306         Delta schedstat field2 run_delay
rq (wait_sum)        3609394         2156310         Delta wait_sum /proc/sched
vol                  324131000       324166000       Delta sum_sleep_runtime
vol (D_SLEEP)        295887000       295923000       Delta sum_block_runtime
--- log collector (cuoi) ---
  hids_irq_call_function_single_exit       0
  hids_irq_deferred_error_apic_entry       0
  hids_irq_deferred_error_apic_exit        0
  hids_irq_error_apic_entry                0
  hids_irq_error_apic_exit                 0
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 0.410 s | CPU collector: user 0.141 s, sys 0.124 s (getrusage RUSAGE_SELF)
kich thuoc file: 73198 byte
du lieu: out/g3-S5-003847.bin | thong ke: out/g3-S5-003847.bin.stats | theo doi: out/g3-S5-003847.bin.periodic

```
### G-real

```
=== G-real: cgroup qdrant 120s ===
cgroup: /sys/fs/cgroup/system.slice/docker-319c38ff33aa4827288f68ca1236600174cf278175fd7d5d68657d48e2a6366f.scope
so tien trinh trong cgroup luc bat dau: 2

```
### G-irq

```
=== G-irq: 30 giay may ranh ===
--- hardirqs-bpfcc (nguyen van) ---
Tracing hard irq event time... Hit Ctrl-C to end.

HARDIRQ                    TOTAL_usecs
vmw_vmci                            23
ens33-rxtx-2                        40
ens33-rxtx-1                        52
ens33-rxtx-0                        58
ens33-rxtx-4                        92
vmw_pvscsi                         156
ahci[0000:02:02.0]                 167
ens33-rxtx-3                       275
ens33-rxtx-7                       347
ens33-rxtx-6                      1232
--- softirqs-bpfcc (nguyen van) ---
Tracing soft irq event time... Hit Ctrl-C to end.

SOFTIRQ          TOTAL_usecs
tasklet                  213
block                    679
timer                  10195
rcu                    26689
net_rx                 27620
sched                  47775
--- log collector (cuoi) ---
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 30.056 s | CPU collector: user 0.147 s, sys 0.109 s (getrusage RUSAGE_SELF)
kich thuoc file: 947 byte
du lieu: out/g3-girq-003526.bin | thong ke: out/g3-girq-003526.bin.stats | theo doi: out/g3-girq-003526.bin.periodic
--- bang doi chieu irq ---
loai                 collector       tham_chieu      nguon
hard                 2665249         TOTAL_usecs     hardirqs-bpfcc TOTAL
soft_raw             (ns):           TOTAL_usecs     softirqs-bpfcc TOTAL
soft_excl            118372012       —             collector (bcc khong tach)
vector               595117318       —             collector only

```
### G7d

```
=== G7d (binary hien tai) ===
=== G7d: loc theo cgroup CHA, tien trinh nam trong cgroup CON, N=1000000 ===
cgroup cha=/sys/fs/cgroup/hids-test inode=21784
cgroup con=/sys/fs/cgroup/hids-test/con inode=21863
sysinj pid=499712
$ cat /proc/499712/cgroup
0::/hids-test/con
collector da gan tracepoint (READY), loc theo cgroup CHA
perf da gan
$ rmdir /sys/fs/cgroup/hids-test/con /sys/fs/cgroup/hids-test
da xoa cgroup tam

--- perf stat (nguyen van) ---

 Performance counter stats for process id '499712':

         1,000,001      raw_syscalls:sys_enter                                                

       3.003154496 seconds time elapsed

--- log collector (nguyen van) ---
CANH BAO: binary build tu cay lam viec con thay doi chua commit (git_commit=e93f01b-dirty).
CANH BAO: du lieu ghi ra khong tai lap duoc tu git. Commit truoc khi do that.
stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
doi chieu vmw_steal_time voi rq->prev_steal_time trong 3s...
doi chieu xong: lech lon nhat 32133 ns tren 24 CPU, nguong max(2000000 ns, 1%)
ghi vao out/g7d-20261007-003600.bin
loc pid: khong co | loc cgroup: /sys/fs/cgroup/hids-test (id=21784) | ring buffer: 64 MiB
READY
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
irq cong don (ns): hard 216463 | soft 22151598 | vector 453853130 | tong 476221191
soft_raw cong don (ns): 22220684 (ke ca hard/vector long ben trong, de so voi softirqs-bpfcc)
irq bat thuong: 0 khoang, 0 ns | loai con dang hoat dong: 0
recursion_misses (bpf_prog_info), tong 0 tren 30 chuong trinh:
  hids_irq_call_function_entry             0
  hids_irq_call_function_exit              0
  hids_irq_call_function_single_entry      0
  hids_irq_call_function_single_exit       0
  hids_irq_deferred_error_apic_entry       0
  hids_irq_deferred_error_apic_exit        0
  hids_irq_error_apic_entry                0
  hids_irq_error_apic_exit                 0
  hids_irq_irq_handler_entry               0
  hids_irq_irq_handler_exit                0
  hids_irq_irq_work_entry                  0
  hids_irq_irq_work_exit                   0
  hids_irq_local_timer_entry               0
  hids_irq_local_timer_exit                0
  hids_irq_reschedule_entry                0
  hids_irq_reschedule_exit                 0
  hids_irq_softirq_entry                   0
  hids_irq_softirq_exit                    0
  hids_irq_spurious_apic_entry             0
  hids_irq_spurious_apic_exit              0
  hids_irq_thermal_apic_entry              0
  hids_irq_thermal_apic_exit               0
  hids_irq_threshold_apic_entry            0
  hids_irq_threshold_apic_exit             0
  hids_irq_x86_platform_ipi_entry          0
  hids_irq_x86_platform_ipi_exit           0
  hids_sched_switch                        0
  hids_sched_wakeup                        0
  hids_sched_wakeup_new                    0
  hids_sys_enter                           0
thoi gian chay: 4.978 s | CPU collector: user 0.347 s, sys 0.388 s (getrusage RUSAGE_SELF)
kich thuoc file: 48001034 byte
du lieu: out/g7d-20261007-003600.bin | thong ke: out/g7d-20261007-003600.bin.stats | theo doi: out/g7d-20261007-003600.bin.periodic

--- bang ket qua ---
N theo thiet ke:                              1000000
perf raw_syscalls:sys_enter (-p 499712):      1000001
so ban ghi collector:                         1000001
so ban ghi nr=110:                            1000000
hieu (perf - ban ghi):                        0

--- thoi gian va dung luong ---
kich thuoc out/g7d-20261007-003600.bin: 48001034 byte

--- rec-stat day du (nguyen van) ---
file: out/g7d-20261007-003600.bin
# hids-collect
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# nr_cpus_possible: 24
# git_commit: e93f01b-dirty
# record_size: 48
# filter_pid: khong co
# filter_cgroup: /sys/fs/cgroup/hids-test (id=21784)
# ringbuf_bytes: 67108864
# stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
# steal_mode: vmw_steal_time
# tsc_khz: 1995312
# tsc_source: dmesg | [    0.000000] vmware: TSC freq read from hypervisor : 1995.312 MHz
# preempt: voluntary (nguyen van: "none (voluntary) full")
# config_hz: 1000
# kernel.sched_schedstats: 1
# CONFIG_IRQ_TIME_ACCOUNTING: is not set
# CONFIG_PARAVIRT_TIME_ACCOUNTING: is not set
# CONFIG_SCHEDSTATS: y
# CONFIG_SCHED_INFO: y
# irq_tracepoints (13 cap): call_function call_function_single deferred_error_apic error_apic irq_handler irq_work local_timer reschedule softirq spurious_apic thermal_apic threshold_apic x86_platform_ipi
# start_mono_ns: 20185031622548
# start_wall: 2026-10-07T00:36:04.73673425+07:00
# duration: khong gioi han

tong so ban ghi trong file : 1000001
so ban ghi sau khi loc     : 1000001
bo loc                     : khong co
ts_enter nho nhat / lon nhat: 20187064722774 / 20187999969429 (ns, CLOCK_MONOTONIC)
ban ghi co co FIRST        : 1
ban ghi co co GAP_BEFORE   : 0
ban ghi co syscall_nr=110  : 1000000

so ban ghi theo tgid (1 tien trinh)
    tgid  ban_ghi   nr=110  FIRST  GAP_BEFORE      nguon_tgid
  499712  1000001  1000000      1           0  ? (suy tu tid)
    TONG  1000001  1000000      1           0                

so ban ghi theo tid (1 thread, in 1 dong dau)
     tid  tgid  ban_ghi   nr=110
  499712     ?  1000001  1000000

top 2 syscall_nr (tong cong 2 gia tri khac nhau)
  syscall_nr  ban_ghi
         110  1000000
         231        1

theo tung CPU (cpu lay tu bit8..15 cua flags; seq_cuoi va mat lay tu .stats)
   cpu  ban_ghi  seq_min  seq_max  lo_hong  seq_thieu  seq_cuoi  mat
    17  1000001        1  1000001        0          0   1000001    0
  TONG  1000001                          0          0   1000001    0

y nghia cac cot:
  ban_ghi   so ban ghi cua CPU do co trong file (tinh tren toan bo file,
            khong phu thuoc -tgid/-nr/-from-mono/-to-mono)
  seq_min   seq nho nhat doc duoc; bang 1 neu khong mat ban ghi nao o dau
  lo_hong   so doan seq lien tuc bi thieu (ke ca doan dau tu 1 den seq_min
            va doan cuoi tu seq_max den seq_cuoi)
  seq_thieu tong so seq bi thieu; so nay doi chieu truc tiep voi cot mat
  seq_cuoi  so lan dinh ghi tren CPU do, doc tu kernel luc collector dung
  mat       bo dem bpf_ringbuf_reserve that bai, doc tu kernel

doi chieu seq (toan cuc)
  so lan dinh ghi (tong seq_cuoi cua moi CPU): 1000001
  so ban ghi collector doc duoc             : 1000001
  so ban ghi dem duoc trong file            : 1000001
  tong bo dem mat (ring buffer day)         : 0
  tong so seq bi thieu theo CPU             : 0
  dinh ghi - ban ghi trong file             : 0

--- file theo doi dinh ky ---
# hids-collect
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# nr_cpus_possible: 24
# git_commit: e93f01b-dirty
# record_size: 48
# filter_pid: khong co
# filter_cgroup: /sys/fs/cgroup/hids-test (id=21784)
# ringbuf_bytes: 67108864
# stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
# steal_mode: vmw_steal_time
# tsc_khz: 1995312
# tsc_source: dmesg | [    0.000000] vmware: TSC freq read from hypervisor : 1995.312 MHz
# preempt: voluntary (nguyen van: "none (voluntary) full")
# config_hz: 1000
# kernel.sched_schedstats: 1
# CONFIG_IRQ_TIME_ACCOUNTING: is not set
# CONFIG_PARAVIRT_TIME_ACCOUNTING: is not set
# CONFIG_SCHEDSTATS: y
# CONFIG_SCHED_INFO: y
# irq_tracepoints (13 cap): call_function call_function_single deferred_error_apic error_apic irq_handler irq_work local_timer reschedule softirq spurious_apic thermal_apic threshold_apic x86_platform_ipi
# start_mono_ns: 20185031622548
# start_wall: 2026-10-07T00:36:04.73673425+07:00
# duration: khong gioi han
# moi dong cach nhau 10s
mono_ns,wall,dinh_ghi_delta,mat_delta,dinh_ghi_tong,mat_tong,irq_hard_delta_ns,irq_soft_delta_ns,irq_vec_delta_ns,soft_raw_delta_ns,irq_hard_tong_ns,irq_soft_tong_ns,irq_vec_tong_ns,soft_raw_tong_ns
20185034775949,2026-10-07T00:36:04.739887592+07:00,0,0,0,0,0,67053,2405544,67306,0,67053,2405544,67306
20190009488714,2026-10-07T00:36:09.714600458+07:00,1000001,0,1000001,0,216463,22084545,451447586,22153378,216463,22151598,453853130,22220684

--- kiem tra kernel sau khi collector thoat ---
$ bpftool prog list | grep -ci hids
0
$ bpftool link list | grep -ci hids
0
$ bpftool map list | grep -ciE 'hids_|ringbuf'
0
$ ls -A /sys/fs/bpf | wc -l
0

du lieu: out/g7d-20261007-003600.bin | thong ke: out/g7d-20261007-003600.bin.stats

```


**recursion_misses:** tong 0 tren 30 chuong trinh BPF (moi chuong trinh 0, xem cuoi log trong tung *-ketqua.txt).

**Chi phí CPU collector (getrusage):**  
- S1: thoi gian chay: 3.094 s | CPU collector: user 0.274 s, sys 0.288 s (getrusage RUSAGE_SELF)
- S2: thoi gian chay: 2.626 s | CPU collector: user 0.159 s, sys 0.118 s (getrusage RUSAGE_SELF)
- S3: thoi gian chay: 2.634 s | CPU collector: user 0.219 s, sys 0.183 s (getrusage RUSAGE_SELF)
- S4: thoi gian chay: 6.107 s | CPU collector: user 0.327 s, sys 0.345 s (getrusage RUSAGE_SELF)
- S5: thoi gian chay: 0.410 s | CPU collector: user 0.141 s, sys 0.124 s (getrusage RUSAGE_SELF)
- G-irq: thoi gian chay: 30.056 s | CPU collector: user 0.147 s, sys 0.109 s (getrusage RUSAGE_SELF)
- G7d: thoi gian chay: 4.978 s | CPU collector: user 0.347 s, sys 0.388 s (getrusage RUSAGE_SELF)

6. **File dữ liệu:** `/root/hids/validation/g3-20261007/`, log `/root/hids/out/jobs/g3-driver.log`

7. **Quyết định tự đưa ra**  
Chờ `pipe_read`; biên cửa sổ từ hai syscall `read` sau `getuid`; G-real chỉ PID trong cgroup.procs hai mốc.

8. **Cần kiến trúc sư**  
G-real tập thread và tổng sched; G-irq đơn vị đối chiếu (bcc usec vs collector ns); wl vẫn sinh nr=228 trong S1/S3/S4 ở lần chạy này.

9. **Việc người dùng:** không.

10. **Tiếp theo:** chạy lại S1–S5 với wl spin 262144; G-irq với parse bcc đã sửa. DỪNG, không M4.
