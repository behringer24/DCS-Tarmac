// Package runner executes Lua test files against a built bundle inside an
// embedded Lua 5.1 VM (gopher-lua), so DCS scripts can be tested without
// starting DCS.
package runner

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"github.com/behringer24/DCS-Tarmac/internal/project"
	lua "github.com/yuin/gopher-lua"
)

// Summary counts the results of a test run.
type Summary struct {
	Files  int
	Passed int
	Failed int
}

// Run executes all *_test.lua files of the project whose name contains one
// of the filters (all files when no filter is given).
func Run(p *project.Project, filters []string, verbose bool) (Summary, error) {
	var sum Summary
	if p.Test.Dir == "" {
		return sum, fmt.Errorf("project has no test.dir")
	}
	files, err := filepath.Glob(filepath.Join(p.Test.Dir, "*_test.lua"))
	if err != nil {
		return sum, err
	}
	sort.Strings(files)
	for _, file := range files {
		if !matches(filepath.Base(file), filters) {
			continue
		}
		sum.Files++
		fmt.Printf("%s\n", filepath.Base(file))
		passed, failed, err := runFile(p, file, verbose)
		if err != nil {
			fmt.Printf("  ERROR %v\n", err)
			failed++
		}
		sum.Passed += passed
		sum.Failed += failed
	}
	return sum, nil
}

func runFile(p *project.Project, file string, verbose bool) (int, int, error) {
	L := lua.NewState()
	defer L.Close()

	cfg := L.NewTable()
	cfg.RawSetString("bundle", lua.LString(p.Output))
	cfg.RawSetString("file", lua.LString(file))
	cfg.RawSetString("verbose", lua.LBool(verbose))
	globals := L.NewTable()
	for _, g := range p.Test.Globals {
		globals.Append(lua.LString(g))
	}
	cfg.RawSetString("globals", globals)
	L.SetGlobal("__TARMAC", cfg)

	for _, setup := range p.Test.Setup {
		if err := L.DoFile(setup); err != nil {
			return 0, 0, fmt.Errorf("setup %s: %w", filepath.Base(setup), err)
		}
	}
	if err := L.DoFile(file); err != nil {
		return 0, 0, err
	}

	run := L.G.Global.RawGetString("__tarmac_run")
	if run == lua.LNil {
		return 0, 0, fmt.Errorf("harness did not define __tarmac_run")
	}
	if err := L.CallByParam(lua.P{Fn: run, NRet: 2, Protect: true}); err != nil {
		return 0, 0, err
	}
	passed := int(lua.LVAsNumber(L.Get(-2)))
	failed := int(lua.LVAsNumber(L.Get(-1)))
	L.Pop(2)
	return passed, failed, nil
}

func matches(name string, filters []string) bool {
	if len(filters) == 0 {
		return true
	}
	for _, f := range filters {
		if strings.Contains(name, f) {
			return true
		}
	}
	return false
}
