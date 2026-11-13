> Research notes, read from the arcade decomp's C and not yet confirmed in the emulator. Frame offsets marked as uncertain need a MAME trace before the grader relies on them.

# 3rd Strike input-timing catalogue (non-motion mechanics)

Source: `vendor/sfIII3-cps3-decomp` (paths below are relative to it, `src/` and `data/` implied by file name). Everything here is read from the C; nothing was run in an emulator, so frame-offset claims are marked where an off-by-one is possible. Offsets are from `offsetof()` over `include/structs.h` (gcc -m32), same method as `tools/offsets.c`, and agree with the existing `ram.lua` values (`player_number` 0x3C0, `sa_stop_flag` 0x41C).

## Conventions used throughout

- Per frame, per player: `Player_move` (PLMAIN.c:73) runs `waza_check` (sw_pick_up + cmd_move, cmd_main_2.c:98), then `player_mv_4000` (PLMAIN.c:250) runs `check_lever_data` (PLS00.c:33, the per-state input checks), then `check_hit_stop`, then the state routine (animation `char_move`), then `look_after_timers`.
- So an input check on frame F sees the animation line loaded by the state routine on frame F-1. Define frame 0 as the frame an action is accepted (routine_no changed in `check_lever_data`, animation line 1 loaded by the state routine that same frame). An animation line with start offset S (sum of ctr of the lines before it) is first visible to input checks on frame S+1.
- Button words in `WORK_CP` (cmd_main_2.c:1511-1626): `sw_new` = held this frame (relative to facing, with synthetic PP/KK bits), `sw_old` = held last frame, `sw_now` = `sw_new & ~sw_old` = NEW presses this frame only, `sw_off` = releases this frame, `sw_chg` = presses or releases, `old_now` = last frame's `sw_now`. `ca14/ca25/ca36` = (old_now | sw_now) contains both buttons (LP+LK / MP+MK / HP+HK).
- Animation line fields (`include/charscr.h` L4 macro, copied verbatim into PLW fields by `check_cgd_patdat`): `cg_ctr` frames, `cg_type` action gate, `cg_cancel` cancel bitmask, `cg_meoshi` chain button set. Every frame line in `data/<char>_char.c` carries them, so per-move timing is tabled and can be parsed (I did for dashes, landing, normals, throws).
- `cg_type` meanings as the input code uses them: 0 nothing, 1 movement cue, 2 "may attack/special/throw/jump but not dash/walk/crouch" (jumping_cg_type_check, PLS00.c:694), 3 "may do everything", 7 "attacks only", 64 "go to neutral now" (TO_nm_36000/37000 which runs the full neutral check), 0xFF end of script.
- `cg_cancel` bits (check_cg_cancel_data, PLS00.c:1633): 0x01 super-jump cancel, 0x02 dash cancel, 0x04 cancel into a different normal, 0x08 chain/target combo, 0x10 rapid repeat of the same normal, 0x20 special cancel, 0x40 super cancel, 0x80 release-trigger flag. 0x01/0x02 and 0x20/0x40 need `meoshi_hit_flag` (set on hit, block or parry by dm_status_copy, HITCHECK.c:1077; whiff leaves it 0).

## Prioritised summary

| # | Mechanic | How often players fail it | Grading feasibility |
|---|---|---|---|
| 1 | Press on or after first actionable frame (no buffer for normals or throws) | Very high | Medium: needs `permited_koa`/`cg_type` plus press history |
| 2 | Throw needs LP+LK within 1 frame, and loses to a 1-frame kara window (jab vs throw) | Very high | Easy: pure input timing plus `cancel_timer` |
| 3 | Special/super cancel window (contact flag and `cg_cancel` bits) | High | Medium: `cg_cancel`, `meoshi_hit_flag`, hit_stop |
| 4 | EX moves: two buttons must land on the same frame | High | Easy: input only |
| 5 | Chain/target combo and rapid repeat (held button outside the chain set, wrong lever, wrong button) | Medium-high | Medium |
| 6 | Link timing (attacker free frame vs defender free frame) | High | Medium-hard: needs both players' `cg_type` plus the next move's startup |
| 7 | Throw tech (LP+LK within 6 frames, blocked by `hazusenai_flag`) | Medium-high | Easy to medium |
| 8 | Throw whiff reasons (opponent throw-immune 6 frames after recovery, wrong state, range) | High | Medium |
| 9 | Parry (10-frame window, red-parry 2-3 frames, neutral-first, tap not hold) | High | Easy (already partly built) |
| 10 | Super jump (down then up within 8 frames, flag lasts 8 frames) | Medium | Easy |
| 11 | Dash (8-frame buffer, no input accepted until `cg_type` 2/3/64, cannot block meanwhile) | Medium | Medium (per-char tables, hop dashes variable) |
| 12 | Reversal / wake-up (motion buffer 12 frames, button must be an edge on or after the free frame) | High | Medium |
| 13 | Quick stand / ukemi (down tap in a 6-frame window) | Medium | Medium |
| 14 | Super freeze eats inputs (command check off in the freeze's last 4 frames) | Medium | Medium |
| 15 | Far vs close normal, taunt, leap, up/down held during throw | Low-medium | Easy |

## 1. Actionable frame and input buffering

### Rule

- There is no input buffer for normals, throws, taunt or leap. `check_nm_attack` (PLS03ATT.c:43) selects the strength with `shot_data_convert(wk->cp->sw_now)` (PLS03ATT.c:498): only buttons newly pressed on this very frame count. A button held from before does not count. If two buttons are new on the same frame the winner is HP > HK > MP > MK > LP > LK (loop order over `shot_prio`, last match wins, data/PLS03_tbl.c:25).
- Specials and supers: the lever motion is buffered, the button is not. A finished motion stays in `waza_flag[slot]` for `reset` frames (12 for specials, CMD_RESET, `command_ok` cmd_main_2.c:1470, decremented by `command_ok_move` cmd_main_2.c:1480). The button is tested on the frame the move starts, from `sw_chg` (btix index 5 = CMD_BT_CHG, PLS03.c check_special_attack), which is press OR release. So a held button released on an actionable frame fires the move (negative edge), but a press before the actionable frame is lost.
- "Actionable" is not one flag. It is the union of which check functions the current state's routine calls, in `data/PLS00_tbl.c:73` `plpnm_xxxxx[]` (normal states) and `plpdm_xxxxx[]` (damage states), together with the `cg_type` of the current animation line (PLS00.c:694 `jumping_cg_type_check`).
    - Neutral states (stand 1, turn 2, walk 3/4, crouch 8/9/10, block 27/29, ...) call every check each frame. Order in `nm_01000` (PLS00.c:110): super, special, taunt, throw, leap, normal, cancel data, turn, dash, 360 jump, jump, crouch, block, walk.
    - Attack states (`process_attack`, PLS00.c:1585) do nothing except cancel checks until the animation line has `cg_type` 64/255 (then `jumping_cg_type_check` hands over to neutral). The line with `cg_type` 64 is the first actionable line.
    - Dash (`nm_05000`, PLS00.c:288): only `jumping_cg_type_check`. Type 2 line allows attacks, throws, specials, jump (not another dash); type 3 allows all; type 64 hands over to `nm_36000`, which allows all.
    - Prejump (`nm_16000/17000`, PLS00.c:545/591): only super/special/taunt/leap. No normals or throws for the prejump frames (3 frames for a jump, 5 for super jump, `nmca_012/013`).
    - Jump landing: the landing script (for example `exca_001` via RJA slots set in `cbca_003`) is 0-1 frame of `cg_type` 0, then type 2, then type 3 (see below). Uncertain which landing script each jump uses, see open questions.
    - Blockstun / hitstun (`process_damage`, PLS00.c:1395): `dm_04000` (PLS00.c:1420, states 1-4,12,13,16) and `dm_08000`. On `cg_type` 64 or 0xFF it calls `TO_nm_36000/01000`, i.e. neutral, and sets `tsukamarenai_flag = 7` (throw protection, see section 2). The stun length is the guard/damage pause (`guard_pause_table` data/etc.c:16: 8/11/14/16 frames by attack level for the slide phase, 12/15/18/20 for the airborne variant; `damage_pause_table` for hit) plus the rest of the reaction animation up to its type-64 line.
    - Wake-up (`dm_18000`, PLS00.c:1488): at `cg_type` 64 goes to `TO_nm_36000` (neutral) with `tsukamarenai_flag = 7`.
    - Parry (`nm_31000`, PLS00.c:1120): `cg_type` 0 (the whole parry animation until the type-64 line) already allows specials, supers, throws, normals. Parry freeze is `dm_stop = -15`, negative hit stop: the animation keeps running (`check_hit_stop` PLMAIN.c:279-306, `hit_stop++` then `char_move`) and `check_lever_data` runs, so the defender can act during the freeze while the attacker is frozen 16+ frames (`set_paring_status`, HITCHECK.c:548-604).
- `check_lever_data` runs before `check_hit_stop`, even during hit stop (PLMAIN.c:253-259), except `sa_stop_flag == 1` (super freeze, below). So presses during hit stop are evaluated, but the animation line (and so `cg_type`) does not advance during hit stop, so an actionable state is not reached sooner. Cancels (section 4) can fire inside hit stop.

### RAM

- `PLW.permited_koa` (0x46C, u16), cleared at the top of `player_mv_4000` (PLMAIN.c:251) and OR-ed as each check is reached: 0x01 super, 0x02 special (only when `cancel_timer == 0`), 0x04 normal (`check_nm_attack`, PLS03ATT.c:46), 0x08 lever-up attack (dead code), 0x10 chain (`check_meoshi_cancel`), 0x20 rapid repeat, 0x40 EX full gauge, 0x80 taunt, 0x100 throw, 0x200 leap. It is only consumed by the CPU AI (Com_Sub.c) but it is an exact "the game was willing to evaluate this action class this frame" indicator. It is only complete on a frame where no earlier check succeeded (the chain returns on first success).
- `PLW.wu.cg_type` (WORK+0x215), `cg_cancel` (+0x221), `cg_ctr` (+0x214), `routine_no[0..3]` (+0x24), `hit_stop` (+0x44), `dm_stop` (+0x32E), `meoshi_hit_flag` (+0x2FF), `PLW.cp` pointer (+0x3B8) to `WORK_CP` (sw_lvbt 0x0, sw_new 0x2, sw_old 0x4, sw_now 0x6, sw_off 0x8, sw_chg 0xA, old_now 0xC, ca14 0x10, ca25 0x11, ca36 0x12, lever_dir 0x15, waza_flag[] 0x16, reset[] 0x86).
- Because `cg_type` changes in the state routine after the input check, reading RAM at end of frame F and seeing `cg_type` in {2,3,7,64,255} means an input on frame F+1 is accepted.

### Failure modes and detection

- Button pressed before the free frame: record the first frame a new press of the intended button occurred, compare with the first frame where `permited_koa` has the 0x04 (or 0x100, 0x02) bit. Press frame < free frame means "too early: no buffer, the press was discarded". Pressing again later works; holding does not.
- Button held across the free frame: `sw_now` is 0 on the free frame, nothing happens. Detect: `sw_new` has the button, `sw_now` does not, and `permited_koa` bit set.
- Special motion done, button early: `waza_flag[slot]` nonzero but the press frame was not actionable.
- Motion older than 12 frames when the button is pressed: `waza_flag` back to 0.
- Dash command done (`waza_flag[0/1]` set for 8 frames) but state not yet accepting dash (before type 3 / 64): dash starts as soon as allowed within those 8 frames, otherwise lost.

Grading feasibility: medium. Needs per-frame sampling of `permited_koa` and press edges (the existing tracker already has `sw_*`), but no new tables.

## 2. Throws

### Input rule

- `check_catch_attack` (PLS03ATT.c:234): requires `cp->ca14` (LP and LK both NEW within a window of the current frame and the previous frame: `ca14 = ((old_now | sw_now) & (LP|LK)) == (LP|LK)`, cmd_main_2.c:1603-1608), `pcon_dp_flag == 0`, `spmv_ng_flag & 0x2000 == 0`. No range check before the attempt starts: the throw animation always starts, range only decides whether it connects.
- Direction: `kos = held-forward + 2*held-back` from `sw_new`. Holding up returns 0 (no throw). Holding down returns 0 for every character (`nml_catch_h2_ok[0][pl] = 16`, bit 1 never set, data/PLS03_tbl.c:20), so you get a crouching LP instead. Air throws only for Ibuki, Oro, Chun-Li (`nml_catch_h2_ok[1] = 17` at rows 7, 9, 16) and only at height >= 24.
- Order: throw is tested before normals (nm_01000), and `check_chouhatsu` (taunt) before it. If both buttons are new on the same frame or one frame apart in the right order the throw wins. If LP is new on frame t and LK on t+1, frame t starts a jab (ca14 false), but see the kara window.
- Kara window (important): every normal sets `cancel_timer = 2` in its RN3_START (`get_cancel_timer`, PLPAT.c:793; value 0 after a target-combo first hit). `process_attack` (PLS00.c:1585-1612) decrements it at the top of each later frame (only when `hit_stop == 0`) and while nonzero lets supers, specials, taunt, throw, leap interrupt the normal. Net effect: exactly one frame, frame 1 (the frame after the normal was accepted). So LP on t then LK on t+1 gives a THROW (cancelling the jab), LK 2+ frames later gives the jab and the LK is wasted (the jab state accepts no normal until its free line). Same one-frame window for a special or super button after a normal button (kara cancel). `process_attack` also lets full-gauge arts flagged `CMD_BT_ALWAYS` start at any frame of a non-special attack (`check_full_gauge_attack(wk, 1)`, PLS00.c:1608).
- Failure statement for the overlay: "second throw button came N frames after the first": N = 0 or 1 -> throw; N >= 2 -> normal (jab/short), whichever was first.

### Range, hit check, whiff recovery

- Range is geometry, not a number: the throw attempt animation (e.g. Ryu `atca_144`: 2 frames, then a 1-frame line with attack field -48 and `hit` row 97, then 20 frames of recovery) has ONE active frame (frame 3 of the attempt on most characters) in which the catch box (`<char>_cat_box`, referenced from the `caix` column of `<char>_hit_ix_table`) must overlap the opponent's caught box (`cau_box`, `cuix` column). `catch_hit_check` (HITCHECK.c:1185) does this. Ryu: cat_box x=-49, w=24 (data/ryu_attbox.c:92), standing cau_box x=-25, w=50 so max centre distance about 74 px (sign/mirroring assumed, uncertain). Forward edge of the catch box per character (px): Gill 52, Alex 58, Ryu/Ken/Gouki 49, Yun/Yang 39, Dudley 45, Necro 49, Hugo 62, Ibuki 40, Elena 45, Oro 48, Sean 45, Urien 50, Chun-Li 48, Makoto 45, Q 46, Twelve 38, Remy 30 (from the `TUKAMIKAKARI A` rows of `data/*_attbox.c`).
- Whiff recovery: Ryu/Alex/Yun/Dudley/Hugo/Yang attempt = 23 frames with no actionable line (cg_type only 255 at the end); others (Gill, Necro, Ibuki, Oro, Ken, Sean, Urien, Gouki, Chun, Makoto, Q, Twelve, Remy) have a type-64 line a few frames before the end (parse of `atca_144`: totals 25-33 frames). Elena's and the 2nd Gouki's scripts use jumps, my linear parse is not valid for them.
- The opponent cannot be thrown when (catch_hit_check, HITCHECK.c:1223-1247):
    - `tsukamarenai_flag != 0` (PLW 0x3C7). Set to 7 on every return to neutral from block/hit stun (`dm_04000` cg_type 64/255, `dm_08000`, `dm_18000`, PLS00.c:1428-1506, PLPDM.c:587/606) and set every airborne frame plus landing of an air knockdown (`Damage_17000`). Decremented once per frame in `look_after_timers` (PLMAIN.c:349, same frame it is set), so the opponent is throw-proof for 6 consecutive frames starting on the first actionable frame (frames F..F+5). A throw whose active frame lands there whiffs.
    - Defender in `PLAYER_DAMAGE` and not at `RN3_START` and not `DAMAGE_STUN` (dizzy): hit-stunned players cannot be thrown (unless the throw has `att.dipsw & 0x60`, the pursuit-throws, checked against `dm_oiuchi_catch`).
    - Wake-up: all OKIAGARI frames use `hit_ix` row 0 or 12, which have `boix = 0` and `cuix = 0` (data/ryu_hitbox.c rows 0 and 12): no body box and no caught box, so fully invulnerable. Ryu's OKIAGARI script is 12+1+2+2+2+4+3+4+4+6+2+1 = 43 frames of this, the type-64 line itself is also row 0.
    - Any frame whose `cuix` row is 0 (no caught box), and airborne frames use the jump caught box (row 3, y from 48) so ground throws miss.
    - Exception: throws with `att.guard & 0x18` skip the `tsukamarenai_flag` and state tests (HITCHECK.c:1229-1230). Which moves have it was not checked.
- Throw clash: both players grabbing on the same frame goes through `set_caught_status` (HITCHECK.c:132-262): if one side is in a parry command window (`waza_flag[3]+[4] != 0`, `check_blocking_flag` HITCHECK.c:297) it loses, otherwise `Game_timer & 1` decides. Update order between the two players (who is processed first) alternates on `Game_timer & 1` unless exactly one player is in `PLAYER_ATTACK` (that one goes first), `tsukami_f` is set or only one side is human (plcntset_2.c:660-699).

### Throw tech

- Window: when a throw connects the thrower runs `set_char_move_init_ca` (PLPCA.c:506): `cat_break_ok_timer = cmyd.koc >> 8` from the throw script's `CM_NGDA` arg. 1542 (0x0606) on all 91 normal and most special throws means 6 frames. 0 means untechable (command throws and supers: 41 uses, in alex, gouki1/2, hugo, ibuki, makoto, necro, oro, q, yang, yun). 1536 (Ibuki) means tech 6, no quick-stand; plain 6 means no tech window but a 6-frame ukemi window.
- `check_nagenuke` (PLPCA.c:116) runs every frame in `Player_catch` while `cat_break_ok_timer != 0` (decremented in `look_after_timers`, so the checks happen on timer values 6..1, six frames starting on the grab frame). Tech condition (`check_nagenuke_cmd`, PLS03ATT.c:219): victim `cat_break_reserve` OR (victim `ca14` and `(sw_now & 0x660) == 0`, i.e. no MP, HP, MK, HK newly pressed that frame; LP and LK may be new). Because `ca14` uses `old_now`, LP+LK pressed together on the frame BEFORE the grab already counts on the grab frame.
- Blocked from teching (`hazusenai_flag`, PLW 0x436): set when the victim is grabbed while `guard_flag == 3` or while a parry command is live (`waza_flag[3]` or `[4]` nonzero, i.e. a forward or down tap in the last 10 frames) (HITCHECK.c:253). `guard_flag == 3` is the state in all attack states (PLPAT.c:201), dashes, prejump, damage start, thrown and throwing states (PLNORMAL.c:230,308,528,547,885,924,970). So being grabbed during your own move, your dash, or right after a parry tap is untechable. `check_nagenuke` ignores `hazusenai_flag` when `cat_break_reserve` is set.
- Auto-tech: during the first 6 frames of your own throw attempt (`Attack_14000/15000`, PLPAT.c:733/761: `cat_break_ok_timer = 6`, `cat_break_reserve = 1` while the timer runs) any grab on you is techable without input.
- Success sends thrower to normal state 48/50 and victim to 47/49 (PLPCA.c:121-135).

### RAM

`wu.routine_no[1]` (3 = caught, 2 = catching), `PLW.tsukamarenai_flag` 0x3C7, `cat_break_ok_timer` 0x434, `cat_break_reserve` 0x435, `hazusenai_flag` 0x436, `guard_flag` 0x3D2, `cp.ca14`, `cp.waza_flag[3,4]`, `tsukami_f` 0x3CE, `tsukamare_f` 0x3CF.

### Failure modes and detection

- LP/LK gap >= 2 frames (jab/short instead): from `sw_now` edges.
- Throw attempted with up/down held: compare lever at the decision frame.
- Throw whiffed because opponent had `tsukamarenai_flag` > 0 at the active frame (attempt frame 3): "opponent was throw-protected for N more frames".
- Throw whiffed on wake-up or hitstun: opponent routine_no and `cg_type`.
- Throw out of range: distance vs catch box edge (data table, parse `cat_box` and `cau_box`).
- Tech failures: gap between grab frame and first LP+LK, MP/HK also pressed that frame, hazusenai reason (own attack, dash, parry tap in last 10 frames).
- Thrower whiff punish window: attempt recovery length (23-33 frames, above).

Grading feasibility: easy for the input rule and tech; medium for whiff-cause attribution (needs defender state at one specific frame).

## 3. Dashes

- Input: `pc_cmd_00/01` (data/cmd_data.c:106/114). Forward dash: new forward, neutral within 6 frames, new EXACT forward within 6 frames, then repeat-forward within 6 frames re-arms it (CK_LEVER_REPEAT, `check_18` cmd_main_2.c:1157). `reset` = 8: `waza_flag[0]` (forward) / `[1]` (back) stays set 8 frames, giving an 8-frame buffer for the dash only. Exact forward means up-forward or down-forward do not count as the second tap. Dead levers: raw back or down (with no buttons) abandon a forward dash (dead_lvr_check compares `sw_new` equality, so a held button defeats it, cmd_main_2.c:1490).
- Start: `check_F_R_dash` (PLS01.c:295): ground only, `spmv_ng_flag & 4` (forward) or `& 8` (back) must be clear (all fighters have neither set, data/PLCNT_tbl.c:81). If both flags set it uses `lever_dir`.
- During the dash: `guard_flag = 3` (Normal_05000/06000, PLNORMAL.c:230,308), so no block or parry until a line with `cg_type` 255/64/2/3/7 (`jumping_guard_type_check`, PLS00.c:952). Inputs are not accepted until the same lines (above).
- Tabled timing (`data/<char>_char.c`, scripts `nmca_004` forward, `nmca_005` back, selected by `normal_05[]`/`normal_06[]` in data/PLPNM_tbl.c:99-118; frame numbers are S, the offset of the first line of that type, accepted on frame S+1 after the dash started). Plain slide dashes (reliable):

| Fighter | Fwd: type 2 / type 3 / type 64 / total | Back: type 2 / type 64 / total |
|---|---|---|
| Ryu | 12 / - / 16 / 24 | - / 14 / 21 |
| Ken | type 7 at 11 / - / 15 / 23 | - / 14 / 21 |
| Sean, Gouki, Shin Gouki | 12 / - / 16 / 24 | - / 14 / 17 |
| Elena | 12 / - / 15 / 24 (script has a jump, approximate) | - / 24 / 25 |
| Makoto | 10 / - / 29 / 38 | - / 13 / 22 |
| Yun, Yang (back dash only is plain) | hop | 28 / 33 (type 3 at 30) / 56 |
| Chun-Li (back dash only is plain) | hop | - / 24 / 28 |

- Everyone else's forward dash and most back dashes are hops (`nm_05_0000`, `nm_06_0100`): the animation has a 250-frame wait line ended by landing (`jumping_union_process`), so the length depends on movement data, not on a table (Gill, Alex, Dudley, Necro, Hugo, Ibuki, Oro, Urien, Q, Twelve, Remy, Yun/Yang forward, Chun forward; their back dashes too except Yun/Yang/Chun/Elena). For these read `cg_type` from RAM each frame instead.
- Dash cancel from a normal: `cg_cancel & 2` and hit/block contact (check_cg_cancel_data, PLS00.c:1666): only 5 script lines in the game (Gill, Yun, Yang, Urien).
- Failure modes: dash input too slow (6-frame steps) or not exact; dash input done but state not yet accepting dash (needs type 3/64 line, or neutral) and buffer (8 frames) ran out; attacking input during the dash before the type-2 line is dropped; being hit during the dash (can't block). 
- Grading feasibility: medium. Input side is already covered by the command checker; "dash recovery" needs `cg_type`/`permited_koa`.

## 4. Cancels

### Chain, rapid repeat, target combo (cg_cancel 0x10, 0x08, 0x04)

- `check_cg_cancel_data` (PLS00.c:1633) is called from `process_attack` and from every neutral check list. Order: super (0x40) and special (0x20) cancel only with `meoshi_hit_flag`; then 0x10 `check_renda_cancel` (no contact needed), 0x08 `check_meoshi_cancel` (needs `meoshi_hit_flag`), 0x04 normal-into-different-normal (no contact test: requires `(sw_now & SHOT) != current_attack`), then with contact 0x02 dash and 0x01 super jump.
- Rapid repeat (0x10, PLS03ATT.c:538): facing unchanged (`rl_flag == rl_waza`), the lever's up/down state must match the move's posture (`renda_status_table[sw_new & 3]` = {0, 20, 32, 0}: standing=0, crouching=32, so repeat a standing jab with the lever not down), and the NEW press must be exactly the same button as `current_attack` (any extra new button on that frame fails). Restarts the animation at the line in `cg_eftype`.
- Chain / target combo (0x08, PLS03ATT.c:577): requires contact. Every button HELD (`sw_new & SHOT`) must be inside the allowed set in `cg_meoshi & 0x770` (e.g. 272 = LP|LK), so holding an HP or MK while pressing the chain button blocks it. The lever must match the lever field in `cg_meoshi` (tables `cnmc_*`, data/PLS03_tbl.c:42-). A new press is required (`shot_data_convert(sw_now) >= 0`) unless the script flags release-trigger (0x80 in `cg_cancel`, then the release edge counts). With `cg_meoshi & 0x800` it jumps to a scripted follow-up (`char_move_cmms2/3`), otherwise it just calls `check_nm_attack`. First use sets `tc_1st_flag` (PLW 0x429) and zeroes the next normal's `cancel_timer`.
- Window per move = lines whose `cg_cancel` has the bit. Example Ryu (parsed from `data/ryu_char.c`, frames of the line relative to frame 0, input frames are +1): st.LP far `atca_000` special/super cancel lines 3..5 (offset 3-6), target-combo lines S 6..9; st.LP close `atca_001` special cancel offsets 8-11, repeat/chain offsets 9-13; first actionable line (type 64) at offset 10 (far) / 14 (close). Parse any character with the same rules (script `parse.py` in the scratchpad was ad hoc, the data is regular: `L4(ctr, type, se, prio, flip, olc, jphos, number, att, hit, meoshi, extdat, cancel, effect, eftype)`).

### Special and super cancels

- Rule: contact (`meoshi_hit_flag != 0`) AND current line has `cg_cancel & 0x20` (special) or `& 0x40` (super, which also needs the gauge via `check_full_gauge_attack`/`check_super_arts_attack`), AND the command motion done (`waza_flag[slot] != 0`), AND the button edge this frame (press or release). Window length in input frames = number of frames of the flagged lines (typically 3-5 for light normals, up to 10 for mediums on Ryu) PLUS the hit-stop frames, because the line is frozen during hit stop but `check_lever_data` still runs (PLMAIN.c:253-259). That is why hit stop effectively widens the cancel window.
- Super freeze, super art interplay: see section 8.
- Kara cancel (cancel of startup into a special/super/throw): exactly one frame, see section 2 (`cancel_timer`). Needs the second button new on the frame after the first (frame 1). No contact needed. Not available after the first hit of a target combo (`tc_1st_flag`).

### RAM

`wu.cg_cancel` 0x221, `wu.cg_meoshi` 0x230, `wu.meoshi_hit_flag` 0x2FF, `wu.hit_stop` 0x44, `PLW.cancel_timer` 0x3E5, `PLW.current_attack` 0x3E8, `PLW.tc_1st_flag` 0x429, `cp.waza_flag[20..55]`, `sw_*`, `permited_koa` (0x01/0x02 bits are suppressed while `cancel_timer != 0`, so during the kara frame specials do not show as "permitted" even though they are).

### Failure modes and detection

- Special cancel on whiff or after the flagged lines ended: `meoshi_hit_flag == 0` or `cg_cancel` bit 0x20 clear.
- Held button outside chain set, wrong lever, extra new button on a repeat: from `sw_new`/`sw_now` at the press frame.
- Button pressed during the window but motion not complete (`waza_flag == 0`) or motion complete but button pressed before the window (no buffer, section 1).
- Kara: second press 0 frames or 2+ frames after the first.

Grading feasibility: medium. The window bits come from RAM per frame, so no per-move table is strictly needed.

## 5. Links

- Nothing special in the engine. A link is "the next normal's press falls on a frame where the attacker is actionable (section 1) and the target move still hits before the defender recovers". There is no buffer, so the press must be a new press on the attacker's first free frame or later. Stun is counted by animation lines (attacker `cg_type` 64 reached; defender `cg_type` 64/255 in `dm_04000/08000`), not by a counter you can read: both attacker and defender freeze on contact (`hit_stop`/`dm_stop` from the attack's `hs_me`/`hs_you`, `dm_status_copy` HITCHECK.c:1049) and lines do not advance during it, so hit stop adds no frame advantage.
- Frame advantage can be derived in RAM as (defender free frame) - (attacker free frame): sample the first frame each side has `cg_type` in {2,3,7,64,255} (for the defender in `PLAYER_DAMAGE`, `cg_type` 64 or 0xFF is the free frame). Early press (before attacker free) -> "no buffer, pressed N frames early". Late press (after the defender's free frame minus the next move's startup) -> "link too late, defender could act".
- Throw immunity after stun (6 frames, section 2) means the next throw in a throw-link vs a just-recovered opponent whiffs even when the press frame is correct.

Grading feasibility: medium-hard. Needs both players' state plus the next move's startup (from the same animation tables: first line with a negative `att` field).

## 6. Parry

- Window: `pc_cmd_03` (stand, forward) and `pc_cmd_04` (down) have `reset = 11`, `pc_cmd_05/06` (air) `reset = 8`, `pc_cmd_12` (short hold, used for jump-in attacks) `reset = 6` (data/cmd_data.c:112-160). `check_10` (cmd_main_2.c:685) sets `waza_flag[slot] = reset` only when the lever was neutral first (case 0) and then a NEW lever press lands on exactly the parry direction (case 1: `now_lvbt & mask` and `sw_lever == w_lvr`); on the ground the air slots are ignored. Holding forward cancels it: after the tap, within about 5 frames (`w_int = 6`) the lever must return to neutral, else (back, any other direction, or timeout) the flag is zeroed (case 2). Cases 3/4 handle the tail (free3 counts down reset+10 frames).
- `waza_flag` is decremented in the same `cmd_move` call that set it, so RAM reads after the frame show `reset - 1` = 10 (stand/down), 7 (air), 5 (short) on the tap frame, then 9, 8, ...
- Parry vs block, `defense_ground` (HITCHECK.c:889): defender must have `py->flag == 0` and `guard_flag & 2 == 0` (no parry in any attack state, dash, prejump, damage start, throw states, since `guard_flag` is 3 there; `Damage_08000` sets `guard_flag = 1`, so hit stun allows parry flag-wise, not verified further) and the attack's `att.guard` bit 2 (high/mid) matched against flag [3], bit 1 (low) against flag [4]; jump-in attacks (`jump_att_flag`) use flag [12]. If `ds->guard_chuu` is 1..4 (defender is currently in a block state: stand/crouch block states 27-30 and blockstun 4-7 via `guard_kind`, PLPDM_tbl.c:335) "just_now" applies: the parry flag must still be at least `blocking_term_tbl[attr_att][0/1]` = 9 for specials/projectiles and 8 for normals (data/HITCHECK_tbl.c:41). With the same-frame decrement this means the tap was 0-1 frames before the hit for specials and 0-2 for normals (derived, off-by-one risk). This is the "red parry" (parry while blocking); there is no separate red-parry flag. Otherwise any nonzero `waza_flag[3/4]` parries: the hit may land from the tap frame to 9 frames later (10 frames).
- The parried defender gets `dm_stop = -15` (free to act, animation running), attacker `hit_stop = 16 (+ attack-dependent)` (HITCHECK.c:567-600), so a successful parry is a long punish window (section 1).
- Slot 7 (`pc_cmd_07`, CK_PARRY_STRICT, reset 2) is mislabelled "red parry (?)" in `cmd_data.c`. The code reads `waza_flag[7]` as the quick-stand (ukemi) input (`check_ukemi_flag`, PLS01.c:81), see section 7.
- RAM: `cp.waza_flag[3,4,5,6,12]`, `PLW.guard_flag` 0x3D2, `guard_chuu` 0x3D3, `wu.dm_stop`.
- Failure modes: tapped too early (flag expired), too late, from a held direction (no neutral first), direction not exact (diagonal), held too long (flag zeroed), in the red-parry zone with a stale tap (flag below 9/8), in a state with `guard_flag & 2`.
- Grading feasibility: easy.

## 7. Reversals, wake-up, quick stand

- Reversal = any special/super/throw/normal started on the first actionable frame out of wake-up, blockstun, hitstun or parry. There is no leniency beyond the motion buffer (12 frames) and the one-frame throw/kara rules: the button must be a new press (or a release) on or after the first frame the game evaluates the check (section 1), with the motion done within the last 12 frames. The usual way to get a frame-perfect reversal is therefore: finish the motion early, press (or hold-and-release) the button on the free frame.
- Wake-up: Ryu OKIAGARI is 43 frames of invulnerability (hit row 0/12) then the type-64 line, which is the first actionable line (`dm_18000`, PLS00.c:1488). `tsukamarenai_flag` gives 6 more throw-proof frames. Quick-stand scripts (`OKIAGARI F/B`) have the same box rows. Per-character lengths can be parsed from `dmca_064..066`, `dmca_090/091`.
- Quick stand / ukemi: at damage start `ukemi_ok_timer = 6` unless the hit is a hard knockdown (`dm_koa & 0x980`, PLPDM.c:231-236) or a throw sets it from `CM_NGDA` (6 on most, 0 on a few). `uot_cd_ok_flag` turns on in flight (`first_flight_union`, PLPDM.c:1118), then `look_after_timers` (PLMAIN.c:355-365) counts it down each frame and sets `ukemi_success = 1` if `waza_flag[7]` is nonzero in the window. The input is `pc_cmd_07`: lever neutral, then a new press of exactly DOWN (CK_PARRY_STRICT `check_23`, cmd_main_2.c:1311), flag lives 2 frames. On the landing frame (`cg_type` 5 in `buttobi_chakuchi_cg_type_check`, PLPDM.c:1180-1195) with `ukemi_success` the routine switches to a get-up (`oki_select_table2`: roll forward/back chosen by facing), grants super gauge and counts a quick stand. If down is already held when you are launched (never neutral) the command never arms. `check_13`/CK_UKEMI (3-punch tech) exists in the code but is not referenced by any record.
- RAM: `PLW.ukemi_ok_timer` 0x3FE, `uot_cd_ok_flag` 0x402, `ukemi_success` 0x403, `cp.waza_flag[7]`.
- Failure modes: no neutral before the down press, down pressed outside the 6-frame window, diagonal down, hard knockdown (no tech possible).
- Grading feasibility: medium (needs the window start, which is a script event, `uot_cd_ok_flag` rising edge).

## 8. Other timing mechanics

- EX moves (two buttons): `pl_lvr_set` (cmd_main_2.c:1536-1590) sets the synthetic `CMD_SW_PP` (0x80) / `CMD_SW_KK` (0x800) bit only when 2 or 3 punches (kicks) are newly pressed on the SAME frame, or released on the same frame. No one-frame leniency (unlike throws). `check_special_attack` (PLS03.c:476-540) tries strengths 3,2,1,0 in order: EX needs `PP` in `sw_chg` with no kick bit, the `CMD_BT_EX` flag, and EX stock (`sa->ex == 1`) and super bar not locked; if EX is unavailable (no stock) it falls through to HP, MP, LP in that order, so LP+MP same frame without stock gives the MP version. If the buttons are 1+ frame apart the first button's move starts immediately (weaker version) on its own frame. Failure: buttons on different frames -> weaker version; no EX stock -> highest single button version.
- Super jump: `pc_cmd_02` (data/cmd_data.c:121): new DOWN then new UP within 8 frames (CK_LEVER_NEW `check_24`, cmd_main_2.c:1369), `reset = 8`. `check_jump_ready` (PLS01.c:360) chooses super jump only if `waza_flag[2] != 0` at the moment of jumping AND `sw_new` has up held. If you were not actionable when you pressed up, you need to jump within 8 frames of the up press or you get a normal jump while still holding up. Cancel into super jump on contact uses `cg_cancel & 1` (`check_hijump_only`, PLS01.c:378; only Yun, Yang, Ibuki, Oro, Chun, Twelve have such lines). RAM: `cp.waza_flag[2]`, `PLW.high_jump_flag` 0x45D.
- Prejump normals: jump prep (3 or 5 frames) accepts no normals/throws, only supers/specials/taunt/leap (`nm_16000/17000`), so an anti-air normal pressed in the first frames of a jump is lost.
- Air actions: `check_air_jump` (PLS01.c:186) Oro-style air jump: up NEW press (`sw_now`), height >= 48, not within `air_jump_ok_time` (4 frames after takeoff), `spmv_ng_flag & 0x80000` clear (set for everyone except Oro: table value 0x50823). `check_sankaku_tobi` wall jump (PLS01.c:215): needs `micchaku_wall_time` 1..7 (touching a wall for fewer than 8 frames, `check_extra_jump_timer` PLS01.c:242) and holding toward the wall, Chun-Li only (0x90823 lacks 0x40000). RAM: `PLW.extra_jump` 0x468, `air_jump_ok_time` 0x469.
- Taunt (HP+HK, `ca36`) and leap (MP+MK, `ca25`): both require the lever fully neutral (`sw_lvbt & LEVER_ALL == 0`, PLS03ATT.c:176, PLS03.c:630) and on the ground; same one-frame-apart tolerance as throw.
- Far vs close normals: `waza_select` (PLS03ATT.c:318) picks the A/B/C variant of the normal by lever (`sw_new` forward etc.) and by opponent distance (`get_em_body_range`, edge distance) using `asstbl_lv_0000.._4000` (data/asstbl.c:2261). The decomp notes say B is the close version; the comparison is `range >= cmd` in `decode_wst_data` (PLS03ATT.c:372), direction not verified here. Failure: "wanted close version at distance X".
- Super freeze: when a super's freeze starts, the OPPONENT gets `hit_stop = N` and `sa_stop_flag = 2`, and when `hit_stop <= sa_stop_sai` (N-4) it becomes 1 (PLMAIN.c:290-304, CHARMOVE.c:1180-1202). With `sa_stop_flag == 1`: `Player_move` calls `key_thru` instead of `waza_check` (PLMAIN.c:106-109) and `check_lever_data` is skipped (PLMAIN.c:253), so for roughly the last 4 freeze frames the opponent's buttons and lever are sampled (edges consumed) but no command progress is made and no action can start; existing `waza_flag` values do not tick. Presses in those frames are lost. `ram.lua` already uses `sa_stop_flag ~= 1` for "command check ran". Earlier freeze frames (flag 2) are processed normally.
- Turn-around: `check_turn_to_back` (PLS01.c:467) is after attacks/dash in the neutral list, so attacks and throws are not delayed by a pending turn, but `rl_waza` (the facing the commands use) switches immediately while the sprite `rl_flag` lags. `hurimukenai_flag` blocks re-turn.
- Chun-Li kicks, Yun/Yang etc: no special engine timing found. Rapid-press specials use the generic `CK_RENDA` (check_4, cmd_main_2.c:399) and `CK_RENDA3` (check_14, cmd_main_2.c:1020) counters, already covered by the command checker.
- CPU/AI only: `permited_koa` consumers in Com_Sub.c, `Receive_Flag`, `caution_flag`.

## RAM field reference (PLW base: 0x02068C6C P1, 0x02069104 P2; WORK_CP base: 0x02026318 P1, 0x0202671E P2 from the existing `ram.lua`)

| Field | Offset | Notes |
|---|---|---|
| `wu.routine_no[0..3]` | 0x24 | PLAYER_ATTACK=4 etc. |
| `wu.hit_stop` | 0x44 | positive freeze, negative = free-to-act freeze (parry) |
| `wu.cg_ctr` / `cg_type` / `cg_cancel` / `cg_meoshi` | 0x214 / 0x215 / 0x221 / 0x230 | current line |
| `wu.pat_status` | 0x20E | posture/air class, used by renda and throw tables |
| `wu.meoshi_hit_flag` | 0x2FF | contact flag |
| `wu.dm_stop` | 0x32E | pending freeze |
| `PLW.cp` | 0x3B8 | pointer to WORK_CP |
| `spmv_ng_flag` | 0x3BC | per-character move disables |
| `tsukami_f` / `tsukamare_f` | 0x3CE / 0x3CF | thrower / thrown |
| `tsukamarenai_flag` | 0x3C7 | throw-proof counter |
| `guard_flag` / `guard_chuu` | 0x3D2 / 0x3D3 | 1 no block, 2 no parry, 3 neither; blocking kind |
| `cancel_timer` | 0x3E5 | kara window |
| `current_attack` | 0x3E8 | last normal's button |
| `ukemi_ok_timer` / `uot_cd_ok_flag` / `ukemi_success` | 0x3FE / 0x402 / 0x403 | quick stand |
| `sa_stop_flag` | 0x41C | 1 = super freeze, inputs not processed |
| `tc_1st_flag` | 0x429 | target combo started |
| `cat_break_ok_timer` / `cat_break_reserve` / `hazusenai_flag` | 0x434 / 0x435 / 0x436 | tech |
| `high_jump_flag` | 0x45D | |
| `extra_jump` / `air_jump_ok_time` | 0x468 / 0x469 | |
| `permited_koa` | 0x46C | per-frame "which action classes were evaluated" bitmask |
| `WORK_CP.sw_lvbt/new/old/now/off/chg/old_now` | 0x0,2,4,6,8,A,C | edges and holds |
| `WORK_CP.ca14/ca25/ca36` | 0x10/0x11/0x12 | button pairs |
| `WORK_CP.waza_flag[56]` | 0x16 | slots: 0 F dash, 1 B dash, 2 super jump, 3/4 parry stand/down, 5/6 air parry, 7 quick stand, 8-11 mashing, 12 short parry, 13 unused (360 jump), 14/15 down-down+P/K, 20-27 supers, 28-37 ground specials, 38-45 air supers, 46-55 air specials |

## Open questions and uncertainties

- Off-by-one: all "first accepted frame" statements assume the input check precedes the state routine on a frame (true in `player_mv_4000`) and that `set_char_move_init` shows line 1 on the acceptance frame. Worth one MAME trace (cg_type, routine_no, input press frame) for a dash and a jab to pin it.
- `cancel_timer` kara window length (1 frame) relies on `get_cancel_timer` setting 2 and the decrement at the top of `process_attack` happening only when `routine_no[3] != 0`, and on no hit stop on frame 1.
- Jump landing recovery: I assumed the landing uses `exca_001` / `exca_011` through the RJA slots set by `cbca_003` (observed in Ryu); not confirmed per jump type and character. Parsed profile: 0-1 frame of `cg_type` 0, then 1-2 frames type 2, then type 3, with first full free frame 2-6 frames after landing.
- Throws with `att.guard & 0x18` bypass throw protection; which moves was not checked.
- The `Damage_08000` `guard_flag = 1` meaning (no block, parry still allowed) is read from the flag tests only.
- `uot_cd_ok_flag` is set in flight (`first_flight_union`) rather than at touchdown; exact start of the 6-frame ukemi window per knockdown type not traced.
- Throw-range pixel maths assumes cat_box / cau_box sign and mirroring as read from the table comments.
- Hop-dash lengths (most forward dashes and many back dashes) are physics, not tabled.

## Measured: first actionable frame after Ryu's forward dash (MAME, `harness/mame/actionable.lua`)

- From the frame after the dash's last input, a jab held on frame 12 or earlier is dropped; from 13 on it comes out.
- The game reads a held input one frame after the script sets it. In RAM terms the rule is: a press that appears in `WORK_CP.sw_new` on frame F is accepted when the animation tag (`cg_type`, WORK +533) stored at the end of frame F-1 is 2, 3 or 64. Here: press read on frame 13 with the tag still 0 after frame 12, dropped; press read on frame 14 with the tag 2 after frame 13, accepted.
- So "first frame you could act" and "frames early" can be computed from RAM alone. Standing and walking states carry tag 0 but always allow acting; the tag only gates inside restricted states (dash, landing, recovery).
