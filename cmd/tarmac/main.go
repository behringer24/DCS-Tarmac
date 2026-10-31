// Command tarmac bundles modular Lua sources into a single DCS mission
// script and runs their tests against a DCS API mock.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/behringer24/DCS-Tarmac/internal/bundle"
	"github.com/behringer24/DCS-Tarmac/internal/project"
	"github.com/behringer24/DCS-Tarmac/internal/runner"
)

const usage = `tarmac - build and test tool for DCS World Lua scripts

Usage:
  tarmac build [-p tarmac.json]                 bundle the modules into one script
  tarmac check [-p tarmac.json]                 check all modules (Lua 5.1 syntax)
  tarmac test  [-p tarmac.json] [-v] [filter]   build, then run the Lua tests
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	cmd := os.Args[1]
	flags := flag.NewFlagSet(cmd, flag.ExitOnError)
	projectFile := flags.String("p", "tarmac.json", "project file")
	verbose := flags.Bool("v", false, "print the DCS log of every test")
	flags.Usage = func() { fmt.Fprint(os.Stderr, usage) }
	_ = flags.Parse(os.Args[2:])

	p, err := project.Load(*projectFile)
	if err != nil {
		fail(err)
	}

	switch cmd {
	case "build":
		build(p)
	case "check":
		modules, err := bundle.Discover(p.Sources)
		if err != nil {
			fail(err)
		}
		errs := bundle.CheckAll(modules)
		for _, e := range errs {
			fmt.Fprintln(os.Stderr, e)
		}
		if len(errs) > 0 {
			os.Exit(1)
		}
		fmt.Printf("%d modules ok\n", len(modules))
	case "test":
		build(p)
		sum, err := runner.Run(p, flags.Args(), *verbose)
		if err != nil {
			fail(err)
		}
		fmt.Printf("\n%d files, %d passed, %d failed\n", sum.Files, sum.Passed, sum.Failed)
		if sum.Failed > 0 || sum.Files == 0 {
			os.Exit(1)
		}
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
}

func build(p *project.Project) {
	res, err := bundle.Build(p)
	if err != nil {
		fail(err)
	}
	fmt.Printf("built %s (%d modules)\n", res.Output, len(res.Modules))
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
