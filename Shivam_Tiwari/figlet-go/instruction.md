# Port pyfiglet to Go

## What this repository is

This repository is a checkout of pyfiglet at commit
`255827efbc09d662875dad50fa0edc1e1263bf45`, a pure-Python implementation of
FIGlet. It reads `.flf` font files and renders text as multi-line ASCII art,
including horizontal smushing, kerning, wrapping, justification and print
direction. The Python implementation and the `.flf` fonts are in the repository.

## What to build

Create a Go program in `/workspace/repo`. Running

```sh
go build -o /tmp/figlet .
```

from `/workspace/repo` must produce a command-line program at `/tmp/figlet`.

Options come first, then the text. The program must accept:

- `-f FONT` — font name (default `standard`)
- `-w COLS` — output width in columns (default `80`)
- `-j auto|left|center|right` — justification (default `auto`)
- `-D auto|left-to-right|right-to-left` — print direction (default `auto`)
- `-r` — mirror the finished output horizontally
- `-F` — flip the finished output vertically
- `-s` — strip leading and trailing blank lines
- `-n` — normalise surrounding blank lines

The remaining arguments are the text; they are joined with single spaces. The
program writes the rendered text to stdout followed by one newline. For the same
arguments, its stdout must equal the stdout of the original pyfiglet `main()`
byte for byte.

Details that are easy to get wrong:

- `-j` justifies inside the `-w` width, not inside 80 columns. `center`
  left-pads each rendered line by `int((width - line_length) / 2)` spaces;
  `right` left-pads by `width - line_length - 1` spaces; `left` adds nothing.
  No trailing padding is added.
- `auto` justification is `left` for left-to-right output and `right` for
  right-to-left output.
- `auto` direction comes from the font header's print direction, and
  `right-to-left` reverses glyph order.
- `-s` and `-n` operate on the finished art. `-s` removes every leading and
  trailing blank line; `-n` removes them and then adds exactly one blank line
  before and after. If both are given, `-s` wins.
- `-r` and `-F` are applied before `-s`/`-n`, in the order `-r`, then `-F`.

## Fonts

The `.flf` font files may be moved inside the repository, but they must stay in
the repository. The program must work from any working directory; do not depend
on the current directory or on the original `pyfiglet/` layout.

## Hard rules

- Use only the Go standard library. No third-party modules.
- No `.py` file may remain anywhere under `/workspace/repo`.
- `go build ./...` must pass.

## Not checked

Speed, memory use, error messages, and the options `-c`, `-L`, `-l`, `-i` are
not checked.

## Grading

Grading runs hidden automatic cases and compares stdout byte for byte. The score
is partial: credit is possible for building and for some correct cases without
matching every case.
