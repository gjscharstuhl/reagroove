GJS - X - CONTROL
=================

Plaats alle .lua-bestanden uit deze map samen in dezelfde map.
Start alleen:

    gjs - x - control.lua

Bestanden:
- gjs - x - control.lua   hoofdscript / loader
- gjs - x - core.lua      gedeelde API, state en MIDI-logica
- gjs - x - screen0.lua   hoofdscherm
- gjs - x - screen1.lua   pattern launcher
- gjs - x - screen2.lua   mixerfaders
- gjs - x - screen3.lua t/m screen7.lua tijdelijke testschermen

De MIDI-output wordt gezocht op DEVICE_NAME = "X" in core.lua.
De Programmer Mode SysEx is nog een hook/comment in auto_program_mode().

Version 21 - subproject mixer page 4
- Screen 2, page 4: volume of up to 8 top-level tracks in the active subproject.
- Screen 3, page 4: pan of the same top-level tracks.
- Child tracks are ignored.
- Values stay synchronized with REAPER and redraw when ActiveTrack changes.
- Shared logic is in gjs - x - subproject_mixer.lua.

Piano sequencer audition
------------------------
Add "gjs: Piano Sequencer Audition" before the instrument on the track you
want to hear. In screen 6 piano mode, pressing a piano pad now sends the exact
selected score pitch; releasing the pad sends note-off. Slider 1 selects the
MIDI output channel (default channel 1).

Screen 6 piano chord mode:
- Piano keys toggle notes into/out of the current chord.
- Pad 38 toggles chord monitoring through the Piano Sequencer Audition JSFX.
- Audition always uses the velocity set by the screen 6 velocity fader.
- Pressing a sequencer step inserts/removes every selected chord note at once.

Launchpad Performance Gate
--------------------------
IMPORTANT: place "gjs: Launchpad Performance Gate" in the track INPUT FX chain,
not in the normal Track FX chain. Input FX receives live controller MIDI only;
MIDI-item and sequencer playback bypasses it, so sequencer notes are never filtered.
For existing projects you can run:

    gjs - x - move performance gate to input fx.lua

This moves an existing normal Performance Gate to Input FX and adds it to armed
tracks when needed.
