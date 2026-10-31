// Package luasrc contains a small Lua tokenizer used to find require calls
// and syntax that DCS (Lua 5.1) does not support, without being fooled by
// comments or string literals.
package luasrc

import (
	"fmt"
	"strings"
)

// Kind classifies a token.
type Kind int

const (
	Ident Kind = iota
	String
	Number
	Symbol
)

// Token is a lexical element together with the line it starts on.
type Token struct {
	Kind Kind
	Text string
	Line int
}

// Tokenize splits Lua source into tokens. Comments and whitespace are
// dropped. String tokens carry their (unescaped) content.
func Tokenize(src string) ([]Token, error) {
	var tokens []Token
	line := 1
	i := 0
	n := len(src)

	for i < n {
		c := src[i]
		switch {
		case c == '\n':
			line++
			i++
		case c == ' ' || c == '\t' || c == '\r' || c == '\f' || c == '\v':
			i++
		case c == '-' && i+1 < n && src[i+1] == '-':
			i += 2
			if level, ok := longBracket(src, i); ok {
				end, lines, err := skipLong(src, i, level)
				if err != nil {
					return nil, fmt.Errorf("line %d: unfinished long comment", line)
				}
				line += lines
				i = end
			} else {
				for i < n && src[i] != '\n' {
					i++
				}
			}
		case c == '[':
			if level, ok := longBracket(src, i); ok {
				start := line
				end, lines, err := skipLong(src, i, level)
				if err != nil {
					return nil, fmt.Errorf("line %d: unfinished long string", line)
				}
				open := level + 2
				body := src[i+open : end-open]
				body = strings.TrimPrefix(strings.TrimPrefix(body, "\r"), "\n")
				tokens = append(tokens, Token{String, body, start})
				line += lines
				i = end
			} else {
				tokens = append(tokens, Token{Symbol, "[", line})
				i++
			}
		case c == '"' || c == '\'':
			start := line
			var b strings.Builder
			i++
			for {
				if i >= n || src[i] == '\n' {
					return nil, fmt.Errorf("line %d: unfinished string", start)
				}
				if src[i] == c {
					i++
					break
				}
				if src[i] == '\\' && i+1 < n {
					if src[i+1] == '\n' {
						line++
					}
					b.WriteByte(src[i+1])
					i += 2
					continue
				}
				b.WriteByte(src[i])
				i++
			}
			tokens = append(tokens, Token{String, b.String(), start})
		case isIdentStart(c):
			j := i + 1
			for j < n && isIdentPart(src[j]) {
				j++
			}
			tokens = append(tokens, Token{Ident, src[i:j], line})
			i = j
		case isDigit(c) || (c == '.' && i+1 < n && isDigit(src[i+1])):
			j := i + 1
			for j < n && (isIdentPart(src[j]) || src[j] == '.' ||
				((src[j] == '+' || src[j] == '-') && (src[j-1] == 'e' || src[j-1] == 'E' || src[j-1] == 'p' || src[j-1] == 'P'))) {
				j++
			}
			tokens = append(tokens, Token{Number, src[i:j], line})
			i = j
		default:
			if c == ':' && i+1 < n && src[i+1] == ':' {
				tokens = append(tokens, Token{Symbol, "::", line})
				i += 2
			} else {
				tokens = append(tokens, Token{Symbol, string(c), line})
				i++
			}
		}
	}
	return tokens, nil
}

// Requires returns the module names passed as literal strings to require.
func Requires(tokens []Token) []string {
	var names []string
	for i := 0; i < len(tokens); i++ {
		t := tokens[i]
		if t.Kind != Ident || t.Text != "require" {
			continue
		}
		// require is only a call when it is not used as a field (x.require)
		if i > 0 && tokens[i-1].Kind == Symbol && (tokens[i-1].Text == "." || tokens[i-1].Text == ":") {
			continue
		}
		j := i + 1
		if j < len(tokens) && tokens[j].Kind == Symbol && tokens[j].Text == "(" {
			j++
		}
		if j < len(tokens) && tokens[j].Kind == String {
			names = append(names, tokens[j].Text)
		}
	}
	return names
}

// Lua51Problems reports syntax that the gopher-lua parser accepts but the
// Lua 5.1 runtime used by DCS rejects.
func Lua51Problems(tokens []Token) []string {
	var problems []string
	for i := 0; i < len(tokens); i++ {
		t := tokens[i]
		if t.Kind == Symbol && t.Text == "::" {
			problems = append(problems, fmt.Sprintf("line %d: labels (::name::) are not available in Lua 5.1", t.Line))
			// skip the closing "::" of the same label
			if i+2 < len(tokens) && tokens[i+1].Kind == Ident && tokens[i+2].Text == "::" {
				i += 2
			}
			continue
		}
		if t.Kind == Ident && t.Text == "goto" && i+1 < len(tokens) && tokens[i+1].Kind == Ident {
			problems = append(problems, fmt.Sprintf("line %d: goto is not available in Lua 5.1", t.Line))
		}
	}
	return problems
}

// longBracket checks for an opening long bracket ([[, [=[, ...) at pos and
// returns its level (number of '=').
func longBracket(src string, pos int) (int, bool) {
	if pos >= len(src) || src[pos] != '[' {
		return 0, false
	}
	j := pos + 1
	for j < len(src) && src[j] == '=' {
		j++
	}
	if j < len(src) && src[j] == '[' {
		return j - pos - 1, true
	}
	return 0, false
}

// skipLong returns the index after the closing bracket of a long string or
// comment starting at pos, and the number of newlines it spans.
func skipLong(src string, pos, level int) (int, int, error) {
	closing := "]" + strings.Repeat("=", level) + "]"
	start := pos + level + 2
	k := strings.Index(src[start:], closing)
	if k < 0 {
		return 0, 0, fmt.Errorf("unterminated")
	}
	end := start + k + len(closing)
	return end, strings.Count(src[pos:end], "\n"), nil
}

func isIdentStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func isIdentPart(c byte) bool {
	return isIdentStart(c) || isDigit(c)
}

func isDigit(c byte) bool {
	return c >= '0' && c <= '9'
}
