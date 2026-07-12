-- gjs - PLAY LED ON

local NOTE = 61
local VELOCITY = 127
local CHANNEL = 3 -- channel 4 = index 3 in MIDI API

local midi_out = reaper.GetMIDIOutput(0)

if midi_out then
  -- Note On
  midi_out:Send(0x90 + CHANNEL, NOTE, VELOCITY)
end
