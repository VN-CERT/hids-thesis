#!/usr/bin/env python3
"""m6c_stats.py - do kien truc su viet. KHONG SUA NOI DUNG.

Dau vao: file TSV co dong tieu de, it nhat 4 cot: load, cond, run, value
  (value la mot so: thong luong, do tre, hoac CPU cgroup - tuy bang).
  Moi load phai co dieu kien C0 (khong collector) lam moc.
Dau ra (TSV, mot dong moi load x cond):
  load cond n mean sd ci95_lo ci95_hi pct_vs_C0 pct_ci95_lo pct_ci95_hi p_perm
  - ci95 cua trung binh: t-Student hai phia.
  - pct_vs_C0 = (mean_cond / mean_C0 - 1) * 100; khoang tin cay 95% cua pct
    bang bootstrap (10000 lan lay mau lai, seed co dinh).
  - p_perm: kiem dinh hoan vi hai phia tren hieu hai trung binh (10000 lan).
  Dong C0 co pct = 0 va cac cot so sanh de "-".
Cach dung:
  python3 m6c_stats.py <file.tsv>
Chi dung thu vien chuan cua Python.
"""
import math
import random
import sys

T95 = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
       2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
       2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]
B = 10000
SEED = 12345


def tcrit(df):
    if df <= 0:
        return float("nan")
    return T95[df - 1] if df <= len(T95) else 1.96


def mean(x):
    return sum(x) / len(x)


def sd(x):
    if len(x) < 2:
        return float("nan")
    m = mean(x)
    return math.sqrt(sum((v - m) ** 2 for v in x) / (len(x) - 1))


def ci_mean(x):
    n = len(x)
    if n < 2:
        return float("nan"), float("nan")
    h = tcrit(n - 1) * sd(x) / math.sqrt(n)
    m = mean(x)
    return m - h, m + h


def pct(a, b):
    return (mean(a) / mean(b) - 1.0) * 100.0


def boot_pct_ci(a, c0, rng):
    vals = []
    for _ in range(B):
        ra = [a[rng.randrange(len(a))] for _ in a]
        rc = [c0[rng.randrange(len(c0))] for _ in c0]
        mc = mean(rc)
        if mc == 0:
            continue
        vals.append((mean(ra) / mc - 1.0) * 100.0)
    vals.sort()
    if not vals:
        return float("nan"), float("nan")
    lo = vals[int(0.025 * (len(vals) - 1))]
    hi = vals[int(0.975 * (len(vals) - 1))]
    return lo, hi


def perm_p(a, c0, rng):
    obs = abs(mean(a) - mean(c0))
    pool = list(a) + list(c0)
    na = len(a)
    hit = 0
    for _ in range(B):
        rng.shuffle(pool)
        if abs(mean(pool[:na]) - mean(pool[na:])) >= obs - 1e-12:
            hit += 1
    return (hit + 1) / (B + 1)


def f(v):
    return "nan" if v != v else f"{v:.4f}"


def main(path):
    data = {}
    order = []
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().strip().split("\t")
        idx = {k: header.index(k) for k in ("load", "cond", "run", "value")}
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < len(header) or not parts[0]:
                continue
            load, cond = parts[idx["load"]], parts[idx["cond"]]
            try:
                v = float(parts[idx["value"]])
            except ValueError:
                continue
            if (load, cond) not in data:
                order.append((load, cond))
                data[(load, cond)] = []
            data[(load, cond)].append(v)

    print("load\tcond\tn\tmean\tsd\tci95_lo\tci95_hi\tpct_vs_C0\tpct_ci95_lo\tpct_ci95_hi\tp_perm")
    rng = random.Random(SEED)
    for load, cond in order:
        x = data[(load, cond)]
        lo, hi = ci_mean(x)
        c0 = data.get((load, "C0"))
        if cond == "C0" or not c0:
            extra = ["0.0000" if cond == "C0" else "-", "-", "-", "-"]
        else:
            plo, phi = boot_pct_ci(x, c0, rng)
            extra = [f(pct(x, c0)), f(plo), f(phi), f(perm_p(x, c0, rng))]
        print("\t".join([load, cond, str(len(x)), f(mean(x)), f(sd(x)), f(lo), f(hi)] + extra))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
