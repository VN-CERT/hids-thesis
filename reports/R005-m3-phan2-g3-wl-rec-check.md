# Báo cáo R005 — M3 PHẦN 2 (mục F–J)

1. **Số báo cáo:** R005 | **Ngày giờ:** 2026-10-07 00:40 (giờ máy) | **Mốc:** M3 PHẦN 2 | **Git commit:** c3d371b

2. **Mục tiêu**  
Hoàn thành M3 mục F–J: , , === S1: wl cpu 10000 300 (CPU 20) ===
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
luu: validation/g3-20261007/S1-ketqua.txt
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
luu: validation/g3-20261007/S2-ketqua.txt
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
luu: validation/g3-20261007/S3-ketqua.txt
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
luu: validation/g3-20261007/S4-ketqua.txt
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
luu: validation/g3-20261007/S5-ketqua.txt
=== G-real: cgroup qdrant 120s ===
cgroup: /sys/fs/cgroup/system.slice/docker-319c38ff33aa4827288f68ca1236600174cf278175fd7d5d68657d48e2a6366f.scope
so tien trinh trong cgroup luc bat dau: 2
--- log collector (cuoi) ---
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
thoi gian chay: 120.012 s | CPU collector: user 0.340 s, sys 0.373 s (getrusage RUSAGE_SELF)
kich thuoc file: 1353985 byte
du lieu: out/g3-greal-003852.bin | thong ke: out/g3-greal-003852.bin.stats | theo doi: out/g3-greal-003852.bin.periodic
--- bang doi chieu (tong thread song suot cua so) ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        277497092       0               Tong Delta schedstat field1
rq                   78916749        0               Tong Delta schedstat field2
vol                  2769340628000   ?               sum_sleep_runtime: chua tong hop
=== G-irq: 30 giay may ranh ===
--- hardirqs-bpfcc (nguyen van) ---
Tracing hard irq event time... Hit Ctrl-C to end.

HARDIRQ                    TOTAL_usecs
vmw_vmci                            28
ens33-rxtx-2                        39
ens33-rxtx-0                        49
ens33-rxtx-1                        58
ens33-rxtx-4                        90
ahci[0000:02:02.0]                 162
vmw_pvscsi                         204
ens33-rxtx-3                       258
ens33-rxtx-7                       471
ens33-rxtx-6                      1156
--- softirqs-bpfcc (nguyen van) ---
Tracing soft irq event time... Hit Ctrl-C to end.

SOFTIRQ          TOTAL_usecs
tasklet                  131
block                    856
timer                  10705
net_rx                 28309
rcu                    29386
sched                  57844
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
thoi gian chay: 30.075 s | CPU collector: user 0.138 s, sys 0.121 s (getrusage RUSAGE_SELF)
kich thuoc file: 947 byte
du lieu: out/g3-girq-004055.bin | thong ke: out/g3-girq-004055.bin.stats | theo doi: out/g3-girq-004055.bin.periodic
--- bang doi chieu irq ---
loai                 collector       tham_chieu      nguon
hard (ns)            2766464         2515 (us)       hardirqs-bpfcc tong cot usecs
soft_raw (ns)        130688884       127231 (us)     softirqs-bpfcc tong cot usecs
soft_excl            130330600       —             collector (bcc khong tach)
vector               632059389       —             collector only
=== G7d (binary hien tai) ===
=== G7d: loc theo cgroup CHA, tien trinh nam trong cgroup CON, N=1000000 ===
cgroup cha=/sys/fs/cgroup/hids-test inode=22212
cgroup con=/sys/fs/cgroup/hids-test/con inode=22291
sysinj pid=516444
$ cat /proc/516444/cgroup
0::/hids-test/con
collector da gan tracepoint (READY), loc theo cgroup CHA
perf da gan
$ rmdir /sys/fs/cgroup/hids-test/con /sys/fs/cgroup/hids-test
da xoa cgroup tam

--- perf stat (nguyen van) ---

 Performance counter stats for process id '516444':

         1,000,001      raw_syscalls:sys_enter                                                

       3.003173446 seconds time elapsed

--- log collector (nguyen van) ---
CANH BAO: binary build tu cay lam viec con thay doi chua commit (git_commit=c3d371b-dirty).
CANH BAO: du lieu ghi ra khong tai lap duoc tu git. Commit truoc khi do that.
stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
doi chieu vmw_steal_time voi rq->prev_steal_time trong 3s...
doi chieu xong: lech lon nhat 14516 ns tren 24 CPU, nguong max(2000000 ns, 1%)
ghi vao out/g7d-20261007-004130.bin
loc pid: khong co | loc cgroup: /sys/fs/cgroup/hids-test (id=22212) | ring buffer: 64 MiB
READY
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
irq cong don (ns): hard 197015 | soft 24831320 | vector 470874635 | tong 495902970
soft_raw cong don (ns): 24883218 (ke ca hard/vector long ben trong, de so voi softirqs-bpfcc)
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
thoi gian chay: 4.958 s | CPU collector: user 0.320 s, sys 0.400 s (getrusage RUSAGE_SELF)
kich thuoc file: 48001034 byte
du lieu: out/g7d-20261007-004130.bin | thong ke: out/g7d-20261007-004130.bin.stats | theo doi: out/g7d-20261007-004130.bin.periodic

--- bang ket qua ---
N theo thiet ke:                              1000000
perf raw_syscalls:sys_enter (-p 516444):      1000001
so ban ghi collector:                         1000001
so ban ghi nr=110:                            1000000
hieu (perf - ban ghi):                        0

--- thoi gian va dung luong ---
kich thuoc out/g7d-20261007-004130.bin: 48001034 byte

--- rec-stat day du (nguyen van) ---
file: out/g7d-20261007-004130.bin
# hids-collect
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# nr_cpus_possible: 24
# git_commit: c3d371b-dirty
# record_size: 48
# filter_pid: khong co
# filter_cgroup: /sys/fs/cgroup/hids-test (id=22212)
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
# start_mono_ns: 20514393747001
# start_wall: 2026-10-07T00:41:34.09885906+07:00
# duration: khong gioi han

tong so ban ghi trong file : 1000001
so ban ghi sau khi loc     : 1000001
bo loc                     : khong co
ts_enter nho nhat / lon nhat: 20516429806912 / 20517341457191 (ns, CLOCK_MONOTONIC)
ban ghi co co FIRST        : 1
ban ghi co co GAP_BEFORE   : 0
ban ghi co syscall_nr=110  : 1000000

so ban ghi theo tgid (1 tien trinh)
    tgid  ban_ghi   nr=110  FIRST  GAP_BEFORE      nguon_tgid
  516444  1000001  1000000      1           0  ? (suy tu tid)
    TONG  1000001  1000000      1           0                

so ban ghi theo tid (1 thread, in 1 dong dau)
     tid  tgid  ban_ghi   nr=110
  516444     ?  1000001  1000000

top 2 syscall_nr (tong cong 2 gia tri khac nhau)
  syscall_nr  ban_ghi
         110  1000000
         231        1

theo tung CPU (cpu lay tu bit8..15 cua flags; seq_cuoi va mat lay tu .stats)
   cpu  ban_ghi  seq_min  seq_max  lo_hong  seq_thieu  seq_cuoi  mat
     8  1000001        1  1000001        0          0   1000001    0
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
# git_commit: c3d371b-dirty
# record_size: 48
# filter_pid: khong co
# filter_cgroup: /sys/fs/cgroup/hids-test (id=22212)
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
# start_mono_ns: 20514393747001
# start_wall: 2026-10-07T00:41:34.09885906+07:00
# duration: khong gioi han
# moi dong cach nhau 10s
mono_ns,wall,dinh_ghi_delta,mat_delta,dinh_ghi_tong,mat_tong,irq_hard_delta_ns,irq_soft_delta_ns,irq_vec_delta_ns,soft_raw_delta_ns,irq_hard_tong_ns,irq_soft_tong_ns,irq_vec_tong_ns,soft_raw_tong_ns
20514396347890,2026-10-07T00:41:34.101459479+07:00,0,0,0,0,997,127166,1776072,127668,997,127166,1776072,127668
20519351640581,2026-10-07T00:41:39.056752341+07:00,1000001,0,1000001,0,196018,24704154,469098563,24755550,197015,24831320,470874635,24883218

--- kiem tra kernel sau khi collector thoat ---
$ bpftool prog list | grep -ci hids
0
$ bpftool link list | grep -ci hids
0
$ bpftool map list | grep -ciE 'hids_|ringbuf'
0
$ ls -A /sys/fs/bpf | wc -l
0

du lieu: out/g7d-20261007-004130.bin | thong ke: out/g7d-20261007-004130.bin.stats
=== xong g3, du lieu trong validation/g3-20261007 === (S1–S5, G-real, G-irq, G7d), lưu , gắn tag .

3. **Đã làm gì**  
- Viết , , === S1: wl cpu 10000 300 (CPU 20) ===
wl pid=517295 tid=517295
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1645696 787895 3
--- moc A /proc/517295/sched ---
sum_sleep_runtime                            :          3741.115897
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.787895
iowait_sum                                   :             0.000000
--- moc B schedstat ---
3010505917 873559 12
--- moc B /proc/517295/sched ---
sum_sleep_runtime                            :          3768.307351
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.873559
iowait_sum                                   :             0.000000
cua so ts_enter: (20523263778865, 20526299923757]
--- rec-check ---
so ban ghi trong cua so: 51240
tid: 517295
cua so ts_enter: (20523263778865, 20526299923757]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 2993460458
steal 0
irq 15425638
rq 67143
vol 27192000
cpu+steal+irq 3008886096
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 51239
p50 0
p99 0
p99.9 0
max 0
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 51239
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
cpu+steal+irq        3008886096      3008860221      Delta schedstat field1 sum_exec_runtime
rq                   67143           85664           Delta schedstat field2 run_delay
rq (wait_sum)        67143           85664           Delta wait_sum /proc/sched
vol                  27192000        27191500        Delta sum_sleep_runtime
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
thoi gian chay: 3.101 s | CPU collector: user 0.281 s, sys 0.299 s (getrusage RUSAGE_SELF)
kich thuoc file: 2460574 byte
du lieu: out/g3-S1-004139.bin | thong ke: out/g3-S1-004139.bin.stats | theo doi: out/g3-S1-004139.bin.periodic
luu: validation/g3-20261007/S1-ketqua.txt
=== S2: wl sleep 5000 500 (CPU 20) ===
wl pid=518876 tid=518876
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1601151 4314 3
--- moc A /proc/518876/sched ---
sum_sleep_runtime                            :          3747.204717
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.004314
iowait_sum                                   :             0.000000
--- moc B schedstat ---
11322480 15468 504
--- moc B /proc/518876/sched ---
sum_sleep_runtime                            :          6305.105732
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.015468
iowait_sum                                   :             0.000000
cua so ts_enter: (20530359566683, 20532927207128]
--- rec-check ---
so ban ghi trong cua so: 1001
tid: 518876
cua so ts_enter: (20530359566683, 20532927207128]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 6038616
steal 0
irq 18606
rq 3373551
vol 2558210000
cpu+steal+irq 6057222
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 1000
p50 0
p99 483
p99.9 499
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 1000
p50 0
p99 483
p99.9 499
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        6057222         9721329         Delta schedstat field1 sum_exec_runtime
rq                   3373551         11154           Delta schedstat field2 run_delay
rq (wait_sum)        3373551         11154           Delta wait_sum /proc/sched
vol                  2558210000      2557900000      Delta sum_sleep_runtime
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
thoi gian chay: 2.622 s | CPU collector: user 0.156 s, sys 0.130 s (getrusage RUSAGE_SELF)
kich thuoc file: 49102 byte
du lieu: out/g3-S2-004146.bin | thong ke: out/g3-S2-004146.bin.stats | theo doi: out/g3-S2-004146.bin.periodic
luu: validation/g3-20261007/S2-ketqua.txt
=== S3: wl mixed 2000 3000 500 (CPU 20) ===
wl pid=520294 tid=520294
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1632557 10184 3
--- moc A /proc/520294/sched ---
sum_sleep_runtime                            :          3742.528361
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.010184
iowait_sum                                   :             0.000000
--- moc B schedstat ---
1027320526 191668 506
--- moc B /proc/520294/sched ---
sum_sleep_runtime                            :          5299.266073
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.191668
iowait_sum                                   :             0.000000
cua so ts_enter: (20536840093570, 20539422708411]
--- rec-check ---
so ban ghi trong cua so: 19495
tid: 520294
cua so ts_enter: (20536840093570, 20539422708411]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 1017957864
steal 17406
irq 4753975
rq 3077503
vol 1556796000
cpu+steal+irq 1022729245
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 19494
p50 0
p99 300
p99.9 483
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 19494
p50 0
p99 300
p99.9 483
max 499
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        1022729245      1025687969      Delta schedstat field1 sum_exec_runtime
rq                   3077503         181484          Delta schedstat field2 run_delay
rq (wait_sum)        3077503         181484          Delta wait_sum /proc/sched
vol                  1556796000      1556740000      Delta sum_sleep_runtime
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
thoi gian chay: 2.636 s | CPU collector: user 0.206 s, sys 0.206 s (getrusage RUSAGE_SELF)
kich thuoc file: 936814 byte
du lieu: out/g3-S3-004152.bin | thong ke: out/g3-S3-004152.bin.stats | theo doi: out/g3-S3-004152.bin.periodic
luu: validation/g3-20261007/S3-ketqua.txt
=== S4: wl cpu 10000 300 (CPU 20) ===
wl pid=521793 tid=521793
stress-ng pid=521797
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1688320 2674831 3
--- moc A /proc/521793/sched ---
sum_sleep_runtime                            :          3748.558768
sum_block_runtime                            :             0.000000
wait_sum                                     :             2.674831
iowait_sum                                   :             0.000000
--- moc B schedstat ---
3011071600 3011862709 953
--- moc B /proc/521793/sched ---
sum_sleep_runtime                            :          3787.199604
sum_block_runtime                            :             0.000000
wait_sum                                     :          3011.862709
iowait_sum                                   :             0.000000
cua so ts_enter: (20543402061676, 20549459290083]
--- rec-check ---
so ban ghi trong cua so: 53800
tid: 521793
cua so ts_enter: (20543402061676, 20549459290083]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         0
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 2999878037
steal 0
irq 9589526
rq 3009117443
vol 38643000
cpu+steal+irq 3009467563
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 53799
p50 0
p99 0
p99.9 0
max 0
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 53799
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
cpu+steal+irq        3009467563      3009383280      Delta schedstat field1 sum_exec_runtime
rq                   3009117443      3009187878      Delta schedstat field2 run_delay
rq (wait_sum)        3009117443      3009190000      Delta wait_sum /proc/sched
vol                  38643000        38640800        Delta sum_sleep_runtime
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
thoi gian chay: 6.105 s | CPU collector: user 0.326 s, sys 0.335 s (getrusage RUSAGE_SELF)
kich thuoc file: 2583454 byte
du lieu: out/g3-S4-004159.bin | thong ke: out/g3-S4-004159.bin.stats | theo doi: out/g3-S4-004159.bin.periodic
luu: validation/g3-20261007/S4-ketqua.txt
=== S5: wl io 300 (CPU 20) ===
wl pid=524136 tid=524136
--- moc A schedstat (sum_exec_runtime run_delay pcount) ---
1609145 4511 3
--- moc A /proc/524136/sched ---
sum_sleep_runtime                            :          3732.389657
sum_block_runtime                            :             0.000000
wait_sum                                     :             0.004511
iowait_sum                                   :             0.000000
--- moc B schedstat ---
28020167 680705 604
--- moc B /proc/524136/sched ---
sum_sleep_runtime                            :          4051.788448
sum_block_runtime                            :           290.915949
wait_sum                                     :             0.680705
iowait_sum                                   :           117.610884
cua so ts_enter: (20553515217472, 20553861699763]
--- rec-check ---
so ban ghi trong cua so: 1503
tid: 524136
cua so ts_enter: (20553515217472, 20553861699763]
co              so_ban_ghi
FIRST           0
GAP_BEFORE      0
D_SLEEP         300
MIGRATED        0
OVERFLOW        0
STEAL_FALLBACK  0
CLAMPED         0
--- tong thanh phan (ns) ---
cpu 24842723
steal 4080
irq 84857
rq 2351958
vol 319203000
cpu+steal+irq 24931660
--- G5 phan du |tat ca (tru FIRST)| (ns) ---
so khoang: 1502
p50 0
p99 472
p99.9 491
max 493
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |khong GAP_BEFORE| (ns) ---
so khoang: 1502
p50 0
p99 472
p99.9 491
max 493
so khoang |phan du| > 1000 ns: 0
so khoang |phan du| > 10000 ns: 0
--- G5 phan du |co GAP_BEFORE| (ns) ---
so khoang: 0
--- bang doi chieu ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        24931660        26411022        Delta schedstat field1 sum_exec_runtime
rq                   2351958         676194          Delta schedstat field2 run_delay
rq (wait_sum)        2351958         676194          Delta wait_sum /proc/sched
vol                  319203000       319399000       Delta sum_sleep_runtime
vol (D_SLEEP)        290719000       290916000       Delta sum_block_runtime
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
thoi gian chay: 0.387 s | CPU collector: user 0.149 s, sys 0.119 s (getrusage RUSAGE_SELF)
kich thuoc file: 73198 byte
du lieu: out/g3-S5-004209.bin | thong ke: out/g3-S5-004209.bin.stats | theo doi: out/g3-S5-004209.bin.periodic
luu: validation/g3-20261007/S5-ketqua.txt
=== G-real: cgroup qdrant 120s ===
cgroup: /sys/fs/cgroup/system.slice/docker-319c38ff33aa4827288f68ca1236600174cf278175fd7d5d68657d48e2a6366f.scope
so tien trinh trong cgroup luc bat dau: 2
--- log collector (cuoi) ---
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
thoi gian chay: 120.012 s | CPU collector: user 0.291 s, sys 0.373 s (getrusage RUSAGE_SELF)
kich thuoc file: 1354993 byte
du lieu: out/g3-greal-004213.bin | thong ke: out/g3-greal-004213.bin.stats | theo doi: out/g3-greal-004213.bin.periodic
--- bang doi chieu (tong thread song suot cua so) ---
thanh_phan           collector       tham_chieu      nguon
cpu+steal+irq        275175586       0               Tong Delta schedstat field1
rq                   78849323        0               Tong Delta schedstat field2
vol                  2753849117000   ?               sum_sleep_runtime: chua tong hop
=== G-irq: 30 giay may ranh ===
--- hardirqs-bpfcc (nguyen van) ---
Tracing hard irq event time... Hit Ctrl-C to end.

HARDIRQ                    TOTAL_usecs
ens33-rxtx-0                        15
vmw_vmci                            32
ens33-rxtx-2                        39
ens33-rxtx-1                        58
ens33-rxtx-4                        94
vmw_pvscsi                         119
ahci[0000:02:02.0]                 168
ens33-rxtx-3                       266
ens33-rxtx-7                       380
ens33-rxtx-6                      1098
--- softirqs-bpfcc (nguyen van) ---
Tracing soft irq event time... Hit Ctrl-C to end.

SOFTIRQ          TOTAL_usecs
tasklet                  203
block                    633
timer                   9893
net_rx                 26144
rcu                    28336
sched                  53589
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
thoi gian chay: 30.050 s | CPU collector: user 0.145 s, sys 0.116 s (getrusage RUSAGE_SELF)
kich thuoc file: 947 byte
du lieu: out/g3-girq-004417.bin | thong ke: out/g3-girq-004417.bin.stats | theo doi: out/g3-girq-004417.bin.periodic
--- bang doi chieu irq ---
loai                 collector       tham_chieu      nguon
hard (ns)            2498630         2269 (us)       hardirqs-bpfcc tong cot usecs
soft_raw (ns)        121435659       118798 (us)     softirqs-bpfcc tong cot usecs
soft_excl            121110394       —             collector (bcc khong tach)
vector               592984451       —             collector only
=== G7d (binary hien tai) ===
=== G7d: loc theo cgroup CHA, tien trinh nam trong cgroup CON, N=1000000 ===
cgroup cha=/sys/fs/cgroup/hids-test inode=22309
cgroup con=/sys/fs/cgroup/hids-test/con inode=22388
sysinj pid=529548
$ cat /proc/529548/cgroup
0::/hids-test/con
collector da gan tracepoint (READY), loc theo cgroup CHA
perf da gan
$ rmdir /sys/fs/cgroup/hids-test/con /sys/fs/cgroup/hids-test
da xoa cgroup tam

--- perf stat (nguyen van) ---

 Performance counter stats for process id '529548':

         1,000,001      raw_syscalls:sys_enter                                                

       3.003137215 seconds time elapsed

--- log collector (nguyen van) ---
CANH BAO: binary build tu cay lam viec con thay doi chua commit (git_commit=c3d371b-dirty).
CANH BAO: du lieu ghi ra khong tai lap duoc tu git. Commit truoc khi do that.
stealclock: bat (24/24 dong "vmware-stealtime" trong dmesg)
doi chieu vmw_steal_time voi rq->prev_steal_time trong 3s...
doi chieu xong: lech lon nhat 9047 ns tren 24 CPU, nguong max(2000000 ns, 1%)
ghi vao out/g7d-20261007-004451.bin
loc pid: khong co | loc cgroup: /sys/fs/cgroup/hids-test (id=22309) | ring buffer: 64 MiB
READY
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
irq cong don (ns): hard 193639 | soft 23025930 | vector 446984466 | tong 470204035
soft_raw cong don (ns): 23067077 (ke ca hard/vector long ben trong, de so voi softirqs-bpfcc)
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
thoi gian chay: 4.933 s | CPU collector: user 0.355 s, sys 0.368 s (getrusage RUSAGE_SELF)
kich thuoc file: 48001034 byte
du lieu: out/g7d-20261007-004451.bin | thong ke: out/g7d-20261007-004451.bin.stats | theo doi: out/g7d-20261007-004451.bin.periodic

--- bang ket qua ---
N theo thiet ke:                              1000000
perf raw_syscalls:sys_enter (-p 529548):      1000001
so ban ghi collector:                         1000001
so ban ghi nr=110:                            1000000
hieu (perf - ban ghi):                        0

--- thoi gian va dung luong ---
kich thuoc out/g7d-20261007-004451.bin: 48001034 byte

--- rec-stat day du (nguyen van) ---
file: out/g7d-20261007-004451.bin
# hids-collect
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# nr_cpus_possible: 24
# git_commit: c3d371b-dirty
# record_size: 48
# filter_pid: khong co
# filter_cgroup: /sys/fs/cgroup/hids-test (id=22309)
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
# start_mono_ns: 20715917669473
# start_wall: 2026-10-07T00:44:55.62278175+07:00
# duration: khong gioi han

tong so ban ghi trong file : 1000001
so ban ghi sau khi loc     : 1000001
bo loc                     : khong co
ts_enter nho nhat / lon nhat: 20717952239959 / 20718840697913 (ns, CLOCK_MONOTONIC)
ban ghi co co FIRST        : 1
ban ghi co co GAP_BEFORE   : 0
ban ghi co syscall_nr=110  : 1000000

so ban ghi theo tgid (1 tien trinh)
    tgid  ban_ghi   nr=110  FIRST  GAP_BEFORE      nguon_tgid
  529548  1000001  1000000      1           0  ? (suy tu tid)
    TONG  1000001  1000000      1           0                

so ban ghi theo tid (1 thread, in 1 dong dau)
     tid  tgid  ban_ghi   nr=110
  529548     ?  1000001  1000000

top 2 syscall_nr (tong cong 2 gia tri khac nhau)
  syscall_nr  ban_ghi
         110  1000000
         231        1

theo tung CPU (cpu lay tu bit8..15 cua flags; seq_cuoi va mat lay tu .stats)
   cpu  ban_ghi  seq_min  seq_max  lo_hong  seq_thieu  seq_cuoi  mat
     4  1000001        1  1000001        0          0   1000001    0
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
# git_commit: c3d371b-dirty
# record_size: 48
# filter_pid: khong co
# filter_cgroup: /sys/fs/cgroup/hids-test (id=22309)
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
# start_mono_ns: 20715917669473
# start_wall: 2026-10-07T00:44:55.62278175+07:00
# duration: khong gioi han
# moi dong cach nhau 10s
mono_ns,wall,dinh_ghi_delta,mat_delta,dinh_ghi_tong,mat_tong,irq_hard_delta_ns,irq_soft_delta_ns,irq_vec_delta_ns,soft_raw_delta_ns,irq_hard_tong_ns,irq_soft_tong_ns,irq_vec_tong_ns,soft_raw_tong_ns
20715920273680,2026-10-07T00:44:55.625385267+07:00,0,0,0,0,0,95923,2678854,95923,0,95923,2678854,95923
20720851054723,2026-10-07T00:45:00.556166589+07:00,1000001,0,1000001,0,193639,22930007,444305612,22971154,193639,23025930,446984466,23067077

--- kiem tra kernel sau khi collector thoat ---
$ bpftool prog list | grep -ci hids
0
$ bpftool link list | grep -ci hids
0
$ bpftool map list | grep -ciE 'hids_|ringbuf'
0
$ ls -A /sys/fs/bpf | wc -l
0

du lieu: out/g7d-20261007-004451.bin | thong ke: out/g7d-20261007-004451.bin.stats
=== xong g3, du lieu trong validation/g3-20261007 ===, .  
- Tự chạy G3; sửa chờ  qua ; giảm syscall  trong .  
- Thêm  vào .

4. **Lệnh build, lệnh chạy**  
```bash
make build
sudo bash scripts/g3.sh
```

5. **Kết quả:**

### S1


### S2


### S3


### S4


### S5


### G-real


### G-irq


### G7d




**recursion_misses:** recursion_misses (bpf_prog_info), tong 0 tren 30 chuong trinh (moi chuong trinh 0 trong log collector).

**Chi phí CPU collector:**  
- S1: thoi gian chay: 3.101 s | CPU collector: user 0.281 s, sys 0.299 s (getrusage RUSAGE_SELF)
- S2: thoi gian chay: 2.622 s | CPU collector: user 0.156 s, sys 0.130 s (getrusage RUSAGE_SELF)
- S3: thoi gian chay: 2.636 s | CPU collector: user 0.206 s, sys 0.206 s (getrusage RUSAGE_SELF)
- S4: thoi gian chay: 6.105 s | CPU collector: user 0.326 s, sys 0.335 s (getrusage RUSAGE_SELF)
- S5: thoi gian chay: 0.387 s | CPU collector: user 0.149 s, sys 0.119 s (getrusage RUSAGE_SELF)
- G-real: thoi gian chay: 120.012 s | CPU collector: user 0.291 s, sys 0.373 s (getrusage RUSAGE_SELF)
- G-irq: thoi gian chay: 30.050 s | CPU collector: user 0.145 s, sys 0.116 s (getrusage RUSAGE_SELF)
- G7d: thoi gian chay: 4.933 s | CPU collector: user 0.355 s, sys 0.368 s (getrusage RUSAGE_SELF)

6. **File dữ liệu:** , log 

7. **Quyết định tự đưa ra:** xem mục 8 báo cáo trước (wchan, g3_window, G-real đơn giản).

8. **Cần kiến trúc sư:** G-real thread set; G-irq đơn vị/phạm vi; wl clock_gettime còn trong S1/S3/S4 lần chạy này.

9. **Việc người dùng:** không.

10. **Tiếp theo:** chạy lại S1–S5 với wl spin mới; G-irq parse đã sửa trong . DỪNG, không M4.
