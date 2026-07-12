local is_new, filename, sectionID, cmdID, mode, resolution, val, valhw =
  reaper.get_action_context()

reaper.ShowMessageBox(
  "is_new = " .. tostring(is_new) ..
  "\nmode = " .. tostring(mode) ..
  "\nresolution = " .. tostring(resolution) ..
  "\nval = " .. tostring(val) ..
  "\nvalhw = " .. tostring(valhw),
  "ACTION CONTEXT",
  0
)
