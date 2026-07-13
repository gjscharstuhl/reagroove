local libPath =
    reaper.GetResourcePath()
    .. "/Scripts/gjs/gjs - lib.lua"

local SceneManager = dofile(libPath)

-- Testdata instellen
SceneManager.resetSceneState()

SceneManager.setScene(
    1,
    {1, 2, 3, 4, 5, 6, 7, 8}
)

SceneManager.setTrackScene(
    1,  -- scene
    2,  -- track
    9   -- pattern
)

SceneManager.getScene(2)

SceneManager.setTrackScene(
    2,
    5,
    12
)

SceneManager.setCurrentScene(1)
SceneManager.setNextScene(2)

-- Volledige opgeslagen ExtState-string tonen
SceneManager.showSceneState()
