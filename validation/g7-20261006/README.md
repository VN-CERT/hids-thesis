# Dữ liệu kiểm chứng G7 — 2026-10-06

Bốn phép đo G7 của mốc M2, chạy bằng binary build từ commit `fc26d21`
(riêng G7c chạy lại bằng `acbcb92`, chỉ khác ở phần đếm tải nền của script).

| File | Nội dung |
|---|---|
| `g7a-ketqua.txt` | G7a: 1 sysinj, N=1.000.000, ring buffer 64 MiB |
| `g7b-ketqua.txt` | G7b: 24 sysinj song song, mỗi cái N=1.000.000, kèm stress-ng --cpu 24, ring buffer 64 MiB |
| `g7b-nho-ketqua.txt` | G7b-nho: giống G7b nhưng ring buffer 1 MiB, để ép ring buffer đầy |
| `g7c-ketqua.txt` | G7c: lọc theo cgroup container caddy, 70 giây, perf đo 60 giây |
| `g7d-ketqua.txt` | G7d: lọc theo cgroup CHA trong khi sysinj nằm trong cgroup CON, N=1.000.000 |
| `g7c-ketqua-lan1.txt` | G7c lần chạy đầu (script khi đó đếm sai số lần docker exec; số đo vẫn hợp lệ) |
| `*.bin.stats` | seq cuối và bộ đếm mất của từng CPU, đọc từ kernel lúc collector dừng |
| `g7-driver.log` | log của việc chạy nền `hids-g7` |

Các file `.bin` không lưu ở đây vì quá lớn (G7a 48 MB, G7b 1,15 GB,
G7b-nho 1,09 GB, G7c 22 MB). Chúng nằm trong `out/` và không được commit.

Lệnh chạy lại:

    sudo bash scripts/g7.sh a
    sudo bash scripts/g7.sh b
    sudo bash scripts/g7.sh b-nho
    sudo bash scripts/g7.sh c
