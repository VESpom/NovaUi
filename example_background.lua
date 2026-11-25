-- NovaUI: settings, backgrounds and colour matching
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"))()

local Window = Library.CreateLib("Nova Hub", "DarkTheme", {
	-- a login logo that works everywhere: your avatar head shot (or { Pixels = <tools/novaui_tool.py output> })
	Image = { User = 1 },
	-- optional: starts with a looping video behind the window
	-- Background = { Video = 1234567890, Dim = 0.62, Glass = 0.2 },
})

local Main = Window:NewTab("Main")
local Section = Main:NewSection("Hello")
Section:NewButton("Click me", "Does a thing", function()
	print("clicked")
end)
Section:NewToggle("Toggle", "Flips", function(on)
	print("toggle", on)
end)

-- Everything below is also available from the gear button in the window.
-- Window:SetBackground({ Image = { Game = 920587237 } })
-- A file in workspace/NovaUI/backgrounds finds its colour map by itself:
--   python3 tools/novaui_tool.py colormap intro.webm --sidecar   (writes intro.map.txt next to it)
-- Window:SetBackground({ Video = "intro.webm", Match = true })
-- For an asset id, pass the map yourself (no loadstring needed for the text format):
-- Window:SetBackground({ Video = 1234567890, ColorMap = Library.ParseColorMap(readfile("NovaUI/backgrounds/intro.map.txt")), Match = true })
-- Window:ClearBackground()
-- Window:ToggleSettings()
