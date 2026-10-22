// Package hostsample doc /proc/stat, loadavg, pressure va cgroup v2 moi giay.
package hostsample

import (
	"strconv"
	"time"
)

// CgroupTarget la mot cgroup dich (-cgroup).
type CgroupTarget struct {
	Path string
	ID   uint64
}

// PressureSome gia tri avg10 va total cua dong "some".
type PressureSome struct {
	Avg10   string
	Total   string
	Present bool
}

// CgroupSample so lieu cgroup v2 doc tu thu muc cgroup.
type CgroupSample struct {
	Path           string
	UsageUsec      string
	NrPeriods      string
	NrThrottled    string
	ThrottledUsec  string
	MemoryCurrent  string
	CPUPressTotal  string
	MemPressureTot string
}

// Sample mot dong host stats.
type Sample struct {
	MonoNs    uint64
	Wall      time.Time
	CPUUser   uint64
	CPUNice   uint64
	CPUSys    uint64
	CPUIdle   uint64
	CPUIOWait uint64
	CPUIrq    uint64
	CPUSoft   uint64
	CPUSteal  uint64
	Load1     string
	PressCPU  PressureSome
	PressMem  PressureSome
	PressIO   PressureSome
	Cgroups   []CgroupSample
	// M6c: delta bo dem PMU user tren moi CPU trong 1 giay; "na" khi PMU tat.
	PMUInstDelta string
	PMUCycDelta  string
}

// HeaderTSV tra ve dong tieu de cot (tab-separated).
func HeaderTSV(cgroups []CgroupTarget) []string {
	cols := []string{
		"mono_ns", "wall",
		"cpu_user", "cpu_nice", "cpu_system", "cpu_idle", "cpu_iowait", "cpu_irq", "cpu_softirq", "cpu_steal",
		"load1",
		"press_cpu_some_avg10", "press_cpu_some_total",
		"press_mem_some_avg10", "press_mem_some_total",
		"press_io_some_avg10", "press_io_some_total",
	}
	for _, cg := range cgroups {
		p := sanitizeCol(cg.Path)
		cols = append(cols,
			p+"_cpu_usage_usec", p+"_cpu_nr_periods", p+"_cpu_nr_throttled", p+"_cpu_throttled_usec",
			p+"_memory_current", p+"_cpu_pressure_total", p+"_memory_pressure_total",
		)
	}
	// M6c: hai cot PMU o CUOI dong.
	cols = append(cols, "pmu_inst_delta", "pmu_cyc_delta")
	return cols
}

// RowTSV chuyen Sample thanh cac cot string.
func (s Sample) RowTSV() []string {
	row := []string{
		strconv.FormatUint(s.MonoNs, 10),
		s.Wall.Format(time.RFC3339Nano),
		strconv.FormatUint(s.CPUUser, 10),
		strconv.FormatUint(s.CPUNice, 10),
		strconv.FormatUint(s.CPUSys, 10),
		strconv.FormatUint(s.CPUIdle, 10),
		strconv.FormatUint(s.CPUIOWait, 10),
		strconv.FormatUint(s.CPUIrq, 10),
		strconv.FormatUint(s.CPUSoft, 10),
		strconv.FormatUint(s.CPUSteal, 10),
		s.Load1,
		s.PressCPU.Avg10, s.PressCPU.Total,
		s.PressMem.Avg10, s.PressMem.Total,
		s.PressIO.Avg10, s.PressIO.Total,
	}
	for _, cg := range s.Cgroups {
		row = append(row,
			cg.UsageUsec, cg.NrPeriods, cg.NrThrottled, cg.ThrottledUsec,
			cg.MemoryCurrent, cg.CPUPressTotal, cg.MemPressureTot,
		)
	}
	inst, cyc := s.PMUInstDelta, s.PMUCycDelta
	if inst == "" {
		inst = "na"
	}
	if cyc == "" {
		cyc = "na"
	}
	row = append(row, inst, cyc)
	return row
}
