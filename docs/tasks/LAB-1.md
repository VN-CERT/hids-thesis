NHIỆM VỤ LAB-1 — máy 201 (nạn nhân, 55.201 / 192.168.77.10), nhánh lab-collector. Nền benign 7 ngày + bộ liều tranh chấp có nhãn + benign-dưới-liều + hai cặp tấn-công/song-sinh cho C5 của Bài 1. Lưu nguyên văn vào docs/tasks/LAB-1.md. Mọi ssh/scp cổng 22022. KHÔNG đụng 192.168.77.20 (phần B1/B4 chạy nội bộ trên 201). KHÔNG chạy lớp A/C, không B2/B3/B5/B6, không dựng CVE LID-DS. Báo cáo: LAB-1-ketqua.txt. In MỌI kết quả ra file .txt, không bắt người dùng thao tác tay.

File kiến trúc sư (KHÔNG sửa; kiểm sha256 trước build và lúc viết báo cáo):
 - bpf/sys_enter.bpf.c = 9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0
 - bpf/proc_events.bpf.c = 39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec
 - analysis/m5f_parse.py = 9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd
 - analysis/m6c_stats.py = 8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25
 - tools/coreclk.c = 88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706
File kiến trúc sư MỚI (người dùng đã chép vào repo; kiểm sha256, sai → DỪNG):
 - docs/giao-thuc-lab1.md
 - analysis/detector_c5.py = (tự kiểm: đọc dòng đầu phải là "#!/usr/bin/env python3" và có chuỗi "CHOT TRUOC KHI THAY DU LIEU")

Sha sai, build/verifier lỗi, cổng không đạt, xung đột git: DỪNG, dán nguyên văn. Không sửa tiêu chí. Điều kiện DỪNG thì DỪNG, không "ghi nhận rồi chạy tiếp".

Thứ tự và cách chạy: 0 → 1 (commit giao thức) → 2 (generator) → 3 (liều + E5, chạy trong phiên, ~1,5 giờ) → ĐẶT MỘT UNIT `hids-lab1-driver` (systemd-run, Restart=no) chạy liên tiếp KHÔNG cần người: 4 (B/N) → 4b (benign dưới liều) → 6 (tự khởi động nền 7 ngày) → ghi `validation/lab1-<ngày>/driver-xong.txt`. Cursor có thể kết thúc lượt sau khi driver khởi động và kiểm 10 phút đầu; người dùng quay lại HÔM SAU với một câu "driver xong, làm bước 5 và 7". Driver ước ~5 giờ. Mọi lỗi trong driver: ghi vào file, dừng driver, KHÔNG tự sửa tiêu chí.

0. Điều kiện: ở trên tag m6c.3 (LAB-0c đã merge); `bpftool prog show | grep -c hids_` = 0; `kernel.perf_event_paranoid` ≤ 1; vPMC có (LAB-0c xác nhận); đĩa trống ≥ 100 GB (`df -h /`). Hai container lab0-postgres, lab0-nginx Up. `make build`, kiểm sha256.

1. COMMIT GIAO THỨC TRƯỚC KHI GHI DỮ LIỆU (mốc chống sửa tiêu chí sau): kiểm `docs/giao-thuc-lab1.md` và `analysis/detector_c5.py` có trong repo và đúng sha/tự-kiểm; commit chúng với thông điệp "LAB-1: chot giao thuc va detector C5 truoc khi ghi du lieu (kien truc su)". In `git rev-parse HEAD` và `git log --oneline -3` vào báo cáo. Nếu hai file chưa có → DỪNG, báo người dùng chép vào.

2. Generator tải benign `scripts/lab1_benign_gen.sh <thu_muc_log>` (tạo nếu chưa có, theo §2b giao thức):
 - Vòng lặp vô hạn, mỗi nhịp 5 phút, chọn mức tải theo giờ trong ngày (đêm 00–06 thấp, ngày cao) + jitter ±20 %:
   nginx `taskset -c 0-3 wrk2 -t2 -c16 -R <rps> -d290s --latency http://127.0.0.1:18080/file4k.bin` (rps ∈ {20,50,120,200});
   postgres `scripts/lab0-load-postgres.sh <tps> 290 <thu_muc_log>` (tps ∈ {15,40,100}; script này đã VACUUM+CHECKPOINT trước mỗi lượt).
 - Ghi mốc mono_ns đầu/cuối mỗi nhịp vào `<thu_muc_log>/nhip-benign.tsv` (cột: nhip_id dich_vu muc t_bat_dau_mono_ns t_ket_thuc_mono_ns).
 - `bash -n` sạch; dừng sạch khi SIGTERM. Chạy THỬ 10 phút ghi log vào `validation/lab1-<ngày>/gen-test/`, xác nhận có lưu lượng (nginx trả 200, pgbench chạy), rồi dừng. In tóm tắt.

3. Bộ liều D1, D3, D4 + E5 (§3–4 giao thức; D2 HOÃN — ghi "D2 hoan: can vCenter" vào nhãn). Container dừng khi chạy liều (để wl độc chiếm CPU), khởi động lại sau. wl lượng cố định ghim CPU 0. Mỗi khối freq_stamp CPU 0 trước/sau. Mỗi liều ghi `lab/nhan-lieu.tsv` (§4 thư viện liều). Mỗi trục 3 lần/mức:
 - D1 (rq): stress-ng --cpu N ghim CPU 0, N ∈ {0,1,2,3,4}. Oracle rq; đối chiếu bpftrace @rq.
 - D3 (bộ nhớ): stress-ng --stream worker ∈ {0,4,12,22} trên CPU 1–7, collector `-pmu on` (lấy CPI khoảng đốt). Oracle CPI.
 - D4 (throttle): wl trong container `--cpus` ∈ {khong_gioi_han, 2, 1, 0.5}. Oracle nr_throttled/throttled_usec từ cpu.stat.
 - E5: như D4 nhưng đo Δrq collector vs Δthrottled_usec; kiểm steal ≈ 0.
 - In bảng mỗi trục (mức → trung vị từng thành phần) vào `validation/lab1-<ngày>/lieu/`. Tiêu chí §3–4 (Spearman ≥ 0,9 thành phần kỳ vọng; thành phần không kỳ vọng đổi < 10 %; E5 Pearson ≥ 0,8; |steal| < 2 % rq). Không đạt → DỪNG, dán số.

4. Hai cặp B/N (§5 giao thức) — TRONG DRIVER. Mỗi mục B1, N1, B4, N4 chạy ở 3 mức tranh chấp (nền D1 N∈{0,2,4}), mỗi phiên 15 phút = 12 phiên ≈ 3 giờ. Mỗi phiên: collector `-datadir -pmu sample=20` lọc 2 cgroup, generator đang chạy, liều nền bật, rồi B hoặc N chạy từ phút 3 đến phút 13 (cửa sổ nhãn). Mỗi lần ghi `lab/nhan-tan-cong.tsv` (§5 danh mục tấn công, mono_ns đầu/cuối + oracle):
 - B1 beacon + N1 poll: client HTTP tự viết trên 201 gọi nội bộ http://127.0.0.1:18080/file4k.bin, chu kỳ ∈ {10s,60s,300s} jitter 0–50%. B1 nhãn trong cửa sổ tấn công (tiến trình tên lạ); N1 nhãn benign, cột song_sinh_cua=B1. Oracle: log client + bản ghi connect trong luồng syscall.
 - B4 đào coin + N4 nén log: B4 stress-ng --cpu 1 bật 2s/nghỉ 20s trong cửa sổ; N4 gzip file log cùng nhịp, song_sinh_cua=B4. Oracle: tiến trình chạy đúng chu kỳ.
 - Tiêu chí §5: mỗi cửa sổ B/N có ≥ 20 chu kỳ bản ghi; mốc nhãn khớp bản ghi ±1 s. In xác nhận vào `validation/lab1-<ngày>/bn/`.

4b. Benign dưới liều (§4b giao thức) — TRONG DRIVER, sau 4: generator chạy bình thường, KHÔNG tấn công, áp D1 N∈{2,4} và D3 worker∈{12,22}, mỗi mức 15 phút × 2 lần (≈ 2 giờ), collector `-datadir -pmu sample=20` lọc 2 cgroup; ghi nhãn benign + cột muc_tranh_chap vào `lab/nhan-lieu.tsv` (dose_id dạng BEN-D1-2, BEN-D3-12…). Tiêu chí: không khoảng mù > 60 s ở cả hai cgroup; oracle (rq với D1, CPI với D3) tăng theo mức. In vào `validation/lab1-<ngày>/benign-lieu/`.

5. (Làm khi người dùng quay lại, sau khi driver xong) Kiểm khói detector (§6 giao thức): rec-export một phiên B1-chậm-300s ra TSV; `python3 analysis/detector_c5.py --tsv <file> --nhan lab/nhan-tan-cong.tsv --window-s 300 --step-s 30`. Xác nhận: chạy không lỗi, in được cả hai nhánh BASELINE và PHANRA, nhánh PHANRA cho tỉ lệ phát hiện ≥ BASELINE ở báo động giả thấp nhất. In nguyên văn bảng vào `validation/lab1-<ngày>/detector-khoi.txt`. KHÔNG chọn ngưỡng, KHÔNG kết luận thống kê (dữ liệu chưa đủ).

6. KHỞI ĐỘNG NỀN BENIGN 7 NGÀY — bước cuối của DRIVER, tự chạy khi 4 và 4b xong (sống qua mất phiên Cursor):
 - Thư mục dữ liệu: `/srv/hids-data/lab1-benign/` (hoặc nơi có ≥ 100 GB). Collector `-datadir <đó> -cgroup <cgroup lab0-postgres> -cgroup <cgroup lab0-nginx> -pmu sample=20` + các cờ như LAB-0b, KHÔNG `-duration` (chạy đến khi dừng tay).
 - Hai unit systemd-run riêng: `hids-lab1-collector` (collector) và `hids-lab1-gen` (generator, ghi log vào `/srv/hids-data/lab1-benign/gen-logs/`). Cả hai Restart=always. Ghi tên unit + lệnh đầy đủ + mốc bắt đầu vào `validation/lab1-<ngày>/benign-khoi-dong.txt` và vào docs/STATE.md.
 - Một unit đồng hồ `hids-lab1-watch` (timer mỗi giờ) ghi một dòng vào `/srv/hids-data/lab1-benign/suc-khoe.tsv`: wall, records_per_sec, kernel_drops_delta, proc_drops_delta, rss_bytes, cpu_seconds_total, tỉ lệ cờ PMU của giờ, free_gb. Đây là nguồn kiểm tiêu chí §2 mà không cần đọc .bin.
 - Driver tự kiểm sau 20 phút: `suc-khoe.tsv` có ≥ 1 dòng hợp lệ, drops = 0, PMU ∈ [4%,6%]; đạt → ghi `driver-xong.txt` và để chạy; không đạt → dừng unit, ghi lỗi vào `driver-loi.txt`.
 - KHÔNG chờ 7 ngày trong phiên này. In hướng dẫn cho người dùng: sau 7 ngày chạy `scripts/lab1_tong_ket.sh` (tạo ở bước này) để dừng unit, gộp suc-khoe.tsv, kiểm 5 tiêu chí §2, in `validation/lab1-FINAL.txt`; rồi gửi file đó cho kiến trúc sư.

7. (Cùng lúc với 5) Báo cáo LAB-1-ketqua.txt: sha256 5 file + 2 file mới; git rev-parse của commit giao thức (bước 1); tóm tắt generator; bảng liều D1/D3/D4 + E5 (số + đạt/không từng tiêu chí); xác nhận B1/N1/B4/N4 (số chu kỳ, khớp nhãn); bảng benign-dưới-liều (oracle theo mức); bảng detector khói; tên unit + mốc khởi động benign + 1 dòng suc-khoe đầu; mục "quyết định tự đưa ra"; mục "việc người dùng cần làm" (chỉ: chờ 7 ngày rồi chạy lab1_tong_ket.sh). Commit mọi thứ TRỪ .bin (theo .gitignore dự án). KHÔNG push nếu repo lab không có remote; nếu có thì push nhánh lab-collector. DỪNG.

Lưu ý tài nguyên: 201 chỉ 8 vCPU. Liều D1/D3 và container benign đều đụng CPU 0–7; liều chạy khi container DỪNG, benign dài chạy khi KHÔNG có liều. Không chạy chồng. Mọi lần khởi động collector: chờ READY (tối đa 20 s), KHONG_READY thì chạy lại lượt (tối đa 2 lần), không sửa số tay.
