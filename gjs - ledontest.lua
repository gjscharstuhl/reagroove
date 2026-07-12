local _, _, _, _, mode, resolution, val, valhw =
  reaper.get_action_context()

local note = math.floor((val / resolution) * 127 + 0.5)

local active_track = nil
local region_num = nil

-- normale mapping
local pc_to_region = {
  [0]  = 1,
  [2]  = 2,
  [3]  = 3,
  [4]  = 4,
  [5]  = 5,
  [7]  = 6,
  [9]  = 7,
  [10] = 8
}

-- wraparound bovenaan Launchpad
if note == 1 then
  active_track = 8
  region_num = 7
elseif note == 2 then
  active_track = 8
  region_num = 8
else
  local pc = note % 12
  region_num = pc_to_region[pc]
  if not region_num then return end

  local base_note = 36
  active_track = math.floor((note - base_note) / 12) + 1
end

if active_track < 1 or active_track > 8 then return end

reaper.ShowMessageBox(
  "note = " .. note ..
  "\nactive_track = " .. active_track ..
  "\nregion_num = " .. region_num,
  "DEBUG",
  0
)
