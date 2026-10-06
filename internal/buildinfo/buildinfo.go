// Package buildinfo tra ve commit git cua binary dang chay.
package buildinfo

import "runtime/debug"

// Commit co the duoc dat luc build bang -ldflags "-X hids/internal/buildinfo.Commit=...".
var Commit string

// GitCommit tra ve commit git. Uu tien gia tri dat luc build, sau do den thong tin
// VCS do Go nhung san vao binary. Khong xac dinh duoc thi tra ve "unknown".
func GitCommit() string {
	if Commit != "" {
		return Commit
	}

	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}

	var rev, modified string
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			rev = s.Value
		case "vcs.modified":
			modified = s.Value
		}
	}
	if rev == "" {
		return "unknown"
	}
	if modified == "true" {
		return rev + "-dirty"
	}
	return rev
}
