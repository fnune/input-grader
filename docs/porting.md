# Porting to another game or emulator

The grader is split so the parts that know nothing about 3rd Strike can be reused:

```
lua/input_grader/
  core/              game-agnostic: app, bench, overlay, CSV, input history, hook multiplexer, run
  platform/          one adapter per emulator: fbneo.lua (players), mame.lua (tests, screenshots)
  games/sfiii3/      everything 3rd Strike: tables, RAM map, checker port, tracker, grader
```

`core/` never requires a game or platform module. A new game adds a folder under `games/`; a new emulator adds a file under `platform/`.

## The platform interface

What `core/run.lua` and the game modules need from an emulator. See `platform/fbneo.lua` for the reference implementation.

| Member | Type | Purpose |
| --- | --- | --- |
| `name`, `romname` | string | Identify the emulator and the loaded set |
| `mem.u8`, `mem.u16`, `mem.s16`, `mem.u32` | `fn(address) -> number` | Read emulated memory, big- or little-endian as the CPU sees it |
| `canvas:text(x, y, s, color)` | | Draw text in screen coordinates |
| `canvas:box(x1, y1, x2, y2, fill, edge)` | | Draw a panel |
| `on_frame(fn)` | | Call `fn` after every emulated frame |
| `on_draw(fn)` | | Call `fn` when the overlay should draw |
| `hotkey(n, fn)` | | Bind a hotkey (FBNeo: Alt+1 to Alt+9) |
| `clock()` | `-> seconds` | Emulated time |
| `timestamp()` | `-> string` | Wall-clock time for the log |
| `appender(path, header)` | `-> fn(line)` | Append lines to a file |
| `print(s)` | | Report to the user |

Colors are names (`text`, `dim`, `good`, `bad`, `warn`, `panel`, `edge`); each adapter maps them to its own format.

## The game module interface

What `core/app.lua` consumes.

| Member | Purpose |
| --- | --- |
| `game:update() -> { attempt, ... }` | Called every frame; returns the attempts graded this frame (usually none) |
| `game:moves() -> { {id, name, notation}, ... }` | Moves the current character can be graded on, for the bench target |
| `game:set_target(id or nil)` | Grade only one move |

### Attempt records

The overlay, the bench and the CSV log only read these fields:

| Field | Example | Notes |
| --- | --- | --- |
| `game`, `character` | `"sfiii3"`, `"ryu"` | |
| `id` | `"ryu:29"` | Stable per move; used for bench targets |
| `move`, `notation` | `"Hadoken"`, `"236+P"` | |
| `ok` | `true` | The move came out |
| `error` | `{ code = "skipped_step", text = "went from 2 to 6 without 3" }` | `nil` when `ok`; codes in [how-it-works.md](how-it-works.md#verdicts) |
| `steps` | `{ {label="2"}, {label="3", used=2, window=10} }` | `used` and `window` in frames, when known |
| `button` | `{ label="LP", after=0, window=10 }` | `after` and `window` when the motion completed first |
| `total`, `minimum` | `5`, `2` | Frames from the first step to the button, and the fastest possible |
| `margin` | `7` | The smallest spare time of any window |
| `side` | `"right"` | The facing during the attempt |

## Adding a game

1. **Find the game's input check.** A decompilation or disassembly is best: it gives exact windows and lets you port the check for offline tests. Without one, a game module can still grade from timing alone, with windows measured in the emulator.
2. **Map the state in RAM.** Write a `ram.lua` that takes the injected `mem` readers. Keep the addresses in one table and say where each came from.
3. **Write a source and a grader.** The 3rd Strike module shows the pattern: `sources.lua` turns each frame into an observation, `tracker.lua` turns state changes into runs, `game.lua` grades runs into attempts. Give the source a scripted twin so the grader can be unit-tested without the game.
4. **Compose it.** Add `games/<game>/init.lua` with a `build(platform, options)` that returns a `core/app` instance, and an entry script like `input_grader.lua`.
5. **Verify against the game.** Use `harness/mame/session.lua` (or an equivalent) to boot into a match, drive inputs and assert verdicts, as `harness/mame/grade.lua` does.

## Adding an emulator

Implement the platform interface in `platform/<emulator>.lua` and an entry script that composes it. Two things to check:

- **One callback per hook?** FBNeo keeps a single function per hook, so running next to another script needs `core/hooks.lua`. MAME allows many.
- **When do callbacks run?** The game modules expect `on_frame` after the frame has been emulated, with RAM reflecting that frame.
