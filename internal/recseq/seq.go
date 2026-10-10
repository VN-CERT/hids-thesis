// Package recseq phan tich day seq theo CPU trong file .bin.
package recseq

import (
	"bufio"
	"fmt"
	"os"
	"slices"
	"sort"

	"hids/internal/recfmt"
)

// Analysis ket qua phan tich seq tren mot CPU.
type Analysis struct {
	Records  int64
	Min      uint32
	Max      uint32
	Holes    int64
	Missing  uint64
	Dup      int64
	Wrapped  bool
	SeqLast  uint32
	HasStats bool
	Drops    uint64
}

// Analyze sap xep day seq va dem lo hong noi bo (modulo 2^32).
func Analyze(seqs []uint32) Analysis {
	var a Analysis
	a.Records = int64(len(seqs))
	if len(seqs) == 0 {
		return a
	}

	slices.Sort(seqs)
	if len(seqs) == 1 {
		a.Min, a.Max = seqs[0], seqs[0]
		return a
	}

	start := 0
	biggest := uint64(seqs[0]) + (1 << 32) - uint64(seqs[len(seqs)-1])
	for i := 0; i+1 < len(seqs); i++ {
		d := uint64(seqs[i+1]) - uint64(seqs[i])
		if d > biggest {
			biggest = d
			start = i + 1
		}
	}
	a.Wrapped = start != 0
	a.Min = seqs[start]
	a.Max = seqs[(start+len(seqs)-1)%len(seqs)]

	for i := 0; i+1 < len(seqs); i++ {
		cur := seqs[(start+i)%len(seqs)]
		next := seqs[(start+i+1)%len(seqs)]
		d := uint64(next-cur) & 0xffffffff
		switch {
		case d == 0:
			a.Dup++
		case d > 1:
			a.Holes++
			a.Missing += d - 1
		}
	}
	return a
}

// Finish bo sung lo hong dau day (tu 1) va cuoi day (den seq_cuoi tu stats).
func (a *Analysis) Finish() {
	if a.Records == 0 {
		if a.HasStats {
			a.Missing = uint64(a.SeqLast)
			if a.SeqLast > 0 {
				a.Holes = 1
			}
		}
		return
	}
	if !a.Wrapped && a.Min > 1 {
		a.Holes++
		a.Missing += uint64(a.Min) - 1
	}
	if a.HasStats {
		if d := uint64(a.SeqLast-a.Max) & 0xffffffff; d > 0 {
			a.Holes++
			a.Missing += d
		}
	}
}

// SeqByCPU doc toan bo file .bin va gom seq theo CPU (tu flags bit8..15).
func SeqByCPU(path string) (map[int][]uint32, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer f.Close()

	br := bufio.NewReaderSize(f, 4*1024*1024)
	header, err := recfmt.ReadHeader(br)
	if err != nil {
		return nil, 0, fmt.Errorf("%s: %w", path, err)
	}
	recordSize, err := recfmt.RecordSizeFromHeader(header)
	if err != nil {
		return nil, 0, fmt.Errorf("%s: %w", path, err)
	}
	payload, err := recfmt.RecordPayloadReader(header, br)
	if err != nil {
		return nil, 0, fmt.Errorf("%s: %w", path, err)
	}

	seqByCPU := map[int][]uint32{}
	var total int64
	_, _, err = recfmt.ForEach(payload, recordSize, func(r recfmt.Record) error {
		total++
		seqByCPU[r.CPU()] = append(seqByCPU[r.CPU()], r.Seq)
		return nil
	})
	if err != nil {
		return nil, 0, err
	}
	return seqByCPU, total, nil
}

// FileReport phan tich mot file .bin.
type FileReport struct {
	Path     string
	Total    int64
	PerCPU   map[int]*Analysis
	StatsErr error
}

// AnalyzeFile chay Analyze+Finish cho tung CPU, ket hop .stats.
func AnalyzeFile(path string) (FileReport, error) {
	seqByCPU, total, err := SeqByCPU(path)
	if err != nil {
		return FileReport{}, err
	}
	fr := FileReport{Path: path, Total: total, PerCPU: map[int]*Analysis{}}
	for cpu, seqs := range seqByCPU {
		a := Analyze(seqs)
		fr.PerCPU[cpu] = &a
	}
	stats, statsErr := recfmt.ReadStats(path + recfmt.StatsSuffix)
	fr.StatsErr = statsErr
	if statsErr == nil {
		for _, c := range stats.PerCPU {
			a, ok := fr.PerCPU[c.CPU]
			if !ok {
				if c.SeqLast == 0 && c.Drops == 0 {
					continue
				}
				a = &Analysis{}
				fr.PerCPU[c.CPU] = a
			}
			a.HasStats = true
			a.SeqLast = c.SeqLast
			a.Drops = c.Drops
		}
	}
	for _, a := range fr.PerCPU {
		a.Finish()
	}
	return fr, nil
}

// BoundaryGap lo hong seq giua hai file lien ke tren mot CPU.
type BoundaryGap struct {
	CPU          int
	PrevFile     string
	NextFile     string
	PrevMax      uint32
	NextMin      uint32
	Holes        int64
	Missing      uint64
	PrevHasSeq   bool
	NextHasSeq   bool
}

// ChainReport ket qua rec-chain.
type ChainReport struct {
	Files      []FileReport
	Boundaries []BoundaryGap
}

// ChainBins phan tich tung file va kiem seq tai ranh gioi file lien ke.
func ChainBins(files []string) (ChainReport, error) {
	if len(files) == 0 {
		return ChainReport{}, fmt.Errorf("can it nhat mot file .bin")
	}
	var rep ChainReport
	for _, path := range files {
		fr, err := AnalyzeFile(path)
		if err != nil {
			return rep, err
		}
		rep.Files = append(rep.Files, fr)
	}
	for i := 0; i+1 < len(rep.Files); i++ {
		rep.Boundaries = append(rep.Boundaries, boundaryGaps(rep.Files[i], rep.Files[i+1])...)
	}
	return rep, nil
}

func boundaryGaps(prev, next FileReport) []BoundaryGap {
	cpus := map[int]struct{}{}
	for cpu := range prev.PerCPU {
		cpus[cpu] = struct{}{}
	}
	for cpu := range next.PerCPU {
		cpus[cpu] = struct{}{}
	}
	list := make([]int, 0, len(cpus))
	for cpu := range cpus {
		list = append(list, cpu)
	}
	sort.Ints(list)

	var out []BoundaryGap
	for _, cpu := range list {
		g := BoundaryGap{CPU: cpu, PrevFile: prev.Path, NextFile: next.Path}
		if pa, ok := prev.PerCPU[cpu]; ok && pa.Records > 0 {
			g.PrevMax = pa.Max
			g.PrevHasSeq = true
		}
		if na, ok := next.PerCPU[cpu]; ok && na.Records > 0 {
			g.NextMin = na.Min
			g.NextHasSeq = true
		}
		if g.PrevHasSeq && g.NextHasSeq {
			d := uint64(g.NextMin-g.PrevMax) & 0xffffffff
			if d > 1 {
				g.Holes = 1
				g.Missing = d - 1
			}
		}
		out = append(out, g)
	}
	return out
}
