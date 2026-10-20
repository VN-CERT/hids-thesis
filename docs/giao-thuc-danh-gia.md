# Giao thức đánh giá — chốt TRƯỚC khi thu dữ liệu

> Mốc commit của file này là bằng chứng rằng tiêu chí được chốt trước khi thấy kết quả.
> KHÔNG sửa tiêu chí sau khi đã nhìn kết quả mô hình. Mọi thay đổi phải ghi rõ lý do và ngày, giữ lại bản cũ.
> Phiên bản 0.2 — 20/10/2026.

## 1. Mục tiêu đánh giá

Chứng minh: phát hiện dựa trên các thành phần thời gian đã phân rã (và có điều kiện theo tranh chấp) **giữ tỉ lệ báo động giả ổn định khi tài nguyên bị tranh chấp**, trong khi vẫn bắt được tấn công "chậm và thưa" chỉ thể hiện qua nhịp thời gian.

## 2. Tiêu chí (thứ tự ưu tiên)

1. **Chính — độ ổn định báo động giả dưới tranh chấp.** Số báo động giả trên mỗi host-ngày (hoặc ARL) ở điều kiện có tranh chấp so với điều kiện không tranh chấp. So sánh giữa các phương pháp phải ở **cùng một điểm trên đường đánh đổi**: hoặc cố định độ phát hiện (cùng tỉ lệ phát hiện tấn công) rồi so báo động giả, hoặc cố định độ trễ phát hiện rồi so. KHÔNG so ở 'cùng ngưỡng thô', vì cùng ngưỡng cho độ phát hiện và độ trễ khác nhau giữa các mô hình. Phương pháp thắng nếu báo động giả **không tăng đáng kể** khi tranh chấp tăng, trong khi baseline trên Δt thô tăng, ở cùng điểm đánh đổi đó.
2. **Phụ 1 — độ phát hiện.** Tỉ lệ phát hiện tấn công đổi nhịp, ở cùng ngân sách báo động giả.
3. **Phụ 2 — AUC và độ trễ phát hiện** (thời gian từ lúc tấn công bắt đầu tới lúc có báo động).
4. **Ràng buộc — không kém ở điều kiện thường.** Trên dữ liệu không tranh chấp (LID-DS, lab rảnh), phương pháp phải **không kém** baseline. Đây là ràng buộc, không phải điểm bán.

## 3. Định nghĩa đo (chốt trước)

- **Báo động giả:** một cảnh báo phát ra trong cửa sổ KHÔNG có tấn công. Đơn vị: số cảnh báo trên mỗi host-ngày.
- **Phát hiện đúng:** có ít nhất một cảnh báo trong cửa sổ tấn công, trong vòng D giây kể từ lúc tấn công bắt đầu. D chốt = 300 giây (phù hợp mối đe doạ "chậm và thưa"; ghi rõ và giữ cố định).
- **Độ trễ phát hiện:** thời gian từ mốc bắt đầu tấn công (ghi theo nhãn) tới cảnh báo đầu tiên trong cửa sổ đó.
- **Đơn vị chấm điểm:** mỗi (tiến trình, cửa sổ thời gian). Kích thước cửa sổ trượt và bước trượt CHỐT SAU một thử nghiệm nhỏ trên dữ liệu benign + một tấn công beacon chậm (300 giây), chọn sao cho cửa sổ đủ dài để thấy ít nhất 2–3 chu kỳ beacon. Giá trị khởi điểm để thử: cửa sổ 60/300/600 giây, bước 10 giây. Một khi đã chốt (ghi ngày và lý do), KHÔNG đổi theo kết quả mô hình.
- **ARL (nếu dùng CUSUM):** số sự kiện trung bình giữa hai báo động giả liên tiếp trên luồng benign.

## 4. Chia dữ liệu — chống rò rỉ (theo Arp et al. 2022)

- **Theo thời gian:** tập huấn luyện là khoảng thời gian TRƯỚC, tập kiểm tra là khoảng thời gian SAU. Không bao giờ huấn luyện trên dữ liệu đến sau tập kiểm tra. Ghi rõ mốc cắt.
- **Theo máy:** không dùng cùng một máy vừa trong tập huấn luyện vừa trong tập kiểm tra cho cùng một loại dịch vụ, khi đo khả năng tổng quát hoá sang máy mới.
- **Chuẩn hoá:** mọi tham số chuẩn hoá (trung bình, phương sai, ngưỡng) tính CHỈ trên tập huấn luyện, áp sang tập kiểm tra. Không bao giờ tính trên toàn bộ.
- **Không điều chỉnh theo tập kiểm tra:** ngưỡng và siêu tham số chọn trên tập validation (một phần của tập huấn luyện theo thời gian), không chọn trên tập kiểm tra.

## 5. Baseline (bắt buộc có)

| Nhóm | Baseline | Vai trò |
|---|---|---|
| Kinh điển chuỗi | STIDE (n-gram cửa sổ syscall) | mốc lịch sử bắt buộc |
| Hiện đại chuỗi | DeepLog-style LSTM đoán syscall kế tiếp; một Transformer nhỏ cho syscall | cho thấy mô hình chuỗi mạnh vẫn không thấy tấn công đổi nhịp |
| Thời gian thô | TPP (RMTPP/THP) trên Δt thô | cho thấy tranh chấp làm báo động giả tăng |
| Kiểm định phân vị | ngưỡng phân vị trên thành phần đã phân rã (kiểu Landauer) | baseline rẻ, cùng đầu vào phân rã |
| Đề xuất | TPP có điều kiện theo tranh chấp (+ tăng cường dữ liệu) | phương pháp của đề tài |

Ablation chính: {Δt thô, phân rã, phân rã + điều kiện, + tăng cường} × {ngưỡng cố định, CUSUM nhiễu đo được}. Mọi mô hình học giữ cỡ nhỏ (huấn luyện CPU); cùng ngân sách tham số khi so, để lợi ích đến từ phân rã + điều kiện chứ không từ kích thước.

## 6. Dữ liệu

- **Benign — production:** thu liên tục ≥ 30 ngày trên ≥ 10 VM đa dạng (web, ứng dụng, cơ sở dữ liệu, worker K8s), nằm trên nhiều host ESXi. Dùng để ước báo động giả trên hành vi thật.
- **Benign — lab:** máy nạn nhân chạy tải sạch, dùng làm nền để chèn tấn công có nhãn.
- **Tấn công — lab cô lập:** theo danh mục tấn công, chạy ở nhiều mức tranh chấp (thư viện liều).
- **Công khai:** LID-DS 2021 (chỉ có Δt thô) để so ở điều kiện không phân rã.
- **Thư viện liều tranh chấp:** áp lên cả benign lẫn tấn công, các mức rq/steal/bộ nhớ/throttle theo đặc tả riêng.

## 7. Ước lượng báo động giả

- Khi một cấu hình cho 0 báo động giả trên N cửa sổ: báo cận trên bằng quy tắc "ba trên N" (xấp xỉ khoảng tin cậy 95% một phía là 3/N).
- Các máy trong cùng hệ thống KHÔNG độc lập (chung ảnh, chung host). Khi gộp host-ngày, ghi rõ giả định và báo khoảng tin cậy có tính tới việc không độc lập (ví dụ gộp theo cụm máy giống nhau).
- Báo cáo báo động giả theo từng loại dịch vụ, không chỉ gộp chung.

## 8. Báo cáo kết quả

- Mọi bảng kết quả in: giá trị đo, baseline so sánh, và điều kiện (mức tranh chấp).
- Báo cả điều kiện không tranh chấp (ràng buộc mục 2.4).
- Đường cong: báo động giả theo mức tranh chấp, cho từng phương pháp (đây là hình trung tâm của bài).
- Không chọn tạp chí hay ngưỡng theo kết quả.
- **Kết quả âm tính vẫn báo cáo.** Nếu conditioning (hoặc tăng cường dữ liệu) KHÔNG cải thiện rõ so với baseline, kết quả đó được báo cáo trung thực và trở thành một phát hiện của bài (giới hạn của hướng tiếp cận), KHÔNG được âm thầm đổi tiêu chí, đổi tập dữ liệu, hay thêm thủ thuật để biến thành dương tính. Việc đã chốt tiêu chí trước (mốc commit file này) là để bảo vệ chính điểm này.

## 9. Mối đe doạ tới tính hợp lệ (ghi trong bài)

- Một tổ chức, một hypervisor (VMware). Không khẳng định tổng quát sang KVM/Hyper-V khi chưa đo.
- Tấn công do nhóm tự dựng trong lab, không phải lưu lượng tấn công thật ngoài đời.
- Các VM production không độc lập thống kê.
- Dữ liệu benign có thể chứa bất thường chưa gán nhãn; nêu rõ cách xử lý.
