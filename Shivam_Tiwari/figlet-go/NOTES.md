# Step 1 — pyfiglet study notes

## Provenance

| Field | Value |
|---|---|
| Upstream | https://github.com/pwaller/pyfiglet |
| Pinned commit | `255827efbc09d662875dad50fa0edc1e1263bf45` |
| Commit date | `2026-08-02T22:51:18+01:00` |
| Licence | **MIT** (`LICENSE`: "The MIT License (MIT)", © 2007-2018) |

Reproduce the checkout:

```sh
git clone https://github.com/pwaller/pyfiglet
cd pyfiglet
git checkout 255827efbc09d662875dad50fa0edc1e1263bf45
git log -1 --format='%H %cI'
# 255827efbc09d662875dad50fa0edc1e1263bf45 2026-08-02T22:51:18+01:00
```

## Why `python -m pyfiglet hello` fails straight after cloning

At this commit the fonts live in **`pyfiglet/fonts-standard/`** (67 `.flf` files, plus
4 `.flc` and one `__init__.py`), but the
loader resolves every font through the package resource **`pyfiglet.fonts`**:

```python
# pyfiglet/__init__.py:148 (FigletFont.preloadFont)
path = importlib.resources.files('pyfiglet.fonts').joinpath(fn)
```

A fresh clone has no `pyfiglet/fonts/`, so that call raises:

```text
ModuleNotFoundError: No module named 'pyfiglet.fonts'
```

This happens before any `FontNotFound` fallback, and `main()` only catches `FontNotFound`,
so the CLI exits with a traceback. (`setup.py`, lines 8-13, copytree's
`fonts-standard` -> `fonts` at install time; the Makefile does the same explicitly.)

**Which Makefile step fixes it:** `make minimal` — more precisely its `clean` target
(recreates `pyfiglet/fonts/`) followed by
`cp pyfiglet/fonts-standard/* pyfiglet/fonts`. `make clean` on its own is **not** enough:
an empty `pyfiglet.fonts` imports fine, so the failure changes to
`pyfiglet error: requested font 'standard' not found.` (verified).

Minimal fix used here:

```sh
mkdir -p pyfiglet/fonts
cp pyfiglet/fonts-standard/* pyfiglet/fonts/
python -m pyfiglet -f slant "hello"
```

Result (verified):

```text
    __         ____    
   / /_  ___  / / /___ 
  / __ \/ _ \/ / / __ \
 / / / /  __/ / / /_/ /
/_/ /_/\___/_/_/\____/ 
                       
```

Note: at this commit the source directory is `pyfiglet/fonts-standard/`, not a
repo-root `fonts-standard/`. `fonts-contrib/` is excluded from the image (mixed authors).

## Smushing rules

Each rule decides what happens at the single edge column where two glyphs meet.
All examples below were verified against `FigletBuilder.smushChars()` with
`prevCharWidth = curCharWidth = 2` and the relevant layout bits enabled.

The six horizontal smushing rules, plus kerning:

1. **Equal character** (`SM_EQUAL = 1`) — two identical visible edge chars collapse into one.
   - `|` + `|` -> `|`
   - `\` + `\` -> `\`

2. **Underscore** (`SM_LOWLINE = 2`) — `_` gives way to any of `|/\[]{}()<>`.
   - `_` + `|` -> `|`
   - `_` + `/` -> `/`
   - (either order)

3. **Hierarchy** (`SM_HIERARCHY = 4`) — six classes, low to high:
   `|` then `/\` then `[]` then `{}` then `()` then `<>`.
   The higher class wins.
   - `|` + `/` -> `/`
   - `/` + `[` -> `[`
   - `[` + `{` -> `{`
   - `{` + `(` -> `(`
   - `(` + `<` -> `<`

4. **Opposite pair** (`SM_PAIR = 8`) — a matching bracket pair becomes a bar.
   - `[` + `]` -> `|`
   - `{` + `}` -> `|`
   - `(` + `)` -> `|`
   - (either order)

5. **Big X** (`SM_BIGX = 16`) — only these orientations:
   - `/` + `\` -> `|`
   - `\` + `/` -> `Y` (not `X`)
   - `>` + `<` -> `X`
   - `<` + `>` -> no smush (`None`, verified)

6. **Hardblank** (`SM_HARDBLANK = 32`) — two hardblanks become one hardblank;
   a hardblank never smushes with a visible char.
   - In `standard.flf` the hardblank is `$`, so `$` + `$` -> `$`
   - Hardblanks are replaced with spaces when the product is emitted, so this rule
     affects spacing only, never visible glyphs.

**Kerning** (`SM_KERN = 64`) — removes blank columns so glyphs just touch, but visible
edges never overlap: `smushChars` returns `None` for every visible + visible pair, and
only a space yields to the other char (`' '` + `/` -> `/`). If smushing (`128`) is also
set, smushing takes precedence.

**Universal smushing** (not one of the six): `SM_SMUSH = 128` set while bits 1-32 are
clear. Edges may overlap; the right-hand char wins left-to-right, the left-hand char
wins right-to-left, and a hardblank yields to a visible char.

Two engine guards worth knowing:
- No smushing when either adjacent glyph is narrower than 2 columns.
- `smushAmount` returns 0 when neither `64` nor `128` is set (no fitting at all).

Bundled-font caveat: `standard.flf` has the header
`flf2a$ 6 5 16 15 46 0 24463 229` — height 6, hardblank `$`, fullLayout `24463`,
which enables equal, lowline, hierarchy, pair and smushing **but not** big X,
hardblank or kerning. No font in `fonts-standard/` sets bits 16 or 32, so the big X
and hardblank rules can only be exercised with a synthetic `smushMode` (or a font that
sets them). Only `banner`, `block`, `lean`, `script` and `smscript` set the kerning
bit (and none of them enable smushing).

## Options in scope

Only these eight are covered. Colour (`-c`), font install (`-L`), font list (`-l`) and
font info (`-i`) are explicitly out of scope.

| Option | Meaning |
|---|---|
| `-f FONT`, `--font FONT` | Font name to render with; default `standard`. Resolved as `FONT.flf`/`FONT.tlf` in `pyfiglet/fonts/`, then cwd, then system figlet font dirs — not a bare file path. |
| `-w COLS`, `--width COLS` | Target output width in columns; default `80`. Starts a new line before the glyph that would reach/exceed it, breaking at the last recorded space, or mid-word if no space exists. Also the width used for justification padding. |
| `-j SIDE`, `--justify SIDE` | `auto`, `left`, `center` or `right`; default `auto` (left for LTR, right for RTL). Pads each output row on the left: center by `int((width - len) / 2)`, right by `width - len - 1`. |
| `-D DIR`, `--direction DIR` | `auto`, `left-to-right` or `right-to-left`; default `auto`, taken from the font header's print direction. RTL reverses glyph order and makes `auto` justification right-aligned. |
| `-r`, `--reverse` | Horizontal mirror of the finished art: each row is reversed and characters are mirrored (`/`<->`\`, `[`<->`]`, `{`<->`}`, `(`<->`)`, `<`<->`>`, `b`<->`d`, `p`<->`q`, etc.). |
| `-F`, `--flip` | Vertical flip: row order is reversed and characters are flipped (`^`<->`v`, `M`<->`W`, and similar). |
| `-s`, `--strip-surrounding-newlines` | Removes leading/trailing all-blank rows from the art (internal blank rows survive). For `standard`, this drops the font's own empty bottom row. |
| `-n`, `--normalize-surrounding-newlines` | Strips surrounding blank rows, then adds exactly one empty line before and one after. |

Processing order in `main()`: render -> `-r` reverse -> `-F` flip -> `-s`/`-n`.
If both `-s` and `-n` are given, **`-s` wins** (`if`/`elif`). The CLI then writes one
extra trailing newline of its own.

## Rare cases / traps

- Fonts are under `pyfiglet/fonts-standard/` at this commit; the final image must copy
  them into `pyfiglet/fonts/` (the Dockerfile already does this).
- `make clean` alone does not fix a fresh clone — it only creates an empty
  `pyfiglet/fonts/`, changing the error from `ModuleNotFoundError` to
  `requested font 'standard' not found`.
- `-D right-to-left` is not just right alignment: glyph order reverses (with `small`,
  `ab` reads as `ba`), and `-j auto` follows it to the right.
- Big X is asymmetric: `\` + `/` -> `Y`; only `>` + `<` gives `X`; `<>` gives nothing.
- Hardblank is `$` in `standard`, never smushes with visible chars, and is printed as a
  space — so the hardblank rule is invisible in final output.
- Equal-character smushing explicitly excludes the hardblank; hardblank + hardblank is
  handled only by rule 32.
- A glyph narrower than 2 columns never smushes; this avoids 1-column overlaps.
- `standard.flf` does not enable big X, hardblank or kerning, so a test that only uses
  `standard` cannot demonstrate those rules; use a kerning-only font (`banner`,
  `block`, `lean`, `script`, `smscript`) for kerning, or a synthetic mode for
  big X/hardblank.
- `-s` overrides `-n` when both are passed.
- Default output already ends with the font's blank bottom row; `-n` strips that and
  adds exactly one empty line on each side, so it is not the same as the default.
- `-w` below a single glyph's width raises `CharNotPrinted("Width is not enough to print
  this character")` as a traceback (for example `-w 2` with `hello`).
- `-j right` leaves one column of slack (`width - len - 1`), unlike a naive flush-right.
- `-r` and `-F` are different operations and are applied in that order.
