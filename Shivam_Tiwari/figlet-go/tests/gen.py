#!/usr/bin/env python3
"""Generate visible.jsonl and hidden.jsonl from the original pyfiglet.

Run on the laptop, with the pinned pyfiglet checkout next to the task folder:

    python tests/gen.py

Every "out" value comes from calling pyfiglet.main() itself. Nothing is
hand-written, and the random seed makes the two files reproducible.
"""

from __future__ import annotations

import contextlib
import io
import json
import multiprocessing as mp
import queue
import random
import sys
from pathlib import Path

TASK_ROOT = Path(__file__).resolve().parents[1]
PYFIGLET = TASK_ROOT.parent / "pyfiglet"
DATA_DIR = TASK_ROOT / "tests" / "data"

if not (PYFIGLET / "pyfiglet" / "__init__.py").is_file():
    raise SystemExit(f"pyfiglet checkout not found at {PYFIGLET}")

sys.path.insert(0, str(PYFIGLET))
import pyfiglet  # noqa: E402

RNG = random.Random(7)

FONTS = ["standard", "slant", "small", "big", "mini", "banner", "shadow", "script"]
WIDTHS = [10, 20, 40, 60, 80, 120]
JUSTIFY = ["auto", "left", "center", "right"]
DIRECTION = ["auto", "left-to-right", "right-to-left"]
FLAGS = ["-r", "-F", "-s", "-n"]

COMBOS = [
    (font, width, justify, direction)
    for font in FONTS
    for width in WIDTHS
    for justify in JUSTIFY
    for direction in DIRECTION
]

WORDS = [
    "hello", "figlet", "go", "port", "harbor", "room", "task", "agent",
    "twin", "ascii", "art", "font", "output", "squeeze", "smush", "kern",
    "width", "justify", "direction", "player", "build", "secret", "banner",
    "shadow", "script", "small", "big", "mini", "slant", "standard", "text",
    "line", "wrap", "column", "character", "glyph", "render", "python",
]

# Text taken from the rare cases in NOTES.md plus the requested categories.
TRICKY = [
    # smushing edges
    "|", "/\\", "\\/", "[]", "{}", "()", "<>", "><", "_", "__",
    "|/\\[]{}()<>", "_|", "_/", "|/", "/[", "[{", "{(", "(<",
    "[]{}()", "<>", "[]{}", "{}()", "()<>", "||", "[][]", "{}{}",
    "(())", "<><>", "a|b", "x/y", "a\\b", "a_b", "a[]b", "a{}b",
    "a()b", "a<>b", "|/_\\|", "_[]_", "_/\\_", "><", "</>", "\\\\",
    "===", "---", "___", "|||", "!!!", "...", "'''", ":::", ";;;",
    "$", "$$", "$|$", "a$b",
    # double spaces and edge spaces
    "hello  world", "a  b", "  leading", "trailing  ", "a   b   c",
    "one  two  three",
    # long sentences that must wrap
    "the quick brown fox jumps over the lazy dog and keeps running through the forest",
    "pack my box with five dozen liquor jugs before the sun goes down",
    "how vexingly quick daft zebras jump over the sleeping dog",
    "the five boxing wizards jump quickly at dawn near the river",
    "sixty zippers were quickly picked from the woven jute bag yesterday",
    "a long line with [] {} () <> /\\ \\/ _ and plenty of ordinary words to wrap",
    "wrapping should happen at a space when one is available in the current line",
    # Latin-1 letters
    "é", "ß", "ñ", "café", "straße", "mañana", "Über", "ÄÖÜäöüß",
    "naïve", "résumé", "piñata", "grüße", "élève", "Bäcker",
    # characters the fonts do not have
    "→", "✓", "漢", "🙂", "€", "Ω", "λ", "→←", "✓✗", "a→b", "a✓b",
    # newline handling
    "first line\nsecond line", "a\nb", "one\n\ntwo",
]

NORMAL = [
    "hello", "hello world", "figlet in go", "port the renderer",
    "keep the output exact", "squeeze the letters", "smush and kern",
    "wrap this text", "justify this line", "right to left", "left to right",
    "a room with a view", "the quick brown fox", "lazy dog", "go build",
]


_FONT_CACHE: dict[str, "pyfiglet.FigletFont"] = {}


def _visible_width(font_name: str, ch: str) -> int:
    """Width of a glyph after its leading blank columns are removed."""
    font = _FONT_CACHE.get(font_name)
    if font is None:
        font = pyfiglet.FigletFont(font_name)
        _FONT_CACHE[font_name] = font
    code = ord(ch)
    glyph = font.chars.get(code)
    if not glyph:
        return 0
    lead = min(len(row) - len(row.lstrip(" ")) for row in glyph)
    return font.width[code] - lead


def _would_hang(font_name: str, width: int, text: str) -> bool:
    """pyfiglet loops forever if a glyph cannot fit on an empty line.

    On an empty buffer the smush amount equals the glyph's leading blanks, so
    currentTotalWidth is the glyph's visible width.  If that reaches the target
    width, cutBufferAtLastChar rewinds the iterator and the same character is
    retried forever.  The real CLI hangs on those arguments, so they cannot be
    cases in the dataset.
    """
    return any(_visible_width(font_name, ch) >= width for ch in text)


class Capture:
    """A stdout stand-in that supports pyfiglet's detach()/binary writes."""

    def __init__(self) -> None:
        self._text = bytearray()
        self._binary: io.BytesIO | None = None

    def write(self, data):  # noqa: ANN001
        if isinstance(data, str):
            data = data.encode("utf-8")
        self._text.extend(data)
        return len(data)

    def flush(self) -> None:
        pass

    def detach(self) -> io.BytesIO:
        self._binary = io.BytesIO()
        return self._binary

    def value(self) -> bytes:
        binary = self._binary.getvalue() if self._binary is not None else b""
        return bytes(self._text) + binary


def _render_inprocess(args: list[str]) -> str | None:
    """Run the original main() and return its exact stdout, or None on error."""
    cap = Capture()
    old_argv, old_stdout = sys.argv, sys.stdout
    sys.argv = ["pyfiglet", *args]
    sys.stdout = cap
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            rc = pyfiglet.main()
    except BaseException:
        return None
    finally:
        sys.stdout = old_stdout
        sys.argv = old_argv
    if rc not in (0, None):
        return None
    try:
        return cap.value().decode("utf-8")
    except UnicodeDecodeError:
        return None


def _render_worker(in_q, out_q) -> None:  # noqa: ANN001
    while True:
        args = in_q.get()
        if args is None:
            return
        out_q.put(_render_inprocess(args))


class Renderer:
    """A worker process, so a hung render can be killed and skipped."""

    def __init__(self) -> None:
        self._start()

    def _start(self) -> None:
        ctx = mp.get_context("spawn")
        self._in_q = ctx.Queue()
        self._out_q = ctx.Queue()
        self._proc = ctx.Process(
            target=_render_worker,
            args=(self._in_q, self._out_q),
            daemon=True,
        )
        self._proc.start()

    def _stop(self) -> None:
        try:
            self._in_q.put(None)
        except Exception:
            pass
        self._proc.terminate()
        self._proc.join(timeout=2)

    def render(self, args: list[str]) -> str | None:
        self._in_q.put(list(args))
        try:
            return self._out_q.get(timeout=3.0)
        except queue.Empty:
            self._stop()
            self._start()
            return None

    def close(self) -> None:
        self._stop()


_RENDERER: Renderer | None = None


def render(args: list[str]) -> str | None:
    global _RENDERER
    if _RENDERER is None:
        _RENDERER = Renderer()
    return _RENDERER.render(args)


def close_renderer() -> None:
    global _RENDERER
    if _RENDERER is not None:
        _RENDERER.close()
        _RENDERER = None


def make_deck() -> list[tuple[str, int, str, str]]:
    deck = COMBOS * 4
    RNG.shuffle(deck)
    return deck


def make_flag_table(size: int) -> dict[str, list[bool]]:
    table = {flag: [True] * (size // 4) + [False] * (size - size // 4) for flag in FLAGS}
    for values in table.values():
        RNG.shuffle(values)
    return table


def make_cases(
    count: int,
    seen: set[tuple[str, ...]],
    label: str,
) -> list[dict[str, object]]:
    deck = make_deck()
    deck_pos = 0
    flags = make_flag_table(count)
    text_pos = 0
    cases: list[dict[str, object]] = []
    attempts = 0

    while len(cases) < count:
        attempts += 1
        if attempts > 300_000:
            raise SystemExit(f"could not build {count} cases for {label}")

        if deck_pos >= len(deck):
            RNG.shuffle(deck)
            deck_pos = 0
        font, width, justify, direction = deck[deck_pos]
        deck_pos += 1

        # Half of the attempts use the fixed tricky pool, half use normal text.
        slot = text_pos
        text_pos += 1
        if slot % 2 == 0:
            text_args = [TRICKY[(slot // 2) % len(TRICKY)]]
        elif RNG.random() < 0.5:
            text_args = [RNG.choice(NORMAL)]
        else:
            words = [RNG.choice(WORDS) for _ in range(RNG.randint(1, 4))]
            if RNG.random() < 0.5:
                text_args = [" ".join(words)]
            else:
                text_args = words

        n = len(cases)
        args = [
            "-f", font,
            "-w", str(width),
            "-j", justify,
            "-D", direction,
        ]
        args += [flag for flag in FLAGS if flags[flag][n]]
        args += text_args

        key = tuple(args)
        if key in seen:
            continue
        if _would_hang(font, width, " ".join(text_args)):
            continue

        out = render(args)
        if out is None:
            continue

        seen.add(key)
        cases.append({"args": args, "out": out})

    return cases


def write_jsonl(path: Path, cases: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for case in cases:
            fh.write(json.dumps(case, ensure_ascii=False, separators=(",", ":")))
            fh.write("\n")


def main() -> int:
    try:
        seen: set[tuple[str, ...]] = set()
        visible = make_cases(2000, seen, "visible")
        hidden = make_cases(2000, seen, "hidden")
        write_jsonl(DATA_DIR / "visible.jsonl", visible)
        write_jsonl(DATA_DIR / "hidden.jsonl", hidden)
        print(f"visible: {len(visible)}")
        print(f"hidden:  {len(hidden)}")
        return 0
    finally:
        close_renderer()


if __name__ == "__main__":
    raise SystemExit(main())
