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

**New to this? Read [INSTRUCTIONS.md](INSTRUCTIONS.md)**: presets, folder backgrounds and the executor check, step by step.

Files: `source.lua` (the library), `unc_test.lua` (executor check, no window), `example.lua` (every call, Kavo style), `example_native.lua` (NovaUI's own API: 5 button styles, tooltips, notifications).
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

## Custom login image

```lua
local Window = Library.CreateLib("My Hub", "DarkTheme", {
	Image = "https://raw.githubusercontent.com/YOU/REPO/main/logo.png", -- or 1234567890 / "rbxassetid://1234567890"
})
```

It replaces the letter logo on the login card (the `Logo` option does the same). Three ways to give it:

| Source | Needs | Notes |
|---|---|---|
| Roblox asset id (`123`, `"rbxassetid://123"`) | nothing | Best option: works everywhere, shows instantly. Upload the image to Roblox first. |
| `https://` link | executor with `writefile` + `getcustomasset` | Roblox can't show a web link directly, so NovaUI downloads it, saves it in `NovaUI/` and loads that copy. Cached, so it downloads once. |
| none | | Letter logo, as before. |

Limits: PNG or JPEG only (no webp/gif), up to 8 MB. If anything fails (old executor, bad link, wrong format) the letter logo stays and a warning is printed; it never errors.

### When links don't work: alternatives that need no downloads

| Option | Example | Notes |
|---|---|---|
| Embedded picture | `Image = { Pixels = <table> }` | Works in **any** executor and Studio, no network. Make it with `python3 tools/novaui_tool.py pixels logo.png --size 32` and paste the output. Up to 64x64: great for logos and icons, not photos. |
| Roblox thumbnails | `Image = { User = 1234 }` (or `Game`, `Group`, `Asset`) | Avatar head shot, game icon, group icon or asset thumbnail. Nothing to upload or download. |
| Fallback list | `Image = { "https://...png", 123456, { Pixels = ... } }` | Tried in order; the first that works wins. Put a Pixels picture last as a guaranteed fallback. |

Discord: a Discord image works if it is a direct `.png`/`.jpg` link, but Discord attachment links carry an expiry (`?ex=...`) and stop working later. For a permanent logo, put the file in your GitHub repo and use its `raw.githubusercontent.com` link, or upload it to Roblox and use the asset id.

## Settings (gear button)

The gear next to minimise/close opens a settings page (click it again, or pick a tab, to go back):

- **Appearance**: theme dropdown (all 8 themes), colour pickers for accent, window, header/sidebar, buttons/rows and text, reset.
- **Presets**: save the whole look under a name, load, delete, **export** a text code and **import** one (share looks with friends). With `writefile`/`readfile` presets are kept in `NovaUI/presets.txt`; without them they last for the session (the page tells you which).
- **Window**: keep-on-screen toggle.
- **Executor check**: tests your executor's file / asset functions (UNC) and names the one that fails.
- **Background**: see below.

`Window:ToggleSettings()`, `SetSettingsOpen(bool)`, `IsSettingsOpen()` and the Kavo `ChangeColor` all work from code too.

## Always on screen

Drag the window anywhere: past an edge it resists softly, and on release (or when you reopen, restore from minimise, or resize the game window) it glides fully back inside, so it can never get stuck off-screen. Turn off with `KeepOnScreen = false` or in Settings.

## Backgrounds (video / image / pixels)

```lua
local Window = Library.CreateLib("My Hub", "DarkTheme", {
	Background = { Video = 1234567890, Dim = 0.62, Glass = 0.2 },
})
Window:SetBackground({ Image = { Game = 920587237 } })   -- change later
Window:ClearBackground()
```

| Source | Needs | Notes |
|---|---|---|
| `Video = 123` / `"rbxassetid://123"` | an uploaded video | Loops, muted. Use roughly the window's shape (about 3:2), it is stretched to fit. |
| `Video = "intro.webm"` (a file in `workspace/NovaUI/backgrounds`; also `Image = "wall.png"`) | executor `getcustomasset` (+ `listfiles` for the picker) | Easiest way. The settings panel lists the folder; see INSTRUCTIONS.md. |
| `Video = "https://...webm"` (`.mp4` too) | executor `writefile` + `getcustomasset` | Downloaded once to `NovaUI/`, up to 40 MB. Not every executor plays local video: if it doesn't, nothing shows and a warning says why. |
| `Image = ...` | same as the login image | Any option from the login image section works. |
| `Pixels = { W, H, Data }` | nothing | Embedded picture, no downloads. |

**It stays readable.** A dim layer (35% to 95%, default 62%) always sits over the footage, and buttons/rows only become see-through up to 40%. NovaUI also reduces the see-through level automatically whenever the worst possible footage (pure white or black) could push your text below a 4.5:1 contrast on a button. Text sitting directly on the dim layer is lower contrast on very bright footage: raise **Dim** if needed.

### Match colours [beta]

Buttons, rows, bars and text take on the colour of the picture behind them (a red patch of video makes the buttons there reddish). Text is re-checked so it stays readable on the tinted button.

**Be aware:** Roblox cannot read pixels from a video or a web image while it plays, so matching needs the colours supplied up front:

- `Pixels` pictures carry their own colours: matching just works.
- **Files in `workspace/NovaUI/backgrounds` (easiest):** make the map once with
  `python3 tools/novaui_tool.py colormap intro.webm --sidecar` (needs ffmpeg). It writes `intro.map.txt` next to the video.
  Put both files in the folder: NovaUI finds `intro.map.txt` by itself (the settings say "Colour map found") and **Match colours** can be switched on.
  Presets remember it. Pictures work the same way (`wall.png` + `wall.map.txt`). The file is plain text and is never run as code.
  `python3 tools/novaui_tool.py convert intro.mp4 --map` converts the video to `.webm` and writes the map in one go.
- **Asset ids and links:** make a *colour map* once: `python3 tools/novaui_tool.py colormap clip.mp4 --cols 12 --rows 8 --fps 2 --out map.lua` (needs ffmpeg), then
  `Background = { Video = 123, ColorMap = loadstring(readfile("map.lua"))(), Match = true }`, or paste the table in directly.
  Or read a text map yourself: `ColorMap = Library.ParseColorMap(readfile("NovaUI/backgrounds/intro.map.txt"))` (no loadstring needed; returns `nil, reason` if the file is wrong).
  The map is indexed by the video's playback time, so colours follow the footage.
- A `ColorMap` given in code always wins over a `.map.txt` file.
- A map belongs to one video: switching to another file or id never reuses the previous map (a folder file finds its own `.map.txt`).
- Without a map the Match switch refuses and tells you exactly what to run.

Map file format (`NVMAP1`), in case you want to write one yourself: the first line is `NVMAP1 cols=12 rows=8 interval=0.5000`, then one line per frame with `cols * rows * 6` hex digits (`rrggbb` per cell, row by row). At most 64 x 64 cells, 4000 frames and 2 MB. Blank lines and lines starting with `#` are ignored; Windows line endings are fine.

It is a beta: colours update 5 times a second, and a button you are hovering keeps its hover colour until you move off.

## Window and login

- The login card is draggable (grab anywhere except the buttons and key box); the window opens where you leave it.
- Tab changes slide and fade; the sidebar highlight glides to the new tab.
- The **×** button and `Window:Close()` fold the window away (the reverse of opening). `Window:Destroy()` stays instant.

## Tests

`python3 test/test_tool.py` checks the tool: `pixels`, `colormap` (Lua and `--sidecar` text maps) and `convert` (needs ffmpeg).

`pip install lupa && python3 test/run_tests.py` runs the suite on a strict mock of the Roblox API (Lua 5.2 + `bit32`). It has not been run inside real Roblox.

## Presets, executor blame, options (round 3)
- Presets save hotkeys and every Toggle / Slider / Input / Dropdown / ColorPicker (matched by `Tab/Label`). Loading runs the callbacks of what changed; create the window with `PresetCallbacks = false` to skip that.
- Dropdowns now have `:Get()` and `:Set(option, silent)`.
- Executor functions are called through one wrapper: a failure names the function and says it is an executor (UNC) problem. `Library.GetExecutorIssues()` lists them; `Library.UNCTest()` runs the full check (also `unc_test.lua`).
