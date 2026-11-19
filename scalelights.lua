-- scalelights
-- major & minor scales
-- on the LinnStrument
--
-- E2: key (circle of 5ths)
-- E3: major / natural minor /
--     harmonic minor
-- K2: relative major <-> minor
-- K3: page (circle / degrees /
--     playing: notes + chord)
-- E1: light style (root + triad /
--     root + scale / rainbow /
--     one octave / follow the lights)
-- grid row 8, cols 1-2: move the
--     one-octave box down / up
--
-- grid: ring = circle of 5ths
--   center = relative maj/min
--   top right = scale type
--   bottom right = keyboard
--
-- routing: LinnStrument -> norns
--   -> Electra One Mini -> Nymphes
--   (LinnStrument notes are passed
--   through to the "out device")

---------------------------------------------------------------- theory

local LETTERS = {"C","D","E","F","G","A","B"}
local NAT     = {0, 2, 4, 5, 7, 9, 11}
local NATURAL = {[0]=true, [2]=true, [4]=true, [5]=true, [7]=true, [9]=true, [11]=true}

-- circle of fifths, clockwise from the top (pos 1 = no sharps/flats)
local MAJOR_KEYS = {"C","G","D","A","E","B","F#","Db","Ab","Eb","Bb","F"}
local MINOR_KEYS = {"A","E","B","F#","C#","G#","D#","Bb","F","C","G","D"}
local ENHARMONIC = {major = "Gb", minor = "Eb"}   -- the 6-accidental position

local SHARP_ORDER = "FCGDAEB"
local FLAT_ORDER  = "BEADGCF"

local MODES = {
  { short = "major", variant = "",
    intervals = {0, 2, 4, 5, 7, 9, 11},
    chords = {"I", "ii", "iii", "IV", "V", "vi", "viio"},
    seventh = "leading tone" },
  { short = "minor", variant = "natural",
    intervals = {0, 2, 3, 5, 7, 8, 10},
    chords = {"i", "iio", "III", "iv", "v", "VI", "VII"},
    seventh = "subtonic" },
  { short = "minor", variant = "harmonic",
    intervals = {0, 2, 3, 5, 7, 8, 11},
    chords = {"i", "iio", "III+", "iv", "V", "VI", "viio"},
    seventh = "leading tone" },
}

local DEGREE_NAMES = {"tonic","supertonic","mediant","subdominant","dominant","submediant"}

---------------------------------------------------------------- hardware

-- LinnStrument CC22 color values are index - 1 ("default" = its own 4ths colors)
local COLORS = {"default","red","yellow","green","cyan","blue","magenta",
                "off","white","orange","lime","pink"}
local COLUMNS = 25   -- LinnStrument 200

-- "root + triad" style:
--   root = yellow, 3rd & 5th (tonic chord) = green, other scale notes = white
local DEGREE_COLORS = {2, 8, 3, 8, 3, 8, 8}
local DEGREE_COLOR_NAMES = {"yellow", "white", "green", "white", "green", "white", "white"}
-- "rainbow" style: root white, then the colors step around the color wheel
-- as the scale goes up (no blue/red), so neighbouring degrees look related
--   1 white, 2 orange, 3 yellow, 4 lime, 5 green, 6 cyan, 7 magenta
--   (raised 7th in harmonic minor: pink)
local RAINBOW = {8, 9, 2, 10, 3, 4, 6}
local RAINBOW_NAMES = {"white", "orange", "yellow", "lime", "green", "cyan", "magenta"}
local RAISED7_RAINBOW = 11   -- pink
local STYLES = {"root + triad", "root + scale", "rainbow", "one octave", "follow the lights"}
local FOLLOW = 5
local SHAPE_BTNS = {{1,8},{2,8}}   -- grid: one-octave box down / up

-- grid layout: a 12-point ring in the left 7x7, clockwise from the top
local RING = {{4,1},{6,1},{7,2},{7,4},{7,6},{6,7},{4,7},{2,7},{1,6},{1,4},{1,2},{2,1}}
local CENTER = {4, 4}
local MODE_BTNS = {{10,1},{11,1},{12,1}}
local WHITE = {[0]=10, [2]=11, [4]=12, [5]=13, [7]=14, [9]=15, [11]=16}   -- row 8
local BLACK = {[1]=11, [3]=12, [6]=14, [8]=15, [10]=16}                   -- row 7

local linn
local out
local g = grid.connect()
local painter
local learning = false   -- waiting for you to press the bottom-left pad
local pos, mode, page = 1, 1, 1

---------------------------------------------------------------- helpers

local function tonic_name()
  return (mode == 1) and MAJOR_KEYS[pos] or MINOR_KEYS[pos]
end

local function acc_str(a)
  return ({[-2] = "bb", [-1] = "b", [0] = "", [1] = "#", [2] = "x"})[a] or "?"
end

-- spell the scale with one letter per degree, the way it's written in class
local function spell_scale()
  local name = tonic_name()
  local li = 1
  for i, l in ipairs(LETTERS) do if l == name:sub(1, 1) then li = i end end
  local acc = ({["#"] = 1, ["b"] = -1})[name:sub(2)] or 0
  local tonic_pc = (NAT[li] + acc) % 12
  local out = {}
  for i, iv in ipairs(MODES[mode].intervals) do
    local l = (li + i - 2) % 7 + 1
    local pc = (tonic_pc + iv) % 12
    local a = (pc - NAT[l] + 6) % 12 - 6
    out[i] = { name = LETTERS[l] .. acc_str(a), pc = pc }
  end
  return out
end

local function degree_map(scale)
  local d = {}
  for i, n in ipairs(scale) do d[n.pc] = i end
  return d
end

local function key_signature()
  local n = pos - 1
  if n == 0 then return "no # or b" end
  if n <= 6 then return n .. "#: " .. SHARP_ORDER:sub(1, n) end
  n = 12 - n
  return n .. "b: " .. FLAT_ORDER:sub(1, n)
end

local function relative_name()
  if mode == 1 then return "rel: " .. MINOR_KEYS[pos] .. " minor" end
  return "rel: " .. MAJOR_KEYS[pos] .. " major"
end

---------------------------------------------------------------- what's being played

local held = {}   -- [channel * 128 + note] = note  (MPE: one channel per finger)

local SHARP_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local FLAT_NAMES  = {"C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"}

-- spell a pitch class: scale spelling if it's in the key, else follow the key signature
local function note_name(pc)
  for _, n in ipairs(spell_scale()) do if n.pc == pc then return n.name end end
  return (pos >= 8) and FLAT_NAMES[pc + 1] or SHARP_NAMES[pc + 1]
end

-- intervals above the root -> chord suffix, roman-numeral case, numeral suffix
local CHORDS = {
  {"0,4,7",     "",      "up", ""},
  {"0,3,7",     "m",     "lo", ""},
  {"0,3,6",     "dim",   "lo", "o"},
  {"0,4,8",     "aug",   "up", "+"},
  {"0,2,7",     "sus2",  "up", "sus2"},
  {"0,5,7",     "sus4",  "up", "sus4"},
  {"0,4,7,11",  "maj7",  "up", "maj7"},
  {"0,4,7,10",  "7",     "up", "7"},
  {"0,3,7,10",  "m7",    "lo", "7"},
  {"0,3,6,10",  "m7b5",  "lo", " half-dim7"},
  {"0,3,6,9",   "dim7",  "lo", "o7"},
  {"0,3,7,11",  "m(maj7)", "lo", "maj7"},
  {"0,4,8,11",  "+maj7", "up", "+maj7"},
  {"0,4,7,9",   "6",     "up", "6"},
  {"0,3,7,9",   "m6",    "lo", "6"},
  {"0,2,4,7",   "add9",  "up", "add9"},
  {"0,2,3,7",   "m(add9)", "lo", "add9"},
  {"0,4,10",    "7(no5)", "up", "7"},
  {"0,3,10",    "m7(no5)", "lo", "7"},
  {"0,4,11",    "maj7(no5)", "up", "maj7"},
  {"0,2,4,7,10","9",     "up", "9"},
  {"0,2,4,7,11","maj9",  "up", "maj9"},
  {"0,2,3,7,10","m9",    "lo", "9"},
}
local INTERVALS = {"m2","M2","m3","M3","P4","tritone","P5","m6","M6","m7","M7"}
local ROMAN = {"I","II","III","IV","V","VI","VII"}

local function held_notes()
  local notes, seen = {}, {}
  for _, n in pairs(held) do
    if not seen[n] then seen[n] = true; notes[#notes + 1] = n end
  end
  table.sort(notes)
  return notes
end

-- returns name (e.g. "Dm7/C"), roman numeral in this key (or nil), and the interval
-- name when only two pitch classes are held
local function identify(notes)
  if #notes == 0 then return nil end
  local pcs, set = {}, {}
  for _, n in ipairs(notes) do
    local pc = n % 12
    if not set[pc] then set[pc] = true; pcs[#pcs + 1] = pc end
  end
  local bass = notes[1] % 12
  if #pcs == 1 then return note_name(bass), nil end
  if #pcs == 2 then
    local hi = (pcs[1] == bass) and pcs[2] or pcs[1]
    return note_name(bass) .. " + " .. note_name(hi), nil, INTERVALS[(hi - bass) % 12]
  end
  -- try the bass as the root first, then every other note (= an inversion)
  local order = {bass}
  for _, pc in ipairs(pcs) do if pc ~= bass then order[#order + 1] = pc end end
  for _, root in ipairs(order) do
    local ivs = {}
    for _, pc in ipairs(pcs) do ivs[#ivs + 1] = (pc - root) % 12 end
    table.sort(ivs)
    local key = table.concat(ivs, ",")
    for _, c in ipairs(CHORDS) do
      if c[1] == key then
        local name = note_name(root) .. c[2]
        if root ~= bass then name = name .. "/" .. note_name(bass) end
        local roman
        local d = degree_map(spell_scale())[root]
        if d then
          roman = ROMAN[d]
          if c[3] == "lo" then roman = roman:lower() end
          roman = roman .. c[4]
          if root ~= bass then roman = roman .. " (inversion)" end
        end
        return name, roman
      end
    end
  end
  -- not a chord we know: list the pitch classes
  local names = {}
  for _, pc in ipairs(pcs) do names[#names + 1] = note_name(pc) end
  return table.concat(names, " "), nil
end

---------------------------------------------------------------- linnstrument lights

local function color_value(id) return params:get(id) - 1 end

local OFF = 7   -- CC22 "off": every pad outside the scale goes dark

local function raised7(d)
  return d == 7 and mode == 3 and params:get("mark_raised7") == 2
end

local function pad_color(pc, deg)
  local d = deg[pc]
  if not d then return OFF end

  if params:get("style") >= 3 then
    if raised7(d) then return RAISED7_RAINBOW end
    return RAINBOW[d]
  end

  if params:get("style") == 1 then
    -- root + triad (harmonic minor's raised 7th can still be marked)
    if d == 7 and mode == 3 and params:get("mark_raised7") == 2 then
      return color_value("raised7_col")
    end
    return DEGREE_COLORS[d]
  end

  -- simple: root + one scale color (with optional triad / raised 7th marks)
  if d == 1 then return color_value("root_col") end
  if d == 7 and mode == 3 and params:get("mark_raised7") == 2 then
    return color_value("raised7_col")
  end
  if params:get("triad") == 2 and (d == 3 or d == 5) then
    return color_value("triad_col")
  end
  return color_value("scale_col")
end

local function pad_note(col, row)
  return params:get("base_note") + (col - 1) + row * params:get("row_offset")
end

-- every pad on the surface that plays the tonic, low to high
local function root_pads()
  local tonic = spell_scale()[1].pc
  local roots = {}
  for row = 0, 7 do
    for col = 1, COLUMNS do
      local n = pad_note(col, row)
      if n % 12 == tonic then roots[#roots + 1] = {col = col, row = row, note = n} end
    end
  end
  table.sort(roots, function(a, b)
    if a.note ~= b.note then return a.note < b.note end
    return a.col < b.col
  end)
  return roots
end

local shape_pos = 1   -- which root the one-octave box starts from

-- "follow the lights": the next note blinks; play it and it stays lit
local trainer = {
  seq = nil,     -- the run: root up to the octave and back down
  i = 1,         -- which note of the run is next
  trail = {},    -- [row * 100 + col] = color, pads you've already played
  done = false,
  blink = nil,   -- clock id
  missed = false,
}

local function pads_for(test)
  local list = {}
  for row = 0, 7 do
    for col = 1, COLUMNS do
      if test(pad_note(col, row)) then list[#list + 1] = {col, row} end
    end
  end
  return list
end

-- one playable octave, root to root, kept in a compact box
-- (columns root-1 .. root+3, the usual 4ths fingering)
local function octave_box()
  local roots = root_pads()
  if #roots == 0 then return {} end
  shape_pos = util.clamp(shape_pos, 1, #roots)
  local a = roots[shape_pos]
  local targets = {}
  for _, iv in ipairs(MODES[mode].intervals) do targets[#targets + 1] = a.note + iv end
  targets[#targets + 1] = a.note + 12
  local box = {}
  for _, t in ipairs(targets) do
    local best, cost
    for row = 0, 7 do
      local col = t - params:get("base_note") - row * params:get("row_offset") + 1
      if col >= 1 and col <= COLUMNS then
        local c = math.abs(col - (a.col + 1)) + ((row < a.row) and 0.5 or 0)
        if not cost or c < cost then best, cost = {col, row}, c end
      end
    end
    if best then box[best[2] * 100 + best[1]] = true end
  end
  return box
end

-- CC20 = column, CC21 = row, CC22 = color. Row is persistent, so set it once per row.
local function paint(clear, slow)
  if not linn then return end
  local ch = params:get("channel")
  local cols = COLUMNS
  local deg = degree_map(spell_scale())
  local box = (params:get("style") == 4) and octave_box() or nil
  local follow = (params:get("style") == FOLLOW) and not trainer.done
  local rest = params:get("box_rest")
  for row = 0, 7 do
    linn:cc(21, row, ch)
    for col = 1, cols do
      local color = 0
      if not clear then
        local pc = pad_note(col, row) % 12
        color = pad_color(pc, deg)
        if follow then color = trainer.trail[row * 100 + col] or OFF end
        if box and not box[row * 100 + col] and color ~= OFF then
          -- outside the box: dark, or one plain color so the box stands out
          color = (rest == 2) and color_value("scale_col") or OFF
        end
      end
      linn:cc(20, col, ch)
      linn:cc(22, color, ch)
    end
    if slow then clock.sleep(0.01) end   -- pace it so nothing gets dropped
  end
end

-- NRPN via CC 99/98 (parameter) + 6/38 (value), then reset the parameter
local function nrpn(num, value, ch)
  linn:cc(99, num // 128, ch)
  linn:cc(98, num % 128, ch)
  linn:cc(6, value // 128, ch)
  linn:cc(38, value % 128, ch)
  linn:cc(101, 127, ch)
  linn:cc(100, 127, ch)
end

-- MLRE may have left the LinnStrument in User Firmware Mode; turn it off
local function reset_linnstrument()
  if not linn then return end
  nrpn(245, 0, params:get("channel"))
end
-- find a MIDI port by name (skips control-only ports like the Electra's CTRL)
local function find_port(pattern)
  for i, v in ipairs(midi.vports) do
    local n = v.name and v.name:lower()
    if n and n:find(pattern) and not n:find("ctrl") then return i end
  end
  return nil
end

-- silence whatever the synth is holding (all 16 channels, for MPE)
local function all_notes_off(dev)
  if not dev then return end
  for ch = 1, 16 do dev:cc(123, 0, ch) end
end

local function send_lights()
  if painter then clock.cancel(painter) end
  painter = clock.run(function()
    paint(false, true)
    painter = nil
  end)
end

local function set_pad(col, row, color)
  if not linn then return end
  local ch = params:get("channel")
  linn:cc(21, row, ch)
  linn:cc(20, col, ch)
  linn:cc(22, color, ch)
end

-- the pads that should blink right now, and their color
local function trainer_targets()
  local deg = degree_map(spell_scale())
  if not trainer.seq then
    -- waiting for you to pick a root: every root pad blinks
    local tonic = spell_scale()[1].pc
    return pads_for(function(n) return n % 12 == tonic end), pad_color(tonic, deg)
  end
  local target = trainer.seq[trainer.i]
  return pads_for(function(n) return n == target end), pad_color(target % 12, deg)
end

local function trainer_next_name()
  if trainer.done then return "done!" end
  if not trainer.seq then return "play any " .. spell_scale()[1].name end
  local n = trainer.seq[trainer.i]
  local d = degree_map(spell_scale())[n % 12]
  local dir = (trainer.i <= 8) and "up" or "down"
  return "next: " .. spell_scale()[d].name .. " (" .. d .. ") " .. dir
end

local function trainer_stop()
  if trainer.blink then clock.cancel(trainer.blink) end
  trainer.blink = nil
end

local function trainer_reset()
  trainer.seq, trainer.i, trainer.trail, trainer.done, trainer.missed = nil, 1, {}, false, false
end

local function trainer_start()
  trainer_stop()
  trainer.blink = clock.run(function()
    local on = true
    while true do
      if not trainer.done and not painter then
        local pads, color = trainer_targets()
        for _, p in ipairs(pads) do
          -- off-beat: a pad you already played shows its steady color, others go dark
          set_pad(p[1], p[2], on and color or (trainer.trail[p[2] * 100 + p[1]] or OFF))
        end
      end
      on = not on
      clock.sleep(0.25)
    end
  end)
end

-- light the pads you just hit for good, and move the blink on
local function trainer_hit(note)
  local deg = degree_map(spell_scale())
  for _, p in ipairs(pads_for(function(n) return n == note end)) do
    local color = pad_color(note % 12, deg)
    trainer.trail[p[2] * 100 + p[1]] = color
    set_pad(p[1], p[2], color)
  end
end

local function trainer_note(note)
  local deg = degree_map(spell_scale())
  if trainer.done then return end
  if not trainer.seq then
    if note % 12 ~= spell_scale()[1].pc then trainer.missed = true; return end
    -- build the run from the root you chose
    local seq = {}
    for _, iv in ipairs(MODES[mode].intervals) do seq[#seq + 1] = note + iv end
    seq[#seq + 1] = note + 12
    for k = 7, 1, -1 do seq[#seq + 1] = note + MODES[mode].intervals[k] end
    -- the root blinks everywhere; turn off the root pads that weren't played
    for _, p in ipairs(pads_for(function(n) return n % 12 == note % 12 end)) do
      set_pad(p[1], p[2], OFF)
    end
    trainer.seq, trainer.i = seq, 2
    trainer_hit(note)
    trainer.missed = false
    return
  end
  if note ~= trainer.seq[trainer.i] then trainer.missed = true; return end
  trainer.missed = false
  -- the pads you're leaving stop blinking: make sure they're steady
  trainer_hit(note)
  trainer.i = trainer.i + 1
  if trainer.i > #trainer.seq then
    -- made it up and back: show the whole scale, then start over
    trainer.done = true
    send_lights()
    clock.run(function()
      clock.sleep(2)
      if params:get("style") == FOLLOW then
        trainer_reset()
        send_lights()
        redraw()
      end
    end)
  end
end

---------------------------------------------------------------- grid

local function grid_redraw()
  g:all(0)
  -- circle of fifths: current key bright, its neighbours (IV and V keys) medium
  for i, c in ipairs(RING) do
    local dist = math.min((i - pos) % 12, (pos - i) % 12)
    local l = 3
    if dist == 1 then l = 7 end
    if i == pos then l = 15 end
    g:led(c[1], c[2], l)
  end
  -- center: relative major/minor (bright when minor)
  g:led(CENTER[1], CENTER[2], (mode == 1) and 4 or 12)
  -- scale type
  for i, c in ipairs(MODE_BTNS) do g:led(c[1], c[2], (i == mode) and 15 or 3) end
  -- keyboard + degree ladder (row 4, cols 10-16 = degrees 1-7):
  -- root brightest, 3rd & 5th medium, other scale notes dim
  local function level(d)
    if d == 1 then return 15 end
    if d == 3 or d == 5 then return 9 end
    return 4
  end
  local deg = degree_map(spell_scale())
  for pc = 0, 11 do
    local x, y = WHITE[pc], 8
    if not x then x, y = BLACK[pc], 7 end
    g:led(x, y, deg[pc] and level(deg[pc]) or 0)
  end
  for d = 1, 7 do g:led(9 + d, 4, level(d)) end
  if params:get("style") == 4 then
    for _, c in ipairs(SHAPE_BTNS) do g:led(c[1], c[2], 8) end
  end
  g:refresh()
end

---------------------------------------------------------------- screen

local function draw_circle()
  local cx, cy, r = 30, 32, 24
  local names = (mode == 1) and MAJOR_KEYS or MINOR_KEYS
  local a = (pos - 1) / 12 * 2 * math.pi - math.pi / 2
  screen.level(2)
  screen.move(cx, cy)
  screen.line(cx + r * 0.55 * math.cos(a), cy + r * 0.55 * math.sin(a))
  screen.stroke()
  for i = 1, 12 do
    local ang = (i - 1) / 12 * 2 * math.pi - math.pi / 2
    local label = names[i]
    if mode ~= 1 then label = label:lower() end   -- minor keys in lowercase
    screen.level(i == pos and 15 or 3)
    screen.move(cx + r * math.cos(ang), cy + r * math.sin(ang) + 3)
    screen.text_center(label)
  end

  local m = MODES[mode]
  local x = 64
  screen.level(15)
  screen.move(x, 10)
  screen.text(tonic_name() .. " " .. m.short)
  local variant = m.variant
  if pos == 7 then
    variant = variant .. " =" .. ((mode == 1) and ENHARMONIC.major or ENHARMONIC.minor)
  end
  screen.level(6)
  screen.move(x, 20)
  screen.text(variant)
  screen.level(10)
  screen.move(x, 34)
  screen.text(key_signature())
  screen.move(x, 46)
  screen.text(relative_name())
  screen.level(3)
  screen.move(x, 60)
  if learning then
    screen.level(15)
    screen.text("press bottom-left")
  elseif params:get("style") == FOLLOW then
    screen.level(15)
    screen.text(trainer.missed and "not that one - " .. trainer_next_name():gsub("next: ", "") or trainer_next_name())
  elseif #held_notes() > 0 then
    screen.level(15)
    screen.text(identify(held_notes()))
  else
    screen.text("E1: " .. STYLES[params:get("style")])
  end
end

local function draw_playing()
  local notes = held_notes()
  screen.level(3)
  screen.move(0, 7)
  screen.text("playing in " .. tonic_name() .. " " .. MODES[mode].short)
  if #notes == 0 then
    screen.level(4)
    screen.move(64, 38)
    screen.text_center("play something")
    return
  end
  local name, roman, interval = identify(notes)
  screen.font_size(16)
  screen.level(15)
  screen.move(0, 26)
  screen.text(name)
  screen.font_size(8)
  screen.level(10)
  screen.move(0, 38)
  screen.text(roman or interval or "")
  -- each note, low to high, with its scale degree ("-" = outside the key)
  local deg = degree_map(spell_scale())
  local x = 0
  for _, n in ipairs(notes) do
    local pc = n % 12
    local label = note_name(pc) .. (n // 12 - 1)
    local w = screen.text_extents(label)
    if x + w > 128 then break end
    screen.level(deg[pc] and 15 or 4)
    screen.move(x, 52)
    screen.text(label)
    screen.level(5)
    screen.move(x, 62)
    screen.text(deg[pc] and tostring(deg[pc]) or "-")
    x = x + w + 6
  end
end

local function draw_degrees()
  local m = MODES[mode]
  local scale = spell_scale()
  for i = 1, 7 do
    local y = i * 9 - 1
    local raised = (mode == 3 and i == 7)
    screen.level((i == 1 or raised) and 15 or 6)
    screen.move(0, y);  screen.text(i)
    screen.move(10, y); screen.text(scale[i].name)
    screen.move(28, y); screen.text(m.chords[i])
    local style = params:get("style")
    if style == 1 or style >= 3 then
      local cname = (style == 1) and DEGREE_COLOR_NAMES[i] or RAINBOW_NAMES[i]
      if raised and params:get("mark_raised7") == 2 then
        cname = (style == 1) and COLORS[params:get("raised7_col")] or "pink"
      end
      screen.move(54, y); screen.text(cname)
      screen.move(88, y); screen.text(DEGREE_NAMES[i] and DEGREE_NAMES[i]:sub(1, 7) or m.seventh:sub(1, 7))
    else
      screen.move(54, y); screen.text(DEGREE_NAMES[i] or m.seventh)
    end
  end
end

function redraw()
  screen.clear()
  screen.font_size(8)
  if page == 1 then draw_circle()
  elseif page == 2 then draw_degrees()
  else draw_playing() end
  screen.update()
end

---------------------------------------------------------------- controls

local function changed()
  trainer_reset()
  send_lights()
  grid_redraw()
  redraw()
end

function enc(n, d)
  if n == 1 then
    params:delta("style", d)   -- its action repaints the lights
  elseif n == 2 then
    pos = util.wrap(pos + d, 1, 12)
    shape_pos = 1
    changed()
  elseif n == 3 then
    mode = util.clamp(mode + d, 1, 3)
    changed()
  end
end

function key(n, z)
  if z == 0 then return end
  if n == 2 then
    -- relative major/minor: same key signature, different tonic
    mode = (mode == 1) and 2 or 1
    changed()
  elseif n == 3 then
    page = page % 3 + 1
    redraw()
  end
end

local function grid_key(x, y, z)
  if z == 0 then return end
  if x == CENTER[1] and y == CENTER[2] then
    mode = (mode == 1) and 2 or 1
    changed()
    return
  end
  for i, c in ipairs(RING) do
    if c[1] == x and c[2] == y then pos = i; changed(); return end
  end
  for i, c in ipairs(MODE_BTNS) do
    if c[1] == x and c[2] == y then mode = i; changed(); return end
  end
  if params:get("style") == 4 then
    if x == SHAPE_BTNS[1][1] and y == SHAPE_BTNS[1][2] then shape_pos = shape_pos - 1; changed() end
    if x == SHAPE_BTNS[2][1] and y == SHAPE_BTNS[2][2] then shape_pos = shape_pos + 1; changed() end
  end
end

-- incoming from the LinnStrument: learn the bottom-left pad, otherwise
-- pass everything (notes, MPE pitch bend / pressure / CC74) on to the synth
function linn_event(data)
  if learning then
    local msg = midi.to_msg(data)
    if msg.type == "note_on" and msg.vel > 0 then
      learning = false
      params:set("base_note", msg.note)   -- its action repaints the lights
      redraw()
    end
    return   -- the learn press doesn't sound
  end
  if out and out ~= linn and params:get("thru") == 2 then
    out:send(data)
  end
  local msg = midi.to_msg(data)
  if msg.type == "note_on" and msg.vel > 0 then
    held[msg.ch * 128 + msg.note] = msg.note
    if params:get("style") == FOLLOW then trainer_note(msg.note) end
    redraw()
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    held[msg.ch * 128 + msg.note] = nil
    redraw()
  end
end

---------------------------------------------------------------- init

function init()
  norns.enc.sens(2, 4)   -- one key per comfortable turn
  g.key = grid_key

  params:add_separator("scalelights")
  params:add_number("midi_dev", "midi device", 1, 16, 1)
  params:set_action("midi_dev", function(v)
    linn = midi.connect(v)
    linn.event = linn_event
    held = {}
    reset_linnstrument()
    send_lights()
  end)
  params:add_number("channel", "midi channel", 1, 16, 1)
  params:add_number("base_note", "bottom-left note", 0, 127, 30)
  params:add_number("row_offset", "row offset", 1, 12, 5)
  params:add_trigger("learn_base", "learn bottom-left note")
  params:set_action("learn_base", function()
    learning = true
    redraw()
  end)

  params:add_separator("synth out")
  params:add_number("out_dev", "out device (Electra Mini)", 1, 16, 2)
  params:set_action("out_dev", function(v)
    all_notes_off(out)
    out = midi.connect(v)
  end)
  params:add_option("thru", "LinnStrument thru", {"off", "on"}, 2)
  params:set_action("thru", function(v)
    if v == 1 then all_notes_off(out) end
  end)

  params:add_separator("lights")
  params:add_option("style", "style", STYLES, 1)
  params:add_option("root_col", "root", COLORS, 3)
  params:add_option("scale_col", "scale tones", COLORS, 9)
  params:add_option("triad", "show tonic triad", {"off", "on"}, 1)
  params:add_option("triad_col", "triad 3rd & 5th", COLORS, 4)
  params:add_option("mark_raised7", "mark raised 7th", {"off", "on"}, 2)
  params:add_option("raised7_col", "raised 7th", COLORS, 7)
  params:add_option("box_rest", "one octave: outside box", {"off", "scale tones"}, 1)
  params:add_trigger("resend", "resend lights")
  params:set_action("resend", function() send_lights() end)

  for _, id in ipairs({"channel",
                       "root_col", "scale_col", "box_rest",
                       "triad", "triad_col", "mark_raised7", "raised7_col"}) do
    params:set_action(id, function() send_lights() end)
  end
  for _, id in ipairs({"base_note", "row_offset"}) do
    params:set_action(id, function() trainer_reset(); send_lights() end)
  end
  params:set_action("style", function(v)
    trainer_stop()
    trainer_reset()
    if v == FOLLOW then trainer_start() end
    send_lights(); grid_redraw(); redraw()
  end)

  params:read()   -- restore your saved tuning/colors, if any
  if params:get("style") > #STYLES then params:set("style", 1, true) end
  local found = find_port("linnstrument")
  if found then params:set("midi_dev", found, true) end
  local mini = find_port("electra")
  if mini then params:set("out_dev", mini, true) end
  linn = midi.connect(params:get("midi_dev"))
  linn.event = linn_event
  out = midi.connect(params:get("out_dev"))
  reset_linnstrument()
  params:bang()
  changed()
end

function cleanup()
  trainer_stop()
  params:write()
  if painter then clock.cancel(painter) end
  all_notes_off(out)
  paint(true, false)   -- clear the scale colors
  g:all(0)
  g:refresh()
end
