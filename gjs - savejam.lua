-- gjs - Save jam snapshot
-- Save current project into ~/jams/jam-YYYY-MM-DD-XX/
-- Copy all used media into media/
-- Reuse SAME project tab
-- No dialogs

local jams_dir = os.getenv("HOME") .. "/jams"
local date = os.date("%Y-%m-%d")

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function copy_file(src, dst)

  local in_f = io.open(src, "rb")
  if not in_f then
    return false
  end

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
  return path:match("([^/\\]+)$")
end

local function unique_path(folder, name)

  local base, ext =
    name:match("^(.*)(%.[^%.]*)$")

  if not base then
    base = name
    ext = ""
  end

  local path =
    folder .. "/" .. name

  local i = 1

  while file_exists(path) do

    path = string.format(
      "%s/%s-%02d%s",
      folder,
      base,
      i,
      ext
    )

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

while true do

  jam_name = string.format(
    "jam-%s-%02d",
    date,
    jam_num
  )

  jam_path =
    jams_dir .. "/" .. jam_name

  if not file_exists(jam_path) then
    break
  end

  jam_num = jam_num + 1
end

------------------------------------------------------------
-- Create folders
------------------------------------------------------------

local media_path =
  jam_path .. "/media"

reaper.RecursiveCreateDirectory(
  jam_path,
  0
)

reaper.RecursiveCreateDirectory(
  media_path,
  0
)

------------------------------------------------------------
-- Copy media + relink
------------------------------------------------------------

reaper.PreventUIRefresh(1)

local copied = {}

local item_count =
  reaper.CountMediaItems(0)

for i = 0, item_count - 1 do

  local item =
    reaper.GetMediaItem(0, i)

  local take_count =
    reaper.CountTakes(item)

  for t = 0, take_count - 1 do

    local take =
      reaper.GetTake(item, t)

    if take and
       not reaper.TakeIsMIDI(take)
    then

      local src =
        reaper.GetMediaItemTake_Source(take)

      local src_path =
        reaper.GetMediaSourceFileName(src, "")

      if src_path and src_path ~= "" then

        local new_path =
          copied[src_path]

        ----------------------------------------------------
        -- Copy once
        ----------------------------------------------------

        if not new_path then

          local filename =
            basename(src_path)

          new_path =
            unique_path(
              media_path,
              filename
            )

          local ok =
            copy_file(
              src_path,
              new_path
            )

          if ok then
            copied[src_path] =
              new_path
          else
            new_path = nil
          end
        end

        ----------------------------------------------------
        -- Relink take
        ----------------------------------------------------

        if new_path then

          local new_src =
            reaper.PCM_Source_CreateFromFile(
              new_path
            )

          if new_src then

            reaper.SetMediaItemTake_Source(
              take,
              new_src
            )

          end
        end
      end
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

------------------------------------------------------------
-- Save project
------------------------------------------------------------

local rpp_path =
  jam_path ..
  "/" ..
  jam_name ..
  ".rpp"

reaper.Main_SaveProjectEx(
  0,
  rpp_path,
  0
)

------------------------------------------------------------
-- Open fresh empty project
-- SAME TAB
-- NO PROMPTS
------------------------------------------------------------
------------------------------------------------------------
-- Open fresh empty project
-- SAME TAB
-- NO PROMPTS
------------------------------------------------------------

local empty_project_path =
  jams_dir .. "/__empty_project.rpp"

local f =
  io.open(empty_project_path, "w")

if f then
  f:write("<REAPER_PROJECT 0.1 \"7.0\" 0\n>\n")
  f:close()


end
