# NovaUI

Dark, modern, draggable UI library for Roblox with a Kavo-style API.

## Getting the library
```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"))()
```
(`game:HttpGet` / `loadstring` only exist in script executors. In Roblox Studio or your own game, put `source.lua` in a ModuleScript and `require` it.)

## Kavo-style usage
```lua
local Window  = Library.CreateLib("TITLE", "DarkTheme")   -- themes: DarkTheme, LightTheme, GrapeTheme, BloodTheme, Ocean, Midnight, Sentinel, Synapse (or a Color3)
local Tab     = Window:NewTab("Main")
local Section = Tab:NewSection("Section")

Section:NewButton("ButtonText", "ButtonInfo", function() print("Clicked") end)
Section:NewToggle("Toggle", "info", function(state) print(state) end)
Section:NewSlider("Speed", "info", 100, 0, function(v) print(v) end)   -- (name, info, max, min, callback)
Section:NewTextBox("Name", "info", function(text) print(text) end)
Section:NewLabel("Some text")
Window:ToggleUI()   -- show/hide (RightShift also toggles)
```

## Native NovaUI API (5 button styles, tooltips, notifications)
See `example.lua`.
