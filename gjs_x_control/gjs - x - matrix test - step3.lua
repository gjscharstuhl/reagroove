-- GJS - X - Matrix test - step 3
-- Tests JSFX command 5 without changing the main project.
-- Stop the main GJS control script before running this test.

local GMEM_NAME = "GJS_X_BRIDGE"
local COMMAND_PROGRAMMER_MODE = 1
local COMMAND_SET_MATRIX_RGB = 5

reaper.gmem_attach(GMEM_NAME)

local sequence = math.floor(reaper.gmem_read(0) or 0)
local stage = 0
local wait_started = reaper.time_precise()

local function send_command(command)
    sequence = sequence + 1
    reaper.gmem_write(1, command)
    reaper.gmem_write(0, sequence)
    wait_started = reaper.time_precise()
end

local function acknowledged()
    return math.floor(reaper.gmem_read(2) or -1) == sequence
end

local function write_test_matrix()
    reaper.gmem_write(10, 64)

    local index = 0

    for row = 1, 8 do
        for col = 1, 8 do
            local red, green, blue

            if row == 1 and col == 1 then
                red, green, blue = 127, 127, 127
            elseif row == 8 and col == 8 then
                red, green, blue = 0, 0, 127
            elseif ((row + col) % 2) == 0 then
                red, green, blue = 127, 0, 0
            else
                red, green, blue = 0, 127, 0
            end

            local base = 11 + (index * 4)
            local note = row * 10 + col

            reaper.gmem_write(base + 0, note)
            reaper.gmem_write(base + 1, red)
            reaper.gmem_write(base + 2, green)
            reaper.gmem_write(base + 3, blue)

            index = index + 1
        end
    end
end

local function fail(message)
    reaper.ShowConsoleMsg("Matrix test mislukt: " .. message .. "\n")
end

local function loop()
    if stage == 0 then
        reaper.ShowConsoleMsg("Matrix test gestart.\n")
        send_command(COMMAND_PROGRAMMER_MODE)
        stage = 1

    elseif stage == 1 then
        if acknowledged() then
            write_test_matrix()
            send_command(COMMAND_SET_MATRIX_RGB)
            stage = 2
        elseif reaper.time_precise() - wait_started > 2.0 then
            fail("Programmer Mode kreeg geen bevestiging van de JSFX.")
            return
        end

    elseif stage == 2 then
        if acknowledged() then
            reaper.ShowConsoleMsg(
                "Matrix test geslaagd: command 5 is door de JSFX bevestigd.\n" ..
                "Verwacht: rood/groen schaakbord, linksboven wit, rechtsonder blauw.\n"
            )
            return
        elseif reaper.time_precise() - wait_started > 2.0 then
            fail("Matrix-command kreeg geen bevestiging van de JSFX.")
            return
        end
    end

    reaper.defer(loop)
end

loop()
