# Chay thu M3 muc A-E, 2026-10-06

Day KHONG phai cong kiem chung G3. G3 (muc H cua M3) chua viet, chua chay.
Day chi la lan chay thu 30 giay de xac nhan: verifier nap duoc, co ban ghi,
file .periodic co dong, va sau khi thoat kernel khong con doi tuong hids_ nao.

## Tai thu
`out/target.py` (khong commit, sinh lai duoc): mot tien trinh python lap
~5 ms dot CPU (vong lap time.monotonic, khong goi syscall) roi ~5 ms ngu
(time.sleep) roi mot getppid.

## Lenh
    make build
    setsid python3 out/target.py > out/target.pid 2>&1 &
    ./bin/hids-collect -pid $(cat out/target.pid) -duration 30s -out out/m3-thu.bin

## File
- `chay-thu-30s.txt` — nguyen van stderr cua hids-collect
- `chay-thu-30s.bin.periodic` — file theo doi 10 giay/dong, co ca header
- `chay-thu-30s.bin.stats` — bo dem seq va mat theo tung CPU
- `tu-nhat-quan.txt` — ket qua soi cheo tu nhat quan (xem duoi)
- `soicheo.py` — script soi cheo dung mot lan

File `out/m3-thu.bin` (286798 byte) khong commit theo quy tac.

## Soi cheo tu nhat quan
`soicheo.py` KHONG phai cong cu cua du an va KHONG so voi nguon tham chieu nao
cua kernel. No chi kiem tra ban ghi co tu mau thuan khong:
Δt giua hai sys_enter lien tiep cua cung tid co bang cpu+steal+irq+rq+vol
khong. Viec doi chieu voi nguon tham chieu that (/proc/<tid>/schedstat,
/proc/<tid>/sched, hardirqs-bpfcc, softirqs-bpfcc) thuoc muc G va H cua M3,
de phien sau.
