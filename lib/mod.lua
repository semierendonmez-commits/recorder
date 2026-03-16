-- recorder
-- v4.0.0 @semi
--
-- tape recorder mod
-- records main output via norns tape API
-- all controls via params menu

local mod = require 'core/mods'

local state = {
  recording = false,
  rec_start = 0,
  segments = 0,
  total_time = 0,
  show_dot = true,
  always_on = false,
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
  state.segments = state.segments + 1
  return string.format("%s%s_%s_%sbpm_%03d.wav",
    state.dir, ts, sname, bpm, state.segments)
end

local function fmt_time(s)
  return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function start_rec()
  if state.recording then return end
  ensure_dir()
  local path = gen_filename()
  -- confirmed norns tape API:
  -- audio.tape_record_open(path) -> opens file
  -- audio.tape_record_start()   -> starts recording main output
  -- audio.tape_record_stop()    -> stops and closes
  audio.tape_record_open(path)
  audio.tape_record_start()
  state.recording = true
  state.rec_start = util.time()
  print("recorder: started " .. path)
end

local function stop_rec()
  if not state.recording then return end
  audio.tape_record_stop()
  local dur = util.time() - state.rec_start
  state.total_time = state.total_time + dur
  state.recording = false
  print(string.format("recorder: saved %.1fs", dur))
end

local function split_rec()
  if not state.recording then
    start_rec()
  else
    stop_rec()
    start_rec()
  end
end

-- ============ PARAMS ============

local function add_params()
  params:add_separator("RECORDER")

  params:add_option("rec_on", "recording", {"OFF", "REC"}, 1)
  params:set_action("rec_on", function(v)
    if v == 2 then start_rec() else stop_rec() end
  end)

  params:add_trigger("rec_split", "> split (new file)")
  params:set_action("rec_split", function() split_rec() end)

  params:add_option("rec_auto", "auto-record", {"OFF", "ON"}, 1)
  params:set_action("rec_auto", function(v) state.always_on = (v == 2) end)

  params:add_option("rec_dot", "show indicator", {"OFF", "ON"}, 2)
  params:set_action("rec_dot", function(v) state.show_dot = (v == 2) end)
end

-- ============ HOOKS ============

mod.hook.register("script_post_init", "recorder", function()
  add_params()

  -- wrap redraw for indicator dot
  local script_redraw = redraw
  redraw = function()
    if script_redraw then script_redraw() end
    if state.recording and state.show_dot then
      local t = util.time() - state.rec_start
      local blink = math.floor(t * 2) % 2
      screen.level(blink == 0 and 12 or 4)
      screen.rect(122, 0, 5, 5)
      screen.fill()
      screen.level(3)
      screen.font_face(1); screen.font_size(8)
      screen.move(119, 7)
      screen.text_right(fmt_time(t))
      screen.update()
    end
  end

  -- auto-start if enabled
  if state.always_on then
    clock.run(function()
      clock.sleep(1.0)
      start_rec()
      pcall(function() params:set("rec_on", 2) end)
    end)
  end
end)

mod.hook.register("script_post_cleanup", "recorder", function()
  stop_rec()
end)

-- ============ MOD MENU ============

local m = {}
local menu_sel = 1
local menu_items = {"recording", "split", "auto-record", "show dot", "---", "segments", "total"}

m.key = function(n, z)
  if n == 2 and z == 1 then mod.menu.exit()
  elseif n == 3 and z == 1 then
    if menu_sel == 1 then
      if state.recording then stop_rec() else start_rec() end
      pcall(function() params:set("rec_on", state.recording and 2 or 1) end)
    elseif menu_sel == 2 then
      split_rec()
      pcall(function() params:set("rec_on", 2) end)
    end
    mod.menu.redraw()
  end
end

m.enc = function(n, d)
  if n == 2 then menu_sel = util.clamp(menu_sel + d, 1, #menu_items)
  elseif n == 3 then
    if menu_sel == 3 then pcall(function() params:delta("rec_auto", d) end)
    elseif menu_sel == 4 then pcall(function() params:delta("rec_dot", d) end)
    end
  end
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  screen.font_face(1); screen.font_size(8)
  screen.level(10); screen.move(1, 7); screen.text("RECORDER")
  if state.recording then
    local t = util.time() - state.rec_start
    screen.level(15); screen.move(128, 7); screen.text_right("REC " .. fmt_time(t))
  end
  local vals = {
    state.recording and "REC" or "off",
    "K3",
    state.always_on and "ON" or "off",
    state.show_dot and "ON" or "off",
    "",
    tostring(state.segments),
    fmt_time(state.total_time),
  }
  for i, name in ipairs(menu_items) do
    if i <= 7 then
      local y = 12 + i * 7
      screen.level(i == menu_sel and 15 or 4)
      screen.move(4, y); screen.text(name)
      screen.move(80, y)
      screen.level(i == menu_sel and 10 or 3)
      screen.text(vals[i])
    end
  end
  screen.level(2); screen.move(1, 63); screen.text("E2:sel E3:adj K3:act")
  screen.update()
end

m.init = function() end
m.deinit = function() stop_rec() end
mod.menu.register(mod.this_name, m)
