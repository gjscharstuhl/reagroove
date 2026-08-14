-- ReaGroove - Choose SFZ v3.lua
-- Pure REAPER Lua browser + SFZ path preprocessor.
-- No js_ReaScriptAPI required.

local sep = package.config:sub(1,1)
local resource = reaper.GetResourcePath()
local cfgdir = resource .. sep .. "Data" .. sep .. "ReaGroove"
local cfg_sfz = cfgdir .. sep .. "current_sfz.txt"
local cfg_shared = cfgdir .. sep .. "current_shared_sample.txt"

local function dirname(path)
  if not path or path == "" then return "" end
  path = path:gsub("[/\\]+$", "")
  return path:match("^(.*)[/\\][^/\\]+$") or path
end

local function parent_dir(path)
  if not path or path == "" then return path end
  local p = path:gsub("[/\\]+$", "")
  local parent = p:match("^(.*)[/\\][^/\\]+$")
  if not parent or parent == "" then
    if p == "/" then return "/" end
    if p:match("^%a:$") then return p .. sep end
    return "/"
  end
  return parent
end

local function join(a,b)
  if not a or a == "" then return b or "" end
  if not b or b == "" then return a end
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then
    return a .. b
  end
  return a .. sep .. b
end

local function normalize(path)
  if not path then return "" end
  path = path:gsub("\\", "/")

  local prefix = ""
  if path:match("^/") then
    prefix = "/"
  elseif path:match("^%a:/") then
    prefix = path:sub(1,3)
    path = path:sub(4)
  end

  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == "." or part == "" then
      -- skip
    elseif part == ".." then
      if #parts > 0 then table.remove(parts) end
    else
      parts[#parts+1] = part
    end
  end

  local body = table.concat(parts, "/")
  if prefix == "/" then
    return "/" .. body
  elseif prefix ~= "" then
    return prefix .. body
  else
    return body
  end
end

local function parse_shared_sample(sfzpath)
  local f = io.open(sfzpath, "r")
  if not f then return "" end

  local default_path = ""
  local global_sample = ""
  local scope = ""

  for raw in f:lines() do
    local line = raw:gsub("//.*$", "")

    if line:find("<control>", 1, true) then scope = "control" end
    if line:find("<global>", 1, true) then scope = "global" end
    if line:find("<master>", 1, true) then scope = "master" end
    if line:find("<group>", 1, true) then scope = "group" end
    if line:find("<region>", 1, true) then scope = "region" end

    if scope == "control" then
      local v = line:match("default_path%s*=%s*([^%s]+)")
      if v then default_path = v end
    elseif scope == "global" then
      local v = line:match("sample%s*=%s*([^%s]+)")
      if v then global_sample = v end
    end
  end
  f:close()

  if global_sample == "" then return "" end

  local base = dirname(sfzpath)
  local resolved = normalize(join(join(base, default_path), global_sample))
  return resolved
end

local function write_file(path, text)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  f:write(text or "", "\n")
  f:close()
  return true
end

local function existing_start_dir()
  local f = io.open(cfg_sfz, "r")
  if f then
    local p = f:read("*l")
    f:close()
    if p and p ~= "" then
      local d = dirname(p)
      if d ~= "" then return d end
    end
  end
  local home = os.getenv("HOME")
  return (home and home ~= "") and home or resource
end

local function scan(path)
  local rows = {{name="..", kind="dir"}}

  local i = 0
  while true do
    local d = reaper.EnumerateSubdirectories(path, i)
    if not d then break end
    if d ~= "." and d ~= ".." then rows[#rows+1] = {name=d, kind="dir"} end
    i = i + 1
  end

  table.sort(rows, function(a,b)
    if a.name == ".." then return true end
    if b.name == ".." then return false end
    return a.name:lower() < b.name:lower()
  end)

  local fs = {}
  i = 0
  while true do
    local fn = reaper.EnumerateFiles(path, i)
    if not fn then break end
    if fn:lower():match("%.sfz$") then fs[#fs+1] = {name=fn, kind="file"} end
    i = i + 1
  end
  table.sort(fs, function(a,b) return a.name:lower() < b.name:lower() end)
  for _,v in ipairs(fs) do rows[#rows+1] = v end

  return rows
end

local function save_and_reload(fullpath)
  reaper.RecursiveCreateDirectory(cfgdir, 0)

  local shared = parse_shared_sample(fullpath)

  local ok, err = write_file(cfg_sfz, fullpath)
  if not ok then
    reaper.ShowMessageBox("Could not write:\n"..cfg_sfz.."\n\n"..tostring(err),
      "ReaGroove SFZ Player", 0)
    return false
  end

  write_file(cfg_shared, shared)

  local track = reaper.GetSelectedTrack(0, 0)
  if track then
    local fxcount = reaper.TrackFX_GetCount(track)
    for fx = 0, fxcount - 1 do
      local okn, name = reaper.TrackFX_GetFXName(track, fx, "")
      if okn and name:find("ReaGroove SFZ Player", 1, true) then
        local cur = reaper.TrackFX_GetParam(track, fx, 0)
        reaper.TrackFX_SetParam(track, fx, 0, cur < 0.5 and 1 or 0)
        return true
      end
    end
  end

  reaper.ShowMessageBox(
    "SFZ selected:\n"..fullpath..
    "\n\nResolved shared sample:\n"..(shared ~= "" and shared or "(none)")..
    "\n\nSelect the ReaGroove SFZ Player track and move Reload trigger once.",
    "ReaGroove SFZ Player", 0)
  return true
end

local current = existing_start_dir()
local rows = scan(current)
local scroll, selected = 0, 1
local row_h, header_h = 24, 70
local last_click_time, last_click_row, last_cap = 0, -1, 0

gfx.init("ReaGroove - Choose SFZ v3", 760, 520, 0)

local function rescan()
  rows = scan(current)
  scroll, selected = 0, 1
end

local function activate(idx)
  local item = rows[idx]
  if not item then return end
  if item.kind == "dir" then
    current = item.name == ".." and parent_dir(current) or join(current, item.name)
    rescan()
  else
    local fullpath = join(current, item.name)
    if save_and_reload(fullpath) then
      gfx.quit()
      return true
    end
  end
end

local function loop()
  local char = gfx.getchar()
  if char < 0 or char == 27 then gfx.quit(); return end
  if char == 8 then current = parent_dir(current); rescan()
  elseif char == 13 then if activate(selected) then return end end

  local wheel = gfx.mouse_wheel
  if wheel ~= 0 then
    scroll = scroll - math.floor(wheel / 120)
    local visible = math.max(1, math.floor((gfx.h-header_h)/row_h))
    scroll = math.max(0, math.min(scroll, math.max(0,#rows-visible)))
    gfx.mouse_wheel = 0
  end

  local cap = gfx.mouse_cap
  local click = (cap & 1) == 1 and (last_cap & 1) == 0
  last_cap = cap

  if click and gfx.mouse_y >= header_h then
    local idx = math.floor((gfx.mouse_y-header_h)/row_h)+1+scroll
    if rows[idx] then
      selected = idx
      local now = reaper.time_precise()
      if last_click_row == idx and now-last_click_time < 0.45 then
        if activate(idx) then return end
        last_click_row = -1
      else
        last_click_row, last_click_time = idx, now
      end
    end
  end

  gfx.set(0.12,0.12,0.12,1); gfx.rect(0,0,gfx.w,gfx.h,1)
  gfx.setfont(1,"Arial",20); gfx.set(1,1,1,1)
  gfx.x,gfx.y=14,10; gfx.drawstr("ReaGroove - Choose SFZ v3")
  gfx.setfont(1,"Arial",13); gfx.set(0.8,0.8,0.8,1)
  gfx.x,gfx.y=14,39; gfx.drawstr(current)

  local visible = math.max(1, math.floor((gfx.h-header_h)/row_h))
  local first,last = scroll+1, math.min(#rows,scroll+visible)

  for i=first,last do
    local y = header_h+(i-first)*row_h
    local item=rows[i]
    if i==selected then gfx.set(0.28,0.32,0.38,1); gfx.rect(0,y,gfx.w,row_h,1) end
    gfx.setfont(1,"Arial",14)
    if item.kind=="dir" then gfx.set(0.72,0.85,1,1) else gfx.set(0.85,1,0.72,1) end
    gfx.x,gfx.y=16,y+4
    gfx.drawstr(item.kind=="dir" and ("[DIR]  "..item.name) or item.name)
  end

  gfx.update()
  reaper.defer(loop)
end

loop()

