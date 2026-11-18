# Hand-in notes

Screenshots (rendered from the real captured job output; the exact text of each
is beside it as a `.txt`):

- `screenshots/oracle.png` / `oracle.txt` — reward 1.000, `*** SECRET UNLOCKED ***`
  and the secret `nice port, human` drawn by the oracle in `slant`.
- `screenshots/nop.png` / `nop.txt` — reward 0.000, `No secret for you. Yet.`
- `screenshots/cheat.png` / `cheat.txt` — reward 0.167 (build 1, no_python 0,
  behaviour 0), `No secret for you. Yet.`

Two honest lines:

1. **Smushing rule that broke me most:** none of the six broke once copied
   verbatim; the one that *looked* like it did was `SM_KERN`. `banner` and
   `script` use `fullLayout = 64`, so `smushChars` must return `None` for every
   non-space pair, and the only overlap allowed is blank space. Debugging that
   felt like a hierarchy/pair bug until `smushAmount` and `smushRow` were
   ported line for line.
2. **Docker trap I hit:** the pinned `golang:1.23-alpine` image has no bash, so
   Harbor dies with `exec: "bash": executable file not found` before any test
   runs. Stage 2 installs bash; stage 1 separately needs `git` and
   `ca-certificates` to clone pyfiglet.

Bonus: the page secret renders cleanly with the oracle code:

```console
$ cd /workspace/repo && go build -o /tmp/figlet . \
    && /tmp/figlet -f slant "$(echo Z28gdG91Y2ggZ3Jhc3M= | base64 -d)"
                   __                   __
   ____ _____     / /_____  __  _______/ /_     ____ __________ ___________
  / __ `/ __ \   / __/ __ \/ / / / ___/ __ \   / __ `/ ___/ __ `/ ___/ ___/
 / /_/ / /_/ /  / /_/ /_/ / /_/ / /__/ / / /  / /_/ / /  / /_/ (__  |__  )
 \__, /\____/   \__/\____/\__,_/\___/_/ /_/   \__, /_/   \__,_/____/____/
/____/                                       /____/
```
