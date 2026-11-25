# NovaUI: how to use presets, backgrounds and the executor check

Written for you, step by step. Open the settings with the **⚙** button next to the close button.

---

## 1. Presets (saving how your UI looks *and* how it is set)

A preset now remembers:

| Remembered | Example |
|---|---|
| Every **toggle** (on/off) | "Fly" was ON |
| Every **hotkey** of buttons, toggles and keybinds | the "Jump" button had **M** |
| Every **slider**, **text box**, **dropdown**, **colour picker** | Speed 80, Name "bob", Team Blue |
| Colours / theme, keep-on-screen, background | your Ocean look with a video behind it |

### Save one
1. Set everything the way you want it.
2. ⚙ → **Presets** → type a name → **Save preset**.
3. The status line says `(kept on disk)`. If it says `this session only`, it also tells you which executor function failed (see section 3).

### Load one
⚙ → **Load preset** → pick the name. The status line tells you what came back, for example:
`Loaded 'Mine': 7 settings, 3 hotkeys restored`.

What loading does:
- Toggles, sliders, dropdowns, text boxes and colours are put back **and your script's code for them runs**, but only for the ones that actually changed. So a toggle that was ON in the preset really turns the feature on.
- **Buttons are never pressed.** Only their hotkey comes back.
- Two hotkeys can swap keys inside one preset without a clash.
- If a key is now used by something that is not in the preset, that hotkey is skipped and the status line says so (the old key stays).
- Things the preset does not know (new buttons you added later) are left alone. Things the preset has but the script no longer has are counted as `not found in this script`.

Script authors: to restore the look of controls **without** running their code, create the window with `PresetCallbacks = false`.

### Where it lives and how to share it
- File: `workspace/NovaUI/presets.txt` (inside your executor's folder). Up to 40 presets, names up to 24 characters.
- **Export look (copy code)** copies one preset as a line of text. Paste it into **Look code** and press Enter on another computer.
- Presets find their controls by **tab name + label** (for example `Main/Fly`). If you rename a label in the script, old presets will not find it.

---

## 2. Backgrounds (the easy way: a folder)

You do not need links or asset ids. Use the folder the executor gives you.

### Steps
1. Run your script and open ⚙ → **Background**. This creates the folder `workspace/NovaUI/backgrounds` for you.
2. Copy your video or picture into that folder (on your computer, inside your executor's `workspace` folder).
3. Back in the UI press **Refresh files**, then pick the file in **Files in folder**.
4. Use **Dim** and **Glass** if the buttons are hard to read.

You can also type the file name (`intro.webm`) into **Source** and press Enter. Presets remember the file, so loading a preset brings the background back.

### Which files work

| File | Works | Notes |
|---|---|---|
| `.webm` (VP8 or VP9) | Best choice | Up to 720p, no sound needed, under 40 MB |
| `.mp4` | Maybe | Roblox's video player is documented for VP8/VP9 webm. mp4 may stay plain |
| `.png`, `.jpg` | Yes | Not `.webp` or `.gif` |

Source for the video rule: a Roblox developer-forum answer from 2022 ([thread](https://devforum.roblox.com/t/what-type-of-filescodecs-do-videoframes-support/1659542)). It may have changed, so trust the 10-second hint below if they disagree.

### Turn any video into a working `.webm`
Install ffmpeg, then:

```
ffmpeg -i input.mp4 -c:v libvpx -b:v 1M -vf scale=-2:540 -an output.webm
```

(That exact command was run and gives a VP8 file at 960x540.)

### If the window stays plain
- After 10 seconds without the video loading, NovaUI tells you in the settings and the console to convert it to `.webm`.
- `file not found` means the name or folder is wrong. The message shows the exact path it looked for.
- `executor function 'getcustomasset' ...` means your executor refused the file. Run the executor check (section 3).
- No **Files in folder** list? Your executor has no `listfiles`. Type the file name in **Source** instead.

### Other ways (still available)
An asset id, an `https://` link (downloaded once into `workspace/NovaUI/`) or a small embedded picture (`Pixels`). See `README.md`.

### Match colours [beta]
This makes buttons and text follow the colours behind them. Roblox cannot read the pixels of a playing video, so it needs a pre-made colour map (see `README.md`, tool `tools/novaui_tool.py`). Files dropped in the folder are **not** matched automatically yet.

---

## 3. Executor check (UNC)

NovaUI relies on file functions that belong to your **executor**, not to NovaUI (`writefile`, `readfile`, `isfile`, `isfolder`, `makefolder`, `listfiles`, `delfile`, `getcustomasset`, `setclipboard`). Executors implement them differently, and some are broken or blocked.

### Run it
- In the UI: ⚙ → **Executor check** → **Run executor check**. The summary appears there and the full list goes to the console.
- Or paste `unc_test.lua` into your executor. It opens no window.

### Read the result
Each line is `PASS`, `FAIL`, `MISSING` or `SKIP`.

| Status | Meaning |
|---|---|
| PASS | The function works |
| FAIL | The function exists but errors or returns wrong data. The line names it and gives the raw error |
| MISSING | Your executor does not have it. Lines marked "optional" do not matter much |
| SKIP | Not tested because a function it depends on failed first |

It also prints what that means for NovaUI, for example:
`Presets saved to disk: limited by your executor: writefile (fail). Presets still work for this session only.`

### While you use NovaUI
When an executor function fails, NovaUI shows it plainly, once per problem:

`[NovaUI] presets: executor function 'writefile' failed: the executor refuses this kind of file ... (UNC / executor problem, not NovaUI's code)`

Script authors can read the list with `Library.GetExecutorIssues()`.

The test creates files named `_unc_test.*` in `workspace/NovaUI` and deletes them. If your executor has no `delfile`, delete them by hand.

---

## 4. Quick fixes

| Problem | Try this |
|---|---|
| Preset says "this session only" | Run the executor check and read which function failed |
| Hotkey not restored | The status line counts skipped keys. Another element owns that key |
| Toggle shows ON but the feature did not start | Your script was created with `PresetCallbacks = false` |
| Background stays plain | Use a `.webm` (VP8/VP9, up to 720p) and read the status text |
| Folder list is empty | Press **Refresh files**. Only `.webm .mp4 .png .jpg .jpeg` are listed, and names may only use English letters, digits, spaces and `- . _ ( )` (no accents, no `;`) |
| Video link does nothing | Put the file in the folder instead. Links need an executor with `writefile` and `getcustomasset` |

Everything here was tested against a simulated Roblox and executor, not in a real executor. If something behaves differently on yours, the executor check shows whether your executor is the cause.
