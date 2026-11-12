#!/usr/bin/env python3
"""Generate lua/input_grader/games/sfiii3/commands.lua from the game's command tables.

Usage: gen_commands.py <prog.bin> <sfIII3-cps3-decomp dir> <out .lua>

The numbers come from the decrypted program ROM, so the output matches the game Fightcade
runs. The decomp only contributes labels (fighter, move name, notation) and a cross-check:
every record whose values differ between the ROM and the decomp is reported, and the ROM wins.
"""
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROM_BASE = 0x06000000
SLOTS = 56
HEAD_WORDS = 12
STEP_WORDS = 4
CMD_END = 28
CK_NONE = 21
RYU_ROW, RYU_HADOKEN_SLOT = 2, 29
RYU_HADOKEN = [12, 1, 0, 16, 16, 16, 16, 0x0C05, 0, 1, 2, 19,
               1, 0, 0, 0x8002, 1, 10, 0, 0x8006, 1, 10, 0, 0x8004, 28]


def words(values):
    return b"".join(struct.pack(">H", v & 0xFFFF) for v in values)


class Rom:
    def __init__(self, path):
        self.data = Path(path).read_bytes()

    def u32(self, addr):
        return struct.unpack_from(">I", self.data, addr - ROM_BASE)[0]

    def s16(self, addr):
        return struct.unpack_from(">h", self.data, addr - ROM_BASE)[0]

    def find_all(self, needle):
        hits, i = [], self.data.find(needle)
        while i >= 0:
            hits.append(ROM_BASE + i)
            i = self.data.find(needle, i + 1)
        return hits

    def record(self, addr):
        head = [self.s16(addr + 2 * i) for i in range(HEAD_WORDS)]
        steps, at = [], addr + 2 * HEAD_WORDS
        while self.s16(at) != CMD_END:
            if self.s16(at) == CK_NONE:
                # Gill's super art slots end on a bare CK_NONE: a step that never completes.
                return head, [[CK_NONE, 0, 0, 0]]
            steps.append([self.s16(at + 2 * i) for i in range(STEP_WORDS)])
            at += 2 * STEP_WORDS
            if len(steps) > 16:
                raise ValueError(f"record at {addr:#x} has no CMD_END")
        return head, steps


def locate_slot_table(rom):
    # Ken and Akuma share the Hadoken's shape, so several records match: keep the one table
    # base whose every slot points at a well-formed record.
    bases = set()
    for record in rom.find_all(words(RYU_HADOKEN)):
        for pointer in rom.find_all(struct.pack(">I", record)):
            if pointer % 4 == 0:
                bases.add(pointer - 4 * (RYU_ROW * SLOTS + RYU_HADOKEN_SLOT))
    valid = [b for b in bases if is_slot_table(rom, b)]
    if len(valid) != 1:
        raise SystemExit(f"expected one command slot table, found {[hex(b) for b in valid]}")
    return valid[0]


def is_slot_table(rom, base):
    try:
        for i in range(21 * SLOTS):
            addr = rom.u32(base + 4 * i)
            if not ROM_BASE <= addr < ROM_BASE + len(rom.data):
                return False
            rom.record(addr)
    except (ValueError, struct.error):
        return False
    return rom.u32(base + 4 * (RYU_ROW * SLOTS + RYU_HADOKEN_SLOT)) in rom.find_all(words(RYU_HADOKEN))


def preprocess(decomp):
    """Expand the decomp's macros so its record values can be compared with the ROM."""
    with tempfile.TemporaryDirectory() as stub:
        for name in ("types.h", "structs.h"):
            Path(stub, name).write_text("")
        prelude = "typedef short s16; typedef const s16* const_s16_arr;\n"
        src = prelude + (decomp / "data/cmd_data.c").read_text()
        out = subprocess.run(
            ["cpp", "-P", "-I", stub, "-I", str(decomp / "include"), "-"],
            input=src, capture_output=True, text=True, check=True,
        ).stdout
    values = {}
    for name, body in re.findall(r"const s16 (\w+)\[\d+\] = \{(.*?)\};", out, re.S):
        values[name] = [eval_c(x) for x in body.split(",") if x.strip()]
    return values


def eval_c(expr):
    expr = re.sub(r"\(\s*s16\s*\)", "", expr.strip())
    expr = expr.replace("|", " | ")
    value = eval(expr, {"__builtins__": {}})  # noqa: S307  digits and C operators only, from cpp output
    return struct.unpack(">h", struct.pack(">H", value & 0xFFFF))[0]


def labels(decomp):
    src = (decomp / "data/cmd_data.c").read_text()
    comments = dict(re.findall(r"const s16 (\w+)\[\d+\] = \{\s*/\*\s*(.*?)\s*\*/", src))
    block = src[src.index("pl_cmd_list[21][56]"):]
    block = block[:block.index("};")]
    rows = []
    for name, body in re.findall(r"\{ /\* (\w+) \*/(.*?)\}", block, re.S):
        rows.append((name, re.findall(r"\w+_cmd_\w+", body)))
    counts = re.search(r"pl_cmd_num\[24\]\[7\] = \{(.*?)\};", src, re.S).group(1)
    slot_counts = [[int(n) for n in row.split(",")] for row in re.findall(r"\{([\d,\s]+)\}", counts)]
    return comments, rows, slot_counts


def super_arts(decomp):
    """super_arts_data (PLCNT_tbl.c): per fighter, the ground and air slot of each super art."""
    src = (decomp / "data/PLCNT_tbl.c").read_text()
    block = src[src.index("super_arts_data[24][4]"):]
    block = block[:block.index("\n};")]
    fighters = []
    for body in re.findall(r"\{\s*/\*[^*]*\*/(.*?)\n    \},", block, re.S):
        arts = []
        for row in re.findall(r"\{ *([\d ,]+),", body)[:3]:
            ix = [int(v) for v in row.split(",")[:6]]
            arts.append((ix[0], ix[3]))
        fighters.append(arts)
    return fighters


def parse_label(comment):
    """'Ryu: Hadoken, 236+P' -> ('Hadoken', '236+P'); shared records have no fighter prefix."""
    guess = "(?)" in comment
    text = comment.replace("(?)", "").strip()
    if ":" in text:
        text = text.split(":", 1)[1].strip()
    name, _, notation = text.rpartition(", ")
    if not name:
        name, notation = text, ""
    return name.strip(), notation.strip(), guess


def reachable(flat):
    """The header and the steps up to the first CK_NONE, which never completes."""
    for i in range(HEAD_WORDS, len(flat), STEP_WORDS):
        if flat[i] == CK_NONE:
            return flat[:i + 1]
    return flat


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(prog, decomp, out):
    rom, decomp = Rom(prog), Path(decomp)
    table = locate_slot_table(rom)
    expanded = preprocess(decomp)
    comments, rows, slot_counts = labels(decomp)
    arts = super_arts(decomp)
    mismatches = []
    lines = [
        "-- Generated by tools/gen_commands.py from the 3rd Strike program ROM. Do not edit.",
        f"-- Slot table at 0x{table:08X}.",
        "return {",
        "  fighters = {",
    ]
    for row, (fighter, record_names) in enumerate(rows):
        art_src = ", ".join(f"{{ ground = {g}, air = {a} }}" for g, a in arts[row])
        lines.append(f"    [{row}] = {{ name = {lua_str(fighter)}, slot_counts = {{ "
                     + ", ".join(map(str, slot_counts[row])) + f" }}, super_arts = {{ {art_src} }}, slots = {{")
        for slot, record_name in enumerate(record_names):
            if record_name == "dm_cmd_xx":
                continue
            head, steps = rom.record(rom.u32(table + 4 * (row * SLOTS + slot)))
            flat = head + [w for s in steps for w in s] + [CMD_END]
            if expanded.get(record_name) is not None and reachable(expanded[record_name]) != reachable(flat):
                mismatches.append(f"{fighter} slot {slot} {record_name}")
            name, notation, guess = parse_label(comments.get(record_name, record_name))
            step_src = ", ".join("{ " + ", ".join(map(str, s)) + " }" for s in steps)
            lines.append(
                f"      [{slot}] = {{ record = {lua_str(record_name)}, name = {lua_str(name)}, "
                f"notation = {lua_str(notation)}, guess = {str(guess).lower()}, "
                f"reset = {head[0]}, dead = {head[1]}, dead2 = {head[2]}, "
                f"rno = {{ {', '.join(map(str, head[3:7]))} }}, btix = {head[7]}, exdt = {{ {', '.join(map(str, head[8:12]))} }}, "
                f"steps = {{ {step_src} }} }},"
            )
        lines.append("    } },")
    lines += ["  },", "}", ""]
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text("\n".join(lines))
    print(f"{out}: {len(rows)} fighters, slot table 0x{table:08X}")
    if mismatches:
        print("ROM and decomp disagree (ROM used):\n  " + "\n  ".join(mismatches))
    else:
        print("every record matches the decomp")


if __name__ == "__main__":
    main(*sys.argv[1:])
