# Agent instructions

Read [ENGINEERING.md](ENGINEERING.md) before changing anything. Its principles apply to code, and its writing style to every doc, commit message and comment you write.

- Before committing, run `nix run .#check`. Changes to the checker, the RAM map, the tracker or the grader also need `nix run .#validate` and `nix run .#grade` (with `ROMSET=sfiii3nr1` for Fightcade's revision).
- Before committing, run the `stripping-code-comments` skill over your diff.
- Commits follow the Git conventions in ENGINEERING.md, with no AI attribution.
