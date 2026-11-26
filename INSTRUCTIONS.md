# NovaUI: how to use backgrounds, background presets and the executor check

Written for you, step by step. Open the settings with the **⚙** button next to the close button.

---

## 1. Background presets (and loading one by itself)

NovaUI has **one kind of preset: for the background**. A background preset remembers a background (the video or picture, how dark it is, how see-through the buttons are, and the Match colours switch). It does **not** touch your script's toggles, sliders or hotkeys: this library is used for many different scripts, so those stay the script's business.

### Save one
1. Pick a background first (section 2).
2. ⚙ → **Background presets** → type a name → **Save background preset**.
3. The note says `(kept on disk)`. If it says `this session only`, it also tells you which executor function failed (see section 3).

### Load one
⚙ → **Load preset** → pick the name. The background changes right away.

### Load one by itself when the UI opens
1. Pick (or save) the preset you want in **Load preset**.
2. Switch on **Auto-load this preset on start**. The note shows `Auto-load: 'Name'`.
3. Next time the UI opens, that background is there without opening the settings.

- Only one preset can be the auto-load one. Selecting another preset shows the switch as off for it; switching it on there moves the auto-load to that preset.
- Your choice wins over a script's own default background. Script authors who do not want that create the window with `AutoBackground = false`.
- Deleting the auto-load preset turns auto-load off. Switch the toggle off to stop it any time.
- Auto-load needs `writefile`/`readfile`. Without them it works only until you close the game (the note says so).

### Good to know
- File: `workspace/NovaUI/bg_presets.txt`. Up to 40 presets, names up to 24 characters.
- Only a **file name, asset id or link** can be saved. A Pixels picture or a game/avatar icon is too big or not a plain source, and the note says so.
- Presets made by the old version (`presets.txt`, "look codes") are **not used any more**. Nothing is deleted: the old file just stays there, ignored.
- Folder videos come back with their colour map (`intro.map.txt`) and the Match switch.

---

## 2. Backgrounds (the easy way: a folder)

You do not need links or asset ids. Use the folder the executor gives you.

### Steps
1. Run your script and open ⚙ → **Background**. This creates the folder `workspace/NovaUI/backgrounds` for you.
2. Copy your video or picture into that folder (on your computer, inside your executor's `workspace` folder).
3. Back in the UI press **Refresh files**, then pick the file in **Files in folder**.
4. Use **Dim** and **Glass** if the buttons are hard to read.

You can also type the file name (`intro.webm`) into **Source** and press Enter. Background presets remember the file, so loading one brings the background back.

### Which files work

| File | Works | Notes |
|---|---|---|
| `.webm` (VP8 or VP9) | Best choice | Up to 720p, no sound needed, under 40 MB |
| `.mp4` | Maybe | Roblox's video player is documented for VP8/VP9 webm. mp4 may stay plain |
| `.png`, `.jpg` | Yes | Not `.webp` or `.gif` |

Source for the video rule: a Roblox developer-forum answer from 2022 ([thread](https://devforum.roblox.com/t/what-type-of-filescodecs-do-videoframes-support/1659542)). It may have changed, so trust the 10-second hint below if they disagree.

### Turn any video into a working `.webm`
You need [ffmpeg](https://ffmpeg.org) and Python on your computer, and the file `tools/novaui_tool.py` from this repo. Then:

```
python3 tools/novaui_tool.py convert input.mp4
```

It writes `input.webm` next to the original: VP8, no sound, at most 540 pixels tall (never enlarged). Copy it into `workspace/NovaUI/backgrounds`.

- Too big or slow to load? Add `--bitrate 600k`, `--height 360` or `--fps 24`.
- It never overwrites a file by accident; add `--force` to replace one.
- If the file name has odd characters (like `!` or `;`) it is cleaned for you, because NovaUI only lists names with letters, digits, space and `- . _ ( )`.

(Without the tool, the same result by hand: `ffmpeg -i input.mp4 -c:v libvpx -b:v 1M -vf scale=-2:540 -an output.webm`.)

### If the window stays plain
- After 10 seconds without the video loading, NovaUI tells you in the settings and the console to convert it to `.webm`.
- `file not found` means the name or folder is wrong. The message shows the exact path it looked for.
- `executor function 'getcustomasset' ...` means your executor refused the file. Run the executor check (section 3).
- No **Files in folder** list? Your executor has no `listfiles`. Type the file name in **Source** instead.

### Other ways (still available)
An asset id, an `https://` link (downloaded once into `workspace/NovaUI/`) or a small embedded picture (`Pixels`). See `README.md`.

### Match colours [beta]
This makes buttons and text follow the colours behind them. Roblox cannot read the pixels of a playing video, so NovaUI needs a small **colour map file** made once on your computer. With a file in the folder it is simple:

1. Make the map next to your video:
   ```
   python3 tools/novaui_tool.py colormap intro.webm --sidecar
   ```
   This creates `intro.map.txt`. (Or do both steps at once: `python3 tools/novaui_tool.py convert intro.mp4 --map`.)
2. Put `intro.webm` **and** `intro.map.txt` in `workspace/NovaUI/backgrounds`. The map must have the same name as the video.
3. Pick the video in ⚙ → **Background**. The note says **Colour map found (intro.map.txt)**.
4. Switch on **Match colours [beta]**.

What to know:
- The `.map.txt` file does not show up in the file picker. That is normal; it is read together with the video.
- Pictures work the same way: `wall.png` + `wall.map.txt`.
- No map file? The switch stays off and the note tells you the exact command to run.
- A broken map file (edited by hand, cut off) is explained in the note and the console, and the background still shows.
- Background presets remember it: loading one brings back the video, its map and the switch.
- A long video: the map covers 60 seconds by default. For a longer one add `--max-seconds 0` (the whole video). The tool warns you when the map is shorter than the video.

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
`Background presets saved to disk: limited by your executor: writefile (fail). Background presets still work for this session only, and cannot auto-load next time.`

### While you use NovaUI
When an executor function fails, NovaUI shows it plainly, once per problem:

`[NovaUI] background presets: executor function 'writefile' failed: the executor refuses this kind of file ... (UNC / executor problem, not NovaUI's code)`

Script authors can read the list with `Library.GetExecutorIssues()`.

The test creates files named `_unc_test.*` in `workspace/NovaUI` and deletes them. If your executor has no `delfile`, delete them by hand.

---

## 4. Quick fixes

| Problem | Try this |
|---|---|
| Preset says "this session only" | Run the executor check and read which function failed |
| Auto-load does nothing next time | Same: it needs `writefile` / `readfile`. Also check the switch shows ON for that preset |
| The script has its own background and ignores mine | It was created with `AutoBackground = false` |
| Background stays plain | Use a `.webm` (VP8/VP9, up to 720p) and read the status text |
| Folder list is empty | Press **Refresh files**. Only `.webm .mp4 .png .jpg .jpeg` are listed, and names may only use English letters, digits, spaces and `- . _ ( )` (no accents, no `;`) |
| Video link does nothing | Put the file in the folder instead. Links need an executor with `writefile` and `getcustomasset` |

Everything here was tested against a simulated Roblox and executor, not in a real executor. If something behaves differently on yours, the executor check shows whether your executor is the cause.
