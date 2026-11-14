local M = {}

M.SLOTS = 56
M.SA_GROUND = 20
M.SP_GROUND = 28
M.SA_AIR = 38
M.SP_AIR = 46

M.LV_UP, M.LV_DOWN, M.LV_FORWARD, M.LV_BACK = 0x1, 0x2, 0x4, 0x8
M.LV_MASK = 0xF
M.LV_EXACT = 0x8000

M.RAW_LEFT, M.RAW_RIGHT = 0x4, 0x8

M.SW_LP, M.SW_MP, M.SW_HP, M.SW_PP = 0x10, 0x20, 0x40, 0x80
M.SW_LK, M.SW_MK, M.SW_HK, M.SW_KK = 0x100, 0x200, 0x400, 0x800
M.SW_PUNCH, M.SW_KICK, M.SW_SHOT = 0x70, 0x700, 0x770

M.CK = {
  INIT = 0,
  LEVER = 1,
  CHARGE = 2,
  HOLD = 3,
  SHOT_HOLD = 4,
  RENDA = 5,
  PRESS = 6,
  TURN = 7,
  SHOT_P = 8,
  SHOT_K = 9,
  LEVER_CHANGE = 10,
  PARRY = 11,
  BACK_DOWN = 12,
  AIR_PARRY = 13,
  UKEMI = 14,
  RENDA3 = 15,
  LEVER_COUNT = 16,
  PRESS_P = 17,
  PRESS_K = 18,
  LEVER_REPEAT = 19,
  LEVER_SET = 20,
  NONE = 21,
  LEVER_PRESS = 22,
  ROTATE = 23,
  PARRY_STRICT = 24,
  LEVER_NEW = 25,
  LEVER_HELD = 26,
  LEVER_OFF = 27,
}
M.CMD_END = 28

M.BT_INDEX = 0xFF
M.BT_NONE = 0x80
M.BT_STRENGTH4 = 0x600
M.BT_EX = 0x400
M.BT_SHELL = 0x800
M.BT_SA_ONLY = 0x1000
M.GOUKI1_ROW, M.GOUKI1_SHELL_SLOTS = 14, { 31, 33, 46 }
M.EX_BUTTON = 0xF

M.CONPANE = { [0] = "sw_lvbt", [1] = "sw_new", [2] = "sw_old", [3] = "sw_now", [4] = "sw_off", [5] = "sw_chg" }
M.BT_PRESS, M.BT_PRESS_OR_RELEASE = 3, 5

M.SHOT_CONV = {
  0x10,
  0x20,
  0x40,
  0x80,
  0x100,
  0x200,
  0x400,
  0x800,
  0x110,
  0x220,
  0x440,
  0x880,
  0,
  0,
  0,
  0,
  0x770,
  0x770,
  0x770,
  0x780,
  0x770,
  0x770,
  0x770,
  0x870,
  0x770,
  0x770,
  0x770,
  0x880,
  0,
  0,
  0,
  0,
}

M.TWO_PUNCHES = { [0x70] = true, [0x30] = true, [0x50] = true, [0x60] = true }
M.TWO_KICKS = { [0x700] = true, [0x300] = true, [0x500] = true, [0x600] = true }

M.LVR_CHK = { 5, 6, 9, 10 }

M.ROTATE_DIRS = { 1, 9, 8, 10, 2, 6, 4, 5 }

M.UKEMI_TIME = { 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 7 }

M.CNT_S1 = 5

return M
