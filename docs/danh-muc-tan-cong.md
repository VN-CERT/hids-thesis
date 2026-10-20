# Danh mục tấn công — lab cô lập

> Mọi tấn công CHỈ chạy trong lab cô lập (máy tấn công 192.168.77.20 → máy nạn nhân 192.168.77.10).
> KHÔNG chạy trên production. Máy tấn công không có đường ra mạng thật.
> Mỗi lần chạy phải ghi: mốc bắt đầu/kết thúc (mono_ns + wall), kỹ thuật, tham số nhịp, oracle xác nhận.
> Phiên bản 0.2 — 20/10/2026.

## 0. Nguyên tắc

- **Nhãn thời gian là trung tâm.** Mỗi tấn công ghi cửa sổ [t_bắt_đầu, t_kết_thúc] theo CLOCK_MONOTONIC của máy nạn nhân, để khớp với bản ghi collector. Dùng một tiến trình "mốc" chạy trên máy nạn nhân phát một syscall đánh dấu (ví dụ ghi vào một file cố định) ngay trước và sau mỗi tấn công.
- **Hai trục biến thiên:** (a) loại tấn công; (b) mức tranh chấp tài nguyên lúc tấn công (theo thư viện liều). Mỗi tấn công chạy ở ≥ 3 mức tranh chấp.
- **Oracle:** mỗi tấn công phải có cách xác nhận độc lập rằng nó thật sự xảy ra (log công cụ tấn công, kết nối mạng quan sát được, file bị tạo, tiến trình con sinh ra). Không có oracle thì không đưa vào dataset.
- **Hai lớp:** lớp A đổi CHUỖI syscall (tấn công kinh điển, baseline chuỗi bắt được); lớp B giữ chuỗi, chỉ đổi NHỊP (chỉ thời gian thấy). Lớp B là trọng tâm của đề tài.

## 1. Lớp A — tấn công có đổi chuỗi (đối chứng)

Mục đích: xác nhận collector và baseline chuỗi hoạt động; làm mẫu "dễ" để so.

| ID | Kỹ thuật (ATT&CK) | Công cụ | Mô tả | Oracle |
|---|---|---|---|---|
| A1 | T1190 khai thác dịch vụ | Metasploit | khai thác một lỗ hổng đã biết trên dịch vụ của máy nạn nhân, lấy shell | phiên Meterpreter mở; log msfconsole |
| A2 | T1059 thực thi lệnh | thủ công qua shell | chạy chuỗi lệnh sau khai thác (whoami, id, uname) | lịch sử lệnh; exec trong luồng proc |
| A3 | T1105 tải công cụ vào | curl/wget trong lab | kéo một file từ máy tấn công về nạn nhân | file xuất hiện; kết nối tới .20 |

## 2. Lớp B — tấn công giữ chuỗi, đổi nhịp (TRỌNG TÂM)

Mục đích: tấn công mà chuỗi syscall trông như benign, chỉ nhịp thời gian khác. Mỗi mục chạy ở nhiều nhịp (nhanh → rất chậm) để tìm ngưỡng mà phát hiện theo thời gian còn thấy.

| ID | Kỹ thuật (ATT&CK) | Công cụ | Trục nhịp | Oracle |
|---|---|---|---|---|
| B1 | T1071 C2 qua kênh ứng dụng | beacon tự viết hoặc Sliver | khoảng beacon: 1s, 10s, 60s, 300s, có jitter 0–50% | kết nối định kỳ tới .20; log beacon |
| B2 | T1030 giới hạn kích thước + T1048 rò dữ liệu | script tự viết | rò 1 file lớn thành từng mẩu nhỏ, nghỉ giữa các mẩu: 1s, 10s, 60s | byte tới .20 khớp kích thước file |
| B3 | T1110.001 dò mật khẩu chậm | hydra/medusa giới hạn tốc độ | khoảng giữa hai lần thử: 1s, 30s, 300s | log thử đăng nhập trên nạn nhân |
| B4 | T1496 lạm dụng tài nguyên bị hãm | stress-ng hãm tốc | đào coin giả lập chạy ngắt quãng: bật 2s nghỉ 20s, v.v. | tiến trình chạy theo chu kỳ |
| B5 | T1053.003 cron | cron trên nạn nhân | tác vụ độc chạy theo lịch thưa: mỗi 5 phút, mỗi 30 phút | cron log; tiến trình sinh đúng nhịp |
| B6 | T1057/T1083 trinh sát rải rác | script tự viết | lệnh trinh sát rải thưa theo thời gian thay vì dồn một đợt | exec thưa trong luồng proc |

## 2b. Benign song sinh (BẮT BUỘC, chống học nhầm "cứ thưa là tấn công")

Mỗi tấn công lớp B phải có một phiên **benign cùng nhịp nhưng vô hại**, để mô hình không học rằng "thưa = độc". Thu trong cùng điều kiện, gán nhãn benign.

| ID | Song sinh benign của | Mô tả vô hại |
|---|---|---|
| N1 | B1 (beacon C2) | một client hợp lệ poll API theo chu kỳ cố định (health check, đồng bộ cấu hình) ở cùng khoảng 10s/60s/300s |
| N2 | B2 (rò dữ liệu từng mẩu) | một job backup/rsync hợp lệ truyền file lớn theo mẩu, nghỉ giữa các mẩu |
| N3 | B3 (dò mật khẩu chậm) | đăng nhập SSH hợp lệ thưa thớt của quản trị viên |
| N4 | B4 (đào coin hãm tốc) | một tác vụ tính toán hợp lệ chạy ngắt quãng (ví dụ nén log định kỳ) |
| N5 | B5 (cron độc) | cron job hợp lệ chạy cùng nhịp (log rotate, cập nhật) |
| N6 | B6 (trinh sát rải rác) | script giám sát hợp lệ chạy lệnh hệ thống rải theo thời gian |

Benign song sinh ghi nhãn như một phiên benign bình thường (không nằm trong cửa sổ tấn công), nhưng đánh dấu cột `song_sinh_cua` = ID tấn công tương ứng để phân tích riêng.

## 3. Lớp C — tấn công né tránh thích nghi (cho Bài 2, giai đoạn sau)

Mục đích: kẻ tấn công biết có bộ phát hiện theo thời gian và cố lách.

| ID | Mô tả | Điều kiện |
|---|---|---|
| C1 | giãn nhịp ngay dưới ngưỡng phát hiện (sau khi biết ngưỡng) | chạy sau khi có mô hình |
| C2 | tự tạo tranh chấp (chạy stress song song) để "hợp thức hoá" nhịp chậm, đánh lừa mô hình có điều kiện | kiểm tra chéo kênh (hướng C của Bài 2) |
| C3 | làm mù ring buffer: bơm nhiều syscall rác để đẩy tràn bộ đệm trong lúc tấn công | collector ghi GAP_BEFORE; đo "thời gian mù" |

## 4. Dựng lại kịch bản công khai (để so với dữ liệu gốc)

- Dựng lại các kịch bản CVE của LID-DS 2021 trong lab, chạy kèm collector của ta, để có tấn công CVE thật kèm phân rã thời gian, đối chiếu được với bản ghi gốc của LID-DS.
- **Việc treo:** xác minh danh sách CVE cụ thể trên repo LID-DS 2021 trước khi chốt (không chép từ trí nhớ).

## 5. Ghi nhãn mỗi lần chạy (bắt buộc)

Mỗi lần chạy sinh một dòng trong `lab/nhan-tan-cong.tsv`:
```
run_id  lop(A/B/C/N)  id(A1../N1..)  att_ck  cong_cu  nhip_tham_so  muc_tranh_chap  song_sinh_cua  t_bat_dau_mono_ns  t_ket_thuc_mono_ns  t_bat_dau_wall  t_ket_thuc_wall  oracle_ket_qua  ghi_chu
```

## 6. An toàn và đạo đức

- Chỉ dùng công cụ tấn công mã nguồn mở, không dùng mẫu mã độc thu từ ngoài.
- Lab cô lập mạng; máy tấn công không ra được production hay internet.
- Không có dữ liệu người dùng thật trên máy nạn nhân lab.
- Ghi rõ trong bài: tấn công do nhóm tự dàn dựng, môi trường kiểm soát.
