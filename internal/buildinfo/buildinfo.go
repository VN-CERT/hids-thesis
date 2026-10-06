// Package buildinfo tra ve commit git cua binary dang chay.
package buildinfo

import (
	"fmt"
	"io"
	"runtime/debug"
	"strings"
)

// Commit co the duoc dat luc build bang -ldflags "-X hids/internal/buildinfo.Commit=...".
var Commit string

const dirtySuffix = "-dirty"

// Info mo ta commit git cua binary.
type Info struct {
	Commit string // vi du "14c2ee1" hoac "unknown"
	Dirty  bool   // cay lam viec co thay doi chua commit luc build
}

// String tra ve chuoi ghi vao header file du lieu.
func (i Info) String() string {
	if i.Dirty {
		return i.Commit + dirtySuffix
	}
	return i.Commit
}

// Git tra ve commit git. Uu tien gia tri dat luc build, sau do den thong tin
// VCS do Go nhung san vao binary.
func Git() Info {
	if Commit != "" {
		rev, found := strings.CutSuffix(Commit, dirtySuffix)
		return Info{Commit: rev, Dirty: found}
	}

	info, ok := debug.ReadBuildInfo()
	if !ok {
		return Info{Commit: "unknown"}
	}

	var out Info
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			out.Commit = s.Value
		case "vcs.modified":
			out.Dirty = s.Value == "true"
		}
	}
	if out.Commit == "" {
		out.Commit = "unknown"
	}
	return out
}

// GitCommit tra ve chuoi commit de ghi vao header file du lieu.
func GitCommit() string { return Git().String() }

// WarnIfDirty in canh bao khi binary duoc build tu cay lam viec con thay doi
// chua commit, vi khi do du lieu ghi ra khong dung lai duoc tu git.
func WarnIfDirty(w io.Writer) {
	info := Git()
	if !info.Dirty {
		return
	}
	fmt.Fprintf(w, "CANH BAO: binary build tu cay lam viec con thay doi chua commit (git_commit=%s).\n", info)
	fmt.Fprintf(w, "CANH BAO: du lieu ghi ra khong tai lap duoc tu git. Commit truoc khi do that.\n")
}
