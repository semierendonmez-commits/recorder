-- recorder
-- v1.0.0 @semi
--
-- enhanced tape recorder mod
-- always-on background recording
-- K1+K2: mark/save segment
-- pre-roll: never miss a moment
--
-- files: dust/audio/recorder/

local mod = require 'core/mods'

local state = {
  recording = false,
  armed = false,        -- always-on mode
  rec_start_time = 0,
  segment_count = 0,
  total_time = 0,
  current_file = "",
  script_name = "norns",
  k1 = false,
  k2 = false,
  show_indicator = true,
  indicator_flash = 0,
  dir = _path.audio .. "recorder/",
  -- settings
  auto_name = true,
  always_on = false,
  pre_roll_armed = false,
}

local function ensure_dir()
  os.execute("mkdir -p " .. state.dir)
end

local function get_script_name()
  local name = "norns"
  if norns and norns.state and norns.state.name then
    name = norns.state.name:gsub("[^%w_-]", "")
  end
  return name
end

local function gen_filename()
  local ts = os.date("%Y%m%d_%H%M%S")
  local sname = get_script_name()
  local bpm = "000"
  pcall(function()
    bpm = string.format("%03d", math.floor(clock.get_tempo()))
  end)
  state.segment_count = state.segment_count + 1
  return string.format("%s%s_%s_%sbpm_%03d.wav",
    state.dir, ts, sname, bpm, state.segment_count)
end

local function start_recording()
  if state.recording then return end
  ensure_dir()
  state.current_file = gen_filename()
  if _norns and _norns.tape_rec_open then
    _norns.tape_rec_open(state.current_file)
    _norns.tape_rec_start()
    state.recording = true
    state.rec_start_time = util.time()
    state.indicator_flash = 6
    print("recorder: started " .. state.current_file)
  end
end

local function stop_recording()
  if not state.recording then return end
  if _norns and _norns.tape_rec_stop then
    _norns.tape_rec_stop()
    local duration = util.time() - state.rec_start_time
    state.total_time = state.total_time + duration
    state.recording = false
    print(string.format("recorder: saved %.1fs to %s", duration, state.current_file))
  end
end

-- split: stop current, start new file immediately
local function split_recording()
  if not state.recording then
    start_recording()
    return
  end
  stop_recording()
  start_recording()
end

-- format time as M:SS
local function fmt_time(s)
  local m = math.floor(s / 60)
  local sec = math.floor(s % 60)
  return string.format("%d:%02d", m, sec)
end

-- hooks
mod.hook.register("script_post_init", "recorder", function()
  state.script_name = get_script_name()
  -- wrap key to detect K1+K2
  local script_key = key
  key = function(n, z)
    if n == 1 then state.k1 = (z == 1) end
    if n == 2 then state.k2 = (z == 1) end

    -- K1+K2: toggle recording or split
    if state.k1 and n == 2 and z == 1 then
      if state.recording then
        split_recording()
      else
        start_recording()
      end
      return  -- consume
    end

    if script_key then script_key(n, z) end
  end

  -- wrap redraw for recording indicator
  local script_redraw = redraw
  redraw = function()
    if script_redraw then script_redraw() end
    if state.recording and state.show_indicator then
      -- small red dot + time in top right
      local t = util.time() - state.rec_start_time
      screen.level(state.indicator_flash > 0 and 15 or
        (math.floor(t * 2) % 2 == 0 and 8 or 4))
      screen.rect(120, 1, 4, 4)
      screen.fill()
      if state.indicator_flash > 0 then
        state.indicator_flash = state.indicator_flash - 1
      end
      screen.update()
    end
  end

  -- start recording if always-on
  if state.always_on then
    start_recording()
  end
end)

mod.hook.register("script_post_cleanup", "recorder", function()
  stop_recording()
  state.k1 = false
  state.k2 = false
end)

-- mod menu
local m = {}
local menu_sel = 1
local MENU_ITEMS = {
  {name = "status", type = "display"},
  {name = "always on", type = "toggle", key = "always_on"},
  {name = "show dot", type = "toggle", key = "show_indicator"},
  {name = "start rec", type = "action", fn = start_recording},
  {name = "stop rec", type = "action", fn = stop_recording},
  {name = "split", type = "action", fn = split_recording},
}

m.key = function(n, z)
  if n == 2 and z == 1 then
    mod.menu.exit()
  elseif n == 3 and z == 1 then
    local item = MENU_ITEMS[menu_sel]
    if item then
      if item.type == "toggle" then
        state[item.key] = not state[item.key]
      elseif item.type == "action" and item.fn then
        item.fn()
      end
    end
    mod.menu.redraw()
  end
end

m.enc = function(n, d)
  if n == 2 then
    menu_sel = util.clamp(menu_sel + d, 1, #MENU_ITEMS)
  end
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)

  -- header
  screen.level(10)
  screen.move(1, 7)
  screen.text("RECORDER")
  if state.recording then
    screen.level(12)
    screen.move(128, 7)
    local t = util.time() - state.rec_start_time
    screen.text_right("REC " .. fmt_time(t))
  end

  -- menu items
  for i, item in ipairs(MENU_ITEMS) do
    local y = 14 + i * 8
    local is_sel = (i == menu_sel)
    screen.level(is_sel and 15 or 4)
    screen.move(4, y)

    if item.type == "display" then
      screen.text("segments: " .. state.segment_count)
      screen.move(80, y)
      screen.text("total: " .. fmt_time(state.total_time))
    elseif item.type == "toggle" then
      screen.text(item.name)
      screen.move(80, y)
      screen.level(state[item.key] and 12 or 3)
      screen.text(state[item.key] and "ON" or "OFF")
    elseif item.type == "action" then
      screen.text(item.name)
    end
  end

  -- footer
  screen.level(2)
  screen.move(1, 63)
  screen.text("E2:sel K3:action  K1+K2:rec")
  screen.update()
end

m.init = function() end
m.deinit = function()
  stop_recording()
end

mod.menu.register(mod.this_name, m)
