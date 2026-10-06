# Chay lai phep thu 30 giay sau M3 PHAN 1, 2026-10-07

PHAN 1 = muc 8.2 + 8.3 trong phan hoi cua kien truc su cho R004:
bo cong don irq per-CPU viet lai theo phuong an (c) (trang thai rieng tung
loai, khong con bien do sau dung chung), in `recursion_misses` cua tung
chuong trinh BPF, them cot `soft_raw_delta_ns` vao `.periodic`, them 4 dong
header `CONFIG_*`.

Day KHONG phai cong kiem chung G3. G3 (muc H cua M3) van chua viet, chua chay.
Day chi la lan chay thu lap lai de xac nhan ban viet lai van nap duoc, van ra
ban ghi, va khong tu mau thuan.

## Tai thu
`out/target.py` (khong commit, sinh lai duoc), giong het lan chay o R004:
mot tien trinh python lap ~5 ms dot CPU (vong lap time.monotonic, khong goi
syscall) roi ~5 ms ngu (time.sleep) roi mot getppid.

## Lenh
    make build
    setsid python3 out/target.py > out/target.pid 2>&1 &
    sleep 2
    ./bin/hids-collect -pid $(cat out/target.pid) -duration 30s -out out/p1-30s.bin
    python3 validation/m3ae-20261006/soicheo.py out/p1-30s.bin

## File
- `chay-thu-30s.txt` — nguyen van stderr cua hids-collect, co bang recursion_misses
- `chay-thu-30s.bin.periodic` — file theo doi 10 giay/dong, co cot soft_raw_delta_ns
- `chay-thu-30s.bin.stats` — bo dem seq va mat theo tung CPU
- `tu-nhat-quan.txt` — ket qua soi cheo tu nhat quan
- `soicheo.py` — ban sao script soi cheo dung mot lan (giong ban o m3ae-20261006)

File `out/p1-30s.bin` (286931 byte) khong commit theo quy tac.

## Soi cheo tu nhat quan
`soicheo.py` KHONG phai cong cu cua du an va KHONG so voi nguon tham chieu nao
cua kernel. No chi kiem tra ban ghi co tu mau thuan khong: Δt giua hai sys_enter
lien tiep cua cung tid co bang cpu+steal+irq+rq+vol khong. Viec doi chieu voi
nguon tham chieu that (/proc/<tid>/schedstat, /proc/<tid>/sched,
hardirqs-bpfcc, softirqs-bpfcc) thuoc muc G va H cua M3, de PHAN 2.
