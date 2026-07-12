-- Create Pattern folder:
-- Pattern
--   track1: pat1  - pat8
--   track2: pat9  - pat16
--   ...
--   track8: pat57 - pat64

local rootName = "Pattern"
local numFolders = 8
local numPadsPerFolder = 8

local patNum = 1

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local insertIndex = reaper.CountTracks(0)

-- Root folder
reaper.InsertTrackAtIndex(insertIndex, true)
local root = reaper.GetTrack(0, insertIndex)
reaper.GetSetMediaTrackInfo_String(root, "P_NAME", rootName, true)
reaper.SetMediaTrackInfo_Value(root, "I_FOLDERDEPTH", 1)

for t = 1, numFolders do
  local folderIndex = reaper.CountTracks(0)

  reaper.InsertTrackAtIndex(folderIndex, true)
  local folder = reaper.GetTrack(0, folderIndex)

  reaper.GetSetMediaTrackInfo_String(folder, "P_NAME", "track" .. t, true)
  reaper.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)

  for p = 1, numPadsPerFolder do
    local patIndex = reaper.CountTracks(0)

    reaper.InsertTrackAtIndex(patIndex, true)
    local pat = reaper.GetTrack(0, patIndex)

    reaper.GetSetMediaTrackInfo_String(pat, "P_NAME", "pat" .. patNum, true)

    if t == numFolders and p == numPadsPerFolder then
      -- laatste pat sluit track8 én Pattern
      reaper.SetMediaTrackInfo_Value(pat, "I_FOLDERDEPTH", -2)
    elseif p == numPadsPerFolder then
      -- laatste pat sluit alleen de huidige track-folder
      reaper.SetMediaTrackInfo_Value(pat, "I_FOLDERDEPTH", -1)
    else
      reaper.SetMediaTrackInfo_Value(pat, "I_FOLDERDEPTH", 0)
    end

    patNum = patNum + 1
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Create Pattern launcher folder structure", -1)
