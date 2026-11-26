# NovaUI

Same calls as Kavo UI Library. Only the look and the loadstring change.

## Getting Loadstring

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"))()
```

## Creating UI Library Window

```lua
local Window = Library.CreateLib("TITLE", "DarkTheme")
```

Themes:
- LightTheme
- DarkTheme
- GrapeTheme
- BloodTheme
- Ocean
- Midnight
- Sentinel
- Synapse

## Creating Tabs

```lua
local Tab = Window:NewTab("TabName")
```

## Creating Section

```lua
local Section = Tab:NewSection("Section Name")
```

## Update Section

```lua
Section:UpdateSection("Section New Title")
```

## Creating Labels

```lua
Section:NewLabel("LabelText")
```

## Update Label

```lua
label:UpdateLabel("New Text")
```

## Creating Buttons

```lua
Section:NewButton("ButtonText", "ButtonInfo", function()
    print("Clicked")
end)
```

## Update Button

Make sure your button is local when updating it.

```lua
button:UpdateButton("New Text")
```

## Creating Toggles

```lua
Section:NewToggle("ToggleText", "ToggleInfo", function(state)
    if state then
        print("Toggle On")
    else
        print("Toggle Off")
    end
end)
```

## Updating Toggles

```lua
toggle:UpdateToggle("Toggle On")
```

## Creating Sliders

```lua
Section:NewSlider("SliderText", "SliderInfo", 500, 0, function(s) -- 500 (MaxValue) | 0 (MinValue)
    print(s)
end)
```

## Creating Textboxes

```lua
Section:NewTextBox("TextboxText", "TextboxInfo", function(txt)
    print(txt)
end)
```

## Creating Keybinds

```lua
Section:NewKeybind("KeybindText", "KeybindInfo", Enum.KeyCode.F, function()
    print("You just clicked the bind")
end)
```

## Toggling UI with Keybinds

```lua
Section:NewKeybind("KeybindText", "KeybindInfo", Enum.KeyCode.F, function()
    Library:ToggleUI()
end)
```

## Creating Dropdowns

```lua
Section:NewDropdown("DropdownText", "DropdownInfo", {"Option 1", "Option 2", "Option 3"}, function(currentOption)
    print(currentOption)
end)
```

## Dropdown Refresh

```lua
local dropdown = Section:NewDropdown("Dropdown", "Info", {"2019", "2020"}, function() end)

Section:NewButton("Update Dropdown", "Refreshes Dropdown", function()
    dropdown:Refresh({"2021", "2022"})
end)
```

## Creating Color Pickers

```lua
Section:NewColorPicker("Color Text", "Color Info", Color3.fromRGB(0, 0, 0), function(color)
    print(color)
end)
```

## Applying Custom Themes / Colors

Make a new table with your colors, then pass it instead of a theme name.

```lua
local colors = {
    SchemeColor = Color3.fromRGB(64, 64, 64),
    Background = Color3.fromRGB(0, 0, 0),
    Header = Color3.fromRGB(0, 0, 0),
    TextColor = Color3.fromRGB(255, 255, 255),
    ElementColor = Color3.fromRGB(20, 20, 20)
}

local Window = Library.CreateLib("TITLE", colors)
```

Change one color later:

```lua
Library:ChangeColor("Background", Color3.fromRGB(10, 10, 10))
```

## Settings

Press the **⚙** button next to the close button. It has themes, colors and backgrounds.

---

# Backgrounds

You set the background yourself. Nothing is stored in GitHub. A background is either a **Roblox asset id** (a number you get after uploading your own image or video to Roblox), or an **Animation** made from your own video on your own computer (last section, no upload, free).

## Image background

1. Upload a **PNG or JPG** on Roblox (Creator Hub, Assets, Images).
2. Copy the number of the image (the id).
3. Use it:

```lua
Window:SetBackground({ Image = 1234567890 })
```

Not supported: webp and gif.

## Video background

1. Make your video match **all** of these:
   1. File type: **.mp4** or **.mov** (Roblox upload accepts these).
   2. Length: **5 minutes at most**. Shorter is better, it loops.
   3. Size: under **3.75 GB**. Aim for **under 50 MB**, so it loads fast.
   4. Resolution: **1280x720 or smaller** is best. 1920x1080 works but is heavier.
   5. Sound is not needed, NovaUI plays it muted.
2. Upload it on Roblox (Creator Hub, Assets, Videos). Your account must be **13+** and **ID verified**, and Roblox charges **2,000 Robux per upload** at the time of writing ([Roblox docs](https://create.roblox.com/docs/ui/video-frames)).
3. Copy the number of the video (the id).
4. Use it:

```lua
Window:SetBackground({ Video = 1234567890 })
```

## Video background without uploading (Animation)

Many executors cannot play a video file from the folder (the console says `Failed to load rbxasset://...webm`). This works anywhere pictures load, costs nothing, and needs no Roblox upload. A small tool turns your video into pictures that NovaUI flips through like a video.

1. Install [ffmpeg](https://ffmpeg.org) and Python, and save `tools/novaui_tool.py` from this repo.
2. Run (replace `intro.mp4` with your file):

```
python3 tools/novaui_tool.py anim intro.mp4 --map
```

3. It writes next to your video: `intro.anim.txt`, `intro.anim1.jpg`, `intro.anim2.jpg` and so on, plus `intro.map.txt`.
4. Put **all of them** in `workspace/NovaUI/backgrounds` (inside your executor's workspace folder).
5. Use it:

```lua
Window:SetBackground({ Animation = "intro.anim.txt" })
```

Or: **⚙ > Background > Refresh files**, then pick `intro.anim.txt`.

Good to know:
1. Use a short loop (up to 12 seconds is the default, 30 seconds is the limit at 8 fps).
2. Smaller and faster: `--fps 6 --width 192`. Smoother and sharper: `--fps 12 --width 320`.
3. `--map` makes the optional colour file, so **Match colours** works.
4. Sound is not included.
5. The picture quality is lower than a real video, which is fine behind the dim layer.

## Make it readable

```lua
Window:SetBackground({ Video = 1234567890, Dim = 0.62, Glass = 0.2 })
```

- `Dim` makes the footage darker (0.35 to 0.95).
- `Glass` makes buttons see-through (0 to 0.4).

## Set it on start, or later

```lua
-- on start
local Window = Library.CreateLib("TITLE", "DarkTheme", { Background = { Video = 1234567890 } })

-- later
Window:SetBackground({ Image = 1234567890 })
Window:ClearBackground()
```

Or without code: **⚙ > Background**, type the id in **Source**, press Enter.

## Save it

**⚙ > Background > Background presets**: type a name, press **Save background preset**. Pick one in **Load preset** any time. Switch on **Auto-load this preset on start** and it comes back by itself next time.

## If nothing shows

1. The id must be a number from **your own upload** (or one Roblox lets your game use). Someone else's private asset will not load.
2. Wait about 10 seconds. If the video did not load, NovaUI says so in the settings and in the console.
3. Images: use the **image** id, not a decal id.
4. Console says `Failed to load rbxasset://...webm`: your executor cannot play folder videos. Use **Animation** above, or a Roblox video id.
5. Animation shows nothing: all `.anim1.jpg`, `.anim2.jpg` files must be in the folder next to `intro.anim.txt`. The note in ⚙ names the missing one.
