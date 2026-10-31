package luasrc

import (
	"reflect"
	"testing"
)

func TestRequiresIgnoresCommentsAndStrings(t *testing.T) {
	src := `
local a = require("tarmac.log")
local b = require 'tarmac.util'
-- local c = require("commented.out")
--[==[ require("long.comment") ]==]
local s = "require('inside.string')"
local d = obj.require("field.call")
local e = require[[tarmac.events]]
`
	tokens, err := Tokenize(src)
	if err != nil {
		t.Fatal(err)
	}
	got := Requires(tokens)
	want := []string{"tarmac.log", "tarmac.util", "tarmac.events"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestLua51Problems(t *testing.T) {
	src := "for i = 1, 3 do\n  goto continue\n  ::continue::\nend\nlocal goto = 1\n"
	tokens, err := Tokenize(src)
	if err != nil {
		t.Fatal(err)
	}
	problems := Lua51Problems(tokens)
	if len(problems) != 2 {
		t.Fatalf("expected 2 problems, got %v", problems)
	}
}

func TestLineNumbersSurviveLongComments(t *testing.T) {
	src := "--[[\none\ntwo\n]]\nlocal x = require('a')\n"
	tokens, err := Tokenize(src)
	if err != nil {
		t.Fatal(err)
	}
	for _, tok := range tokens {
		if tok.Text == "require" && tok.Line != 5 {
			t.Fatalf("require on line %d, want 5", tok.Line)
		}
	}
}

func TestUnfinishedString(t *testing.T) {
	if _, err := Tokenize("local s = 'open\n"); err == nil {
		t.Fatal("expected an error")
	}
}
