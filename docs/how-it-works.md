# Internals

The grader reads 3rd Strike's own command-input state from emulator memory every frame and explains each attempt in the game's terms: which step matched when, how many frames each window allowed, and what went wrong. This page covers where the data comes from, how it was verified, and what the game actually does.

## The game's command check

3rd Strike checks motions with one small state machine per move, called every frame for each player (`waza_check` in the arcade decomp's [`CMD_MAIN_2.C`](https://github.com/gibletto/sfIII3-cps3-decomp/blob/main/src/cmd_main_2.c)).

- Each character has 56 command slots: dashes, parries and mashing in 0 to 15, super arts from 20, ground specials from 28, air specials from 46.
- Each slot runs a record: a 12-word header (how long a completed motion stays ready, which inputs cancel it, which buttons start which strength) and a list of steps.
- A step names a check routine and a window. The common one, `CK_LEVER`, waits up to `time` frames for an exact direction; other routines handle charges, 360s, "press then let go" and mashing.
- When the last step matches, the slot's flag is set to the record's `reset` value and counts down. The move starts if a fitting button is pressed (or, for most moves, released) while the flag is non-zero.

Directions are relative to the facing the command check uses (`rl_waza`), which can differ from the sprite's facing for a few frames around a cross-up.

## Data sources

| Data | Source | How it is checked |
| --- | --- | --- |
| Command records (steps, windows, buttons) | Decrypted program ROM (`tools/romdump.py`, `tools/gen_commands.py`) | Every record matches the [arcade decomp](https://github.com/gibletto/sfIII3-cps3-decomp)'s `data/cmd_data.c` |
| Move names and notation | The decomp's annotations | Names marked `(?)` are the decomp's guesses |
| Super art to slot mapping | The decomp's `super_arts_data` | |
| Struct layouts and offsets | `offsetof()` over the decomp's headers (`tools/offsets.c`) | Cross-checked with [3rd_training_lua](https://github.com/Grouflon/3rd_training_lua)'s independent addresses |
| RAM addresses of `WORK_CP` and `WAZA_WORK` | Found by scanning RAM in MAME for known values | Validated frame by frame (below) |
| Player object, match state | 3rd_training_lua | |

The generated tables live in `lua/input_grader/games/sfiii3/commands.lua`; `nix run .#gen` rebuilds them byte for byte from the ROM and the pinned decomp.

### RAM map (P1, P2)

| What | P1 | P2 | Notes |
| --- | --- | --- | --- |
| `WORK_CP` (inputs, `waza_flag[56]`) | `0x02026318` | `0x0202671E` | 1030 bytes; `waza_flag` at `+0x16` |
| `WAZA_WORK[56]` (per-slot state) | `0x020256C4` | `0x02025CE4` | 28 bytes per slot; `w_ptr` at `+8` points into the ROM record |
| Player object | `0x02068C6C` | `0x02069104` | `rl_waza` `+0x0B`, height `+0x68`, `routine_no` `+0x24`, character `+0x3C0`, `sa_stop_flag` `+0x41C`, `do_not_move` `+0x455` |
| Command slot table (ROM, 990608) | `0x06613968` | | Used by the table generator only |

Each slot's `w_ptr` points at the next step of its ROM record. Rather than look records up in ROM, which depends on the revision and on the emulator letting Lua read ROM, the reader takes the smallest `w_ptr` seen per slot as "waiting for step 1": every slot is idle most of the time, and an idle slot always points just past its first step. Step numbers follow from the 8-byte step size.

The training script's Chun-Li kick counters (`0x02025A03`) and Alex charge counters (`0x02025A49`) land exactly on slot 29's `flag` and slot 32's `free1` in this layout, which is independent confirmation of the `WAZA_WORK` address.

## Verification

### The Lua checker against the game

`lua/input_grader/games/sfiii3/checker.lua` is a transliteration of the game's check. `harness/mame/validate.lua` drives Ryu in a real match with randomized motions and input noise, and on every frame:

1. loads the game's command state from RAM into the Lua checker,
2. steps the checker with the input word the game read,
3. compares all 56 slots, every field, with RAM on the next frame.

Frames where the game did not run the check (super freeze, `do_not_move`) and slots that game code outside the check reset (when a move starts, a jump starts or lands) are recognised and counted separately.

| Run (flake's pinned MAME) | Frames compared | Frames with a mismatch |
| --- | --- | --- |
| All 21 character entries, 120 attempts each (`VALIDATE_CHAR=0..20`) | 142,748 | 0 |
| Ryu, 400 attempts, seed 3 | 22,705 | 0 |
| Ryu on the 990512 set (`ROMSET=sfiii3nr1`), 400 attempts, seed 21 | 22,661 | 0 |
| Ryu, 600 attempts, seed 11 | 34,033 | 1, in the high-jump and parry slots, which the grader does not use |

### The grader against the game

`harness/mame/grade.lua` plays scripted attempts in a real match and checks the live grader's verdict: a clean Hadoken, a skipped diagonal, a slow diagonal, a late button, an early button held through the motion, an early press released on 6, a cancel by pressing up, a Shoryuken and a Tatsumaki. All nine pass.

## Live grading

Live grading does not simulate anything. Every frame the game ran its check, `games/sfiii3/sources.lua` reads the inputs, the facing and every slot's state from RAM, plus whether a move started (`routine_no`). From that:

- `tracker.lua` turns slot state changes into runs: the check frame each step matched, the completion, and resets with their cause (a timeout or a cancelling input).
- `game.lua` waits a few frames after each button press (an early press can still turn into a move on release), picks the move the player was going for, and grades it.

Frames are counted in check frames, the clock the game's windows use, so super freeze does not count against the player.

### Picking the intended move

A button press is graded only when it looks like an attempt at a special move, so moving around and pressing buttons between reps stays silent. A move qualifies when its button fits the press and:

- **The game started it.** Always graded, as out.
- **Most of its motion is there, in order.** At least half its directions and at least 2: the steps the game accepted, then the remaining directions as they followed, allowing one to be missing (a skipped diagonal).
- **Its directions came in time.** A direction later than its window by more than the 8-frame grace is not part of the same motion, so two Hadokens in a row are not a super with a 30-frame gap.
- **The motion ended close to the button.** A finished motion may be followed by a late button, up to 8 frames past the button window, which is graded as late. An unfinished motion counts only if its last direction came within 3 frames of the button, so a crouch held for a while before a cr.HP is not a missed Shoryuken.
- **It's on the right ground.** Ground moves only on the ground, air moves only in the air.

With a target move set (Alt+8), only that move is considered, and any of its motion ending close to the button counts. That's the mode for drilling one move while moving freely in between. Among qualifying moves, the one that got furthest wins; ties go to the move that came out, then the longer motion.

`tests/test_intent.lua` pins this against ordinary play: dashes, jumps, walking, crouch-blocking, normals and throws produce no attempt. One input stays ambiguous by nature: crouch, roll to down-forward and press a punch is both a cr.LP and a Hadoken missing its 6, and is graded as the latter.

### Verdicts

| Code | Meaning |
| --- | --- |
| out | The move started |
| `skipped_step` | A diagonal never appeared but the next direction did ("went from 2 to 6 without 3") |
| `too_slow` | The direction came, but after its window closed |
| `missing_step` | The motion never reached a direction |
| `early_button` | The button came before the motion completed, and was still held after the window |
| `late_button` | The button came after the window that follows the motion |
| `wrong_button` | The motion was complete, but the button was one the move does not take (a punch for the Tatsumaki). Without a target, only when the button came inside the window and fits no other move |
| `cancelled` | An input that cancels the motion (exactly up, for most specials) arrived mid-motion |
| `other_move` | A different move started (for example the super instead of the Hadoken) |
| `parry_early`, `parry_late` | The parry tap came before the window could reach the hit, or after the hit |
| `parry_direction` | The tap was forward against a low attack, or down against one that is only high |
| `no_parry` | The attack connected with no tap |
| `followup_early` | The press after a dash came before the dash let you act; the game dropped it |
| `throw_split`, `throw_whiff` | LP and LK did not land together, or the throw was out of range |
| `mash_short`, `mash_mixed` | Fewer than five presses of one strength, or five split across strengths |
| `cancel_late`, `cancel_early` | Motion and button were in time during an attack, but the press came after the attack's cancel window closed, or before the attack connected |
| `cancel_whiff`, `cancel_none` | The attack being cancelled missed, or connected but has no frames that cancel into this kind of move |
| `no_meter` | A super art with no stock ready (`SA_WORK.ok` 0) |
| `projectile_alive` | A projectile move while the fighter's projectile from it is still on screen |
| `super_art_only` | A move that only works while the super art runs (Q's Ningen Bakudan) |
| `not_allowed` | Motion and button were in time, but the game did not start the move for none of the reasons above |

## Cancels

A special or super pressed during a normal comes out only inside the normal's cancel window (`check_cg_cancel_data` in `PLS00.c`): the attack must have hit or been blocked (`meoshi_hit_flag`, player + 0x2FF), and its current animation frame must allow the move (`cg_cancel`, player + 0x221: `0x40` for super arts, `0x20` for specials). The check sees the state the previous frame ended with.

`harness/mame/cancel.lua` measured Ryu's 2MK into SA I on Fightcade's 990512 set:

| HP after MK | On hit or block | On whiff |
| --- | --- | --- |
| 5 to 6 frames | refused: before contact | refused |
| 7 to 19 frames | super, cancelled | refused |
| 20 to 29 frames | refused: the window closed | refused |
| 30 frames or more | super, after the kick recovered | super, from 27 |

At 7 frames the press itself is a frame early, and the game takes the button's release on the next frame. When the game refuses a move whose motion and button were in time during an attack, the grader reads this window from RAM and names the miss instead of reporting a refusal. The live cases in `harness/mame/grade.lua` cover a cancel in the window, 3 frames late, before a blocked kick connects, and after a whiff.

## Refusals

The game also refuses a move whose motion and button were in time for reasons outside the input (`PLS03.c`). The grader reads them from RAM and names them; the card shows them in grey, and they count as good input.

- **No meter**: `check_super_arts_attack` starts a super art only while the player's `SA_WORK.ok` (through `PLW.sa`, player + 0x3F0) is 1. It is 0 without a stock and -1 while the art runs.
- **Projectile on screen**: `check_special_attack` skips a move flagged `CMD_BT_SHELL` while `shell_live_check` finds a projectile from it: the fighter lists its projectiles in `shell_ix` (player + 0x34C), each an effect block at `0x02028990 + index × 0x800` whose `original_vitality` (+0x362) holds the command slot that fired it, unless `refrected` (+0x3C5) says it was reflected. For Gouki any of slots 31, 33 and 46 blocks them all. The flag is in the ROM tables, so every character's projectile moves are covered.
- **Super art only**: moves flagged `CMD_BT_SA_ONLY` start only while `SA_WORK.ok` is -1.

`harness/mame/refusals.lua` logs these fields through a super with and without meter, two Hadokens in a row and an EX Hadoken. An EX special without meter is never refused: the game starts the normal version. The live cases in `harness/mame/grade.lua` cover a super without meter and a Hadoken while the last one is on screen.

## Parries

The game parries in `defense_ground` and `defense_sky` (`HITCHECK.C`): when an attack connects, the parry is taken if the slot of the tapped direction still has a positive flag. Measured in MAME (`harness/mame/parry.lua`, Ryu against Ryu's standing MP and crouching MK):

- A forward tap sets slot 3's flag to 10 on the next frame, then the flag counts down by one per frame. The attack is parried if it connects while the flag is positive: from 9 frames after the tap's frame to the frame itself.
- Down sets slot 4 the same way, for low attacks. The attack's `att.guard` bits say which it accepts: 0x02 high (standing MP: 0x3E), 0x01 low (crouching MK: 0x2D), 0x04 air.
- Jump-ins use slot 12, which the same forward tap sets to 5: a 5-frame window.
- Right after blocking (`guard_chuu` 1 to 4) a red parry needs the flag at least 9 (specials) or 8 (normals), from `blocking_term_tbl`: 2 or 3 frames.

The grader watches the flags and P1's routine (`routine_no` 0.31 to 0.35 parried, 1.x hit or blocked), and grades each contact a few frames later so a late tap is seen. The live cases in `harness/mame/grade.lua` cover a parry in the window, too early, too late, the wrong direction and a low parry.

## Timing after a dash

`harness/mame/throw.lua` measured Ryu's dashes and throws:

- A forward dash is P1 routine 0.5, a back dash 0.6. Each frame of animation carries a type (`cg_type`, player + 0x215); in RAM, a press seen on a frame whose type is 2, 3 or 64 starts a move, and an earlier press is dropped. After a forward dash that is 12 frames after its last input.
- A throw starts as routine 4.14 and becomes 2.2 (throwing) two frames later when in range; out of range it stays 4.14, the whiff.
- From standing, LP and LK must land on the same frame: LK one frame later gives a jab. Right after a dash the game also threw on LP then LK one frame later, so the grader judges a throw by its outcome and only calls the buttons split when no throw came.

The follow-up targets grade the first press after the dash against that first frame. The live cases in `harness/mame/grade.lua` cover a throw on the first frame, one frame early, three late, LP and LK two frames apart, and out of range.

## Mash moves

Chun-Li's Hyakuretsukyaku (slot 29) is the only move whose command is a mash step (`CK_RENDA`): five presses of the same strength while the step's count runs (98 frames, restarted when it runs out). Each strength has its own counter, so LK, LK, LK, MK, MK is not five. Slots 8 to 11 ("punch mashing", "kick mashing") are different: animation scripts read them (`comm_rapp` and friends in `CHARMOVE.c`) to keep a move going while the player keeps mashing, so they are not targets. `harness/mame/mash.lua` checks five LK, mixed strengths and four LK live.

## Surprises in the game's input rules

Each of these is pinned by a test in `tests/test_checker.lua` or `harness/mame/grade.lua`.

- **Holding the first direction re-arms it, every 11 frames.** Once 2 is accepted, 3 must follow within 10 frames; if that runs out while 2 is still held, the game accepts 2 again and starts a fresh 10. So the window counts from the last re-acceptance, not from letting go: hold 2, then pass through 1 for 6 frames before 3, and the Hadoken comes out after a 1 to 4 frame hold, fails after 5 to 11, works again after 12 to 15, and so on.
- **Windows count from the previous step.** "3 within 10 frames" means within 10 frames of the frame 2 matched.
- **The button window is 10 frames for almost every move.** The motion may complete on the same frame as the button, or the button may follow up to 10 frames later.
- **Most specials and supers accept the release of a button.** A button pressed early and let go on the last direction still works (negative edge), unless the press started a normal and the character is busy.
- **The Shoryuken's first step has no time limit.** 6 may be held as long as you like; 2 must come within 5 frames of letting go of 6.
- **Super motions skip the last 6.** 236236+P is checked as 2 3 6 2 3: the final 6 is not needed.
- **Only an exact up cancels.** The cancelling input is compared with the whole input word, so up-forward does not cancel a Hadoken, but neutral up does.
- **The selected super art is checked before specials.** A super motion also contains a Hadoken motion; the super wins when it can start.

See [windows.md](windows.md) for every character's steps and windows.

## Deviations of the Lua checker from the game

- Meter, a projectile already on screen and super-art-only moves are not modelled in `Checker:start()`. Live grading reads the game's own decision instead.
- The simulator source (`sources.sim`) blocks new moves for 30 frames after one starts, standing in for recovery and spent meter.
- Game code outside the check that resets slots (move start, jump start and landing) is not modelled; live grading reads the result from RAM.

## Known limits

- Validated on both Japan sets: 990608 (`sfiii3n`) and 990512 (`sfiii3nr1`, the one Fightcade runs). The end-to-end grading cases pass on both.
- P1 only. The RAM map has P2's addresses; the overlay and options do not expose P2 yet.
- The end-to-end grading cases use Ryu. Every character's checker has been validated frame by frame, but the verdicts have only been spot-checked with Ryu's moves.
- Charge, 360 and mash moves are graded from the game's state, but their feedback is less specific than for motions.
