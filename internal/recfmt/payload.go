package recfmt

import (
	"fmt"
	"io"
	"strconv"

	"github.com/klauspost/compress/zstd"
)

// RecordPayloadReader tra ve reader cho phan ban ghi nhi phan sau header.
// Neu header co zstd_level > 0 thi giai nen luong zstd.
func RecordPayloadReader(h Header, r io.Reader) (io.Reader, error) {
	raw := h.Get("zstd_level")
	if raw == "" || raw == "0" {
		return r, nil
	}
	lvl, err := strconv.Atoi(raw)
	if err != nil || lvl < 1 || lvl > 3 {
		return nil, fmt.Errorf("zstd_level khong hop le trong header: %q", raw)
	}
	dec, err := zstd.NewReader(r)
	if err != nil {
		return nil, fmt.Errorf("mo giai nen zstd: %w", err)
	}
	return dec, nil
}
