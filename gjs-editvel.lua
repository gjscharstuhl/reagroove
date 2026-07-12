--[[
  Advanced Velocity Shaper for Selected MIDI Notes

  Features:
  - Start / End velocity
  - Curve types: Linear, Exponential, Sine, Triangle, Square
  - Shape width (cycles / intensity)
  - Reverse option

  Auteur: ChatGPT
--]]

-- USER INPUT
local ret, input = reaper.GetUserInputs(
  "Velocity Shaper",
  5,
  "StartVel (1-127),EndVel (1-127),Shape (linear/exp/sine/tri/square),Width (>=1),Reverse (0/1)",
  "40,110,linear,1,0"
)

if not ret then return end

local startVel, endVel, shape, width, reverse = input:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")

startVel = tonumber(startVel) or 40
endVel   = tonumber(endVel) or 110
shape    = tostring(shape):lower()
width    = tonumber(width) or 1
reverse  = tonumber(reverse) or 0

-- Clamp values
startVel = math.max(1, math.min(127, startVel))
endVel   = math.max(1, math.min(127, endVel))
width    = math.max(0.001, width)

local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
if not take or not reaper.TakeIsMIDI(take) then
  reaper.ShowMessageBox("Geen actieve MIDI take.", "Fout", 0)
  return
end

-- Verzamel geselecteerde noten
local notes = {}
local _, noteCount = reaper.MIDI_CountEvts(take)

for i = 0, noteCount - 1 do
  local retval, selected, muted, startppq, endppq, chan, pitch, vel =
    reaper.MIDI_GetNote(take, i)

  if selected then
    table.insert(notes, {
      index = i,
      startppq = startppq,
      endppq = endppq,
      chan = chan,
      pitch = pitch,
      muted = muted
    })
  end
end

if #notes < 2 then
  reaper.ShowMessageBox("Selecteer minstens 2 noten.", "Info", 0)
  return
end

-- Sorteer op tijd
table.sort(notes, function(a, b)
  return a.startppq < b.startppq
end)

-- Shape functies
local function applyShape(t)
  if shape == "linear" then
    return t

  elseif shape == "exp" then
    return t ^ (1 + width * 2)

  elseif shape == "sine" then
    return 0.5 + 0.5 * math.sin((t * width * 2 * math.pi) - math.pi/2)

  elseif shape == "tri" then
    local x = (t * width) % 1
    return x < 0.5 and (x * 2) or (2 - x * 2)

  elseif shape == "square" then
    local x = (t * width) % 1
    return x < 0.5 and 0 or 1
  end

  return t
end

reaper.Undo_BeginBlock()
reaper.MIDI_DisableSort(take)

local count = #notes

for i, note in ipairs(notes) do
  local t = (i - 1) / (count - 1)

  if reverse == 1 then
    t = 1 - t
  end

  local shaped = applyShape(t)

  local newVel = math.floor(startVel + (endVel - startVel) * shaped + 0.5)

  newVel = math.max(1, math.min(127, newVel))

  reaper.MIDI_SetNote(
    take,
    note.index,
    true,
    note.muted,
    note.startppq,
    note.endppq,
    note.chan,
    note.pitch,
    newVel,
    false
  )
end

reaper.MIDI_Sort(take)
reaper.Undo_EndBlock("Advanced velocity shaping", -1)
reaper.UpdateArrange()
