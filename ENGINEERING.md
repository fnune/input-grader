# Engineering principles

How this repository is built and changed. Adapted from the [openmusa engineering principles](https://github.com/openmusa/openmusa/blob/main/engineering/README.md) for a different kind of project: Lua scripts that run inside an emulator, plus the tools that derive and check their data. What did not carry over is listed at the end.

## Principles

### Ground truth over guesses

The grader tells players how many frames they had. That claim has to be right, so every number traces back to the game itself.

- Numbers come from the program ROM. `tools/gen_commands.py` reads the command tables out of the decrypted ROM; the decomp only contributes names and a cross-check, and the ROM wins when they disagree.
- Behaviour is checked in the real game. `harness/mame/validate.lua` compares the Lua checker with the game's own command state on every frame, and `harness/mame/grade.lua` checks the grader's verdicts end to end. A change to the checker, the RAM map or the grader is not done until both pass.
- A finding that contradicts intuition is pinned by a test named after it (for example "Shoryuken: 2 must come within 5 frames of letting go of 6"), so it is not "fixed" later.
- Every address, offset and constant states where it came from: the decomp's struct layout (`tools/offsets.c`), a RAM search in the harness, or a cited source.

### Calm tool

The overlay sits on top of a game someone is trying to play. It stays out of the way.

- Show the verdict, the reason and the numbers, then fade. No sounds, no flashing, no streaks.
- Feedback is plain and specific: "went from 2 to 6 without 3", not "bad input". It never blames.
- One hotkey hides everything. Nothing nags.
- Failures are quiet and accurate: a broken frame prints one line with context and the script keeps running.

### Testability via dependency injection

Reference: [Mark Seemann](https://blog.ploeh.dk/), [*Dependency Injection Principles, Practices, and Patterns*](https://www.manning.com/books/dependency-injection-principles-practices-patterns).

- Volatile dependencies are the emulator's API: memory reads, callbacks, drawing, hotkeys, files and time. Only the platform adapters in `lua/input_grader/platform/` touch emulator globals.
- Stable dependencies (the command tables, pure functions, the bit helpers) are required directly, never injected.
- Composition roots are the entry scripts: `input_grader.lua`, the generated training launcher and the harness scripts. `games/<game>/init.lua` holds the wiring they share. Nothing else knows which platform it runs on.
- No ambient context in `core/` or `games/`: no `os.time`, `os.date`, `print` or emulator globals. Clocks, timestamps and output arrive as parameters.
- Tests follow the seams: the grader is tested with the Lua checker as its source, the entry script with a fake FBNeo API, and the whole stack against the real game in MAME.

### Layers and abstraction ownership

- `core/` is game-agnostic: input history, card, pearls, menu, drawing, CSV, hook multiplexer, app. It never requires a game or a platform module.
- `games/<game>/` implements the game module interface that `core/app.lua` consumes, and declares the source interface its grader consumes (`sources.lua`).
- `platform/` implements the platform interface that `core/run.lua` and the game modules consume.
- The interface belongs to the consumer. `docs/porting.md` is its specification.

### Lua dialect and types

- Everything that runs in the emulator is Lua 5.1, the version FBNeo embeds. Tests run on LuaJIT (5.1) and Lua 5.4 so neither dialect drifts in.
- No bitwise operators: use `core/bits.lua`.
- Public functions carry LuaLS annotations (`---@param`). Boundaries are checked at runtime: ROM hashes before any tool runs, the ROM name when the script loads, and every callback is guarded.

### Code comments

- Code is self-evident. Comments are a last resort.
- A comment is only justified by a non-obvious why: a game quirk kept on purpose, a hidden constraint, an emulator limitation.
- The checker port is the exception that proves the rule: it keeps the decomp's names so it can be read side by side with `CMD_MAIN_2.C`.

### Dependency hygiene

- No runtime dependencies. The scripts use only what the emulator provides.
- Tooling (Lua interpreters, MAME, Python, formatter, linter) is pinned by `flake.lock`. The decomp is a pinned flake input.
- If it is under 50 lines, write it: the test runner and the bit helpers are hand-written.

### Error handling

- No silent failures. An error in a callback is caught, printed once with what failed, and the next frame tries again. FBNeo unloads a script whose callback throws, which would end the player's session.
- Tools fail loudly with context: a ROM that does not hash, a slot table that is not found, a record that disagrees with the decomp.

### Local checks before pushing

- `nix run .#check` runs the formatter check, the linter and the tests on both Lua dialects.
- Touching the checker, the RAM map, the tracker or the grader also needs `nix run .#validate` and `nix run .#grade` (both need the ROMs in `roms/`).

### Reproducible, one-command environment

- `nix develop` gives the pinned toolchain. `nix run .#<app>` runs any task without entering the shell.
- `roms.sha1` pins the ROM files by content. ROMs are never committed.
- The emulator that matters for players, Fightcade's FBNeo, cannot be pinned from here: the tested Fightcade version is recorded in the README instead.

### Git conventions

- [Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `revert`. Scope optional and lowercase, for example `fix(sfiii3):`.
- Imperative mood, subject under 72 characters, body for the why.
- No value-judgement words ("improve", "better", "cleaner", "robust") and no vague qualifiers ("various", "ensure").
- No AI attribution and no Co-Authored-By for AI tools.
- One logical change per commit.

### Writing style

Docs, commit messages and comments follow these rules. Most of them avoid the habits listed in Wikipedia's [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing).

- Write for the reader of that page. The README is for players; developer detail goes in `docs/development.md` or the internals.
- Sentence case in headings, and no headings phrased as questions or starting with a question word (What, How, Why, Where).
- Plain, short sentences. Split a sentence that chains clauses with colons, or nests parentheses.
- No fragments as openers ("Plain keys, no setup."). Start with a full sentence that says what the thing is.
- Bold sparingly, and never as a label at the start of a list item.
- No em-dashes. Use a colon, comma, semicolon or period.
- No rhetorical triplets, and no "not X but Y" contrasts against a claim nobody made.
- No claims of significance ("stands as", "serves as", "a testament to"), and no "-ing" tails that add importance ("highlighting how…").
- Say each fact once, in one place, and link to it from elsewhere.
- Image alt text is one sentence.
- Never hard-wrap markdown: one line per paragraph and per list item.

## Use of AI and LLMs

LLMs may write code here, held to the same standards as any other code: tests at the unit and real-game levels, ground-truth data, and review of every change.

Before committing, an agent runs the `stripping-code-comments` skill over its diff: delete every comment it added, make the code clear without them, move the reasons worth keeping into tests named after them, and report the rest for a person to decide.

## Not adopted from the original

TypeScript, pnpm, Biome, Renovate and the package budgets do not apply to Lua emulator scripts. The service baselines (observability, authentication, health-data privacy) do not apply to an offline training tool. CI is not set up yet: the real-game checks need ROMs, which cannot be distributed.
