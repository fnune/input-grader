#!/usr/bin/env python3
import sys
import zipfile
from pathlib import Path

CHIP = 0x200000
KEY1, KEY2 = 0xA55432B4, 0x0C129981


def rol16(v, n):
    v &= 0xFFFF
    return ((v << n) | (v >> (16 - n))) & 0xFFFF


def rotxor(val, x):
    res = (val + rol16(val, 2)) & 0xFFFF
    return (rol16(res, 4) ^ (res & (val ^ x))) & 0xFFFF


def mask(addr):
    addr ^= KEY1
    v = (addr & 0xFFFF) ^ 0xFFFF
    v = rotxor(v, KEY2 & 0xFFFF)
    v ^= ((addr >> 16) & 0xFFFF) ^ 0xFFFF
    v = rotxor(v, KEY2 >> 16)
    v ^= (addr & 0xFFFF) ^ (KEY2 & 0xFFFF)
    return (v | (v << 16)) & 0xFFFFFFFF


def read_simm(z, n, base):
    chips = [z.read(f"sfiii3-simm{n}.{i}") for i in range(4)]
    out = bytearray(4 * CHIP)
    for i in range(CHIP):
        w = (chips[0][i] << 24 | chips[1][i] << 16 | chips[2][i] << 8 | chips[3][i]) ^ mask(base + i * 4)
        out[i * 4:i * 4 + 4] = w.to_bytes(4, "big")
    return out


def main(rom, out):
    with zipfile.ZipFile(rom) as z:
        prog = read_simm(z, 1, 0x06000000) + read_simm(z, 2, 0x06800000)
    Path(out).write_bytes(prog)
    print(f"{out}: {len(prog)} bytes")


if __name__ == "__main__":
    main(*sys.argv[1:])
