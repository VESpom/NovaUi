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
-- Window:SetBackground({ Video = 1234567890, ColorMap = loadstring(readfile("map.lua"))(), Match = true })
-- Window:ClearBackground()
-- Window:ToggleSettings()
