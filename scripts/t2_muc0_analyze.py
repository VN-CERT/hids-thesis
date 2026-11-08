#!/usr/bin/env python3
"""M6i-c8: phan tich T2 bat gi o muc_0 (tan cong khong tai).
Doc features_ghep, fit covariance tren nen muc 0 (nhu t2_score), cham moi cua so tan cong muc_0,
lay 20 diem cao nhat + phan ra dong gop Mahalanobis tung chieu.
Doc lai dinh nghia tu c5_score (import). KHONG sua c5_score."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
_c5path = os.path.join(os.path.dirname(__file__), "..", "analysis", "c5_score.py")
spec = importlib.util.spec_from_file_location("c5", os.path.abspath(_c5path))
c5 = importlib.util.module_from_spec(spec); spec.loader.exec_module(c5)

def main():
    feat = sys.argv[1]; nhan = sys.argv[2]; nhan_tid = sys.argv[3]; muc = sys.argv[4]
    chieu = sys.argv[5] if len(sys.argv) > 5 else "D"
    train_until = int(sys.argv[6]) if len(sys.argv) > 6 else 1006289550843307
    rows, dims_all = c5.read_features(feat, mien_log=True)
    labels = c5.read_nhan(nhan)
    tid_labels = c5.read_nhan_tid(nhan_tid, labels)
    mucd = c5.read_muc(muc)
    for w in rows:
        c5.gan_nhan(w, labels, tid_labels, True)
        w.muc_nhan = c5.muc_tu_nhan(w, labels, tid_labels, True)
        if mucd: c5.gan_muc(w, mucd)
    rows = [w for w in rows if not (w.branch != c5.AGG_BRANCH and w.nrec is not None and w.nrec < 30)]
    want = c5.CHIEU_PHANRA[chieu]
    rb = [w for w in rows if w.branch == "PHANRA_5tp"]
    dims_idx = [i for i,d in enumerate(dims_all) if d in want and any(w.f[i]==w.f[i] for w in rb)]
    def lvl(w):
        mm = w.muc_nhan if w.muc_nhan not in (None,"") else "0"
        return mm if mm not in (None,"") else "0"
    train = [w for w in rb if w.nguon=="nen" and w.stop<=train_until and w.atk is None and w.twin is None and lvl(w)=="0"]
    fit = c5.fit_cov(train, dims_idx)
    if not fit:
        print("khong fit duoc cov"); return
    med, Sinv = fit
    # cham tan cong muc_0
    atk0 = [w for w in rb if w.atk is not None and lvl(w)=="0"]
    scored = []
    for w in atk0:
        if any(w.f[di]!=w.f[di] for di in dims_idx): continue
        d = [w.f[di]-med[j] for j,di in enumerate(dims_idx)]
        # T2 + dong gop tung chieu: contrib_i = d_i * sum_j Sinv[i][j] d_j
        Sd = [sum(Sinv[i][j]*d[j] for j in range(len(d))) for i in range(len(d))]
        t2 = sum(d[i]*Sd[i] for i in range(len(d)))
        contrib = [(dims_all[dims_idx[i]], d[i]*Sd[i]) for i in range(len(d))]
        scored.append((t2, w, contrib))
    scored.sort(reverse=True, key=lambda x:x[0])
    print("# T2 muc_0 (tan cong khong tai), bo chieu=%s, %d cua so; 20 diem cao nhat:" % (chieu, len(scored)))
    print("rank\ttid\tnguon\tt2\tchieu_dong_gop_lon_nhat(3)")
    for r,(t2,w,contrib) in enumerate(scored[:20],1):
        contrib.sort(reverse=True, key=lambda x:abs(x[1]))
        top3 = "  ".join("%s=%.1f%%" % (c,100*v/t2) for c,v in contrib[:3])
        print("%d\t%s\t%s\t%.2f\t%s" % (r, w.tid, w.nguon, t2, top3))
    # tong hop: chieu nao dong gop nhieu nhat trung binh tren 20 cua so
    agg = {}
    for t2,w,contrib in scored[:20]:
        for c,v in contrib:
            agg[c] = agg.get(c,0)+v/t2
    print("\n# dong gop trung binh (20 cua so cao nhat), theo chieu:")
    for c,v in sorted(agg.items(), key=lambda x:-x[1]):
        print("  %s: %.1f%%" % (c, 100*v/20))

main()
