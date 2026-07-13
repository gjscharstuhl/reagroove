local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")
local SCRIPT_ID = "GJS_PatternLauncherBlink"
local BLINK_INTERVAL = 0.25

local _, _, _, _, mode, resolution, val =
    reaper.get_action_context()

if val == 0 then
    return -- release negeren
end

local note = math.floor((val / resolution) * 127 + 0.5)

if note < 60 or note > 75 then
    return
end

local slot = (12-math.floor((note-60)/4)*4)+math.floor(((note-60)%4))+1
local filename="slot_"..tostring(slot)


if slot < 1 or slot > 16 then return end


-- gjs - Save multi-tab jam snapshot
-- Save all open project tabs into ~/jams/jam-YYYY-MM-DD-XX/
-- Copy all used media into shared media/
-- Create .RPL project list
-- No dialogs

local jams_dir = os.getenv("HOME") .. "/jams"
local date = os.date("%Y-%m-%d")

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function copy_file(src, dst)
  local in_f = io.open(src, "rb")
  if not in_f then return false end

  local out_f = io.open(dst, "wb")
  if not out_f then
    in_f:close()
    return false
  end

  out_f:write(in_f:read("*all"))
  in_f:close()
  out_f:close()
  return true
end

local function basename(path)
  return path:match("([^/\\]+)$") or path
end

local function strip_ext(name)
  return (name:gsub("%.[^%.]+$", ""))
end

local function safe_name(name)
  name = name:gsub("[/\\:%*%?\"<>|]", "_")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "project" end
  return name
end

local function unique_path(folder, name)
  local base, ext = name:match("^(.*)(%.[^%.]*)$")
  if not base then base = name; ext = "" end

  local path = folder .. "/" .. name
  local i = 1

  while file_exists(path) do
    path = string.format("%s/%s-%02d%s", folder, base, i, ext)
    i = i + 1
  end

  return path
end

------------------------------------------------------------
-- Find next jam folder
------------------------------------------------------------

local jam_num = 1
local jam_name
local jam_path


  jam_name = filename
  jam_path = jams_dir .. "/" .. jam_name


  


local media_path = jam_path .. "/media"

reaper.RecursiveCreateDirectory(jam_path, 0)
reaper.RecursiveCreateDirectory(media_path, 0)

------------------------------------------------------------
-- Collect open projects
------------------------------------------------------------

local projects = {}
local idx = 0

while true do
  local proj, projfn = reaper.EnumProjects(idx, "")
  if not proj then break end

  projects[#projects + 1] = {
    proj = proj,
    path = projfn or "",
    index = idx + 1
  }

  idx = idx + 1
end

------------------------------------------------------------
-- Copy media + relink per project
------------------------------------------------------------

reaper.PreventUIRefresh(1)

local copied = {}
local saved_paths = {}

for p = 1, #projects do
  local proj = projects[p].proj

  local item_count = reaper.CountMediaItems(proj)

  for i = 0, item_count - 1 do
    local item = reaper.GetMediaItem(proj, i)
    local take_count = reaper.CountTakes(item)

    for t = 0, take_count - 1 do
      local take = reaper.GetTake(item, t)

      if take and not reaper.TakeIsMIDI(take) then
        local src = reaper.GetMediaItemTake_Source(take)
        local src_path = reaper.GetMediaSourceFileName(src, "")

        if src_path and src_path ~= "" then
          local new_path = copied[src_path]

          if not new_path then
            local filename = basename(src_path)
            new_path = unique_path(media_path, filename)

            if copy_file(src_path, new_path) then
              copied[src_path] = new_path
            else
              new_path = nil
            end
          end

          if new_path then
            local new_src = reaper.PCM_Source_CreateFromFile(new_path)
            if new_src then
              reaper.SetMediaItemTake_Source(take, new_src)
            end
          end
        end
      end
    end
  end

  ----------------------------------------------------------
  -- Save this project tab
  ----------------------------------------------------------

  local project_name

  if projects[p].path ~= "" then
    project_name = strip_ext(basename(projects[p].path))
  else
    project_name = string.format("project-%02d", projects[p].index)
  end

  project_name = safe_name(project_name)

  local rpp_path = unique_path(
    jam_path,
    string.format("%02d-%s.rpp", projects[p].index, project_name)
  )

  reaper.Main_SaveProjectEx(proj, rpp_path, 0)
  saved_paths[#saved_paths + 1] = rpp_path
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

------------------------------------------------------------
-- Write RPL project list
------------------------------------------------------------

local rpl_path = jam_path .. "/" .. jam_name .. ".RPL"
local rpl = io.open(rpl_path, "w")

if rpl then
  for i = 1, #saved_paths do
    rpl:write(saved_paths[i] .. "\n")
  end
  rpl:close()
end

------------------------------------------------------------
-- Done
------------------------------------------------------------


