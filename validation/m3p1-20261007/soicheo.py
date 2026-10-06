import struct, sys
path = sys.argv[1]
data = open(path,'rb').read()
i = data.index(b'#END\n') + len(b'#END\n')
recs = [struct.unpack_from('<QQIIHHIIIII', data, o) for o in range(i, len(data)-47, 48)]
print("so ban ghi:", len(recs))
by = {}
for r in recs:
    by.setdefault(r[2], []).append(r)
tong = {'cpu':0,'steal':0,'irq':0,'rq':0,'vol':0,'dt':0}
lech_max = 0; n_lech = 0; n_so = 0
fl = {}
for tid, rs in by.items():
    rs.sort(key=lambda r: r[0])
    for a, b in zip(rs, rs[1:]):
        dt = b[0]-a[0]
        s = b[6]+b[7]+b[8]+b[9]+b[10]*1000
        if b[5] & 0x02:   # GAP_BEFORE -> gop nhieu khoang, khong so
            continue
        n_so += 1
        d = abs(int(dt)-int(s))
        if d > lech_max: lech_max = d
        if d > 1000: n_lech += 1
        tong['dt']+=dt; tong['cpu']+=b[6]; tong['steal']+=b[7]
        tong['irq']+=b[8]; tong['rq']+=b[9]; tong['vol']+=b[10]*1000
for r in recs:
    for bit,name in [(0,'FIRST'),(1,'GAP_BEFORE'),(2,'D_SLEEP'),(3,'MIGRATED'),(4,'OVERFLOW'),(5,'STEAL_FALLBACK'),(6,'CLAMPED')]:
        if r[5] & (1<<bit): fl[name] = fl.get(name,0)+1
print("so khoang so sanh duoc:", n_so)
print("lech |dt - (cpu+steal+irq+rq+vol)| lon nhat:", lech_max, "ns")
print("so khoang lech > 1000 ns:", n_lech)
print("tong dt   :", tong['dt'], "ns")
print("tong cong :", tong['cpu']+tong['steal']+tong['irq']+tong['rq']+tong['vol'], "ns")
for k in ('cpu','steal','irq','rq','vol'):
    print("  %-6s %16d ns  %6.2f%%" % (k, tong[k], 100.0*tong[k]/tong['dt'] if tong['dt'] else 0))
print("flags:", fl)
print("CPU xuat hien (bit8-15):", sorted({(r[5]>>8)&0xff for r in recs}))
