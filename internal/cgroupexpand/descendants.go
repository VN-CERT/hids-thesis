package cgroupexpand

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// DescendantIDs tra ve id (inode) cua moi thu muc cgroup v2 nam duoi cac root,
// gom ca chinh root.
func DescendantIDs(roots []string) ([]uint64, error) {
	seen := make(map[uint64]struct{})
	for _, root := range roots {
		root = filepath.Clean(root)
		if err := walk(root, seen); err != nil {
			return nil, err
		}
	}
	out := make([]uint64, 0, len(seen))
	for id := range seen {
		out = append(out, id)
	}
	return out, nil
}

func walk(root string, seen map[uint64]struct{}) error {
	info, err := os.Stat(root)
	if err != nil {
		return fmt.Errorf("doc cgroup %s: %w", root, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("%s khong phai thu muc cgroup", root)
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return fmt.Errorf("khong lay duoc inode cua %s", root)
	}
	seen[st.Ino] = struct{}{}

	entries, err := os.ReadDir(root)
	if err != nil {
		return fmt.Errorf("doc %s: %w", root, err)
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if name == ".." || name == "." {
			continue
		}
		child := filepath.Join(root, name)
		if err := walk(child, seen); err != nil {
			return err
		}
	}
	return nil
}
