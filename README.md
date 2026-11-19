# NovaUI

Dark, modern, draggable UI library for Roblox with the **same API as Kavo UI Library**. Only the look and the loadstring change.

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"))()
local Window = Library.CreateLib("TITLE", "DarkTheme")
local Tab = Window:NewTab("TabName")
local Section = Tab:NewSection("Section Name")
Section:NewButton("ButtonText", "ButtonInfo", function() print("Clicked") end)
```

Everything in Kavo's docs is supported: `UpdateSection`, `NewLabel`/`UpdateLabel`, `NewButton`/`UpdateButton`, `NewToggle`/`UpdateToggle`, `NewSlider` (name, info, max, min, cb), `NewTextBox`, `NewKeybind`, `NewDropdown` + `:Refresh`, `NewColorPicker`, custom colour tables, `Library:ToggleUI()` and `Library:ChangeColor()`.
Themes: LightTheme, DarkTheme, GrapeTheme, BloodTheme, Ocean, Midnight, Sentinel, Synapse.

NovaUI extras (optional 3rd argument to `CreateLib`): `{ Loader = false, ToggleKey = Enum.KeyCode.RightControl, Parent = gui, OnEnter = fn }`.
By default the UI shows an Enter button, then a loading bar, then opens. Pass `Loader = false` to open instantly like Kavo.

Executor behaviour: parents to `gethui()`, else CoreGui, else PlayerGui. Re-running the script replaces the old window (via `getgenv().__NovaUI`). RightShift hides/shows the UI.

Files: `source.lua` (the library), `example.lua` (every call, Kavo style), `example_native.lua` (NovaUI's own API: 5 button styles, tooltips, notifications).
In Studio or your own game without an executor, put `source.lua` in a ModuleScript and `require` it.
