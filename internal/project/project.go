// Package project loads the tarmac.json file that describes how a Lua
// project is bundled and tested.
package project

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Project is the parsed content of a tarmac.json file. All paths are
// resolved relative to the directory containing the project file.
type Project struct {
	Name    string   `json:"name"`
	Entry   string   `json:"entry"`
	Sources []string `json:"sources"`
	Output  string   `json:"output"`
	Banner  []string `json:"banner"`
	Test    Test     `json:"test"`

	// Dir is the directory of the project file.
	Dir string `json:"-"`
}

// Test configures the Lua test runner.
type Test struct {
	// Dir holds the *_test.lua files.
	Dir string `json:"dir"`
	// Setup lists Lua files executed before every test file, e.g. the DCS
	// mock and the test harness.
	Setup []string `json:"setup"`
	// Globals lists the global names the bundle may create while strict
	// mode is active.
	Globals []string `json:"globals"`
}

// Load reads and validates a project file.
func Load(path string) (*Project, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p Project
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	p.Dir = filepath.Dir(abs)

	if p.Entry == "" {
		return nil, fmt.Errorf("%s: missing \"entry\"", path)
	}
	if len(p.Sources) == 0 {
		return nil, fmt.Errorf("%s: missing \"sources\"", path)
	}
	if p.Output == "" {
		return nil, fmt.Errorf("%s: missing \"output\"", path)
	}
	for i, s := range p.Sources {
		p.Sources[i] = p.Resolve(s)
	}
	p.Output = p.Resolve(p.Output)
	if p.Test.Dir != "" {
		p.Test.Dir = p.Resolve(p.Test.Dir)
	}
	for i, s := range p.Test.Setup {
		p.Test.Setup[i] = p.Resolve(s)
	}
	return &p, nil
}

// Resolve turns a project relative path into an absolute one.
func (p *Project) Resolve(path string) string {
	if filepath.IsAbs(path) {
		return filepath.Clean(path)
	}
	return filepath.Join(p.Dir, filepath.FromSlash(path))
}
