// Package bpflog in loi verifier/libbpf nguyen van ra stderr va ghi vao file log.
package bpflog

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/cilium/ebpf"
)

// Format tra ve noi dung loi day du. Loi verifier duoc in nguyen van, khong cat bot.
func Format(err error) string {
	var ve *ebpf.VerifierError
	if errors.As(err, &ve) {
		return fmt.Sprintf("%+v", ve)
	}
	return err.Error()
}

// Report in loi ra stderr va ghi them vao logPath.
func Report(logPath, context string, err error) {
	ReportTo(os.Stderr, logPath, context, err)
}

// ReportTo in loi ra w va ghi them vao logPath.
func ReportTo(w io.Writer, logPath, context string, err error) {
	text := Format(err)
	fmt.Fprintf(w, "%s:\n%s\n", context, text)

	if mkErr := os.MkdirAll(filepath.Dir(logPath), 0o755); mkErr != nil {
		fmt.Fprintf(w, "khong tao duoc thu muc log: %v\n", mkErr)
		return
	}
	f, openErr := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if openErr != nil {
		fmt.Fprintf(w, "khong mo duoc %s: %v\n", logPath, openErr)
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "=== %s %s ===\n%s\n", time.Now().Format(time.RFC3339), context, text)
}

// Note in mot dong thong bao ra w va ghi them vao logPath. Dung cho canh bao
// luc dang chay, vi du mat ban ghi vi ring buffer day.
func Note(w io.Writer, logPath, line string) {
	fmt.Fprintln(w, line)

	if mkErr := os.MkdirAll(filepath.Dir(logPath), 0o755); mkErr != nil {
		return
	}
	f, openErr := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if openErr != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "%s %s\n", time.Now().Format(time.RFC3339), line)
}
