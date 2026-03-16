-- recorder
-- v2.0.0 @semi
--
-- enhanced tape recorder mod
-- params menu integrated
-- no key combos (avoids conflicts)

local mod = require 'core/mods'

local state = {
  recording = false,
  rec_start_time = 0,
  segment_count = 0,
  total_time = 0,
  current_file = "",
  show_dot = true,
  always_on = false,
  rec_clock = nil,
  dir = _path.audio .. "recorder/",
}

local function ensure_dir()
  os.execute("mkdir -p " .. state.dir)
end

local function get_script_name()
  local name = "norns"
  pcall(function()
    if norns.state.name then name = norns.state.name:gsub("[^%w_-]", "") end
  end)
  return name
end

local function gen_filename()
  local ts = os.date("%Y%m%d_%H%M%S")
  local sname = get_script_name()
  local bpm = "000"
  pcall(function() bpm = string.format("%03d", math.floor(clock.get_tempo())) end)
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
    print("recorder: started " .. state.current_file)
  end
end

local function stop_recording()
  if not state.recording then return end
  if _norns and _norns.tape_rec_stop then
    _norns.tape_rec_stop()
    local dur = util.time() - state.rec_start_time
    state.total_time = state.total_time + dur
    state.recording = false
    print(string.format("recorder: saved %.1fs", dur))
  end
end

local function split_recording()
  if not state.recording then
    start_recording()
    return
  end
  stop_recording()
  start_recording()
end

local function fmt_time(s)
  return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

-- ============ PARAMS ============

local function add_params()
  params:add_separator("RECORDER")

  params:add_option("rec_record", "recording", {"OFF", "ON"}, 1)
  params:set_action("rec_record", function(v)
    if v == 2 then start_recording() else stop_recording() end
  end)

  params:add_trigger("rec_split", "split (new file)")
  params:set_action("rec_split", function() split_recording() end)

  params:add_option("rec_always_on", "auto-record", {"OFF", "ON"}, 1)
  params:set_action("rec_always_on", function(v)
    state.always_on = (v == 2)
  end)

  params:add_option("rec_show_dot", "show indicator", {"OFF", "ON"}, 2)
  params:set_action("rec_show_dot", function(v)
    state.show_dot = (v == 2)
  end)
end

-- ============ HOOKS ============

mod.hook.register("script_post_init", "recorder", function()
  add_params()

  -- wrap redraw for recording indicator
  local script_redraw = redraw
  redraw = function()
    if script_redraw then script_redraw() end
    if state.recording and state.show_dot then
      local t = util.time() - state.rec_start_time
      -- blinking red dot top-right
      local blink = math.floor(t * 2) % 2 == 0
      screen.level(blink and 10 or 4)
      screen.rect(122, 1, 4, 4)
      screen.fill()
      -- time indicator
      screen.level(3)
      screen.move(120, 7)
      screen.text_right(fmt_time(t))
      screen.update()
    end
  end

  -- auto-record if enabled
  if state.always_on then
    clock.run(function()
      clock.sleep(0.5)
      start_recording()
      params:set("rec_record", 2)
    end)
  end
end)

mod.hook.register("script_post_cleanup", "recorder", function()
  if state.recording then
    stop_recording()
  end
end)

-- ============ MOD MENU ============

local m = {}
local menu_items = {"record", "split", "auto-record", "show dot", "segments", "total time"}
local menu_sel = 1

m.key = function(n, z)
  if n == 2 and z == 1 then
    mod.menu.exit()
  elseif n == 3 and z == 1 then
    if menu_sel == 1 then
      if state.recording then stop_recording() else start_recording() end
      pcall(function() params:set("rec_record", state.recording and 2 or 1) end)
    elseif menu_sel == 2 then
      split_recording()
    end
    mod.menu.redraw()
  end
end

m.enc = function(n, d)
  if n == 2 then
    menu_sel = util.clamp(menu_sel + d, 1, #menu_items)
  elseif n == 3 then
    if menu_sel == 3 then
      pcall(function() params:delta("rec_always_on", d) end)
    elseif menu_sel == 4 then
      pcall(function() params:delta("rec_show_dot", d) end)
    end
  end
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  screen.font_face(1); screen.font_size(8)
  screen.level(10)
  screen.move(1, 7); screen.text("RECORDER")
  if state.recording then
    screen.level(12)
    local t = util.time() - state.rec_start_time
    screen.move(128, 7); screen.text_right("REC " .. fmt_time(t))
  end

  for i, name in ipairs(menu_items) do
    local y = 14 + i * 8
    if y > 56 then break end
    screen.level(i == menu_sel and 15 or 4)
    screen.move(4, y)
    screen.text(name)
    screen.move(80, y)
    if i == 1 then
      screen.level(state.recording and 12 or 3)
      screen.text(state.recording and "REC" or "off")
    elseif i == 2 then
      screen.level(3); screen.text("K3")
    elseif i == 3 then
      screen.level(state.always_on and 8 or 3)
      screen.text(state.always_on and "ON" or "off")
    elseif i == 4 then
      screen.level(state.show_dot and 8 or 3)
      screen.text(state.show_dot and "ON" or "off")
    elseif i == 5 then
      screen.level(6); screen.text(tostring(state.segment_count))
    elseif i == 6 then
      screen.level(6); screen.text(fmt_time(state.total_time))
    end
  end

  screen.level(2)
  screen.move(1, 63); screen.text("E2:sel E3:adj K3:action")
  screen.update()
end

m.init = function() end
m.deinit = function() stop_recording() end
mod.menu.register(mod.this_name, m)
