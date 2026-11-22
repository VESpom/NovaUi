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

## Key system (optional)

```lua
local Window = Library.CreateLib("My Hub", "DarkTheme", { KeySystem = { Key = "hello123" } })
-- code here only runs after a valid key is typed
```

No `KeySystem` option = no key screen, the UI opens right after **Enter**. See `example_keysystem.lua`.

| Field | What it does |
|---|---|
| `Key` / `Keys` | Plain key(s). Hashed (salted, 1000 rounds of SHA-256) as soon as the script loads. |
| `KeyHash` / `KeyHashes` | Store only `Library.HashKey("yourkey")` in the script, not the key itself. |
| `Validate(key)` | Your own check (e.g. your web server). Must return exactly `true`; a 2nd return value comes back as the 2nd result of `CreateLib`. |
| `Note`, `Link`, `LinkText` | Text under the title; a button that copies your key-link. |
| `MaxAttempts`, `Timeout` | Wrong keys before a lockout (30s, doubling each time); how long `Validate` may take. |

What it protects, honestly: `CreateLib` blocks until the key is valid, element callbacks are gated, the window cannot be revealed by RightShift/`ToggleUI`, a wrong or misconfigured setup **stays locked**, and the key is never stored in plain text on the UI side.
What it can't: anyone who can *edit the script they run* can delete the key check, because it runs on their machine. For real protection, keep the valuable code on your server and return it from `Validate` as the payload.

## Window and login

- The login card is draggable (grab anywhere except the buttons and key box); the window opens where you leave it.
- Tab changes slide and fade; the sidebar highlight glides to the new tab.
- The **×** button and `Window:Close()` fold the window away (the reverse of opening). `Window:Destroy()` stays instant.

## Tests

`pip install lupa && python3 test/run_tests.py` runs the suite on a strict mock of the Roblox API (Lua 5.2 + `bit32`). It has not been run inside real Roblox.
