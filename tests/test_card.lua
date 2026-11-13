local App = require("input_grader.core.app")
local card = require("input_grader.core.card")
local draw = require("input_grader.core.draw")
local pearls = require("input_grader.core.pearls")
local menu = require("input_grader.core.menu")
local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")
local inputs = require("input_grader.games.sfiii3.inputs")
local T = require("helpers")

local COL = draw.COL

local function canvas()
  local c = { texts = {}, icons = {}, boxes = 0, lines = {}, pixels = 0 }
  function c:text(_, _, s, colour)
    table.insert(self.texts, { s = s, c = colour })
  end
  function c:icon(key)
    table.insert(self.icons, key)
    return true
  end
  function c:box()
    self.boxes = self.boxes + 1
  end
  function c:line(_, _, _, _, colour)
    table.insert(self.lines, colour)
  end
  function c:pixel()
    self.pixels = self.pixels + 1
  end
  function c:has_text(s)
    for _, t in ipairs(self.texts) do
      if t.s == s then
        return t
      end
    end
    return nil
  end
  function c:has_line(colour)
    for _, l in ipairs(self.lines) do
      if l == colour then
        return true
      end
    end
    return false
  end
  return c
end

local function attempt(script, opts)
  opts = opts or {}
  local row = opts.row or 2
  local source = sources.sim(T.commands(), row, 0)
  local target = opts.target and (T.commands().fighters[row].name .. ":" .. opts.target) or nil
  local game = Game.new(source, T.commands(), { target = target })
  local timeline = inputs.timeline(script, true)
  for _ = 1, 30 do
    table.insert(timeline, 0)
  end
  for _, raw in ipairs(timeline) do
    source:push(raw, true)
    local graded = game:update()
    if graded[1] then
      return graded[1]
    end
  end
  error("no attempt graded")
end

local CLEAN = { { 5, 6 }, { 2, 2 }, { 3, 2 }, { 6, 1, "LP" } }
local SKIP = { { 5, 6 }, { 2, 3 }, { 6, 1, "LP" } }

local function drawn(a, opts)
  local c = canvas()
  local box = card.draw(c, a, { x0 = 44, y0 = 145, target = opts and opts.target })
  return c, box
end

return {
  {
    "a clean Hadoken: green box, meters per step and the button, CLEAN with the star",
    function()
      local a = attempt(CLEAN)
      T.eq(card.kind(a), "clean")
      local c = drawn(a)
      T.truthy(c:has_text("HADOKEN"), "name")
      T.truthy(c:has_text("CLEAN"), "clean label")
      T.eq(c:has_text("CLEAN").c, COL.gold)
      T.truthy(c:has_text("2/10"), "step meter")
      T.truthy(c:has_text("0/10"), "button meter")
      T.truthy(c:has_line(COL.good), "green box")
      T.truthy(c.pixels > 50, "sparkle drawn")
    end,
  },
  {
    "a frame-perfect Hadoken is gold and says FRAME-PERFECT",
    function()
      local a = attempt({ { 5, 6 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } })
      T.eq(card.kind(a), "perfect")
      local c = drawn(a)
      T.truthy(c:has_text("FRAME-PERFECT"), "label")
      T.truthy(c:has_line(COL.gold), "gold box")
    end,
  },
  {
    "a skipped diagonal: red box, NO and the missing direction, an empty column",
    function()
      local a = attempt(SKIP)
      local c = drawn(a)
      T.truthy(c:has_line(COL.bad), "red box")
      T.truthy(c:has_text("NO "), "reason")
      T.truthy(c:has_text("---"), "empty column for the skipped step")
      T.truthy(c:has_text("-/10"), "empty meter still shows the window")
    end,
  },
  {
    "columns put the late 6 of a skip under its own step, not under the skipped one",
    function()
      local reach, cols = card.columns(attempt(SKIP))
      T.eq(#cols[2], 0)
      T.truthy(reach[3] ~= nil, "the 6 was reached")
    end,
  },
  {
    "the Shoryuken's first step is marked as let go",
    function()
      local a = attempt({ { 5, 6 }, { 6, 2 }, { 5, 2 }, { 2, 1 }, { 3, 1, "HP" } })
      T.eq(a.trace.steps[1].release, true)
      local _, cols = card.columns(a)
      T.eq(cols[1][1].dir, 6)
    end,
  },
  {
    "6 let go straight into 2: the frame goes to the 2's column, the 6 hold to the first",
    function()
      local a = attempt({ { 5, 6 }, { 6, 2 }, { 2, 1 }, { 3, 1, "HP" } })
      local _, cols = card.columns(a)
      T.eq(cols[1][1].dir, 6)
      T.eq(#cols[2], 1)
      T.eq(cols[2][1].dir, 2)
      T.eq(drawn(a):has_text("---"), nil)
    end,
  },
  {
    "the super's optional last 6 is drawn in a dashed box before the button",
    function()
      local a = attempt({ { 5, 6 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } })
      T.eq(#a.trace.optional, 1)
      local c = drawn(a)
      local icons = table.concat(c.icons, ",")
      T.contains(icons, "r,LP")
    end,
  },
  {
    "a targeted dash has no button column and says TARGET",
    function()
      local a = attempt({ { 5, 4 }, { 6, 1 }, { 5, 2 }, { 6, 1 }, { 5, 20 } }, { target = 0 })
      T.eq(a.button, nil)
      local c = drawn(a, { target = true })
      T.truthy(c:has_text("TARGET"), "marker")
      T.truthy(c:has_text("FORWARD DASH"), "name")
    end,
  },
  {
    "the wrong button: the slot shows the button the move needs, the reason the one pressed",
    function()
      local a = attempt({ { 5, 6 }, { 2, 2 }, { 1, 2 }, { 4, 1, "LP" } }, { target = 30 })
      local c = drawn(a, { target = true })
      T.truthy(c:has_text(" NOT "), "reason")
      T.contains(table.concat(c.icons, ","), "LK")
      T.truthy(c:has_line(COL.bad), "red box")
    end,
  },
  {
    "refused by the game (a fireball on screen): grey, not red, and a clean input still says CLEAN",
    function()
      local a = attempt(CLEAN)
      a.ok, a.error = false, { code = "not_allowed", text = "refused" }
      T.eq(card.kind(a), "refused")
      local c = drawn(a)
      T.eq(c:has_line(COL.bad), false, "no red")
      T.truthy(c:has_text("CLEAN"), "clean input")
      T.truthy(c:has_text("GAME REFUSED"), "reason")
    end,
  },
  {
    "a parry card: the tap and the hit, with where the hit landed in the tap's window",
    function()
      local a = {
        move = "parry",
        ok = true,
        parry = { need_dir = 6, tap_dir = 6, used = 4, window = 10 },
        steps = {},
        trace = { frames = {}, steps = {} },
      }
      local c = drawn(a)
      T.truthy(c:has_text("PARRIED"), "outcome")
      T.truthy(c:has_text("5/10"), "landed on frame 5 of 10")
      T.truthy(c:has_text("4F BEFORE THE HIT"), "reason line")
      a.ok, a.error = false, { code = "parry_direction" }
      a.parry.need_dir = 2
      c = drawn(a)
      T.truthy(c:has_text("GOT HIT"), "outcome")
      T.eq(c:has_text("5/10"), nil, "no timing for the wrong direction")
    end,
  },
  {
    "a dash > throw card: the press timed against the first frame to act",
    function()
      local a = {
        move = "dash > throw",
        ok = true,
        followup = { action = "forward_dash", gap = 0, buttons = { "LP", "LK" }, need = { "LP", "LK" } },
      }
      T.eq(card.kind(a), "perfect")
      local c = drawn(a)
      T.truthy(c:has_text("FRAME-PERFECT"), "reason")
      T.truthy(c:has_line(COL.gold), "gold box")
      a.ok, a.followup.gap, a.error = false, -1, { code = "followup_early", frames = 1 }
      c = drawn(a)
      T.truthy(c:has_text("1F EARLY"), "early by a frame")
      T.truthy(c:has_text("-1F"), "timing")
    end,
  },
  {
    "pearls: one per attempt, the shown one lifted",
    function()
      local list = { attempt(CLEAN), attempt(SKIP), attempt(CLEAN) }
      local c = canvas()
      pearls.draw(c, { x0 = 44, y1 = 197 }, list, 2)
      T.truthy(c.boxes >= 3, "three pearls")
      T.truthy(c.pixels > 0, "shadow under the shown pearl")
    end,
  },
  {
    "pearls: clean attempts in the history keep their gold plus, dimmed",
    function()
      local function pixels(list)
        local c = canvas()
        pearls.draw(c, { x0 = 44, y1 = 197 }, list, #list)
        return c.pixels
      end
      T.truthy(pixels({ attempt(CLEAN), attempt(SKIP) }) > pixels({ attempt(SKIP), attempt(SKIP) }), "plus drawn")
    end,
  },
  {
    "menu rows: ALL MOVES, specials, then other moves after a divider",
    function()
      local rows = menu.rows({
        { id = "ryu:0", name = "forward dash", notation = "", buttonless = true, other = true },
        { id = "ryu:29", name = "Hadoken", notation = "236+P" },
        { id = "ryu:29b", name = "Hadoken", notation = "236+P" },
        { id = "ryu:8", name = "punch mashing", notation = "longer window", other = true },
      })
      T.eq(rows[1].name, "ALL MOVES")
      T.eq(rows[2].name, "Hadoken")
      T.eq(rows[3].divider, true)
      T.eq(rows[4].name, "forward dash")
      T.eq(rows[5].notation, "")
      T.eq(#menu.selectable(rows), 4)
    end,
  },
  {
    "app: M opens the menu on ALL MOVES and blocks input, the stick moves, LP picks the target",
    function()
      local target
      local game = {
        update = function()
          return {}
        end,
        moves = function()
          return {
            { id = "ryu:28", name = "Shoryuken", notation = "623+P" },
            { id = "ryu:29", name = "Hadoken", notation = "236+P" },
          }
        end,
        set_target = function(_, id)
          target = id
        end,
      }
      local app = App.new({
        game = game,
      })
      app:controls({ M = true }, {})
      T.eq(app:blocks_input(), true)
      app:controls({}, { down = true })
      app:controls({}, {})
      app:controls({}, { down = true })
      app:controls({}, {})
      app:controls({}, { LP = true })
      T.eq(target, "ryu:29")
      T.eq(app:blocks_input(), false)
    end,
  },
  {
    "app: a target keeps its success count and rate, refused inputs counting as good, reset on a new target",
    function()
      local queue = {}
      local game = {
        update = function()
          local out = queue
          queue = {}
          return out
        end,
        moves = function()
          return { { id = "ryu:29", name = "Hadoken", notation = "236+P" } }
        end,
        set_target = function() end,
      }
      local app = App.new({ game = game })
      app:choose({ id = "ryu:29", name = "Hadoken" })
      local refused = attempt(CLEAN)
      refused.ok, refused.error = false, { code = "not_allowed", text = "" }
      queue = { attempt(CLEAN), attempt(SKIP), refused }
      app:frame()
      T.eq(app:tally_text(), "2/3  67%")
      local c = canvas()
      app:draw(c)
      T.truthy(c:has_text("2/3  67%"), "drawn above the card")
      app:choose({ id = "ryu:28", name = "Shoryuken" })
      T.eq(app:tally_text(), "0/0")
      T.eq(app:stale(), true, "the Hadoken card does not answer the new target")
    end,
  },
  {
    "app: M brings a hidden overlay back, so the menu is never open unseen",
    function()
      local app = App.new({
        game = {
          update = function()
            return {}
          end,
          moves = function()
            return {}
          end,
          set_target = function() end,
        },
      })
      app:controls({ H = true }, {})
      T.eq(app.visible, false)
      app:controls({}, {})
      app:controls({ M = true }, {})
      T.eq(app.visible, true)
    end,
  },
  {
    "app: Page Up shows older attempts, a new attempt returns to the latest, H toggles",
    function()
      local queue = {}
      local game = {
        update = function()
          local out = queue
          queue = {}
          return out
        end,
        moves = function()
          return {}
        end,
        set_target = function() end,
      }
      local app = App.new({ game = game })
      queue = { attempt(CLEAN), attempt(SKIP) }
      app:frame()
      app:controls({ pageup = true }, {})
      T.eq(app.shown, 1)
      queue = { attempt(CLEAN) }
      app:frame()
      T.eq(app.shown, nil)
      app:controls({ H = true }, {})
      T.eq(app.visible, false)
      local c = canvas()
      app:draw(c)
      T.eq(#c.texts, 0)
    end,
  },
  {
    "app: a button that gets no card dims the last one, so it is not read as the answer",
    function()
      local queue = { attempt(CLEAN) }
      local game = {
        update = function()
          local out = queue
          queue = {}
          return out
        end,
        moves = function()
          return {}
        end,
        set_target = function() end,
      }
      local app = App.new({
        game = game,
      })
      local function name_alpha()
        local c = canvas()
        app:draw(c)
        return c:has_text("HADOKEN").c % 256
      end
      app:frame()
      local bright = name_alpha()
      app:controls({}, { MK = true })
      app:frame()
      T.eq(name_alpha(), bright, "not yet: the card for this press may still come")
      for _ = 1, App.STALE_AFTER do
        app:controls({}, {})
        app:frame()
      end
      T.truthy(name_alpha() < bright, "dimmed")
      queue = { attempt(CLEAN) }
      app:frame()
      T.eq(name_alpha(), bright, "a new card is bright")
    end,
  },
  {
    "app: outside a match (character select) nothing is drawn",
    function()
      local in_match = false
      local app = App.new({
        game = {
          update = function()
            return { attempt(CLEAN) }
          end,
          moves = function()
            return {}
          end,
          set_target = function() end,
        },
        active = function()
          return in_match
        end,
      })
      app:frame()
      local c = canvas()
      app:draw(c)
      T.eq(#c.texts, 0)
      in_match = true
      c = canvas()
      app:draw(c)
      T.truthy(c:has_text("HADOKEN"), "card")
      T.truthy(c:has_text(App.HELP), "the key legend stays on screen with a card")
    end,
  },
  {
    "app: with no attempt yet, a line of help is shown",
    function()
      local game = {
        update = function()
          return {}
        end,
        moves = function()
          return {}
        end,
        set_target = function() end,
      }
      local app = App.new({
        game = game,
      })
      local c = canvas()
      app:draw(c)
      T.truthy(c:has_text(App.HELP), "help")
    end,
  },
}
