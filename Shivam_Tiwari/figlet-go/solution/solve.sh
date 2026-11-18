#!/bin/bash
set -euo pipefail

cd /workspace/repo

# Keep the FIGlet fonts in the repository, but move them out of the Python
# package so that the whole Python tree can be removed.
mkdir -p fonts
if [ -d pyfiglet/fonts ]; then
  mv pyfiglet/fonts/*.flf fonts/ 2>/dev/null || true
fi
if [ -d pyfiglet/fonts-standard ]; then
  cp -f pyfiglet/fonts-standard/*.flf fonts/ 2>/dev/null || true
fi

rm -rf pyfiglet test-fonts
find . -type f -name '*.py' -delete

cat > go.mod <<'GO_MOD_EOF'
module figlet

go 1.23
GO_MOD_EOF

cat > main.go <<'GO_MAIN_EOF'
package main

import (
	"embed"
	"fmt"
	"os"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

//go:embed fonts/*.flf
var fontFS embed.FS

const (
	smEqual     = 1
	smLowline   = 2
	smHierarchy = 4
	smPair      = 8
	smBigX      = 16
	smHardblank = 32
	smKern      = 64
	smSmush     = 128
)

// Translation tables lifted verbatim from pyfiglet's FigletString.
var reverseMap = [256]rune{
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
	0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
	0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x29, 0x28, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x5c,
	0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3e, 0x3d, 0x3c, 0x3f,
	0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
	0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5d, 0x2f, 0x5b, 0x5e, 0x5f,
	0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f,
	0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7d, 0x7c, 0x7b, 0x7e, 0x7f,
	0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
	0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f,
	0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf,
	0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf,
	0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf,
	0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf,
	0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef,
	0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
}

var flipMap = [256]rune{
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
	0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
	0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x5c,
	0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f,
	0x40, 0x56, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x57, 0x4e, 0x4f,
	0x62, 0x51, 0x62, 0x53, 0x54, 0x55, 0x41, 0x4d, 0x58, 0x59, 0x5a, 0x5b, 0x2f, 0x5d, 0x76, 0x2d,
	0x60, 0x61, 0x50, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x77, 0x6e, 0x6f,
	0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x5e, 0x6d, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f,
	0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
	0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f,
	0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf,
	0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf,
	0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf,
	0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf,
	0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef,
	0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
}

func isPySpace(r rune) bool {
	switch r {
	case '\x1c', '\x1d', '\x1e', '\x1f':
		return true
	}
	return unicode.IsSpace(r)
}

func pyStrip(s string) string {
	return strings.TrimFunc(s, isPySpace)
}

// splitLines mirrors Python's str.splitlines for the characters that can
// appear in font data and rendered output.
func splitLines(s string) []string {
	if s == "" {
		return nil
	}
	rs := []rune(s)
	var out []string
	start := 0
	for i := 0; i < len(rs); i++ {
		r := rs[i]
		brk := r == '\n' || r == '\r' || r == '\v' || r == '\f' ||
			r == '\x1c' || r == '\x1d' || r == '\x1e' || r == '\u0085' ||
			r == '\u2028' || r == '\u2029'
		if !brk {
			continue
		}
		out = append(out, string(rs[start:i]))
		if r == '\r' && i+1 < len(rs) && rs[i+1] == '\n' {
			i++
		}
		start = i + 1
	}
	if start < len(rs) {
		out = append(out, string(rs[start:]))
	}
	return out
}

func runeLen(s string) int { return utf8.RuneCountInString(s) }

func runeAt(s string, i int) rune {
	n := 0
	for _, r := range s {
		if n == i {
			return r
		}
		n++
	}
	return 0
}

type Font struct {
	height         int
	hardBlank      rune
	printDirection int
	smushMode      int
	chars          map[rune][]string
	width          map[rune]int
}

func parseFont(data string) (*Font, error) {
	data = strings.NewReplacer("\u0085", " ", "\u2028", " ", "\u2029", " ").Replace(data)
	lines := splitLines(data)
	if len(lines) == 0 {
		return nil, fmt.Errorf("empty font")
	}

	header := lines[0]
	if len(header) < 5 || (header[0] != 'f' && header[0] != 't') || header[1:4] != "lf2" {
		return nil, fmt.Errorf("not a figlet font")
	}
	lines = lines[1:]
	fields := strings.Fields(header[5:])
	if len(fields) < 6 {
		return nil, fmt.Errorf("malformed header")
	}

	f := &Font{
		hardBlank:      []rune(fields[0])[0],
		printDirection: -1,
		chars:          map[rune][]string{},
		width:          map[rune]int{},
	}

	height, err := strconv.Atoi(fields[1])
	if err != nil {
		return nil, err
	}
	oldLayout, err := strconv.Atoi(fields[4])
	if err != nil {
		return nil, err
	}
	commentLines, err := strconv.Atoi(fields[5])
	if err != nil {
		return nil, err
	}
	f.height = height

	fullLayout := -1
	if len(fields) > 6 {
		if v, err := strconv.Atoi(fields[6]); err == nil {
			f.printDirection = v
		}
	}
	if len(fields) > 7 {
		if v, err := strconv.Atoi(fields[7]); err == nil {
			fullLayout = v
		}
	}
	if fullLayout == -1 {
		if oldLayout == 0 {
			fullLayout = 64
		} else if oldLayout < 0 {
			fullLayout = 0
		} else {
			fullLayout = (oldLayout & 31) | 128
		}
	}
	f.smushMode = fullLayout

	pos := 0
	for i := 0; i < commentLines; i++ {
		pos++
	}

	var endRune rune
	readChar := func() (int, []string, error) {
		width := 0
		rows := make([]string, 0, f.height)
		for i := 0; i < f.height; i++ {
			if pos >= len(lines) {
				return 0, nil, fmt.Errorf("unexpected end of font")
			}
			line := lines[pos]
			pos++
			if endRune == 0 {
				rs := []rune(line)
				idx := len(rs) - 1
				for idx >= 0 && isPySpace(rs[idx]) {
					idx--
				}
				if idx < 0 {
					return 0, nil, fmt.Errorf("no end marker")
				}
				endRune = rs[idx]
			}
			line = strings.TrimRightFunc(line, isPySpace)
			rs := []rune(line)
			if len(rs) >= 2 && rs[len(rs)-1] == endRune && rs[len(rs)-2] == endRune {
				rs = rs[:len(rs)-2]
			} else if len(rs) >= 1 && rs[len(rs)-1] == endRune {
				rs = rs[:len(rs)-1]
			}
			line = string(rs)
			if n := runeLen(line); n > width {
				width = n
			}
			rows = append(rows, line)
		}
		return width, rows, nil
	}

	for i := rune(32); i < 127; i++ {
		w, rows, err := readChar()
		if err != nil {
			return nil, err
		}
		if i == 32 || strings.Join(rows, "") != "" {
			f.chars[i] = rows
			f.width[i] = w
		}
	}

	if pos < len(lines) {
		for _, r := range "ÄÖÜäöüß" {
			w, rows, err := readChar()
			if err != nil {
				return nil, err
			}
			if strings.Join(rows, "") != "" {
				f.chars[r] = rows
				f.width[r] = w
			}
		}
	}

	for pos < len(lines) {
		line := pyStrip(lines[pos])
		pos++
		if line == "" {
			continue
		}
		tag := strings.SplitN(line, " ", 2)[0]
		low := strings.ToLower(tag)
		if strings.HasPrefix(low, "0x") {
			code, err := strconv.ParseInt(tag[2:], 16, 32)
			if err != nil {
				continue
			}
			w, rows, err := readChar()
			if err != nil {
				return nil, err
			}
			if strings.Join(rows, "") != "" {
				f.chars[rune(code)] = rows
				f.width[rune(code)] = w
			}
		}
	}

	return f, nil
}

func loadFont(name string) (*Font, error) {
	base := strings.TrimSuffix(name, ".flf")
	base = strings.TrimSuffix(base, ".tlf")
	data, err := fontFS.ReadFile("fonts/" + base + ".flf")
	if err != nil {
		return nil, err
	}
	return parseFont(string(data))
}

type marker struct {
	buf  []string
	iter int
}

type Builder struct {
	text     []rune
	direction string
	width    int
	font     *Font
	justify  string

	iterator       int
	maxSmush       int
	curCharWidth   int
	prevCharWidth  int
	currentTotal   int
	blankMarkers   []marker
	queue          [][]string
	buffer         []string
}

func newBuilder(text string, font *Font, direction string, width int, justify string) *Builder {
	return &Builder{
		text:      []rune(text),
		direction: direction,
		width:     width,
		font:      font,
		justify:   justify,
		buffer:    make([]string, font.height),
	}
}

func (b *Builder) getCharAt(i int) ([]string, bool) {
	if i < 0 || i >= len(b.text) {
		return nil, false
	}
	rows, ok := b.font.chars[b.text[i]]
	return rows, ok
}

func (b *Builder) getCharWidthAt(i int) (int, bool) {
	if i < 0 || i >= len(b.text) {
		return 0, false
	}
	w, ok := b.font.width[b.text[i]]
	return w, ok
}

func (b *Builder) addCharToProduct() error {
	if b.iterator >= len(b.text) {
		return nil
	}
	cur := b.text[b.iterator]
	if cur == '\n' {
		b.blankMarkers = append(b.blankMarkers, marker{buf: append([]string{}, b.buffer...), iter: b.iterator})
		b.handleNewLine()
		return nil
	}
	curChar, ok := b.getCharAt(b.iterator)
	if !ok {
		return nil
	}
	curWidth, _ := b.getCharWidthAt(b.iterator)
	if b.width < curWidth {
		return fmt.Errorf("width is not enough to print this character")
	}
	b.curCharWidth = curWidth
	b.maxSmush = b.smushAmount(b.buffer, curChar)
	b.currentTotal = runeLen(b.buffer[0]) + b.curCharWidth - b.maxSmush

	if cur == ' ' {
		b.blankMarkers = append(b.blankMarkers, marker{buf: append([]string{}, b.buffer...), iter: b.iterator})
	}

	if b.currentTotal >= b.width {
		b.handleNewLine()
	} else {
		for row := 0; row < b.font.height; row++ {
			b.addCurCharRowToBufferRow(curChar, row)
		}
	}
	b.prevCharWidth = b.curCharWidth
	return nil
}

func (b *Builder) smushAmount(buffer, curChar []string) int {
	if b.font.smushMode&(smSmush|smKern) == 0 {
		return 0
	}
	maxSmush := b.curCharWidth
	for row := 0; row < b.font.height; row++ {
		lineLeft := buffer[row]
		lineRight := curChar[row]
		if b.direction == "right-to-left" {
			lineLeft, lineRight = lineRight, lineLeft
		}

		linebd := runeLen(strings.TrimRight(lineLeft, " ")) - 1
		if linebd < 0 {
			linebd = 0
		}
		var ch1 rune
		if linebd < runeLen(lineLeft) {
			ch1 = runeAt(lineLeft, linebd)
		} else {
			linebd = 0
			ch1 = 0
		}

		charbd := runeLen(lineRight) - runeLen(strings.TrimLeft(lineRight, " "))
		var ch2 rune
		if charbd < runeLen(lineRight) {
			ch2 = runeAt(lineRight, charbd)
		} else {
			charbd = runeLen(lineRight)
			ch2 = 0
		}

		amt := charbd + runeLen(lineLeft) - 1 - linebd
		if ch1 == 0 || ch1 == ' ' {
			amt++
		} else if ch2 != 0 {
			if _, ok := b.smushChars(ch1, ch2); ok {
				amt++
			}
		}
		if amt < maxSmush {
			maxSmush = amt
		}
	}
	return maxSmush
}

func (b *Builder) smushChars(left, right rune) (rune, bool) {
	if left == ' ' {
		return right, true
	}
	if right == ' ' {
		return left, true
	}
	if b.prevCharWidth < 2 || b.curCharWidth < 2 {
		return 0, false
	}
	mode := b.font.smushMode
	if mode&smSmush == 0 {
		return 0, false
	}

	if mode&63 == 0 {
		if left == b.font.hardBlank {
			return right, true
		}
		if right == b.font.hardBlank {
			return left, true
		}
		if b.direction == "right-to-left" {
			return left, true
		}
		return right, true
	}

	if mode&smHardblank != 0 {
		if left == b.font.hardBlank && right == b.font.hardBlank {
			return left, true
		}
	}
	if left == b.font.hardBlank || right == b.font.hardBlank {
		return 0, false
	}

	if mode&smEqual != 0 && left == right {
		return left, true
	}

	type rule struct{ a, b string }
	var rules []rule
	if mode&smLowline != 0 {
		rules = append(rules, rule{"_", `|/\[]{}()<>`})
	}
	if mode&smHierarchy != 0 {
		rules = append(rules,
			rule{"|", `/\[]{}()<>`},
			rule{`\/`, "[]{}()<>"},
			rule{"[]", "{}()<>"},
			rule{"{}", "()<>"},
			rule{"()", "<>"},
		)
	}
	for _, r := range rules {
		if strings.ContainsRune(r.a, left) && strings.ContainsRune(r.b, right) {
			return right, true
		}
		if strings.ContainsRune(r.a, right) && strings.ContainsRune(r.b, left) {
			return left, true
		}
	}

	if mode&smPair != 0 {
		pair := string([]rune{left, right})
		rev := string([]rune{right, left})
		if pair == "[]" || pair == "{}" || pair == "()" ||
			rev == "[]" || rev == "{}" || rev == "()" {
			return '|', true
		}
	}

	if mode&smBigX != 0 {
		if left == '/' && right == '\\' {
			return '|', true
		}
		if right == '/' && left == '\\' {
			return 'Y', true
		}
		if left == '>' && right == '<' {
			return 'X', true
		}
	}
	return 0, false
}

func (b *Builder) getLeftSmushedChar(i int, addLeft string) (rune, int) {
	idx := runeLen(addLeft) - b.maxSmush + i
	var left rune
	if idx >= 0 && idx < runeLen(addLeft) {
		left = runeAt(addLeft, idx)
	} else {
		left = 0
	}
	return left, idx
}

func updateSmushedChar(addLeft string, idx int, smushed rune) string {
	rs := []rune(addLeft)
	if idx < 0 || idx > len(rs) {
		return addLeft
	}
	rs[idx] = smushed
	return string(rs)
}

func (b *Builder) smushRow(curChar []string, row int) (string, string) {
	addLeft := b.buffer[row]
	addRight := curChar[row]
	if b.direction == "right-to-left" {
		addLeft, addRight = addRight, addLeft
	}
	for i := 0; i < b.maxSmush; i++ {
		left, idx := b.getLeftSmushedChar(i, addLeft)
		var right rune
		if i < runeLen(addRight) {
			right = runeAt(addRight, i)
		} else {
			right = ' '
		}
		smushed, ok := b.smushChars(left, right)
		if !ok {
			continue
		}
		addLeft = updateSmushedChar(addLeft, idx, smushed)
	}
	return addLeft, addRight
}

func (b *Builder) addCurCharRowToBufferRow(curChar []string, row int) {
	addLeft, addRight := b.smushRow(curChar, row)
	rs := []rune(addRight)
	if b.maxSmush < len(rs) {
		b.buffer[row] = addLeft + string(rs[b.maxSmush:])
	} else {
		b.buffer[row] = addLeft
	}
}

func (b *Builder) cutBufferCommon() {
	b.currentTotal = 0
	b.buffer = make([]string, b.font.height)
	b.blankMarkers = nil
	b.prevCharWidth = 0
	curChar, ok := b.getCharAt(b.iterator)
	if !ok {
		return
	}
	b.maxSmush = b.smushAmount(b.buffer, curChar)
}

func (b *Builder) cutBufferAtLastBlank(savedBuffer []string, savedIterator int) {
	b.queue = append(b.queue, savedBuffer)
	b.iterator = savedIterator
	b.cutBufferCommon()
}

func (b *Builder) cutBufferAtLastChar() {
	b.queue = append(b.queue, b.buffer)
	b.iterator--
	b.cutBufferCommon()
}

func (b *Builder) handleNewLine() {
	if len(b.blankMarkers) == 0 {
		b.cutBufferAtLastChar()
		return
	}
	m := b.blankMarkers[len(b.blankMarkers)-1]
	b.blankMarkers = b.blankMarkers[:len(b.blankMarkers)-1]
	b.cutBufferAtLastBlank(m.buf, m.iter)
}

func (b *Builder) justifyString(justify string, buffer []string) {
	for row := range buffer {
		pad := 0
		switch justify {
		case "right":
			pad = b.width - runeLen(buffer[row]) - 1
		case "center":
			pad = (b.width - runeLen(buffer[row])) / 2
		}
		if pad > 0 {
			buffer[row] = strings.Repeat(" ", pad) + buffer[row]
		}
	}
}

func (b *Builder) formatProduct() string {
	var sb strings.Builder
	for _, buffer := range b.queue {
		b.justifyString(b.justify, buffer)
		s := strings.Join(buffer, "\n") + "\n"
		s = strings.ReplaceAll(s, string(b.font.hardBlank), " ")
		sb.WriteString(s)
	}
	return sb.String()
}

func (b *Builder) render() (string, error) {
	for b.iterator < len(b.text) {
		if err := b.addCharToProduct(); err != nil {
			return "", err
		}
		b.iterator++
	}
	if b.buffer[0] != "" {
		b.queue = append(b.queue, b.buffer)
	}
	return b.formatProduct(), nil
}

func applyMap(s string, table *[256]rune) string {
	rs := []rune(s)
	for i, r := range rs {
		if r < 256 {
			rs[i] = table[r]
		}
	}
	return string(rs)
}

func reverseArt(s string) string {
	rows := splitLines(s)
	out := make([]string, 0, len(rows))
	for _, row := range rows {
		row = applyMap(row, &reverseMap)
		rs := []rune(row)
		for i, j := 0, len(rs)-1; i < j; i, j = i+1, j-1 {
			rs[i], rs[j] = rs[j], rs[i]
		}
		out = append(out, string(rs))
	}
	return strings.Join(out, "\n") + "\n"
}

func flipArt(s string) string {
	rows := splitLines(s)
	out := make([]string, 0, len(rows))
	for i := len(rows) - 1; i >= 0; i-- {
		out = append(out, applyMap(rows[i], &flipMap))
	}
	return strings.Join(out, "\n") + "\n"
}

func stripSurrounding(s string) string {
	rows := splitLines(s)
	out := make([]string, 0, len(rows))
	seen := false
	for _, row := range rows {
		if pyStrip(row) != "" || seen {
			seen = true
			out = append(out, row)
		}
	}
	res := strings.Join(out, "\n") + "\n"
	return strings.TrimRightFunc(res, isPySpace)
}

type options struct {
	font      string
	width     int
	justify   string
	direction string
	reverse   bool
	flip      bool
	strip     bool
	normalize bool
}

func parseArgs(argv []string) (*options, []string, error) {
	opts := &options{font: "standard", width: 80, justify: "auto", direction: "auto"}
	var text []string

	takeValue := func(i *int, attached string) (string, error) {
		if attached != "" {
			return attached, nil
		}
		*i++
		if *i >= len(argv) {
			return "", fmt.Errorf("option requires a value")
		}
		return argv[*i], nil
	}

	i := 0
	for i < len(argv) {
		arg := argv[i]
		if arg == "--" {
			text = append(text, argv[i+1:]...)
			break
		}
		if strings.HasPrefix(arg, "--") {
			name := arg[2:]
			value := ""
			attached := false
			if eq := strings.IndexByte(name, '='); eq >= 0 {
				value = name[eq+1:]
				name = name[:eq]
				attached = value != ""
			}
			switch name {
			case "font", "direction", "justify", "width":
				v := value
				if !attached {
					var err error
					v, err = takeValue(&i, "")
					if err != nil {
						return nil, nil, err
					}
				}
				switch name {
				case "font":
					opts.font = v
				case "direction":
					opts.direction = v
				case "justify":
					opts.justify = v
				case "width":
					n, err := strconv.Atoi(v)
					if err != nil {
						return nil, nil, err
					}
					opts.width = n
				}
			case "reverse":
				opts.reverse = true
			case "flip":
				opts.flip = true
			case "strip-surrounding-newlines":
				opts.strip = true
			case "normalize-surrounding-newlines":
				opts.normalize = true
			default:
				return nil, nil, fmt.Errorf("no such option: %s", arg)
			}
		} else if len(arg) > 1 && arg[0] == '-' {
			for j := 1; j < len(arg); j++ {
				c := arg[j]
				switch c {
				case 'f', 'D', 'j', 'w':
					v, err := takeValue(&i, arg[j+1:])
					if err != nil {
						return nil, nil, err
					}
					switch c {
					case 'f':
						opts.font = v
					case 'D':
						opts.direction = v
					case 'j':
						opts.justify = v
					case 'w':
						n, err := strconv.Atoi(v)
						if err != nil {
							return nil, nil, err
						}
						opts.width = n
					}
					j = len(arg)
				case 'r':
					opts.reverse = true
				case 'F':
					opts.flip = true
				case 's':
					opts.strip = true
				case 'n':
					opts.normalize = true
				default:
					return nil, nil, fmt.Errorf("no such option: -%c", c)
				}
			}
		} else {
			text = append(text, arg)
		}
		i++
	}
	return opts, text, nil
}

func main() {
	opts, words, err := parseArgs(os.Args[1:])
	if err != nil {
		os.Exit(2)
	}

	font, err := loadFont(opts.font)
	if err != nil {
		fmt.Fprintf(os.Stderr, "pyfiglet error: requested font %q not found.\n", opts.font)
		os.Exit(1)
	}

	direction := opts.direction
	if direction == "auto" {
		if font.printDirection == 1 {
			direction = "right-to-left"
		} else {
			direction = "left-to-right"
		}
	}

	justify := opts.justify
	if justify == "auto" {
		if direction == "right-to-left" {
			justify = "right"
		} else {
			justify = "left"
		}
	}

	text := strings.Join(words, " ")
	builder := newBuilder(text, font, direction, opts.width, justify)
	art, err := builder.render()
	if err != nil {
		os.Exit(1)
	}

	if opts.reverse {
		art = reverseArt(art)
	}
	if opts.flip {
		art = flipArt(art)
	}
	if opts.strip {
		art = stripSurrounding(art)
	} else if opts.normalize {
		art = "\n" + stripSurrounding(art) + "\n"
	}

	os.Stdout.WriteString(art + "\n")
}
GO_MAIN_EOF

GOCACHE="${GOCACHE:-/tmp/go-cache}" go build -o /tmp/figlet .
go build ./...
