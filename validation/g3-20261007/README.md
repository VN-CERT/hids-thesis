# Kiem chung G3 (M3 muc H), 2026-10-07

Chay bang: `sudo bash scripts/g3-driver.sh` (hoac `sudo bash scripts/g3.sh`).

Dau script: `kernel.sched_schedstats=1`, cuoi script tra lai gia tri cu (luu trong `sched_schedstats.before`).

File `.bin` lon khong commit; chi `*-ketqua.txt`, `.periodic`, `.stats`.

## Lenh
    make build
    sudo bash scripts/g3.sh

## Noi dung
- S1–S5: kich ban wl tren CPU 20, doi chieu voi Delta `/proc/<tid>/schedstat` va `/proc/<tid>/sched`
- G-real: loc cgroup container qdrant 120 giay
- G-irq: 30 giay, hardirqs-bpfcc + softirqs-bpfcc song song collector
- G7d: `scripts/g7.sh d`

## Ghi chu ky thuat
- `wl` doi CPU bang `CLOCK_THREAD_CPUTIME_ID`; phien chay nay con nhieu ban ghi `clock_gettime` (nr 228) trong S1/S3/S4 nen G5 co so khoang lon; phien sau da tang spin trong vong dot CPU.
