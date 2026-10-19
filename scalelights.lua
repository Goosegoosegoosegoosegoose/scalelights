-- scalelights
-- major & minor scales
-- on the LinnStrument
--
-- E2: key (circle of 5ths)
-- E3: major / natural minor /
--     harmonic minor
-- K2: relative major <-> minor
-- K3: page (circle / degrees)
-- E1: light style (root + triad /
--     root + scale)
--
-- grid: ring = circle of 5ths
--   center = relative maj/min
--   top right = scale type
--   bottom right = keyboard

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
local STYLES = {"root + triad", "root + scale"}

-- grid layout: a 12-point ring in the left 7x7, clockwise from the top
local RING = {{4,1},{6,1},{7,2},{7,4},{7,6},{6,7},{4,7},{2,7},{1,6},{1,4},{1,2},{2,1}}
local CENTER = {4, 4}
local MODE_BTNS = {{10,1},{11,1},{12,1}}
local WHITE = {[0]=10, [2]=11, [4]=12, [5]=13, [7]=14, [9]=15, [11]=16}   -- row 8
local BLACK = {[1]=11, [3]=12, [6]=14, [8]=15, [10]=16}                   -- row 7

local linn
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

---------------------------------------------------------------- linnstrument lights

local function color_value(id) return params:get(id) - 1 end

local OFF = 7   -- CC22 "off": every pad outside the scale goes dark

local function pad_color(pc, deg)
  local d = deg[pc]
  if not d then return OFF end

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

-- CC20 = column, CC21 = row, CC22 = color. Row is persistent, so set it once per row.
local function paint(clear, slow)
  if not linn then return end
  local ch = params:get("channel")
  local cols = COLUMNS
  local base, offset = params:get("base_note"), params:get("row_offset")
  local deg = degree_map(spell_scale())
  for row = 0, 7 do
    linn:cc(21, row, ch)
    for col = 1, cols do
      local color = 0
      if not clear then
        color = pad_color((base + (col - 1) + row * offset) % 12, deg)
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
-- find the LinnStrument among the MIDI ports by name
local function find_linnstrument()
  for i, v in ipairs(midi.vports) do
    if v.name and v.name:lower():find("linnstrument") then return i end
  end
  return nil
end

local function send_lights()
  if painter then clock.cancel(painter) end
  painter = clock.run(function()
    paint(false, true)
    painter = nil
  end)
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
  else
    screen.text("E1: " .. STYLES[params:get("style")])
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
    if params:get("style") == 1 then
      screen.move(54, y); screen.text(DEGREE_COLOR_NAMES[i])
      screen.move(88, y); screen.text(DEGREE_NAMES[i] and DEGREE_NAMES[i]:sub(1, 7) or m.seventh:sub(1, 7))
    else
      screen.move(54, y); screen.text(DEGREE_NAMES[i] or m.seventh)
    end
  end
end

function redraw()
  screen.clear()
  screen.font_size(8)
  if page == 1 then draw_circle() else draw_degrees() end
  screen.update()
end

---------------------------------------------------------------- controls

local function changed()
  send_lights()
  grid_redraw()
  redraw()
end

function enc(n, d)
  if n == 1 then
    params:delta("style", d)
    grid_redraw()
    redraw()
  elseif n == 2 then
    pos = util.wrap(pos + d, 1, 12)
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
    page = (page == 1) and 2 or 1
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
end

-- incoming notes from the LinnStrument: used to learn the bottom-left pad's note
function linn_event(data)
  if not learning then return end
  local msg = midi.to_msg(data)
  if msg.type == "note_on" and msg.vel > 0 then
    learning = false
    params:set("base_note", msg.note)   -- its action repaints the lights
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

  params:add_separator("lights")
  params:add_option("style", "style", STYLES, 1)
  params:add_option("root_col", "root", COLORS, 3)
  params:add_option("scale_col", "scale tones", COLORS, 9)
  params:add_option("triad", "show tonic triad", {"off", "on"}, 1)
  params:add_option("triad_col", "triad 3rd & 5th", COLORS, 4)
  params:add_option("mark_raised7", "mark raised 7th", {"off", "on"}, 2)
  params:add_option("raised7_col", "raised 7th", COLORS, 7)
  params:add_trigger("resend", "resend lights")
  params:set_action("resend", function() send_lights() end)

  for _, id in ipairs({"channel", "base_note", "row_offset", "style",
                       "root_col", "scale_col",
                       "triad", "triad_col", "mark_raised7", "raised7_col"}) do
    params:set_action(id, function() send_lights() end)
  end

  params:read()   -- restore your saved tuning/colors, if any
  if params:get("style") > #STYLES then params:set("style", 1, true) end
  local found = find_linnstrument()
  if found then params:set("midi_dev", found, true) end
  linn = midi.connect(params:get("midi_dev"))
  linn.event = linn_event
  reset_linnstrument()
  params:bang()
  changed()
end

function cleanup()
  params:write()
  if painter then clock.cancel(painter) end
  paint(true, false)   -- clear the scale colors
  g:all(0)
  g:refresh()
end
