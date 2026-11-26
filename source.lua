--[==[
	NovaUI - modern dark UI library for Roblox
	Drop this in a ModuleScript (e.g. ReplicatedStorage.NovaUI) and require it from a LocalScript.

	Window:   local Window = NovaUI.new({ Title = "My Hub", Subtitle = "v1.0" })
	Tabs:     local Main = Window:Tab("Main")
	Elements: Main:Section("Combat")
	          Main:Button("Do thing", function() --[[ your code ]] end)
	          Main:Toggle("God mode", false, function(on) --[[ your code ]] end)
	          Main:Slider("Speed", 0, 100, 16, function(v) --[[ your code ]] end)
	          Main:Input("Name", "type here", function(text) --[[ your code ]] end)
	          Main:Label("Some text")
	OnEnter:  NovaUI.new({ OnEnter = function(window) window:Notify("Hi", "Loaded") end })  -- receives the window
	Extras:   Window:Notify("Title", "Message", 4)
	          Window:SelectTab("Main")     -- jump to a tab from any button
	          Window:Destroy()

	Hotkeys: every button and toggle gets a small box on its right. Click it, press a key to bind;
	          Esc or any mouse click cancels, Backspace/Delete clears, a taken key flashes "Taken".
	          Opts: { Hotkey = Enum.KeyCode.F } default key, { Hotkey = false } no hotkey, OnHotkeyChanged = fn(key|nil);
	          window option { Hotkeys = false } hides all boxes. obj:SetHotkey(key|nil), obj:GetHotkey(),
	          Window:GetHotkeys() / Window:SetHotkeys(map) to save and restore.

	Login image (optional): { Image = 1234567890 } or { Image = "rbxassetid://1234567890" } or { Image = "https://host/logo.png" }
	          Links need an executor with writefile + getcustomasset; PNG or JPEG only, up to 8 MB. If it can't load,
	          the letter logo stays and a warning is printed.

	Key system (optional - leave it out and the UI just opens after Enter):
	          NovaUI.CreateLib("Hub", "DarkTheme", { KeySystem = { Key = "hello123" } })
	          KeySystem fields: Key / Keys (plain text, hashed on load), KeyHash / KeyHashes (from NovaUI.HashKey),
	          Validate(key) -> true [, payload] (your own server check), Note, Link, MaxAttempts, Timeout.
	          CreateLib/new WAIT until a valid key is entered, so the rest of your script does not run before that.
	          A client-side check can always be edited out by whoever runs the script; for real protection keep
	          your code on your server and return it from Validate (it comes back as the 2nd result of CreateLib).
]==]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Library = {}
Library.__index = Library

local Tab = {}
Tab.__index = Tab

----------------------------------------------------------------------
-- Theme & constants
----------------------------------------------------------------------

local DEFAULT_THEME = {
	Background = Color3.fromRGB(13, 13, 18),
	Panel = Color3.fromRGB(19, 19, 26),
	Element = Color3.fromRGB(26, 26, 35),
	ElementHover = Color3.fromRGB(36, 36, 49),
	Off = Color3.fromRGB(52, 52, 68),
	Stroke = Color3.fromRGB(255, 255, 255), -- always used with high transparency
	Text = Color3.fromRGB(236, 236, 246),
	Muted = Color3.fromRGB(140, 140, 165),
	Accent = Color3.fromRGB(150, 120, 255),
	AccentLight = Color3.fromRGB(181, 160, 255),
	White = Color3.fromRGB(255, 255, 255),
}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)

local function mix(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- Kavo-shaped colour schemes. Custom themes use the same five keys.
local SCHEME_KEYS = { "SchemeColor", "Background", "Header", "TextColor", "ElementColor" }
local SCHEMES = {
	DarkTheme = {
		SchemeColor = Color3.fromRGB(150, 120, 255), Background = Color3.fromRGB(13, 13, 18),
		Header = Color3.fromRGB(19, 19, 26), TextColor = Color3.fromRGB(236, 236, 246),
		ElementColor = Color3.fromRGB(26, 26, 35),
	},
	LightTheme = {
		SchemeColor = Color3.fromRGB(80, 120, 255), Background = Color3.fromRGB(245, 245, 250),
		Header = Color3.fromRGB(230, 230, 238), TextColor = Color3.fromRGB(24, 24, 32),
		ElementColor = Color3.fromRGB(255, 255, 255),
	},
	GrapeTheme = {
		SchemeColor = Color3.fromRGB(166, 71, 214), Background = Color3.fromRGB(64, 50, 71),
		Header = Color3.fromRGB(36, 28, 41), TextColor = Color3.fromRGB(255, 255, 255),
		ElementColor = Color3.fromRGB(74, 58, 84),
	},
	BloodTheme = {
		SchemeColor = Color3.fromRGB(227, 27, 27), Background = Color3.fromRGB(10, 10, 10),
		Header = Color3.fromRGB(5, 5, 5), TextColor = Color3.fromRGB(255, 255, 255),
		ElementColor = Color3.fromRGB(20, 20, 20),
	},
	Ocean = {
		SchemeColor = Color3.fromRGB(86, 76, 251), Background = Color3.fromRGB(26, 32, 58),
		Header = Color3.fromRGB(38, 45, 71), TextColor = Color3.fromRGB(200, 200, 200),
		ElementColor = Color3.fromRGB(38, 45, 71),
	},
	Midnight = {
		SchemeColor = Color3.fromRGB(26, 189, 158), Background = Color3.fromRGB(44, 62, 82),
		Header = Color3.fromRGB(57, 81, 105), TextColor = Color3.fromRGB(255, 255, 255),
		ElementColor = Color3.fromRGB(52, 74, 95),
	},
	Sentinel = {
		SchemeColor = Color3.fromRGB(230, 35, 69), Background = Color3.fromRGB(32, 32, 32),
		Header = Color3.fromRGB(24, 24, 24), TextColor = Color3.fromRGB(119, 209, 146),
		ElementColor = Color3.fromRGB(24, 24, 24),
	},
	Synapse = {
		SchemeColor = Color3.fromRGB(152, 99, 53), Background = Color3.fromRGB(13, 15, 12),
		Header = Color3.fromRGB(36, 38, 35), TextColor = Color3.fromRGB(230, 210, 190),
		ElementColor = Color3.fromRGB(24, 26, 23),
	},
}

-- Fill any missing keys from DarkTheme so partial custom tables still work.
local function completeScheme(scheme)
	local out = {}
	for _, key in ipairs(SCHEME_KEYS) do
		out[key] = (scheme and scheme[key]) or SCHEMES.DarkTheme[key]
	end
	return out
end

-- Derive the full palette from the five Kavo keys. Mutates `theme` in place
-- (element code reads theme.X live, so changes show up on the next hover/tween).
local function applyScheme(theme, scheme)
	local bg, text, element, accent = scheme.Background, scheme.TextColor, scheme.ElementColor, scheme.SchemeColor
	local light = luminance(bg) > 0.5
	theme.Background = bg
	theme.Panel = scheme.Header
	theme.Text = text
	theme.Element = element
	theme.ElementHover = light and mix(element, BLACK, 0.07) or mix(element, WHITE, 0.07)
	theme.Accent = accent
	theme.AccentLight = mix(accent, WHITE, 0.35)
	theme.Muted = mix(text, bg, 0.45)
	theme.Off = mix(element, text, 0.22)
	theme.Stroke = light and BLACK or WHITE
	theme.White = WHITE
end

local FONT_REGULAR = Enum.Font.Gotham
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local TOPBAR_H = 44
local SIDEBAR_W = 150

-- sidebar tab geometry (the sliding highlight is positioned from these)
local TAB_H = 36
local TAB_GAP = 4
local TAB_TOP = 10

-- Enter screen
local CARD_W = 360
local CARD_H = { Welcome = 262, Key = 346, Load = 262 }
local STAGE_X, STAGE_Y = 28, 154
local STAGE_W = CARD_W - 56
local COLOR_BAD = Color3.fromRGB(255, 95, 110)
local COLOR_GOOD = Color3.fromRGB(80, 220, 140)

local STYLE_QUAD = Enum.EasingStyle.Quad
local STYLE_QUART = Enum.EasingStyle.Quart
local STYLE_BACK = Enum.EasingStyle.Back
local DIR_OUT = Enum.EasingDirection.Out
local DIR_IN = Enum.EasingDirection.In
local DIR_INOUT = Enum.EasingDirection.InOut

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function clamp(value, lo, hi)
	if value < lo then
		return lo
	end
	if value > hi then
		return hi
	end
	return value
end

local function create(className, props, children)
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = parent -- parent last: one replication/render hit
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function pillCorner()
	return create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(color, transparency, thickness)
	return create("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(left, top, right, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
	})
end

local function listLayout(gap)
	return create("UIListLayout", {
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- One tween per property so a new tween only cancels the *same* property.
local activeTweens = {}

local function tween(inst, duration, props, style, direction)
	local info = TweenInfo.new(duration, style or STYLE_QUAD, direction or DIR_OUT)
	local perInstance = activeTweens[inst]
	if not perInstance then
		perInstance = {}
		activeTweens[inst] = perInstance
		inst.Destroying:Connect(function()
			activeTweens[inst] = nil
		end)
	end
	local last = nil
	for prop, value in pairs(props) do
		local old = perInstance[prop]
		if old then
			old:Cancel()
		end
		local t = TweenService:Create(inst, info, { [prop] = value })
		perInstance[prop] = t
		t:Play()
		last = t
	end
	return last
end

-- Callbacks run in their own thread and can never break the UI.
local function safe(fn, ...)
	if type(fn) ~= "function" then
		return
	end
	task.spawn(function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[NovaUI] callback error: " .. tostring(err))
		end
	end, ...)
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function viewport()
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function textLabel(props, children)
	local base = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return create("TextLabel", base, children)
end

----------------------------------------------------------------------
-- Key system core: salted + stretched SHA-256, and the unlock gate.
-- Nothing here is exposed as a field on the window table, so a script
-- that pokes window._something cannot flip the gate; only the key UI's
-- closures call unlockWindow().
----------------------------------------------------------------------

local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
local rshift, rrotate = bit32.rshift, bit32.rrotate
local MOD32 = 4294967296

local SHA_K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local shaW = {}

local function be32(n)
	return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
end

-- Plain SHA-256 (FIPS 180-4), returns lowercase hex.
local function sha256(msg)
	local len = #msg
	local bitLen = len * 8
	msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
		.. be32(math.floor(bitLen / MOD32)) .. be32(bitLen % MOD32)
	local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
	local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
	local w = shaW
	for chunk = 1, #msg, 64 do
		for i = 1, 16 do
			local p = chunk + (i - 1) * 4
			local b1, b2, b3, b4 = string.byte(msg, p, p + 3)
			w[i] = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
		end
		for i = 17, 64 do
			local w15, w2 = w[i - 15], w[i - 2]
			local s0 = bxor(rrotate(w15, 7), rrotate(w15, 18), rshift(w15, 3))
			local s1 = bxor(rrotate(w2, 17), rrotate(w2, 19), rshift(w2, 10))
			w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD32
		end
		local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
		for i = 1, 64 do
			local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local t1 = (h + S1 + ch + SHA_K[i] + w[i]) % MOD32
			local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
			local maj = bxor(band(a, b), band(a, c), band(b, c))
			local t2 = (S0 + maj) % MOD32
			h = g
			g = f
			f = e
			e = (d + t1) % MOD32
			d = c
			c = b
			b = a
			a = (t1 + t2) % MOD32
		end
		h0 = (h0 + a) % MOD32
		h1 = (h1 + b) % MOD32
		h2 = (h2 + c) % MOD32
		h3 = (h3 + d) % MOD32
		h4 = (h4 + e) % MOD32
		h5 = (h5 + f) % MOD32
		h6 = (h6 + g) % MOD32
		h7 = (h7 + h) % MOD32
	end
	return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4, h5, h6, h7)
end

-- Key stretching: every guess costs `rounds` hashes, so offline guessing is slow
-- and a plain-text key never has to sit in the script.
local KDF_ROUNDS = 1000
local MAX_ROUNDS = 50000
local MAX_KEY_LEN = 256

local function deriveKey(key, salt, rounds)
	local h = sha256(salt .. "\0" .. key)
	for _ = 2, rounds do
		h = sha256(h .. salt .. key)
	end
	return h
end

-- "nv1$<rounds>$<salt hex>$<hash hex>"
local function parseKeyHash(text)
	if type(text) ~= "string" then
		return nil
	end
	local rounds, salt, hex = string.match(text, "^nv1%$(%d+)%$(%x+)%$(%x+)$")
	rounds = tonumber(rounds)
	if not rounds or rounds < 1 or rounds > MAX_ROUNDS or #hex ~= 64 or #salt < 8 or #salt > 64 then
		return nil
	end
	return { rounds = rounds, salt = salt, hex = string.lower(hex) }
end

-- Library.HashKey("hello123") -> the string to store as KeyHash.
local function hashKey(key, salt, rounds)
	key = tostring(key)
	if salt == nil then
		local parts = {}
		for i = 1, 4 do
			parts[i] = string.format("%04x", math.random(0, 65535))
		end
		salt = table.concat(parts)
	end
	rounds = rounds or KDF_ROUNDS
	return "nv1$" .. rounds .. "$" .. salt .. "$" .. deriveKey(key, salt, rounds)
end

-- Compares two strings without bailing out at the first different character.
local function constantTimeEquals(a, b)
	if #a ~= #b then
		return false
	end
	local diff = 0
	for i = 1, #a do
		diff = bor(diff, bxor(string.byte(a, i), string.byte(b, i)))
	end
	return diff == 0
end

local function matchesAnyHash(entries, input)
	local matched = false
	for _, entry in ipairs(entries) do -- no early exit: time does not reveal which entry matched
		if constantTimeEquals(deriveKey(input, entry.salt, entry.rounds), entry.hex) then
			matched = true
		end
	end
	return matched
end

-- Turns the user's KeySystem table into a checked config. Misconfiguration fails CLOSED:
-- the window stays locked and says so, it never opens.
local function prepareKeySystem(cfg)
	local out = { entries = {}, validate = nil, maxAttempts = 5, timeout = 15 }
	if type(cfg) ~= "table" then
		warn("[NovaUI] KeySystem must be a table like { Key = \"...\" }; the window will stay locked")
		out.misconfigured = true
		return out
	end
	local function each(value, fn)
		if type(value) == "table" then
			for _, v in ipairs(value) do
				fn(v)
			end
		elseif value ~= nil then
			fn(value)
		end
	end
	each(cfg.Key, function(k)
		if type(k) == "string" and k ~= "" and #k <= MAX_KEY_LEN then
			table.insert(out.entries, parseKeyHash(hashKey(k)))
		else
			warn("[NovaUI] KeySystem.Key must be a non-empty string up to " .. MAX_KEY_LEN .. " characters; ignored")
		end
	end)
	each(cfg.Keys, function(k)
		if type(k) == "string" and k ~= "" and #k <= MAX_KEY_LEN then
			table.insert(out.entries, parseKeyHash(hashKey(k)))
		else
			warn("[NovaUI] KeySystem.Keys entries must be non-empty strings; ignored one")
		end
	end)
	local function addHash(h)
		local parsed = parseKeyHash(h)
		if parsed then
			table.insert(out.entries, parsed)
		else
			warn("[NovaUI] KeySystem.KeyHash is not a valid NovaUI.HashKey string; ignored")
		end
	end
	each(cfg.KeyHash, addHash)
	each(cfg.KeyHashes, addHash)
	if type(cfg.Validate) == "function" then
		out.validate = cfg.Validate
	elseif cfg.Validate ~= nil then
		warn("[NovaUI] KeySystem.Validate must be a function; ignored")
	end
	if #out.entries == 0 and not out.validate then
		warn("[NovaUI] KeySystem has no usable Key, KeyHash or Validate; the window will stay locked")
		out.misconfigured = true
	end
	out.maxAttempts = clamp(math.floor(tonumber(cfg.MaxAttempts) or 5), 1, 20)
	out.timeout = clamp(tonumber(cfg.Timeout) or 15, 2, 120)
	out.note = type(cfg.Note) == "string" and cfg.Note or nil
	out.link = type(cfg.Link) == "string" and cfg.Link or nil
	out.linkText = type(cfg.LinkText) == "string" and cfg.LinkText or "Get Key"
	return out
end

-- Returns ok, payload. Validate must return exactly `true` (a truthy string does not count).
local function checkKey(cfg, input)
	if #input > MAX_KEY_LEN then
		return false
	end
	if #cfg.entries > 0 and matchesAnyHash(cfg.entries, input) then
		return true
	end
	if cfg.validate then
		local ok, result, payload = pcall(cfg.validate, input)
		if not ok then
			warn("[NovaUI] KeySystem.Validate error: " .. tostring(result))
		elseif result == true then
			return true, payload
		end
	end
	return false
end

-- Unlock state lives here, keyed by window, weakly, out of reach of the window table.
local gate = setmetatable({}, { __mode = "k" })
local payloads = setmetatable({}, { __mode = "k" })
-- Open windows live here, not on the Library table, so nothing can grab a window that is still locked.
local liveWindows = {}

local function isUnlocked(win)
	return gate[win] == true
end

local function unlockWindow(win, payload)
	gate[win] = true
	payloads[win] = payload
end

-- Every user callback goes through here, so nothing runs while a window is locked.
local function runGated(win, fn, ...)
	if gate[win] ~= true then
		return
	end
	safe(fn, ...)
end

-- Text/colour helpers for the Enter screen.
local function linearChannel(c)
	if c <= 0.03928 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function relativeLuminance(c)
	return 0.2126 * linearChannel(c.R) + 0.7152 * linearChannel(c.G) + 0.0722 * linearChannel(c.B)
end

local function contrastRatio(a, b)
	local l1, l2 = relativeLuminance(a), relativeLuminance(b)
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
end

-- Accent darkened just enough that white text on it reads clearly (WCAG AA, 4.5:1).
local function readableFill(accent)
	local t = 0.18
	local c = mix(accent, BLACK, t)
	while contrastRatio(WHITE, c) < 4.5 and t < 0.9 do
		t = t + 0.04
		c = mix(accent, BLACK, t)
	end
	return c
end

-- Pushes `color` towards white (dark bg) or black (light bg) until it reaches `ratio`:1 contrast.
local function legible(color, bg, ratio)
	local target = luminance(bg) > 0.5 and BLACK or WHITE
	local t, c = 0, color
	while contrastRatio(c, bg) < ratio and t < 1 do
		t = t + 0.05
		c = mix(color, target, t)
	end
	return c
end

----------------------------------------------------------------------
-- Button styles. Each builder fills `parent` (a row) and returns
-- (clickable GuiButton, setText function).
----------------------------------------------------------------------

local ROW_HEIGHT = { Default = 40, Pill = 44, Sweep = 42, Push = 48, Glow = 42 }
local STYLES = {}

-- Clean default: dark card, hover lift, press shrink, chevron.
function STYLES.Default(win, parent, text)
	local theme = win.Theme
	local btn = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	local scale = create("UIScale", { Scale = 1, Parent = btn })
	local label = textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Text = text,
		TextColor3 = theme.Text,
	})
	label.Parent = btn
	local chevron = textLabel({
		Name = "Chevron",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(14, 20),
		Text = "›",
		TextSize = 20,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	chevron.Parent = btn

	win:_connect(btn.MouseEnter, function()
		tween(btn, 0.15, { BackgroundColor3 = theme.ElementHover })
		tween(chevron, 0.15, { TextColor3 = theme.Accent })
	end)
	win:_connect(btn.MouseLeave, function()
		tween(btn, 0.15, { BackgroundColor3 = theme.Element })
		tween(chevron, 0.15, { TextColor3 = theme.Muted })
		tween(scale, 0.1, { Scale = 1 })
	end)
	win:_connect(btn.MouseButton1Down, function()
		tween(scale, 0.08, { Scale = 0.97 })
	end)
	win:_connect(btn.MouseButton1Up, function()
		tween(scale, 0.12, { Scale = 1 }, STYLE_BACK)
	end)

	return btn, function(newText)
		label.Text = newText
	end
end

-- Round icon button that expands into a pill showing its label on hover.
function STYLES.Pill(win, parent, text, opts)
	local theme = win.Theme
	local collapsedBg = Color3.fromRGB(20, 20, 20)
	local btn = create("TextButton", {
		Name = "Hit",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = collapsedBg,
		AutoButtonColor = false,
		ClipsDescendants = true,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	}, { pillCorner() })
	local ring = create("UIStroke", {
		Color = theme.AccentLight,
		Transparency = 0.75,
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = btn,
	})
	local icon = textLabel({
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Text = opts.Icon or "+",
		TextSize = 18,
		Font = FONT_BOLD,
		TextColor3 = theme.White,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	icon.Parent = btn
	local label = textLabel({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 34),
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextSize = 13,
		Font = FONT_BOLD,
		TextColor3 = theme.White,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	label.Parent = btn

	local function expand(on)
		if on then
			tween(btn, 0.3, { Size = UDim2.fromOffset(170, 40), BackgroundColor3 = theme.AccentLight }, STYLE_QUART)
			tween(icon, 0.3, { Position = UDim2.new(0.5, 0, 0.5, -34) }, STYLE_QUART)
			tween(label, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, STYLE_QUART)
			tween(ring, 0.3, { Transparency = 0.5 })
		else
			tween(btn, 0.3, { Size = UDim2.fromOffset(40, 40), BackgroundColor3 = collapsedBg }, STYLE_QUART)
			tween(icon, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, STYLE_QUART)
			tween(label, 0.3, { Position = UDim2.new(0.5, 0, 0.5, 34) }, STYLE_QUART)
			tween(ring, 0.3, { Transparency = 0.75 })
		end
	end
	win:_connect(btn.MouseEnter, function()
		expand(true)
	end)
	win:_connect(btn.MouseLeave, function()
		expand(false)
	end)

	return btn, function(newText)
		label.Text = newText
	end
end

-- Gradient button; a dark panel slides away on hover to reveal the gradient.
function STYLES.Sweep(win, parent, text, opts)
	local theme = win.Theme
	local group = create("CanvasGroup", {
		Name = "Group",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	}, { corner(10) })
	local scale = create("UIScale", { Scale = 1, Parent = group })
	local bg = create("Frame", {
		Name = "Gradient",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.White,
		BorderSizePixel = 0,
		Parent = group,
	}, {
		create("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(142, 45, 226), Color3.fromRGB(74, 0, 224)),
		}),
	})
	local cover = create("Frame", {
		Name = "Cover",
		Position = UDim2.fromScale(-0.1, 0),
		Size = UDim2.fromScale(1.2, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = group,
	})
	local btn = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(248, 248, 255),
		Text = (opts.Icon and (opts.Icon .. "  ") or "") .. text,
		ZIndex = 3,
		Parent = group,
	})
	local prefix = opts.Icon and (opts.Icon .. "  ") or ""

	win:_connect(btn.MouseEnter, function()
		tween(cover, 0.4, { Position = UDim2.fromScale(1, 0) }, STYLE_QUART)
	end)
	win:_connect(btn.MouseLeave, function()
		tween(cover, 0.4, { Position = UDim2.fromScale(-0.1, 0) }, STYLE_QUART)
		tween(scale, 0.1, { Scale = 1 })
	end)
	win:_connect(btn.MouseButton1Down, function()
		tween(scale, 0.08, { Scale = 0.95 })
	end)
	win:_connect(btn.MouseButton1Up, function()
		tween(scale, 0.12, { Scale = 1 }, STYLE_BACK)
	end)

	return btn, function(newText)
		btn.Text = prefix .. newText
	end, bg
end

-- 3D push button: raised face on a dark base, drops when pressed.
function STYLES.Push(win, parent, text)
	local base = create("TextButton", {
		Name = "Hit",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	}, { corner(10) })
	local face = create("Frame", {
		Name = "Face",
		Position = UDim2.fromOffset(0, -4),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(232, 232, 232),
		BorderSizePixel = 0,
		Parent = base,
	}, { corner(10), stroke(Color3.fromRGB(0, 0, 0), 0, 2) })
	local label = textLabel({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = FONT_BOLD,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	label.Parent = face

	win:_connect(base.MouseEnter, function()
		tween(face, 0.1, { Position = UDim2.fromOffset(0, -6) })
	end)
	win:_connect(base.MouseLeave, function()
		tween(face, 0.1, { Position = UDim2.fromOffset(0, -4) })
	end)
	win:_connect(base.MouseButton1Down, function()
		tween(face, 0.06, { Position = UDim2.fromOffset(0, 0) })
	end)
	win:_connect(base.MouseButton1Up, function()
		tween(face, 0.1, { Position = UDim2.fromOffset(0, -6) })
	end)

	return base, function(newText)
		label.Text = newText
	end
end

-- Soft glow button: dark radial-ish body, light edge line that brightens on hover.
function STYLES.Glow(win, parent, text)
	local btn = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(168, 168, 168),
		Text = text,
		Parent = parent,
	}, {
		corner(8),
		stroke(Color3.fromRGB(255, 255, 255), 0.9, 1),
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(11, 21, 30)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(11, 21, 30)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(71, 81, 92)),
			}),
		}),
	})
	local scale = create("UIScale", { Scale = 1, Parent = btn })
	local line = create("Frame", {
		Name = "Edge",
		Position = UDim2.new(0.15, 0, 1, -1),
		Size = UDim2.new(0.7, 0, 0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Parent = btn,
	}, {
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	win:_connect(btn.MouseEnter, function()
		tween(scale, 0.35, { Scale = 1.02 }, STYLE_QUART)
		tween(btn, 0.35, { TextColor3 = Color3.fromRGB(255, 255, 255) })
		tween(line, 0.35, { BackgroundTransparency = 0 })
	end)
	win:_connect(btn.MouseLeave, function()
		tween(scale, 0.35, { Scale = 1 }, STYLE_QUART)
		tween(btn, 0.35, { TextColor3 = Color3.fromRGB(168, 168, 168) })
		tween(line, 0.35, { BackgroundTransparency = 0.8 })
	end)

	return btn, function(newText)
		btn.Text = newText
	end
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

function Library:_connect(signal, fn)
	local conn = signal:Connect(fn)
	table.insert(self._conns, conn)
	return conn
end

----------------------------------------------------------------------
-- Hotkeys: ONE registry and ONE "press a key to bind" capture shared by every hotkey box
-- and Keybind element. While capturing, nothing else reacts to the input (so RightShift
-- cannot hide the window mid-bind), Esc / any mouse click cancels, Backspace / Delete clears,
-- and the click that cancelled is swallowed so it cannot press whatever is underneath.
----------------------------------------------------------------------

local CAPTURE_TIMEOUT = 8

local function isKeyCode(k)
	local ok, result = pcall(function()
		return typeof(k) == "EnumItem" and k.EnumType == Enum.KeyCode
	end)
	return ok and result == true
end

function Library:_clicksSwallowed()
	if self._swallowArmed then
		if os.clock() - (self._swallowSince or 0) < 5 then
			return true
		end
		self._swallowArmed = false -- lost release event: never stay stuck
	end
	return os.clock() < (self._swallowUntil or 0)
end

-- Like _connect, for click handlers: ignored while a cancelled-binding click is still pending.
function Library:_connectClick(signal, fn)
	return self:_connect(signal, function(...)
		if self:_clicksSwallowed() then
			return
		end
		fn(...)
	end)
end

function Library:_addHotkey(hk)
	table.insert(self._hotkeys, hk)
end

function Library:_hotkeyId(base)
	local n = (self._hotkeyIds[base] or 0) + 1
	self._hotkeyIds[base] = n
	return n == 1 and base or (base .. " #" .. n)
end

function Library:_keyTaken(code, except)
	if code == self._toggleKey then
		return true
	end
	for _, hk in ipairs(self._hotkeys) do
		if hk ~= except and hk.key == code then
			return true
		end
	end
	return false
end

-- onDone(result, key): "bound" (key) | "cleared" | "cancelled" | "taken" (key). check(code) -> true if allowed.
function Library:_beginCapture(onDone, check)
	self:_endCapture("cancelled") -- only one capture at a time
	local token = (self._captureToken or 0) + 1
	self._captureToken = token
	self._capture = { done = onDone, check = check }
	task.delay(CAPTURE_TIMEOUT, function()
		if not self._destroyed and self._captureToken == token and self._capture then
			self:_endCapture("cancelled") -- never stay stuck on "..."
		end
	end)
end

function Library:_endCapture(result, key)
	local cap = self._capture
	if not cap then
		return
	end
	self._capture = nil
	self._captureToken = (self._captureToken or 0) + 1
	cap.done(result, key)
end

function Library:_inputConsumed(input)
	return self._consumedInput == input
end

function Library:_onInput(input, processed)
	local UIT = Enum.UserInputType
	local cap = self._capture
	if cap then
		self._consumedInput = input
		local t = input.UserInputType
		if t == UIT.MouseButton1 or t == UIT.Touch then
			self._swallowArmed = true
			self._swallowSince = os.clock()
			self:_endCapture("cancelled")
		elseif t == UIT.MouseButton2 or t == UIT.MouseButton3 then
			self:_endCapture("cancelled")
		elseif t == UIT.Keyboard then
			local code = input.KeyCode
			if code == Enum.KeyCode.Escape then
				self:_endCapture("cancelled")
			elseif code == Enum.KeyCode.Backspace or code == Enum.KeyCode.Delete then
				self:_endCapture("cleared")
			elseif code == Enum.KeyCode.Unknown then
				return -- keep waiting
			elseif cap.check and not cap.check(code) then
				self:_endCapture("taken", code)
			else
				self:_endCapture("bound", code)
			end
		end
		return
	end
	if processed then
		return
	end
	local ok, focused = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)
	if ok and focused then
		return -- typing in a text box never triggers hotkeys
	end
	local code = input.KeyCode
	if code == self._toggleKey then
		self:ToggleVisible()
	elseif code == Enum.KeyCode.Return and self._loaderEnter then
		self._loaderEnter() -- Return = click Enter on the Enter screen
	end
	if input.UserInputType == UIT.Keyboard and code ~= Enum.KeyCode.Unknown and isUnlocked(self) and not self._closing then
		local list = {}
		for i, hk in ipairs(self._hotkeys) do
			list[i] = hk
		end
		for _, hk in ipairs(list) do
			if hk.key == code and hk.fire then
				safe(hk.fire)
			end
		end
	end
end

-- Save / restore bindings: GetHotkeys() -> { ["Tab/Element"] = "F" }, SetHotkeys(map) (false clears one).
function Library:GetHotkeys()
	local out = {}
	for _, hk in ipairs(self._hotkeys) do
		if hk.key then
			out[hk.id] = hk.key.Name
		end
	end
	return out
end

function Library:SetHotkeys(map)
	if type(map) ~= "table" then
		warn("[NovaUI] SetHotkeys expects a table like { [\"Main/Fly\"] = \"F\" }")
		return
	end
	for _, hk in ipairs(self._hotkeys) do
		local want = map[hk.id]
		if want == false then
			hk:SetKey(nil)
		elseif type(want) == "string" then
			local ok, code = pcall(function()
				return Enum.KeyCode[want]
			end)
			if not ok or not isKeyCode(code) then
				warn("[NovaUI] SetHotkeys: '" .. want .. "' is not a key name (" .. hk.id .. ")")
			elseif self:_keyTaken(code, hk) then
				warn("[NovaUI] SetHotkeys: " .. want .. " is already used (" .. hk.id .. ")")
			else
				hk:SetKey(code)
			end
		end
	end
end

function Library:_updateScale()
	local vp = viewport()
	local s = math.min(1, (vp.X - 24) / self._size.X, (vp.Y - 24) / self._size.Y)
	self._uiScale.Scale = math.max(s, 0.4)
	if self._loaderScale then
		local ls = math.min(1, (vp.X - 24) / CARD_W, (vp.Y - 24) / CARD_H.Key)
		self._loaderScale.Scale = math.max(ls, 0.5)
	end
	self:_settle(self._main)
	if self._loader and self._loader.Visible then
		self:_settle(self._loader)
	end
end

function Library:_showTip(target, title, body)
	local tip = self._tip
	self._tipTitle.Text = title or ""
	self._tipTitle.Visible = title ~= nil and title ~= ""
	self._tipBody.Text = body or ""
	local pos, size = target.AbsolutePosition, target.AbsoluteSize
	local vp = viewport()
	local x = clamp(pos.X + size.X / 2, 120, math.max(120, vp.X - 120))
	if pos.Y < 110 then
		tip.AnchorPoint = Vector2.new(0.5, 0)
		tip.Position = UDim2.fromOffset(x, pos.Y + size.Y + 10)
	else
		tip.AnchorPoint = Vector2.new(0.5, 1)
		tip.Position = UDim2.fromOffset(x, pos.Y - 10)
	end
	tip.GroupTransparency = 1
	tip.Visible = true
	tween(tip, 0.18, { GroupTransparency = 0 })
end

function Library:_hideTip()
	self._tip.Visible = false
end

function Library:_attachTip(target, tip)
	if not tip then
		return
	end
	local title, body
	if type(tip) == "table" then
		title, body = tip.Title, tip.Text
	else
		body = tostring(tip)
	end
	self:_connect(target.MouseEnter, function()
		self:_showTip(target, title, body)
	end)
	self:_connect(target.MouseLeave, function()
		self:_hideTip()
	end)
end

-- `blocker(input)` (optional) returns true for presses that must NOT start a drag, e.g. on a button.
----------------------------------------------------------------------
-- Keep on screen. The WHOLE window (not just its centre) stays inside the viewport, so it can
-- never end up with its title bar out of reach. While dragging, the edge pushes back softly
-- (rubber band, max 40px); on release, show and resize it settles back in with a short glide.
----------------------------------------------------------------------

local EDGE_MARGIN = 8
local MAX_OVERSHOOT = 40

local function insideCenter(cx, cy, w, h, vp)
	local hw, hh = w / 2 + EDGE_MARGIN, h / 2 + EDGE_MARGIN
	local x = (hw * 2 >= vp.X) and vp.X / 2 or clamp(cx, hw, vp.X - hw)
	local y = (hh * 2 >= vp.Y) and vp.Y / 2 or clamp(cy, hh, vp.Y - hh)
	return x, y
end

local function softOvershoot(excess)
	local sign = excess < 0 and -1 or 1
	return sign * math.min(MAX_OVERSHOOT, math.abs(excess) * 0.3)
end

-- Final on-screen size (px) of a draggable target, ignoring any animation in progress.
function Library:_boundsOf(target)
	if target == self._main then
		local scale = self._uiScale and self._uiScale.Scale or 1
		local h = self.Minimized and TOPBAR_H or self._size.Y
		return self._size.X * scale, h * scale
	end
	local scale = self._loaderScale and self._loaderScale.Scale or 1
	return CARD_W * scale, CARD_H[self._loaderStage or "Welcome"] * scale
end

function Library:_settle(target, instant)
	if self._destroyed or self._keepOnScreen == false or not target then
		return
	end
	local vp = viewport()
	local pos = target.Position
	local cx = vp.X * pos.X.Scale + pos.X.Offset
	local cy = vp.Y * pos.Y.Scale + pos.Y.Offset
	local w, h = self:_boundsOf(target)
	local nx, ny = insideCenter(cx, cy, w, h, vp)
	if math.abs(nx - cx) < 0.5 and math.abs(ny - cy) < 0.5 then
		return
	end
	local goal = UDim2.new(pos.X.Scale, nx - vp.X * pos.X.Scale, pos.Y.Scale, ny - vp.Y * pos.Y.Scale)
	if instant then
		tween(target, 0, { Position = goal })
	else
		tween(target, 0.28, { Position = goal }, STYLE_QUART)
	end
end

function Library:_makeDraggable(handle, target, blocker)
	local dragging = false
	local dragInput = nil
	local startX, startY, startPos = 0, 0, nil

	self:_connect(handle.InputBegan, function(input)
		if isPress(input) and not (blocker and blocker(input)) then
			dragging = true
			dragInput = input
			startX, startY = input.Position.X, input.Position.Y
			tween(target, 0, { Position = target.Position }) -- stop a settle glide that is still running
			startPos = target.Position
			self:_hideTip()
		end
	end)
	self:_connect(UserInputService.InputChanged, function(input)
		if not dragging then
			return
		end
		local isMove = input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and input == dragInput)
		if not isMove then
			return
		end
		local vp = viewport()
		local dx, dy = input.Position.X - startX, input.Position.Y - startY
		local cx = vp.X * startPos.X.Scale + startPos.X.Offset + dx
		local cy = vp.Y * startPos.Y.Scale + startPos.Y.Offset + dy
		if self._keepOnScreen == false then
			cx, cy = clamp(cx, 0, vp.X), clamp(cy, 0, vp.Y) -- legacy: only the centre is kept on screen
		else
			local w, h = self:_boundsOf(target)
			local ix, iy = insideCenter(cx, cy, w, h, vp)
			cx, cy = ix + softOvershoot(cx - ix), iy + softOvershoot(cy - iy)
		end
		target.Position = UDim2.new(startPos.X.Scale, cx - vp.X * startPos.X.Scale, startPos.Y.Scale, cy - vp.Y * startPos.Y.Scale)
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if not dragging then
			return
		end
		if input == dragInput or (input.UserInputType == Enum.UserInputType.MouseButton1 and dragInput.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			self:_settle(target)
		end
	end)
end

function Library:_expand()
	if self._destroyed or not isUnlocked(self) then
		return
	end
	local main = self._main
	self._token = (self._token or 0) + 1
	main.Visible = true
	self.Visible = true
	main.Size = UDim2.fromOffset(self._size.X * 0.7, TOPBAR_H)
	local height = self.Minimized and TOPBAR_H or self._size.Y
	tween(main, 0.45, { Size = UDim2.fromOffset(self._size.X, height) }, STYLE_BACK)
	self:_settle(main) -- reopening near an edge can never leave it stuck off-screen
end

-- Reverse of _expand: the window folds down to a title bar, then flattens away.
function Library:_collapse(onDone)
	if self._destroyed then
		return
	end
	self._token = (self._token or 0) + 1
	local token = self._token
	self.Visible = false
	self:_hideTip()
	local main = self._main
	local w = self._size.X * 0.7
	tween(main, 0.26, { Size = UDim2.fromOffset(w, TOPBAR_H) }, STYLE_QUART, DIR_IN)
	task.delay(0.26, function()
		if self._destroyed or self._token ~= token then
			return
		end
		tween(main, 0.14, { Size = UDim2.fromOffset(w * 0.8, 0) }, STYLE_QUART)
		task.delay(0.14, function()
			if self._destroyed or self._token ~= token then
				return
			end
			main.Visible = false
			if onDone then
				onDone()
			end
		end)
	end)
end

function Library:SetVisible(visible)
	if self._destroyed or not self._opened or self._closing then
		return
	end
	if visible == self.Visible then
		return
	end
	if visible then
		self:_expand()
	else
		self:_collapse()
	end
end

function Library:ToggleVisible()
	self:SetVisible(not self.Visible)
end

function Library:SetMinimized(minimized)
	if self._destroyed then
		return
	end
	self.Minimized = minimized == true
	local height = self.Minimized and TOPBAR_H or self._size.Y
	tween(self._main, 0.3, { Size = UDim2.fromOffset(self._size.X, height) }, STYLE_QUART)
	self._minButton.Text = self.Minimized and "+" or "–"
	self:_settle(self._main)
end

----------------------------------------------------------------------
-- Enter screen (draggable card): Enter -> [key entry] -> loading -> window
----------------------------------------------------------------------

local function trimText(s)
	return (string.match(tostring(s), "^%s*(.-)%s*$"))
end

----------------------------------------------------------------------
-- Custom login image: Image = 123456 | "rbxassetid://123" | "https://host/pic.png"
-- Roblox cannot show a web link directly, so links are downloaded by the executor,
-- saved under NovaUI/ and loaded with getcustomasset. Anything that fails falls back
-- to the letter logo (never an error).
----------------------------------------------------------------------

local MAX_IMAGE_BYTES = 8 * 1024 * 1024

local function envFn(getter)
	local ok, fn = pcall(getter)
	if ok and type(fn) == "function" then
		return fn
	end
	return nil
end

----------------------------------------------------------------------
-- Executor (UNC) functions, with blame.
-- writefile, readfile, getcustomasset ... belong to the executor, not to NovaUI. Every call goes
-- through uncRun, so a failure is reported as "your executor's <function> failed" with the raw
-- error and a short hint, never as a NovaUI bug. Each problem is printed once per session and
-- kept for Library.GetExecutorIssues(). unc_test.lua checks all of them in one go.
----------------------------------------------------------------------

local UNC_GETTERS = {
	writefile = function() return writefile end,
	readfile = function() return readfile end,
	isfile = function() return isfile end,
	isfolder = function() return isfolder end,
	makefolder = function() return makefolder end,
	listfiles = function() return listfiles end,
	delfile = function() return delfile end,
	getgenv = function() return getgenv end,
	getcustomasset = function() return getcustomasset end,
	getsynasset = function() return getsynasset end,
	setclipboard = function() return setclipboard end,
	toclipboard = function() return toclipboard end,
	loadstring = function() return loadstring end,
	request = function() return request end,
	http_request = function() return http_request end,
}
local UNC_ALIASES = {
	getcustomasset = { "getcustomasset", "getsynasset" },
	setclipboard = { "setclipboard", "toclipboard" },
	request = { "request", "http_request" },
}
local uncIssues = {}
local uncSeen = {}

-- returns the function and the name that was found (aliases: getcustomasset / getsynasset ...)
local function uncFn(name)
	for _, alias in ipairs(UNC_ALIASES[name] or { name }) do
		local getter = UNC_GETTERS[alias]
		local fn = getter and envFn(getter)
		if fn then
			return fn, alias
		end
	end
	return nil, name
end

local function uncHint(err)
	local e = string.lower(tostring(err))
	local function has(...)
		for _, part in ipairs({ ... }) do
			if string.find(e, part, 1, true) then
				return true
			end
		end
		return false
	end
	if has("attempt to call a nil value", "not implemented", "unsupported") then
		return "the executor lists this function but does not really implement it"
	elseif has("extension", "file type", "filetype", "not allowed", "forbidden") then
		return "the executor refuses this kind of file or path (its own workspace rules)"
	elseif has("permission", "denied", "blocked", "sandbox", "disabled") then
		return "the executor blocked the call (permission / sandbox rule)"
	elseif has("path", "directory", "folder", "no such", "not exist", "cannot find") then
		return "the executor could not use the path (its workspace folder rules)"
	elseif has("bad argument", "invalid argument", "expected") then
		return "the executor's own argument check rejected the call"
	end
	return "the executor's function raised an error"
end

-- kind: "missing" | "error" | "silent" (reported success, but the result does not add up)
local function uncRecord(feature, name, kind, hint, raw)
	local key = feature .. "|" .. name .. "|" .. kind
	local text
	if kind == "missing" then
		text = "this executor has no '" .. name .. "' function, so it is not UNC-complete (an executor gap, not a NovaUI bug)"
	elseif kind == "silent" then
		text = "executor function '" .. name .. "' said it worked, but " .. tostring(raw) .. " (UNC / executor problem, not NovaUI's code)"
	else
		text = "executor function '" .. name .. "' failed: " .. hint .. ". Raw error: " .. tostring(raw) .. " (UNC / executor problem, not NovaUI's code)"
	end
	local message = "[NovaUI] " .. feature .. ": " .. text
	if not uncSeen[key] then
		uncSeen[key] = true
		if #uncIssues < 60 then
			table.insert(uncIssues, { Feature = feature, Function = name, Kind = kind, Hint = hint, Raw = raw and tostring(raw) or nil, Message = message })
		end
		warn(message .. ". Run unc_test.lua to see exactly which functions your executor supports.")
	end
	return text
end

-- ok, value, why. quietMissing = true: a missing function is not worth a console warning
-- (used for passive reads); a function that exists but throws is always reported.
local function uncRun(feature, name, quietMissing, ...)
	local fn, used = uncFn(name)
	if not fn then
		if not quietMissing then
			return false, nil, uncRecord(feature, name, "missing")
		end
		return false, nil, "this executor has no '" .. name .. "' function"
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		local hint = uncHint(result)
		uncRecord(feature, used, "error", hint, result)
		return false, nil, "executor function '" .. used .. "' failed (" .. hint .. ")"
	end
	return true, result
end

-- Files the user drops into the executor's workspace folder (workspace/NovaUI/backgrounds).
-- A source like "intro.webm" or "NovaUI/backgrounds/intro.webm" is a plain file name in that folder: no
-- sub-folders, no "..", only letters, digits, space and - . _ ( ). Anything else is not treated as a file.
local BG_FOLDER = "NovaUI/backgrounds"
local BG_FILE_KINDS = { webm = "video", mp4 = "video", png = "image", jpg = "image", jpeg = "image" }
-- "intro.anim.txt" is a picture animation (sprite sheets made by tools/novaui_tool.py anim): the answer for executors
-- where Roblox refuses local video files. Its sheets (intro.anim1.jpg ...) sit next to it.

local function localBgFile(src)
	if type(src) ~= "string" or #src > 120 then
		return nil
	end
	local name = string.match(src, "^NovaUI/backgrounds/(.+)$") or src
	if string.find(name, "..", 1, true) or not string.match(name, "^[%w%-%._ %(%)]+$") then
		return nil
	end
	local kind = BG_FILE_KINDS[string.lower(string.match(name, "%.(%w+)$") or "")]
	if string.match(string.lower(name), "%.anim%.txt$") and #name > 9 then
		kind = "anim"
	end
	if not kind then
		return nil
	end
	return BG_FOLDER .. "/" .. name, kind, name
end

-- done(asset) | done(nil, reason). A missing file and a broken executor function give different reasons.
local function resolveLocalFile(path, done)
	if not uncFn("getcustomasset") then
		return done(nil, "this executor has no getcustomasset, so files from the folder are unavailable: use an asset id instead (run unc_test.lua to confirm)")
	end
	local okFile, exists = uncRun("background folder", "isfile", true, path)
	if okFile and exists == false then
		return done(nil, "file not found: put it in workspace/" .. BG_FOLDER .. " (looked for " .. path .. ")")
	end
	local ok, asset, why = uncRun("background folder", "getcustomasset", false, path)
	if ok and type(asset) == "string" and asset ~= "" then
		return done(asset)
	elseif ok then
		uncRecord("background folder", "getcustomasset", "silent", nil, "it returned " .. type(asset) .. " for " .. path)
		return done(nil, "executor function 'getcustomasset' returned nothing for " .. path .. " (UNC / executor problem: it may refuse this file type)")
	end
	return done(nil, tostring(why))
end

local function imageKind(data)
	if string.sub(data, 1, 8) == "\137PNG\r\n\26\n" then
		return "png"
	end
	if string.sub(data, 1, 3) == "\255\216\255" then
		return "jpg"
	end
	return nil
end

-- body, or nil + the raw reason (a refused game:HttpGet is the executor's / network's doing, not NovaUI's)
local function downloadImage(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and body ~= "" then
		return body
	end
	local reason = ok and "empty answer" or tostring(body)
	local request = uncFn("request")
	if request then
		local ok2, res = pcall(request, { Url = url, Method = "GET" })
		if ok2 and type(res) == "table" and res.StatusCode == 200 and type(res.Body) == "string" then
			return res.Body
		end
		reason = ok2 and ("HTTP " .. tostring(type(res) == "table" and res.StatusCode or "?")) or tostring(res)
	end
	return nil, string.sub(reason, 1, 160)
end

-- done(asset) on success, done(nil, reason) otherwise. May answer later (downloads run in a thread).
local function resolveImage(src, done)
	if type(src) == "number" then
		if src > 0 and src == math.floor(src) then
			return done("rbxassetid://" .. string.format("%d", src))
		end
		return done(nil, "invalid asset id")
	end
	if type(src) ~= "string" or src == "" then
		return done(nil, "Image must be an asset id or an https link")
	end
	if string.match(src, "^%d+$") then
		return done("rbxassetid://" .. src)
	end
	if string.match(src, "^rbxassetid://%d+$") then
		return done(src)
	end
	local localPath, localKind = localBgFile(src)
	if localPath then
		if localKind ~= "image" then
			return done(nil, "that file is a video, not an image")
		end
		return resolveLocalFile(localPath, done)
	end
	if not string.match(src, "^https?://[%w%-%._~:/%?#@!$&'()*+,;=%%]+$") or #src > 2000 then
		return done(nil, "unsupported image source (use an asset id, an http/https link, or a file name from workspace/NovaUI/backgrounds)")
	end
	if not uncFn("writefile") or not uncFn("getcustomasset") then
		return done(nil, "this executor can't load images from links (needs writefile + getcustomasset); use an rbxassetid instead")
	end
	-- the file name comes from a hash, never from the link
	local base = "NovaUI/img_" .. string.sub(sha256(src), 1, 24)
	task.spawn(function()
		local path = nil
		for _, ext in ipairs({ "png", "jpg" }) do
			local ok, exists = uncRun("images", "isfile", true, base .. "." .. ext)
			if ok and exists then
				path = base .. "." .. ext
			end
		end
		if not path then
			local data, why = downloadImage(src)
			if not data then
				return done(nil, "download failed (" .. tostring(why) .. ")")
			end
			if #data > MAX_IMAGE_BYTES then
				return done(nil, "image too large (max 8 MB)")
			end
			local kind = imageKind(data)
			if not kind then
				return done(nil, "not a PNG or JPEG (Roblox cannot show webp/gif)")
			end
			local okFolder, hasFolder = uncRun("images", "isfolder", true, "NovaUI")
			if not (okFolder and hasFolder) then
				uncRun("images", "makefolder", true, "NovaUI")
			end
			path = base .. "." .. kind
			local okWrite, _, whyWrite = uncRun("images", "writefile", false, path, data)
			if not okWrite then
				return done(nil, "could not save the image: " .. tostring(whyWrite))
			end
		end
		local ok, asset, why = uncRun("images", "getcustomasset", false, path)
		if ok and type(asset) == "string" and asset ~= "" then
			done(asset)
		elseif ok then
			uncRecord("images", "getcustomasset", "silent", nil, "it returned " .. type(asset) .. " for " .. path)
			done(nil, "could not load the image: executor function 'getcustomasset' returned nothing for the saved file")
		else
			done(nil, "could not load the image: " .. tostring(why))
		end
	end)
end

-- Alternatives that never touch the network or the executor's file functions:
--   Image = { Pixels = { W, H, Data } }      a small picture embedded in the script (tools/novaui_tool.py makes it)
--   Image = { User = 1234 }                  Roblox avatar head shot of that user (also Game / Group / Asset = id)
--   Image = { User = "Local" }               the avatar of whoever is playing (the local player), whoever they are
--   Image = "rbxthumb://type=..." or "rbxasset://..." strings
--   Image = { "https://...", 12345, { Pixels = ... } }   a fallback list, tried in order
-- done(asset) | done(nil, reason) | done(nil, nil, pixels)
local validPixels, renderPixels
local THUMB_KINDS = {
	User = "AvatarHeadShot", Game = "GameIcon", Group = "GroupIcon", Asset = "Asset",
}
-- User = "Local" (or "LocalPlayer" / "Me" / true): the person in game, instead of one fixed user id
local LOCAL_USER_WORDS = { ["local"] = true, localplayer = true, me = true, player = true }
local function localUserId()
	local ok, id = pcall(function()
		return Players.LocalPlayer.UserId
	end)
	if ok and type(id) == "number" and id > 0 and id == math.floor(id) then
		return id
	end
	return nil
end

local resolveImageAny
function resolveImageAny(src, done)
	if type(src) == "string" and string.match(src, "^rbxthumb://type=%a+&id=%d+[%w=&_]*$") then
		return done(src)
	end
	if type(src) ~= "table" then
		return resolveImage(src, done)
	end
	if src.Pixels ~= nil then
		if validPixels(src.Pixels) then
			return done(nil, nil, src.Pixels)
		end
		return done(nil, "Pixels must be { W, H, Data } with W*H*6 hex digits (max 64 x 64)")
	end
	for key, kind in pairs(THUMB_KINDS) do
		local id = src[key]
		if id ~= nil then
			if key == "User" and (id == true or (type(id) == "string" and LOCAL_USER_WORDS[string.lower(id)])) then
				id = localUserId()
				if not id then
					return done(nil, 'User = "Local" needs a local player, and there is none here')
				end
			end
			id = tonumber(id)
			if not id or id <= 0 or id ~= math.floor(id) then
				return done(nil, key .. ' must be a positive number (or "Local" for User)')
			end
			return done(string.format("rbxthumb://type=%s&id=%d&w=150&h=150", kind, id))
		end
	end
	if #src == 0 then
		return done(nil, "empty image list")
	end
	-- fallback list: first one that works wins
	local index, lastWhy = 0, "no image worked"
	local function nextOne()
		index = index + 1
		if index > #src or index > 8 then
			return done(nil, lastWhy)
		end
		resolveImageAny(src[index], function(asset, why, px)
			if asset or px then
				return done(asset, why, px)
			end
			lastWhy = why or lastWhy
			nextOne()
		end)
	end
	nextOne()
end

-- Filled accent button with a bold white label. The gradient lives on its own frame
-- (a UIGradient on the button itself would tint the label too).
-- Returns the clickable TextButton and its holder frame.
local function primaryButton(win, parent, text, x, y, w, h)
	local theme = win.Theme
	local top = readableFill(theme.Accent)
	local holder = create("Frame", {
		Name = "Primary",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	local scale = create("UIScale", { Scale = 1, Parent = holder })
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = holder,
	}, {
		corner(10),
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, mix(top, BLACK, 0.25)) }),
	})
	local ring = create("UIStroke", {
		Color = theme.AccentLight,
		Transparency = 0.55,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = fill,
	})
	local btn = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = WHITE,
		Text = text,
		ZIndex = 2,
		Parent = holder,
	})
	win:_connect(btn.MouseEnter, function()
		tween(scale, 0.15, { Scale = 1.03 })
		tween(ring, 0.15, { Transparency = 0.1 })
	end)
	win:_connect(btn.MouseLeave, function()
		tween(scale, 0.15, { Scale = 1 })
		tween(ring, 0.15, { Transparency = 0.55 })
	end)
	win:_connect(btn.MouseButton1Down, function()
		tween(scale, 0.08, { Scale = 0.97 })
	end)
	win:_connect(btn.MouseButton1Up, function()
		tween(scale, 0.12, { Scale = 1.03 }, STYLE_BACK)
	end)
	return btn, holder
end

local function secondaryButton(win, parent, text, x, y, w, h)
	local theme = win.Theme
	local btn = create("TextButton", {
		Name = "Secondary",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = legible(theme.Text, theme.Element, 9),
		Text = text,
		Parent = parent,
	}, { corner(10), stroke(theme.Accent, 0.4, 1) })
	local scale = create("UIScale", { Scale = 1, Parent = btn })
	win:_connect(btn.MouseEnter, function()
		tween(btn, 0.15, { BackgroundColor3 = theme.ElementHover })
		tween(scale, 0.15, { Scale = 1.03 })
	end)
	win:_connect(btn.MouseLeave, function()
		tween(btn, 0.15, { BackgroundColor3 = theme.Element })
		tween(scale, 0.15, { Scale = 1 })
	end)
	return btn
end

-- keyCfg: nil (no key system) or the table from prepareKeySystem.
-- startAtKey: skip the Enter step and the loading bar (Loader = false with a key system).
function Library:_buildLoader(options, keyCfg, startAtKey)
	local theme = self.Theme
	local title = tostring(options.Title or "NovaUI")
	local toggleName = (options.ToggleKey and options.ToggleKey.Name) or "RightShift"
	local current = startAtKey and "Key" or "Welcome"
	local interactive = { Welcome = {}, Key = {}, Load = {} }

	-- Every colour on this screen is contrast-checked against what it sits on, whatever the theme.
	local dark = luminance(theme.Background) <= 0.5
	local cardBg = dark and mix(theme.Background, WHITE, 0.06) or theme.Background
	local boxBg = dark and mix(cardBg, BLACK, 0.30) or WHITE -- inset field: darker than the card so light text pops
	local textMain = legible(theme.Text, cardBg, 9)
	local textSub = legible(mix(theme.Text, cardBg, 0.22), cardBg, 4.5)
	local boxText = legible(theme.Text, boxBg, 9)
	local boxHint = legible(mix(theme.Text, boxBg, 0.3), boxBg, 4.5)
	local colBad = legible(COLOR_BAD, cardBg, 4.5)
	local colGood = legible(COLOR_GOOD, cardBg, 4.5)

	local card = create("CanvasGroup", {
		Name = "Loader",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H[current]),
		BackgroundColor3 = cardBg,
		BorderSizePixel = 0,
		Parent = self.Gui,
	}, { corner(18), stroke(theme.Accent, 0.35, 1) })
	-- soft accent glow across the top of the card
	create("Frame", {
		Name = "Glow",
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = card,
	}, {
		create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0.72, 1),
		}),
	})
	self._loaderScale = create("UIScale", { Scale = 1, Parent = card })

	-- grip: tells people the card can be dragged
	create("Frame", {
		Name = "Grip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(40, 4),
		BackgroundColor3 = theme.Muted,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = card,
	}, { pillCorner() })

	local closeBtn = create("TextButton", {
		Name = "CardClose",
		Position = UDim2.new(1, -38, 0, 10),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_BOLD,
		TextSize = 20,
		TextColor3 = textSub,
		Text = "×",
		ZIndex = 3,
		Parent = card,
	})
	self:_connect(closeBtn.MouseEnter, function()
		tween(closeBtn, 0.12, { TextColor3 = colBad })
	end)
	self:_connect(closeBtn.MouseLeave, function()
		tween(closeBtn, 0.12, { TextColor3 = textSub })
	end)
	self:_connect(closeBtn.Activated, function()
		self:Close()
	end)

	local logoFill = readableFill(theme.Accent)
	create("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = card,
	}, {
		corner(16),
		stroke(theme.AccentLight, 0.4, 2),
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(logoFill, mix(logoFill, BLACK, 0.25)) }),
	})
	local logoLetter = textLabel({
		Name = "LogoText",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(56, 56),
		Text = string.upper(string.sub(title, 1, 1)),
		Font = FONT_BOLD,
		TextSize = 28,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = card,
	})
	if options.Image ~= nil or options.Logo ~= nil then
		local logoImage = create("ImageLabel", {
			Name = "LogoImage",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 26),
			Size = UDim2.fromOffset(56, 56),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = "",
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 3,
			Parent = card,
		}, { corner(16) })
		resolveImageAny(options.Image ~= nil and options.Image or options.Logo, function(asset, why, px)
			if self._destroyed then
				return
			end
			if px then
				local holder = create("CanvasGroup", {
					Name = "LogoPixels",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 26),
					Size = UDim2.fromOffset(56, 56),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					GroupTransparency = 1,
					ZIndex = 3,
					Parent = card,
				}, { corner(16) })
				renderPixels(holder, px)
				tween(holder, 0.3, { GroupTransparency = 0 })
				tween(logoLetter, 0.3, { TextTransparency = 1 })
				return
			end
			if not asset then
				warn("[NovaUI] Image: " .. tostring(why))
				return
			end
			logoImage.Image = asset
			tween(logoImage, 0.3, { ImageTransparency = 0 })
			tween(logoLetter, 0.3, { TextTransparency = 1 })
		end)
	end
	textLabel({
		Name = "Title",
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 30),
		Text = title,
		Font = FONT_BOLD,
		TextSize = 24,
		TextColor3 = textMain,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local subtitle = textLabel({
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 20),
		Text = options.Subtitle or "Click Enter to continue",
		TextSize = 14,
		Font = FONT_MEDIUM,
		TextColor3 = textSub,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	local function stageFrame(name, height, visible)
		return create("CanvasGroup", {
			Name = name,
			Position = UDim2.fromOffset(STAGE_X, STAGE_Y),
			Size = UDim2.fromOffset(STAGE_W, height),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = visible and 0 or 1,
			Visible = visible,
			Parent = card,
		})
	end
	local welcome = stageFrame("Welcome", 82, current == "Welcome")
	local keyStage = stageFrame("KeyStage", 176, current == "Key")
	local loadStage = stageFrame("LoadStage", 82, false)
	local stages = { Welcome = welcome, Key = keyStage, Load = loadStage }

	-- welcome stage ------------------------------------------------------
	local enterBtn = primaryButton(self, welcome, "Enter  ›", 0, 0, STAGE_W, 48)
	interactive.Welcome[1] = enterBtn
	textLabel({
		Name = "Hint",
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "Drag to move  ·  " .. toggleName .. " hides the menu",
		Font = FONT_MEDIUM,
		TextSize = 12,
		TextColor3 = textSub,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = welcome,
	})

	-- key stage ----------------------------------------------------------
	local boxHome = UDim2.fromOffset(0, 22)
	textLabel({
		Name = "KeyLabel",
		Size = UDim2.new(1, 0, 0, 16),
		Text = "ACCESS KEY",
		Font = FONT_BOLD,
		TextSize = 12,
		TextColor3 = textSub,
		Parent = keyStage,
	})
	local boxStroke = stroke(theme.Accent, 0.55, 1)
	local box = create("TextBox", {
		Name = "KeyBox",
		Position = boxHome,
		Size = UDim2.fromOffset(STAGE_W, 46),
		BackgroundColor3 = boxBg,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = FONT_MEDIUM,
		PlaceholderText = "Paste your key here",
		PlaceholderColor3 = boxHint,
		Text = "",
		TextColor3 = boxText,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = keyStage,
	}, { corner(10), padding(14, 0, 14, 0), boxStroke })
	local hasLink = keyCfg ~= nil and keyCfg.link ~= nil
	local verifyW = hasLink and 176 or STAGE_W
	local verifyBtn = primaryButton(self, keyStage, "Verify", 0, 80, verifyW, 46)
	interactive.Key[1] = box
	interactive.Key[2] = verifyBtn
	local linkBtn = nil
	if hasLink then
		linkBtn = secondaryButton(self, keyStage, keyCfg.linkText, verifyW + 8, 80, STAGE_W - verifyW - 8, 46)
		interactive.Key[3] = linkBtn
	end
	local msg = textLabel({
		Name = "Message",
		Position = UDim2.fromOffset(0, 134),
		Size = UDim2.new(1, 0, 0, 40),
		Text = "",
		Font = FONT_MEDIUM,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = textSub,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = keyStage,
	})
	local function setMsg(text, kind)
		msg.Text = text
		msg.TextColor3 = (kind == "bad" and colBad) or (kind == "good" and colGood) or textSub
	end

	-- loading stage ------------------------------------------------------
	local barBack = create("Frame", {
		Name = "BarBack",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.fromOffset(STAGE_W, 6),
		BackgroundColor3 = theme.Off,
		BorderSizePixel = 0,
		Parent = loadStage,
	}, { pillCorner() })
	local barFill = create("Frame", {
		Name = "BarFill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = barBack,
	}, { pillCorner() })
	local status = textLabel({
		Name = "Status",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		TextSize = 13,
		Font = FONT_MEDIUM,
		TextColor3 = textSub,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = loadStage,
	})

	-- stage switching ----------------------------------------------------
	local function showStage(name, instant)
		current = name
		self._loaderStage = name
		for key, stage in pairs(stages) do
			if key == name then
				stage.Visible = true
				if instant then
					stage.GroupTransparency = 0
				else
					stage.GroupTransparency = 1
					tween(stage, 0.25, { GroupTransparency = 0 })
				end
			elseif instant then
				stage.Visible = false
				stage.GroupTransparency = 1
			else
				tween(stage, 0.15, { GroupTransparency = 1 })
				task.delay(0.15, function()
					if not self._destroyed and current ~= key then
						stage.Visible = false
					end
				end)
			end
		end
		local size = UDim2.fromOffset(CARD_W, CARD_H[name])
		if instant then
			card.Size = size
		else
			tween(card, 0.3, { Size = size }, STYLE_QUART)
		end
	end
	self._loaderStage = current

	-- drag the card from anywhere except its own buttons / key box
	local function overInteractive(input)
		local px, py = input.Position.X, input.Position.Y
		local targets = { closeBtn }
		for _, obj in ipairs(interactive[current]) do
			table.insert(targets, obj)
		end
		for _, obj in ipairs(targets) do
			local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
			if px >= pos.X and px <= pos.X + size.X and py >= pos.Y and py <= pos.Y + size.Y then
				return true
			end
		end
		return false
	end
	self:_makeDraggable(card, card, overInteractive)

	-- open the real window where the card was left ------------------------
	local function openMain()
		tween(card, 0.25, { GroupTransparency = 1 })
		task.wait(0.25)
		if self._destroyed then
			return
		end
		card.Visible = false
		self._main.Position = card.Position
		self._opened = true
		self._loaderEnter = nil
		self:_expand()
		runGated(self, options.OnEnter, self)
	end

	local function runLoading()
		showStage("Load")
		barFill.Size = UDim2.fromScale(0, 1)
		tween(barFill, 1.65, { Size = UDim2.fromScale(1, 1) }, STYLE_QUAD, DIR_INOUT)
		task.spawn(function()
			for _, step in ipairs({ "Loading modules", "Building interface", "Almost ready" }) do
				if self._destroyed then
					return
				end
				status.Text = step
				task.wait(0.55)
			end
			if self._destroyed then
				return
			end
			openMain()
		end)
	end

	-- key entry ----------------------------------------------------------
	local fails, lockedUntil, lockLevel, lockToken = 0, 0, 0, 0
	local busy, attemptId = false, 0

	local function shake()
		task.spawn(function()
			for _, dx in ipairs({ 8, -8, 5, -5, 0 }) do
				if self._destroyed then
					return
				end
				tween(box, 0.05, { Position = UDim2.fromOffset(dx, 22) })
				task.wait(0.05)
			end
		end)
	end

	local function startLock()
		lockLevel = lockLevel + 1
		local seconds = math.min(30 * 2 ^ (lockLevel - 1), 600)
		lockedUntil = os.clock() + seconds
		lockToken = lockToken + 1
		local token = lockToken
		task.spawn(function()
			while not self._destroyed and lockToken == token do
				local left = math.ceil(lockedUntil - os.clock())
				if left <= 0 then
					break
				end
				setMsg("Too many wrong keys. Try again in " .. left .. "s.", "bad")
				task.wait(1)
			end
			if not self._destroyed and lockToken == token and not isUnlocked(self) then
				fails = 0
				setMsg("You can try again now.", "muted")
			end
		end)
	end

	local function submit()
		if self._destroyed or isUnlocked(self) or busy or not keyCfg then
			return
		end
		if keyCfg.misconfigured then
			setMsg("This key system is not set up correctly.", "bad")
			return
		end
		local waitLeft = lockedUntil - os.clock()
		if waitLeft > 0 then
			setMsg("Too many wrong keys. Try again in " .. math.ceil(waitLeft) .. "s.", "bad")
			return
		end
		local input = trimText(box.Text)
		if input == "" then
			setMsg("Type your key first.", "bad")
			return
		end
		busy = true
		attemptId = attemptId + 1
		local id = attemptId
		verifyBtn.Text = "Checking..."
		setMsg("Checking key...", "muted")
		-- a Validate that never answers must not freeze the screen
		task.delay(keyCfg.timeout, function()
			if not self._destroyed and busy and attemptId == id then
				attemptId = attemptId + 1
				busy = false
				verifyBtn.Text = "Verify"
				setMsg("No answer from the key server. Try again.", "bad")
			end
		end)
		task.spawn(function()
			local ok, payload = checkKey(keyCfg, input)
			if self._destroyed or attemptId ~= id then
				return
			end
			busy = false
			verifyBtn.Text = "Verify"
			if ok then
				setMsg("Key accepted", "good")
				unlockWindow(self, payload)
				task.delay(0.55, function()
					if self._destroyed then
						return
					end
					if startAtKey then
						openMain()
					else
						runLoading()
					end
				end)
				return
			end
			fails = fails + 1
			local left = keyCfg.maxAttempts - fails
			if left <= 0 then
				startLock()
			else
				setMsg("Invalid key. " .. left .. (left == 1 and " attempt" or " attempts") .. " left.", "bad")
			end
			shake()
		end)
	end

	local function goKey(instant)
		subtitle.Text = (keyCfg and keyCfg.note) or "Enter your key to continue"
		showStage("Key", instant)
		if keyCfg and keyCfg.misconfigured then
			setMsg("This key system is not set up correctly.", "bad")
		end
		task.delay(0.35, function()
			if not self._destroyed and current == "Key" then
				pcall(function()
					box:CaptureFocus()
				end)
			end
		end)
	end

	if keyCfg then
		self:_connect(verifyBtn.Activated, submit)
		self:_connect(box.FocusLost, function(enterPressed)
			tween(boxStroke, 0.15, { Transparency = 0.55 })
			if enterPressed then
				submit()
			end
		end)
		self:_connect(box.Focused, function()
			tween(boxStroke, 0.15, { Transparency = 0.1 })
		end)
		if linkBtn then
			self:_connect(linkBtn.Activated, function()
				local link = keyCfg.link
				local copied = false
				pcall(function()
					local copier = (type(setclipboard) == "function" and setclipboard)
						or (type(toclipboard) == "function" and toclipboard)
					if copier then
						copier(link)
						copied = true
					end
				end)
				if copied then
					setMsg("Link copied to your clipboard.", "good")
				else
					setMsg("Open this link: " .. link, "muted")
				end
			end)
		end
	end

	-- enter ----------------------------------------------------------------
	local entering = startAtKey == true
	local function startEnter()
		if entering or self._destroyed then
			return
		end
		entering = true
		if keyCfg and not isUnlocked(self) then
			goKey(false)
		else
			runLoading()
		end
	end
	self._loaderEnter = function()
		if current == "Welcome" then
			startEnter()
		end
	end
	self:_connect(enterBtn.Activated, startEnter)
	if startAtKey then
		goKey(true)
	end

	return card
end

-- Parent order: explicit option > gethui() > CoreGui (if writable) > PlayerGui.
local function resolveParent(explicit)
	if explicit then
		return explicit
	end
	local okHui, hui = pcall(function()
		return gethui and gethui()
	end)
	if okHui and hui then
		return hui
	end
	local okCore, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCore and core then
		local probe = Instance.new("Folder")
		local writable = pcall(function()
			probe.Parent = core
		end)
		probe:Destroy()
		if writable then
			return core
		end
	end
	local player = Players.LocalPlayer
	return player and player:WaitForChild("PlayerGui")
end

function Library.new(options)
	options = options or {}
	local self = setmetatable({}, Library)

	self.Theme = {}
	for key, value in pairs(DEFAULT_THEME) do
		self.Theme[key] = value
	end
	self._scheme = completeScheme(options.Scheme)
	if options.Accent then
		self._scheme.SchemeColor = options.Accent
	end
	applyScheme(self.Theme, self._scheme)
	self._baseScheme = completeScheme(self._scheme)
	local theme = self.Theme

	self._conns = {}
	self.Tabs = {}
	self._tabsByName = {}
	self._size = options.Size or Vector2.new(580, 380)
	self._destroyed = false
	self._opened = false
	self.Visible = false
	self.Minimized = false
	self._hotkeys = {}
	self._hotkeyIds = {}
	self._keepOnScreen = options.KeepOnScreen ~= false
	self._showChips = options.Hotkeys ~= false -- Hotkeys = false hides the hotkey boxes (code-set Hotkey keys still work)

	-- Optional key system. No KeySystem option = no gate, the window opens after Enter as before.
	local keyCfg = nil
	if options.KeySystem ~= nil and options.KeySystem ~= false then
		keyCfg = prepareKeySystem(options.KeySystem)
	end
	if not keyCfg then
		gate[self] = true
	end

	-- Re-running the script replaces the old window instead of stacking a second one.
	-- Only a handle with Destroy() is published, never the window table itself.
	local envOk, genv = pcall(function()
		return getgenv()
	end)
	local handle = {
		Destroy = function()
			self:Destroy()
		end,
	}
	self._handle = handle
	if envOk and type(genv) == "table" and genv.__NovaUI and genv.__NovaUI ~= handle then
		pcall(function()
			genv.__NovaUI:Destroy()
		end)
	end
	if envOk and type(genv) == "table" then
		genv.__NovaUI = handle
	end

	local parent = resolveParent(options.Parent)

	self.Gui = create("ScreenGui", {
		Name = options.Name or "NovaUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
		Parent = parent,
	})

	-- main window --------------------------------------------------------
	local main = create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(self._size.X, self._size.Y),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		Parent = self.Gui,
	}, { corner(14), stroke(theme.Stroke, 0.92, 1) })
	self._main = main
	self._uiScale = create("UIScale", { Scale = 1, Parent = main })

	local topBar = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, TOPBAR_H),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Parent = main,
	})
	self._topBar = topBar
	create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = topBar,
	}, { pillCorner() })
	textLabel({
		Name = "Title",
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -176, 1, 0),
		Text = options.Title or "NovaUI",
		Font = FONT_BOLD,
		TextSize = 15,
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = topBar,
	})
	if options.Subtitle then
		textLabel({
			Name = "Subtitle",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -118, 0.5, 0),
			Size = UDim2.fromOffset(110, 20),
			Text = options.Subtitle,
			Font = FONT_REGULAR,
			TextSize = 12,
			TextColor3 = theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = topBar,
		})
	end

	local function windowButton(name, text, xOffset, hoverColor)
		local button = create("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, xOffset, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = theme.Element,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = FONT_BOLD,
			TextSize = 16,
			TextColor3 = theme.Muted,
			Text = text,
			Parent = topBar,
		}, { corner(7) })
		self:_connect(button.MouseEnter, function()
			tween(button, 0.12, { BackgroundTransparency = 0, TextColor3 = hoverColor })
		end)
		self:_connect(button.MouseLeave, function()
			tween(button, 0.12, { BackgroundTransparency = 1, TextColor3 = theme.Muted })
		end)
		return button
	end
	self._gear = windowButton("Settings", "⚙", -78, theme.Accent)
	self._gear.TextSize = 17
	self:_connect(self._gear.Activated, function()
		self:ToggleSettings()
	end)
	self._minButton = windowButton("Minimize", "–", -44, theme.Text)
	local closeButton = windowButton("Close", "×", -10, Color3.fromRGB(255, 95, 110))
	self:_connect(self._minButton.Activated, function()
		self:SetMinimized(not self.Minimized)
	end)
	self:_connect(closeButton.Activated, function()
		self:Close()
	end)

	create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(0, TOPBAR_H),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.Stroke,
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		Parent = main,
	})

	local body = create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, TOPBAR_H + 1),
		Size = UDim2.new(1, 0, 1, -(TOPBAR_H + 1)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = main,
	})
	local sidebar = create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_W, 1, 0),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Parent = body,
	})
	self._tabList = create("ScrollingFrame", {
		Name = "TabList",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = sidebar,
	})
	-- the highlight sits in the scrolling canvas next to (not inside) the layout holder,
	-- so the list layout leaves it alone and it can glide between tabs
	self._tabIndicator = create("Frame", {
		Name = "Indicator",
		Position = UDim2.fromOffset(8, TAB_TOP),
		Size = UDim2.new(1, -16, 0, TAB_H),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
		Parent = self._tabList,
	}, {
		corner(8),
		create("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(3, 18),
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
		}, { pillCorner() }),
	})
	self._tabHolder = create("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = self._tabList,
	}, { listLayout(TAB_GAP), padding(8, TAB_TOP, 8, 10) })
	self._content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_W, 0),
		Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = body,
	})

	if options.Background ~= nil then
		self:SetBackground(options.Background)
	end
	if options.AutoBackground ~= false then
		self:_autoLoadBackground() -- the user's saved "auto-load" background preset, if they turned it on
	end

	-- tooltip ------------------------------------------------------------
	local tip = create("CanvasGroup", {
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
		Parent = self.Gui,
	}, { corner(12), stroke(theme.Stroke, 0.88, 1), listLayout(4), padding(12, 10, 12, 10) })
	self._tip = tip
	self._tipTitle = textLabel({
		Name = "TipTitle",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = theme.Text,
		ZIndex = 51,
		Parent = tip,
	})
	self._tipBody = textLabel({
		Name = "TipBody",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		Font = FONT_REGULAR,
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(180, 180, 200),
		ZIndex = 51,
		Parent = tip,
	})

	-- notifications ------------------------------------------------------
	self._notes = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.new(0, 280, 1, -32),
		BackgroundTransparency = 1,
		ZIndex = 60,
		Parent = self.Gui,
	}, { create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}) })

	-- behaviour ----------------------------------------------------------
	self:_makeDraggable(topBar, main)
	self:_updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		self:_connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
			self:_updateScale()
		end)
	end

	local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	self._toggleKey = toggleKey
	self:_connect(UserInputService.InputBegan, function(input, processed)
		self:_onInput(input, processed)
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		local t = input.UserInputType
		if self._swallowArmed and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			-- the click that cancelled a binding is over: swallow its release, then clicks work normally again
			self._swallowArmed = false
			self._swallowUntil = os.clock() + 0.12
		end
	end)

	if keyCfg then
		-- locked: the key screen always shows; Loader = false only skips the Enter + loading steps
		self._loader = self:_buildLoader(options, keyCfg, options.Loader == false)
	elseif options.Loader == false then
		self._opened = true
		self:_expand()
		runGated(self, options.OnEnter, self)
	else
		self._loader = self:_buildLoader(options, nil, false)
	end
	self:_updateScale()

	table.insert(liveWindows, self)

	if keyCfg then
		-- Hold the caller here until a valid key is entered, so the code after CreateLib
		-- (tabs, buttons, the script's own logic) cannot run on a locked window.
		while not isUnlocked(self) and not self._destroyed do
			task.wait(0.1)
		end
		if not isUnlocked(self) then
			error("[NovaUI] key system: the window was closed before a valid key was entered", 0)
		end
		return self, payloads[self]
	end
	return self
end

Library.CreateWindow = Library.new

-- Animated close: the window folds away like it opened, then is destroyed.
-- (Destroy() stays instant.)
function Library:Close()
	if self._destroyed or self._closing then
		return
	end
	self._closing = true
	if self._opened and self._main.Visible then
		self:_collapse(function()
			self:Destroy()
		end)
		return
	end
	local card = self._loader
	if not self._opened and card and card.Visible then
		tween(card, 0.2, { GroupTransparency = 1 })
		if self._loaderScale then
			tween(self._loaderScale, 0.2, { Scale = self._loaderScale.Scale * 0.9 }, STYLE_QUART)
		end
		task.delay(0.22, function()
			self:Destroy()
		end)
		return
	end
	self:Destroy()
end

function Library:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	-- forget this window; module-level calls fall back to the newest one still alive
	for i, w in ipairs(liveWindows) do
		if w == self then
			table.remove(liveWindows, i)
			break
		end
	end
	local envOk, genv = pcall(function()
		return getgenv()
	end)
	if envOk and type(genv) == "table" and genv.__NovaUI == self._handle then
		genv.__NovaUI = nil
	end
	for _, conn in ipairs(self._conns) do
		conn:Disconnect()
	end
	self._conns = {}
	self.Gui:Destroy()
end

----------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------

function Library:Notify(title, text, duration)
	if self._destroyed then
		return
	end
	local theme = self.Theme
	duration = tonumber(duration) or 4
	self._noteOrder = (self._noteOrder or 0) + 1
	local note = create("CanvasGroup", {
		Name = "Note",
		LayoutOrder = self._noteOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = self._notes,
	}, { corner(12), stroke(theme.Stroke, 0.88, 1), listLayout(3), padding(14, 12, 14, 14) })
	textLabel({
		Name = "NoteTitle",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = tostring(title or ""),
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = theme.Text,
		Parent = note,
	})
	textLabel({
		Name = "NoteBody",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = tostring(text or ""),
		Font = FONT_REGULAR,
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(180, 180, 200),
		Parent = note,
	})
	local bar = create("Frame", {
		Name = "Timer",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = note,
	}, { pillCorner() })

	tween(note, 0.25, { GroupTransparency = 0 })
	tween(bar, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
	task.delay(duration, function()
		if self._destroyed then
			return
		end
		tween(note, 0.3, { GroupTransparency = 1 })
		task.wait(0.3)
		if not self._destroyed then
			note:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------

local PAGE_IN, PAGE_OUT = 0.28, 0.14

local function styleTab(tab, selected)
	local theme = tab.Window.Theme
	tween(tab._button, 0.2, { TextColor3 = selected and theme.Text or theme.Muted })
end

function Library:Tab(name, icon)
	local theme = self.Theme
	name = tostring(name or "Tab")
	local tab = setmetatable({ Window = self, Name = name, _order = 0, _index = #self.Tabs + 1 }, Tab)

	-- the button is transparent: the sliding highlight behind it shows which tab is active
	tab._button = create("TextButton", {
		Name = "Tab_" .. name,
		LayoutOrder = tab._index,
		Size = UDim2.new(1, 0, 0, TAB_H),
		BackgroundColor3 = theme.Element,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		TextSize = 14,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = (icon and (icon .. "  ") or "") .. name,
		Parent = self._tabHolder,
	}, { corner(8), padding(16, 0, 8, 0) })

	-- every page sits in a CanvasGroup so the whole page can fade as one
	tab._holder = create("CanvasGroup", {
		Name = "Holder_" .. name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		Parent = self._content,
	})
	tab.Page = create("ScrollingFrame", {
		Name = "Page_" .. name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = tab._holder,
	}, { listLayout(8), padding(12, 12, 14, 12) })

	self:_connect(tab._button.MouseEnter, function()
		if self._selected ~= tab then
			tween(tab._button, 0.12, { TextColor3 = theme.Text })
		end
	end)
	self:_connect(tab._button.MouseLeave, function()
		if self._selected ~= tab then
			tween(tab._button, 0.12, { TextColor3 = theme.Muted })
		end
	end)
	self:_connect(tab._button.Activated, function()
		self:SelectTab(tab)
	end)

	table.insert(self.Tabs, tab)
	self._tabsByName[name] = self._tabsByName[name] or tab -- first tab with a name wins
	if #self.Tabs == 1 then
		self:SelectTab(tab)
	end
	return tab
end

-- Smooth navigation: the sidebar highlight glides to the new tab while the old page fades
-- up and out and the new page rises in. Rapid clicking is safe (hide tokens + per-property tweens).
function Library:SelectTab(target)
	local tab = target
	if type(target) == "string" then
		tab = self._tabsByName[target]
	end
	if not tab or tab.Window ~= self then
		warn("[NovaUI] SelectTab: unknown tab " .. tostring(target))
		return
	end
	if self._settingsOpen then
		self:SetSettingsOpen(false)
	end
	local previous = self._selected
	if previous == tab then
		return
	end
	self:_hideTip()
	self._selected = tab
	for _, other in ipairs(self.Tabs) do
		styleTab(other, other == tab)
	end

	local indicator = self._tabIndicator
	local goal = UDim2.fromOffset(8, TAB_TOP + (tab._index - 1) * (TAB_H + TAB_GAP))
	if previous == nil then
		-- very first tab: show it in place, nothing to animate from
		indicator.Position = goal
		indicator.Visible = true
		tab._holder.Visible = true
		tab._holder.GroupTransparency = 0
		return
	end
	tween(indicator, 0.35, { Position = goal }, STYLE_QUART)

	local dir = tab._index > previous._index and 1 or -1
	previous._hideToken = (previous._hideToken or 0) + 1
	local hideToken = previous._hideToken
	tween(previous._holder, PAGE_OUT, { GroupTransparency = 1 })
	tween(previous.Page, PAGE_OUT, { Position = UDim2.fromOffset(0, -8 * dir) })
	task.delay(PAGE_OUT, function()
		if not self._destroyed and previous._hideToken == hideToken and self._selected ~= previous then
			previous._holder.Visible = false
		end
	end)

	tab._hideToken = (tab._hideToken or 0) + 1 -- cancels a pending hide of this same page
	tab._holder.Visible = true
	tab.Page.Position = UDim2.fromOffset(0, 14 * dir)
	tween(tab._holder, PAGE_IN, { GroupTransparency = 0 }, STYLE_QUART)
	tween(tab.Page, PAGE_IN, { Position = UDim2.fromOffset(0, 0) }, STYLE_QUART)
end

----------------------------------------------------------------------
-- Elements
----------------------------------------------------------------------

function Tab:_row(height, name)
	self._order = self._order + 1
	if self.Window._bg then
		self.Window:_bgQueueGlass() -- new rows join the glass / colour matching
	end
	return create("Frame", {
		Name = name,
		LayoutOrder = self._order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = self.Page,
	})
end

function Tab:Section(text)
	local theme = self.Window.Theme
	local row = self:_row(24, "Section")
	local label = textLabel({
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(tostring(text)),
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = theme.Accent,
		Parent = row,
	})
	return {
		Instance = row,
		Set = function(_, newText)
			label.Text = string.upper(tostring(newText))
		end,
	}
end

function Tab:Label(text)
	local theme = self.Window.Theme
	local row = create("Frame", {
		Name = "Label",
		LayoutOrder = self._order + 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = self.Page,
	})
	self._order = self._order + 1
	local label = textLabel({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = tostring(text),
		Font = FONT_REGULAR,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = theme.Muted,
		Parent = row,
	})
	return {
		Instance = row,
		Set = function(_, newText)
			label.Text = tostring(newText)
		end,
	}
end

local CHIP_W, CHIP_H = 56, 26
local SHORT_KEYS = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl", LeftAlt = "LAlt",
	RightAlt = "RAlt", Return = "Enter", Backquote = "`", Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]",
	Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\", CapsLock = "Caps",
	Insert = "Ins", PageUp = "PgUp", PageDown = "PgDn", Space = "Space",
}
local function chipText(key)
	if not key then
		return "None"
	end
	return SHORT_KEYS[key.Name] or key.Name
end

-- Registers a hotkey for an element and (when chipProps is given) builds its rebind box.
-- opts.Hotkey: Enum.KeyCode default | false = no hotkey at all. opts.OnHotkeyChanged(key|nil).
-- Returns the hotkey record (key, SetKey) or nil when disabled.
function Tab:_hotkey(parent, opts, fire, label, chipProps)
	if opts.Hotkey == false then
		return nil
	end
	local win = self.Window
	local theme = win.Theme
	local hk = { key = nil, id = win:_hotkeyId(self.Name .. "/" .. label) }
	if opts.Hotkey ~= nil then
		if isKeyCode(opts.Hotkey) then
			hk.key = opts.Hotkey
		else
			warn("[NovaUI] Hotkey must be an Enum.KeyCode (or false for none); ignored for '" .. label .. "'")
		end
	end
	local chip, chipStroke
	local listening = false
	local mutedText = legible(theme.Muted, theme.Background, 4.5)
	local accentText = legible(theme.Accent, theme.Background, 4.5)
	local badText = legible(COLOR_BAD, theme.Background, 4.5)

	local function refresh()
		if not chip then
			return
		end
		chip.Text = listening and "..." or chipText(hk.key)
		chip.TextColor3 = (listening or hk.key) and accentText or mutedText
		tween(chipStroke, 0.15, { Transparency = listening and 0 or 0.65, Color = theme.Accent })
	end

	function hk.SetKey(_, key, silent)
		if key ~= nil and not isKeyCode(key) then
			warn("[NovaUI] SetHotkey expects an Enum.KeyCode or nil")
			return false
		end
		hk.key = key
		refresh()
		if not silent and opts.OnHotkeyChanged then
			safe(opts.OnHotkeyChanged, key)
		end
		return true
	end

	hk.fire = function()
		fire()
		if chip then
			tween(chipStroke, 0.08, { Transparency = 0, Color = theme.AccentLight })
			task.delay(0.2, function()
				if not win._destroyed and not listening then
					refresh()
				end
			end)
		end
	end

	if chipProps and win._showChips then
		chipStroke = stroke(theme.Accent, 0.65, 1)
		chip = create("TextButton", {
			Name = "Hotkey",
			AnchorPoint = chipProps.AnchorPoint,
			Position = chipProps.Position,
			Size = UDim2.fromOffset(CHIP_W, CHIP_H),
			BackgroundColor3 = theme.Background,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = mutedText,
			Text = chipText(hk.key),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 5,
			Parent = parent,
		}, { corner(6), chipStroke })
		refresh()
		win:_connect(chip.MouseEnter, function()
			if not listening then
				tween(chipStroke, 0.12, { Transparency = 0.3 })
			end
		end)
		win:_connect(chip.MouseLeave, function()
			if not listening then
				tween(chipStroke, 0.12, { Transparency = 0.65 })
			end
		end)
		win:_attachTip(chip, { Title = "Hotkey", Text = "Click, then press a key. Esc or a click cancels, Backspace clears." })
		win:_connectClick(chip.Activated, function()
			if listening then
				win:_endCapture("cancelled")
				return
			end
			listening = true
			refresh()
			win:_beginCapture(function(result, key)
				listening = false
				if result == "bound" then
					hk:SetKey(key)
				elseif result == "cleared" then
					hk:SetKey(nil)
				elseif result == "taken" then
					chip.Text = "Taken"
					chip.TextColor3 = badText
					tween(chipStroke, 0.1, { Transparency = 0, Color = COLOR_BAD })
					task.delay(0.9, function()
						if not win._destroyed and not listening then
							refresh()
						end
					end)
					return
				end
				refresh()
			end, function(code)
				return not win:_keyTaken(code, hk)
			end)
		end)
	end

	win:_addHotkey(hk)
	return hk
end

-- opts: string style, or { Style, Icon, Tooltip, Hotkey, OnHotkeyChanged }
-- Styles: "Default", "Pill", "Sweep", "Push", "Glow"
function Tab:Button(text, callback, opts)
	if type(opts) == "string" then
		opts = { Style = opts }
	end
	opts = opts or {}
	local style = opts.Style or "Default"
	local builder = STYLES[style]
	if not builder then
		warn("[NovaUI] unknown button style '" .. tostring(style) .. "', using Default")
		style = "Default"
		builder = STYLES.Default
	end
	local win = self.Window
	local row = self:_row(ROW_HEIGHT[style], "Button_" .. style)
	-- the button style is built inside a host frame so the hotkey box fits on the right
	local host = row
	local chipProps = nil
	if opts.Hotkey ~= false and win._showChips then
		host = create("Frame", {
			Name = "ButtonHost",
			Size = UDim2.new(1, -(CHIP_W + 8), 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = row,
		})
		chipProps = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) }
	end
	local clickable, setText = builder(win, host, tostring(text), opts)
	local hk = self:_hotkey(row, opts, function()
		runGated(win, callback)
	end, tostring(text), chipProps)

	win:_connectClick(clickable.Activated, function()
		runGated(win, callback)
	end)
	win:_attachTip(clickable, opts.Tooltip)

	return {
		Instance = row,
		SetText = function(_, newText)
			setText(tostring(newText))
		end,
		SetHotkey = function(_, key)
			return hk ~= nil and hk:SetKey(key) or false
		end,
		GetHotkey = function()
			return hk and hk.key or nil
		end,
	}
end

function Tab:Toggle(text, default, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	local state = default == true
	local row = self:_row(40, "Toggle")
	local chipOn = opts.Hotkey ~= false and win._showChips
	local btn = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	local nameLabel = textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -(80 + (chipOn and (CHIP_W + 10) or 0)), 1, 0),
		Text = tostring(text),
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = btn,
	})
	local track = create("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(42, 22),
		BackgroundColor3 = state and theme.Accent or theme.Off,
		BorderSizePixel = 0,
		Parent = btn,
	}, { pillCorner() })
	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = state and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = theme.White,
		BorderSizePixel = 0,
		Parent = track,
	}, { pillCorner() })

	local obj = { Instance = row }

	function obj.SetText(_, newText)
		nameLabel.Text = tostring(newText)
	end

	local function render()
		tween(track, 0.2, { BackgroundColor3 = state and theme.Accent or theme.Off })
		tween(knob, 0.2, {
			Position = state and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}, STYLE_BACK)
	end

	-- Set(value, silent): silent = true skips the callback
	function obj.Set(_, value, silent)
		value = value == true
		if value == state then
			return
		end
		state = value
		render()
		if not silent then
			runGated(win, callback, state)
		end
	end

	function obj.Get()
		return state
	end

	local hk = self:_hotkey(row, opts, function()
		obj:Set(not state)
	end, tostring(text), chipOn and { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(12 + 42 + 10), 0.5, 0) } or nil)
	function obj.SetHotkey(_, key)
		return hk ~= nil and hk:SetKey(key) or false
	end
	function obj.GetHotkey()
		return hk and hk.key or nil
	end

	win:_connectClick(btn.Activated, function()
		obj:Set(not state)
	end)
	win:_connect(btn.MouseEnter, function()
		tween(btn, 0.15, { BackgroundColor3 = theme.ElementHover })
	end)
	win:_connect(btn.MouseLeave, function()
		tween(btn, 0.15, { BackgroundColor3 = theme.Element })
	end)
	win:_attachTip(btn, opts.Tooltip)

	return obj
end

function Tab:Slider(text, min, max, default, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	min = tonumber(min) or 0
	max = tonumber(max) or 100
	if max <= min then
		warn("[NovaUI] Slider '" .. tostring(text) .. "': max must be greater than min, using max = min + 1")
		max = min + 1
	end
	local step = tonumber(opts.Step) or 1
	if step <= 0 then
		step = 1
	end
	local decimals = 0
	local probe = step
	while probe < 1 and decimals < 6 do
		probe = probe * 10
		decimals = decimals + 1
	end
	local suffix = opts.Suffix or ""
	local fmt = "%." .. decimals .. "f"

	local function snap(v)
		v = clamp(v, min, max)
		v = min + math.floor((v - min) / step + 0.5) * step
		v = clamp(v, min, max)
		local m = 10 ^ decimals
		return math.floor(v * m + 0.5) / m
	end

	local value = snap(tonumber(default) or min)
	local row = self:_row(56, "Slider")
	local card = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	local nameLabel = textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -100, 0, 20),
		Text = tostring(text),
		TextColor3 = theme.Text,
		Parent = card,
	})
	local valueLabel = textLabel({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.fromOffset(80, 20),
		Text = "",
		TextColor3 = theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local track = create("TextButton", {
		Name = "Track",
		Position = UDim2.new(0, 14, 1, -26),
		Size = UDim2.new(1, -28, 0, 20),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = card,
	})
	local bar = create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = theme.Off,
		BorderSizePixel = 0,
		Parent = track,
	}, { pillCorner() })
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = bar,
	}, { pillCorner() })
	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = theme.White,
		BorderSizePixel = 0,
		Parent = bar,
	}, { pillCorner() })

	local obj = { Instance = row }

	function obj.SetText(_, newText)
		nameLabel.Text = tostring(newText)
	end

	local function render()
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = string.format(fmt, value) .. suffix
	end

	local function apply(v, silent)
		v = snap(v)
		if v == value then
			return
		end
		value = v
		render()
		if not silent then
			runGated(win, callback, value)
		end
	end

	function obj.Set(_, v, silent)
		v = tonumber(v)
		if v then
			apply(v, silent)
		end
	end

	function obj.Get()
		return value
	end

	local dragging = false
	local function fromX(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		apply(min + (max - min) * alpha)
	end

	win:_connect(track.InputBegan, function(input)
		if isPress(input) then
			dragging = true
			tween(knob, 0.1, { Size = UDim2.fromOffset(18, 18) })
			fromX(input.Position.X)
		end
	end)
	win:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	win:_connect(UserInputService.InputEnded, function(input)
		if dragging and isPress(input) then
			dragging = false
			tween(knob, 0.1, { Size = UDim2.fromOffset(14, 14) })
		end
	end)
	win:_attachTip(card, opts.Tooltip)

	render()
	return obj
end

function Tab:Input(text, placeholder, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	local row = self:_row(40, "Input")
	local card = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.4, -14, 1, 0),
		Text = tostring(text),
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local boxStroke = stroke(theme.Accent, 1, 1)
	local box = create("TextBox", {
		Name = "Box",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.6, -16, 0, 26),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = FONT_REGULAR,
		PlaceholderText = tostring(placeholder or ""),
		PlaceholderColor3 = theme.Muted,
		Text = tostring(opts.Default or ""),
		TextColor3 = theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}, { corner(6), padding(8, 0, 8, 0), boxStroke })

	win:_connect(box.Focused, function()
		tween(boxStroke, 0.15, { Transparency = 0.2 })
	end)
	win:_connect(box.FocusLost, function(enterPressed)
		tween(boxStroke, 0.15, { Transparency = 1 })
		if enterPressed or opts.FireOnBlur then
			runGated(win, callback, box.Text)
		end
	end)
	win:_attachTip(card, opts.Tooltip)

	return {
		Instance = row,
		Get = function()
			return box.Text
		end,
		Set = function(_, newText)
			box.Text = tostring(newText)
		end,
	}
end

----------------------------------------------------------------------
-- More elements: Keybind, Dropdown, ColorPicker
----------------------------------------------------------------------

local function keyName(key)
	local ok, name = pcall(function()
		return key.Name
	end)
	if ok and name then
		return name
	end
	return key == nil and "None" or tostring(key)
end

-- Keybind(text, defaultKeyCode, function() ... end). Click the key box, then press a key to rebind.
function Tab:Keybind(text, default, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	local key = default
	local listening = false
	local row = self:_row(40, "Keybind")
	local card = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -120, 1, 0),
		Text = tostring(text),
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local keyButton = create("TextButton", {
		Name = "Key",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(96, 26),
		BackgroundColor3 = theme.Background,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		TextSize = 13,
		TextColor3 = theme.Accent,
		Text = keyName(key),
		Parent = card,
	}, { corner(6) })

	local obj = { Instance = row }
	-- registered in the shared hotkey list: one dispatcher, no firing while typing / locked / binding
	local hk = {
		key = key,
		id = win:_hotkeyId(self.Name .. "/" .. tostring(text)),
		fire = function()
			runGated(win, callback)
		end,
	}
	function hk.SetKey(_, newKey)
		hk.key = newKey
		keyButton.Text = keyName(hk.key)
		return true
	end
	win:_addHotkey(hk)
	function obj.Get()
		return hk.key
	end
	function obj.Set(_, newKey)
		hk:SetKey(newKey)
	end

	win:_connectClick(keyButton.Activated, function()
		if listening then
			win:_endCapture("cancelled")
			return
		end
		listening = true
		keyButton.Text = "..."
		win:_beginCapture(function(result, code)
			listening = false
			if result == "bound" then
				hk.key = code
			elseif result == "cleared" then
				hk.key = nil
			elseif result == "taken" then
				keyButton.Text = "Taken"
				task.delay(0.9, function()
					if not win._destroyed and not listening then
						keyButton.Text = keyName(hk.key)
					end
				end)
				return
			end
			keyButton.Text = keyName(hk.key)
		end, function(code)
			return not win:_keyTaken(code, hk)
		end)
	end)
	win:_attachTip(card, opts.Tooltip)
	return obj
end

-- Dropdown(text, list, function(option) ... end). obj:Refresh(newList) swaps the options.
function Tab:Dropdown(text, list, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	local ROW, ITEM, MAX_VISIBLE = 40, 30, 5
	local items = {}
	local buttons = {}
	local open = false
	local selected = nil -- last option chosen by the user or by Set
	local row = self:_row(ROW, "Dropdown")
	local card = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	local head = create("TextButton", {
		Name = "Hit",
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = card,
	})
	textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, -14, 1, 0),
		Text = tostring(text),
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = head,
	})
	local valueLabel = textLabel({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -34, 0, 0),
		Size = UDim2.new(0.5, -40, 1, 0),
		Text = "",
		TextColor3 = theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = head,
	})
	local arrow = textLabel({
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.fromOffset(16, ROW),
		Text = "+",
		Font = FONT_BOLD,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = head,
	})
	local listFrame = create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(6, ROW + 2),
		Size = UDim2.new(1, -12, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, { listLayout(2) })

	local function listHeight()
		return math.min(#items, MAX_VISIBLE) * (ITEM + 2)
	end

	local function layout()
		local h = listHeight()
		listFrame.Size = UDim2.new(1, -12, 0, h)
		local target = open and (ROW + 8 + h) or ROW
		tween(row, 0.2, { Size = UDim2.new(1, 0, 0, target) })
		arrow.Text = open and "–" or "+"
	end

	local function setOpen(value)
		if value and #items == 0 then
			return
		end
		open = value
		layout()
	end

	local function rebuild(newItems)
		for _, b in ipairs(buttons) do
			b:Destroy()
		end
		buttons = {}
		items = {}
		for index, item in ipairs(newItems) do
			items[index] = tostring(item)
			local b = create("TextButton", {
				Name = "Option",
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, ITEM),
				BackgroundColor3 = theme.Background,
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Font = FONT_MEDIUM,
				TextSize = 13,
				TextColor3 = theme.Text,
				Text = items[index],
				Parent = listFrame,
			}, { corner(6) })
			win:_connect(b.MouseEnter, function()
				tween(b, 0.1, { BackgroundColor3 = theme.ElementHover })
			end)
			win:_connect(b.MouseLeave, function()
				tween(b, 0.1, { BackgroundColor3 = theme.Background })
			end)
			win:_connect(b.Activated, function()
				selected = items[index]
				valueLabel.Text = items[index]
				setOpen(false)
				runGated(win, callback, items[index])
			end)
			buttons[index] = b
		end
		if open then
			if #items == 0 then
				open = false
			end
			layout()
		else
			listFrame.Size = UDim2.new(1, -12, 0, listHeight())
		end
	end

	win:_connect(head.Activated, function()
		setOpen(not open)
	end)
	win:_attachTip(head, opts.Tooltip)
	rebuild(type(list) == "table" and list or {})

	-- choose(option, silent): picks an option that is in the list; the callback runs only when it changes
	local function choose(option, silent)
		option = tostring(option)
		local found = false
		for _, item in ipairs(items) do
			if item == option then
				found = true
				break
			end
		end
		if not found then
			return false
		end
		local changed = selected ~= option
		selected = option
		valueLabel.Text = option
		if changed and not silent then
			runGated(win, callback, option)
		end
		return true
	end

	return {
		Instance = row,
		Refresh = function(_, newList)
			if type(newList) ~= "table" then
				warn("[NovaUI] Dropdown:Refresh expects a table")
				return
			end
			rebuild(newList)
		end,
		Get = function()
			return selected
		end,
		-- Set(option, silent): silent = true skips the callback. Returns false when the option is not in the list.
		Set = function(_, option, silent)
			return choose(option, silent)
		end,
	}
end

-- ColorPicker(text, defaultColor3, function(color3) ... end). Click to expand R/G/B sliders.
function Tab:ColorPicker(text, default, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	local ROW, PANEL = 40, 3 * 56 + 2 * 6
	local color = default or Color3.fromRGB(255, 255, 255)
	local r = math.floor(color.R * 255 + 0.5)
	local g = math.floor(color.G * 255 + 0.5)
	local b = math.floor(color.B * 255 + 0.5)
	local open = false
	local row = self:_row(ROW, "ColorPicker")
	local card = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	local head = create("TextButton", {
		Name = "Hit",
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = card,
	})
	textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -70, 1, 0),
		Text = tostring(text),
		TextColor3 = theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = head,
	})
	local swatch = create("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(34, 20),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = head,
	}, { corner(6), stroke(theme.Stroke, 0.7, 1) })
	local panel = create("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(8, ROW + 4),
		Size = UDim2.new(1, -16, 0, PANEL),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = card,
	}, { listLayout(6) })
	local host = setmetatable({ Window = win, Name = "ColorPanel", Page = panel, _order = 0 }, Tab)

	local function push()
		color = Color3.fromRGB(r, g, b)
		swatch.BackgroundColor3 = color
		runGated(win, callback, color)
	end
	local sr = host:Slider("Red", 0, 255, r, function(v)
		r = v
		push()
	end)
	local sg = host:Slider("Green", 0, 255, g, function(v)
		g = v
		push()
	end)
	local sb = host:Slider("Blue", 0, 255, b, function(v)
		b = v
		push()
	end)

	win:_connect(head.Activated, function()
		open = not open
		tween(row, 0.25, { Size = UDim2.new(1, 0, 0, open and (ROW + PANEL + 12) or ROW) }, STYLE_QUART)
	end)
	win:_attachTip(head, opts.Tooltip)

	local picker = {
		Instance = row,
		Get = function()
			return color
		end,
		-- Set(color3, silent): moves the sliders and swatch; silent = true skips the callback
		Set = function(_, c, silent)
			if typeof(c) ~= "Color3" then
				return
			end
			r, g, b = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
			color = Color3.fromRGB(r, g, b)
			swatch.BackgroundColor3 = color
			sr:Set(r, true)
			sg:Set(g, true)
			sb:Set(b, true)
			if not silent then
				runGated(win, callback, color)
			end
		end,
	}
	return picker
end

----------------------------------------------------------------------
-- Settings panel (gear button): themes, colours, window options, background (+ background presets)
----------------------------------------------------------------------

local function fromHex(h)
	if type(h) ~= "string" or not string.match(h, "^%x%x%x%x%x%x$") then
		return nil
	end
	return Color3.fromRGB(tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16))
end

function Library:IsSettingsOpen()
	return self._settingsOpen == true
end

function Library:_buildSettings()
	if self._settings then
		return self._settings
	end
	local win = self
	local theme = self.Theme
	local panel = create("CanvasGroup", {
		Name = "SettingsPanel",
		Position = UDim2.fromOffset(0, TOPBAR_H + 1),
		Size = UDim2.new(1, 0, 1, -(TOPBAR_H + 1)),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = self._main,
	})
	local page = create("ScrollingFrame", {
		Name = "SettingsPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { listLayout(8), padding(16, 12, 18, 14) })
	local host = setmetatable({ Window = self, Name = "Settings", Page = page, _order = 0 }, Tab)
	local S = { panel = panel, page = page, host = host, pickers = {} }
	self._settings = S

	host:Section("Appearance")
	S.status = host:Label("Pick a theme or change a colour: it applies right away.")
	local names = {}
	for name in pairs(SCHEMES) do
		table.insert(names, name)
	end
	table.sort(names)
	S.themeDropdown = host:Dropdown("Theme", names, function(name)
		if SCHEMES[name] then
			Library._recolor(win, SCHEMES[name])
			win:_syncSettings()
			S.status:Set("Theme: " .. name)
		end
	end)
	local pickerDefs = {
		{ "SchemeColor", "Accent colour" },
		{ "Background", "Window background" },
		{ "Header", "Header & sidebar" },
		{ "ElementColor", "Buttons & rows" },
		{ "TextColor", "Text colour" },
	}
	for _, def in ipairs(pickerDefs) do
		S.pickers[def[1]] = host:ColorPicker(def[2], win._scheme[def[1]], function(c)
			if not S.syncing then
				Library._recolor(win, { [def[1]] = c })
			end
		end)
	end
	host:Button("Reset colours", function()
		Library._recolor(win, win._baseScheme)
		win:_syncSettings()
		S.status:Set("Colours reset")
	end)

	host:Section("Window")
	S.keepToggle = host:Toggle("Keep window on screen", win._keepOnScreen, function(on)
		win._keepOnScreen = on
		if on then
			win:_settle(win._main)
		end
	end, { Hotkey = false })

	if win._buildBackgroundSettings then
		win:_buildBackgroundSettings(host, S)
	end

	host:Section("Executor check")
	S.uncStatus = host:Label("Checks the file and asset functions of your executor (UNC). Details go to the console.")
	host:Button("Run executor check", function()
		local report = Library.UNCTest({ Quiet = false })
		S.uncStatus:Set(report.Summary)
	end, { Hotkey = false })
	return S
end

-- pulls the controls in line with the live scheme (after theme / reset changes)
function Library:_syncSettings()
	local S = self._settings
	if not S then
		return
	end
	S.syncing = true
	for key, picker in pairs(S.pickers) do
		picker:Set(self._scheme[key], true)
	end
	S.keepToggle:Set(self._keepOnScreen, true)
	S.syncing = false
	if self._bgSync then
		self:_bgSync()
	end
end

function Library:SetSettingsOpen(open)
	open = open == true
	if self._destroyed or self._settingsOpen == open then
		return
	end
	local S = self:_buildSettings()
	self._settingsOpen = open
	self:_hideTip()
	S.token = (S.token or 0) + 1
	local token = S.token
	if open then
		S.panel.Visible = true
		S.page.Position = UDim2.fromOffset(0, 14)
		tween(S.panel, PAGE_IN, { GroupTransparency = 0 }, STYLE_QUART)
		tween(S.page, PAGE_IN, { Position = UDim2.fromOffset(0, 0) }, STYLE_QUART)
	else
		tween(S.panel, PAGE_OUT, { GroupTransparency = 1 })
		tween(S.page, PAGE_OUT, { Position = UDim2.fromOffset(0, 8) })
		task.delay(PAGE_OUT, function()
			if not self._destroyed and S.token == token and not self._settingsOpen then
				S.panel.Visible = false
			end
		end)
	end
	if self._gear then
		tween(self._gear, 0.2, { TextColor3 = open and self.Theme.Accent or self.Theme.Muted })
	end
end

function Library:ToggleSettings()
	self:SetSettingsOpen(not self._settingsOpen)
end

----------------------------------------------------------------------
-- Backgrounds: a looping video / image / embedded pixel picture behind the window.
--   * a dim layer (never lighter than BG_MIN_DIM) keeps text readable on any footage
--   * buttons and rows become slightly see-through ("glass", at most BG_MAX_GLASS)
--   * Match colours [beta]: rows, bars and text take on the colour of the picture behind them.
--     Roblox cannot read pixels from a video or a web image, so this needs a colour map
--     (made once with tools/novaui_tool.py) or a Pixels picture, which carries its own colours.
----------------------------------------------------------------------

local BG_MIN_DIM, BG_MAX_DIM, BG_DEFAULT_DIM = 0.35, 0.95, 0.62
local BG_MAX_GLASS, BG_DEFAULT_GLASS = 0.40, 0.20
local MATCH_STEP = 0.2 -- seconds between colour updates
local MATCH_STRENGTHS = { 0.55, 0.45, 0.35, 0.25, 0.15, 0 }
local MAX_VIDEO_BYTES = 40 * 1024 * 1024
local MAX_PIXELS = 64 -- Pixels pictures: at most 64 x 64

local function videoKind(data)
	if string.sub(data, 1, 4) == "\26\69\223\163" then
		return "webm"
	end
	if string.sub(data, 5, 8) == "ftyp" then
		return "mp4"
	end
	return nil
end

local function urlEncode(s)
	return (string.gsub(tostring(s), "[^%w%-%._~:/%?#@!$&'()*+,%%]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function urlDecode(s)
	return (string.gsub(tostring(s), "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

-- done(asset) | done(nil, reason). Videos: rbxassetid, or an https link the executor downloads and plays from disk.
local function resolveVideo(src, done)
	if type(src) == "number" then
		if src > 0 and src == math.floor(src) then
			return done("rbxassetid://" .. string.format("%d", src))
		end
		return done(nil, "invalid asset id")
	end
	if type(src) ~= "string" or src == "" then
		return done(nil, "Video must be an asset id, an https link, or a file name from workspace/NovaUI/backgrounds")
	end
	if string.match(src, "^%d+$") then
		return done("rbxassetid://" .. src)
	end
	if string.match(src, "^rbxassetid://%d+$") then
		return done(src)
	end
	local localPath, localKind = localBgFile(src)
	if localPath then
		if localKind ~= "video" then
			return done(nil, "that file is an image, not a video")
		end
		return resolveLocalFile(localPath, done)
	end
	if not string.match(src, "^https?://[%w%-%._~:/%?#@!$&'()*+,;=%%]+$") or #src > 2000 then
		return done(nil, "unsupported video source (use an asset id, an http/https link, or a file name from workspace/NovaUI/backgrounds)")
	end
	if not uncFn("writefile") or not uncFn("getcustomasset") then
		return done(nil, "this executor can't play videos from links (needs writefile + getcustomasset); put the file in workspace/NovaUI/backgrounds or use an rbxassetid")
	end
	local base = "NovaUI/vid_" .. string.sub(sha256(src), 1, 24)
	task.spawn(function()
		local path = nil
		for _, ext in ipairs({ "webm", "mp4" }) do
			local ok, exists = uncRun("videos", "isfile", true, base .. "." .. ext)
			if ok and exists then
				path = base .. "." .. ext
			end
		end
		if not path then
			local data, why = downloadImage(src)
			if not data then
				return done(nil, "download failed (" .. tostring(why) .. ")")
			end
			if #data > MAX_VIDEO_BYTES then
				return done(nil, "video too large (max 40 MB)")
			end
			local kind = videoKind(data)
			if not kind then
				return done(nil, "not a .webm or .mp4 video")
			end
			local okFolder, hasFolder = uncRun("videos", "isfolder", true, "NovaUI")
			if not (okFolder and hasFolder) then
				uncRun("videos", "makefolder", true, "NovaUI")
			end
			path = base .. "." .. kind
			local okWrite, _, whyWrite = uncRun("videos", "writefile", false, path, data)
			if not okWrite then
				return done(nil, "could not save the video: " .. tostring(whyWrite))
			end
		end
		local ok, asset, why = uncRun("videos", "getcustomasset", false, path)
		if ok and type(asset) == "string" and asset ~= "" then
			done(asset)
		elseif ok then
			uncRecord("videos", "getcustomasset", "silent", nil, "it returned " .. type(asset) .. " for " .. path)
			done(nil, "could not load the video: executor function 'getcustomasset' returned nothing for the saved file")
		else
			done(nil, "could not load the video: " .. tostring(why))
		end
	end)
end

-- A colour map is { Cols, Rows, Interval, Frames = { "rrggbb" x Cols*Rows, ... } } (row-major).
local function validMap(map)
	if type(map) ~= "table" then
		return false
	end
	local cols, rows, frames = map.Cols, map.Rows, map.Frames
	if type(cols) ~= "number" or type(rows) ~= "number" or cols ~= math.floor(cols) or rows ~= math.floor(rows) then
		return false
	end
	if cols < 1 or rows < 1 or cols > MAX_PIXELS or rows > MAX_PIXELS or type(frames) ~= "table" or #frames < 1 or #frames > 4000 then
		return false
	end
	if map.Interval ~= nil and (type(map.Interval) ~= "number" or map.Interval <= 0) then
		return false
	end
	for _, f in ipairs(frames) do
		if type(f) ~= "string" or #f ~= cols * rows * 6 or string.find(f, "%X") then
			return false
		end
	end
	return true
end

-- Text colour maps ("sidecar" files). A plain-text file next to a folder video holds its colour map, so
-- Match colours works for folder files without any loadstring. Made by tools/novaui_tool.py:
--   NVMAP1 cols=12 rows=8 interval=0.5000
--   <one line of cols*rows*6 hex digits per frame, row by row>
-- Lines starting with # are comments. Returns the map, or nil + a reason in plain words.
local MAX_MAP_TEXT = 2000000

local function mapNumber(value)
	if string.match(value, "^%d+%.?%d*$") then
		return tonumber(value)
	end
	return nil
end

local function parseColorMap(text)
	if type(text) ~= "string" or text == "" then
		return nil, "the file is empty"
	end
	if #text > MAX_MAP_TEXT then
		return nil, "the file is over 2 MB: make the map again with a lower --fps, fewer --cols/--rows or a shorter --max-seconds"
	end
	if string.sub(text, 1, 3) == "\239\187\191" then
		text = string.sub(text, 4) -- the invisible UTF-8 marker some editors add
	end
	local cols, rows, interval
	local frames = {}
	local seenHeader = false
	for line in string.gmatch(text, "[^\r\n]+") do
		line = trimText(line)
		if line ~= "" and string.sub(line, 1, 1) ~= "#" then
			if not seenHeader then
				seenHeader = true
				local rest = line == "NVMAP1" and "" or string.match(line, "^NVMAP1%s+(.*)$")
				if not rest then
					return nil, "the first line must start with NVMAP1 (make the file with tools/novaui_tool.py)"
				end
				for key, value in string.gmatch(rest, "(%a+)=(%S+)") do
					if key == "cols" then
						cols = mapNumber(value)
					elseif key == "rows" then
						rows = mapNumber(value)
					elseif key == "interval" then
						interval = mapNumber(value)
						if not interval or interval <= 0 then
							return nil, "interval= must be a number above 0"
						end
					end
				end
				if not cols or not rows or cols ~= math.floor(cols) or rows ~= math.floor(rows) or cols < 1 or rows < 1 or cols > MAX_PIXELS or rows > MAX_PIXELS then
					return nil, "the header needs cols= and rows= (whole numbers from 1 to " .. MAX_PIXELS .. ")"
				end
			else
				local n = #frames + 1
				if n > 4000 then
					return nil, "more than 4000 frames: make the map again with a lower --fps or a shorter --max-seconds"
				end
				if #line ~= cols * rows * 6 then
					return nil, "frame " .. n .. " has " .. #line .. " characters, expected " .. (cols * rows * 6) .. " (cols x rows x 6)"
				end
				if string.find(line, "%X") then
					return nil, "frame " .. n .. " has characters that are not hex digits"
				end
				frames[n] = line
			end
		end
	end
	if not seenHeader then
		return nil, "the file is empty"
	end
	if #frames < 1 then
		return nil, "the file has a header but no frames"
	end
	local map = { Cols = cols, Rows = rows, Interval = interval, Frames = frames }
	if not validMap(map) then
		return nil, "the map is not valid"
	end
	return map
end

-- Library.ParseColorMap(readfile("NovaUI/backgrounds/intro.map.txt")) -> map | nil, reason
Library.ParseColorMap = parseColorMap

-- "NovaUI/backgrounds/intro.webm" -> "NovaUI/backgrounds/intro.map.txt"
local function sidecarPathFor(fullPath)
	local stem = string.match(fullPath, "^(.*)%.[aA][nN][iI][mM]%.[tT][xX][tT]$") or string.match(fullPath, "^(.*)%.%w+$")
	if not stem then
		return nil
	end
	return stem .. ".map.txt", (string.match(stem, "([^/]+)$") or stem) .. ".map.txt"
end

-- map, fileName  when a valid sidecar sits next to the file.
-- nil, nil       when there is none (normal: the map is optional, nothing is said).
-- nil, nil, why  when there is one that cannot be used (executor failed to read it, or it is malformed).
local function loadSidecar(fullPath)
	local mapPath, mapName = sidecarPathFor(fullPath)
	if not mapPath then
		return nil
	end
	local okFile, exists = uncRun("background folder", "isfile", true, mapPath)
	if not okFile or exists ~= true then
		return nil
	end
	local okRead, text, whyRead = uncRun("background folder", "readfile", false, mapPath)
	if not okRead then
		return nil, nil, "could not read " .. mapName .. ": " .. tostring(whyRead)
	end
	local map, reason = parseColorMap(text)
	if not map then
		return nil, nil, mapName .. " is not usable: " .. tostring(reason)
	end
	return map, mapName
end

-- Picture animations: "NVANIM1 cols=4 rows=5 fw=256 fh=192 fps=8 frames=68" in intro.anim.txt, and the frames laid out
-- row by row on intro.anim1.jpg, intro.anim2.jpg ... (cols*rows frames per sheet, the last sheet may be partly empty).
local AnimBG = {}

function AnimBG.parse(text)
	text = string.gsub(tostring(text), "^\239\187\191", "")
	local line = string.match(text, "^[^\r\n]*") or ""
	local rest = string.match(line, "^NVANIM1%s+(.-)%s*$")
	if not rest then
		return nil, "it does not start with NVANIM1 (make it with: python3 tools/novaui_tool.py anim video.mp4)"
	end
	local v = {}
	for key, val in string.gmatch(rest, "(%a+)=([%w%.]+)") do
		v[key] = tonumber(val)
	end
	local function whole(n, lo, hi)
		return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
	end
	if not (whole(v.cols, 1, 16) and whole(v.rows, 1, 16) and whole(v.fw, 16, 1024) and whole(v.fh, 16, 1024) and whole(v.frames, 1, 240)) then
		return nil, "the header numbers are missing or out of range"
	end
	if type(v.fps) ~= "number" or v.fps <= 0 or v.fps > 30 then
		return nil, "fps must be above 0 and at most 30"
	end
	if v.cols * v.fw > 1024 or v.rows * v.fh > 1024 then
		return nil, "a sheet is larger than 1024 px"
	end
	local per = v.cols * v.rows
	return { cols = v.cols, rows = v.rows, fw = v.fw, fh = v.fh, fps = v.fps, frames = v.frames, per = per,
		sheets = math.ceil(v.frames / per), duration = v.frames / v.fps }
end

-- done(meta, assets) | done(nil, nil, reason). path is NovaUI/backgrounds/intro.anim.txt
function AnimBG.resolve(path, done)
	local okFile, exists = uncRun("background folder", "isfile", true, path)
	if okFile and exists == false then
		return done(nil, nil, "file not found: put it in workspace/" .. BG_FOLDER .. " (looked for " .. path .. ")")
	end
	local okRead, text, why = uncRun("background folder", "readfile", false, path)
	if not okRead then
		return done(nil, nil, tostring(why))
	end
	local meta, reason = AnimBG.parse(text)
	if not meta then
		return done(nil, nil, string.match(path, "([^/]+)$") .. " is not usable: " .. tostring(reason))
	end
	local stem = string.match(path, "^(.*)%.[aA][nN][iI][mM]%.[tT][xX][tT]$") or path
	local assets, failure = {}, nil
	for i = 1, meta.sheets do
		resolveLocalFile(stem .. ".anim" .. i .. ".jpg", function(asset, reason2)
			if asset then
				assets[i] = asset
			else
				failure = failure or reason2
			end
		end)
		if failure then
			break
		end
	end
	if failure then
		return done(nil, nil, tostring(failure))
	end
	return done(meta, assets)
end

-- One Heartbeat connection per window; it only does something while an animation is the background.
function AnimBG.ensureLoop(win)
	if win._animConn then
		return
	end
	win._animConn = win:_connect(RunService.Heartbeat, function(dt)
		local a = win._bgAnim
		if not a or win._destroyed or win._closing or not win.Visible then
			return
		end
		local m = a.meta
		a.t = (a.t + (tonumber(dt) or 0)) % m.duration
		local idx = math.floor(a.t * m.fps) % m.frames
		if idx == a.idx then
			return
		end
		a.idx = idx
		local sheet = math.floor(idx / m.per) + 1
		local within = idx % m.per
		local label = a.labels[sheet]
		if not label then
			return
		end
		if a.shown ~= sheet then
			if a.labels[a.shown] then
				a.labels[a.shown].ImageTransparency = 1
			end
			label.ImageTransparency = 0
			a.shown = sheet
		end
		label.ImageRectOffset = Vector2.new((within % m.cols) * m.fw, math.floor(within / m.cols) * m.fh)
	end)
end

-- Pixels = { W, H, Data = "rrggbb..." } (row-major). Doubles as a one-frame colour map.
function validPixels(px)
	if type(px) ~= "table" or type(px.W) ~= "number" or type(px.H) ~= "number" or type(px.Data) ~= "string" then
		return false
	end
	if px.W ~= math.floor(px.W) or px.H ~= math.floor(px.H) or px.W < 1 or px.H < 1 or px.W > MAX_PIXELS or px.H > MAX_PIXELS then
		return false
	end
	return #px.Data == px.W * px.H * 6 and not string.find(px.Data, "%X")
end

local function mapCell(map, frame, u, v)
	local col = clamp(math.floor(u * map.Cols), 0, map.Cols - 1)
	local row = clamp(math.floor(v * map.Rows), 0, map.Rows - 1)
	local at = (row * map.Cols + col) * 6 + 1
	return fromHex(string.sub(map.Frames[frame], at, at + 5))
end

-- Draws a Pixels picture as horizontal runs of equal colour (far fewer Frames than one per pixel).
function renderPixels(parent, px)
	local holder = create("Frame", {
		Name = "BgPixels",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	for y = 0, px.H - 1 do
		local x = 0
		while x < px.W do
			local at = (y * px.W + x) * 6 + 1
			local hex = string.sub(px.Data, at, at + 5)
			local run = 1
			while x + run < px.W and string.sub(px.Data, at + run * 6, at + run * 6 + 5) == hex do
				run = run + 1
			end
			create("Frame", {
				Name = "Run",
				Position = UDim2.new(x / px.W, 0, y / px.H, 0),
				Size = UDim2.new(run / px.W, 1, 1 / px.H, 1),
				BackgroundColor3 = fromHex(hex),
				BorderSizePixel = 0,
				Parent = holder,
			})
			x = x + run
		end
	end
	return holder
end

-- worst-case contrast the text can have on a glass card over the dimmed picture
-- (the picture is assumed to be the colour that is hardest for the text)
local function worstCardContrast(theme, dim, glass)
	local worstMedia = luminance(theme.Text) > 0.5 and WHITE or BLACK
	worstMedia = luminance(theme.Text) > 0.5 and WHITE or BLACK
	local scrimmed = mix(worstMedia, theme.Background, dim)
	local card = mix(scrimmed, theme.Element, 1 - glass)
	return contrastRatio(theme.Text, card)
end

local function clampLevels(theme, dim, glass)
	dim = clamp(tonumber(dim) or BG_DEFAULT_DIM, BG_MIN_DIM, BG_MAX_DIM)
	glass = clamp(tonumber(glass) or BG_DEFAULT_GLASS, 0, BG_MAX_GLASS)
	-- if the choice could make card text hard to read on the worst footage, make the cards more solid
	while glass > 0 and worstCardContrast(theme, dim, glass) < 4.5 do
		glass = math.max(0, glass - 0.05)
	end
	return dim, glass
end

local GLASS_KINDS = { "Element", "ElementHover", "Background" }

function Library:_bgQueueGlass()
	local bg = self._bg
	if not bg or self._bgGlassQueued or self._destroyed then
		return
	end
	self._bgGlassQueued = true
	task.defer(function()
		self._bgGlassQueued = false
		if not self._destroyed and self._bg then
			self:_bgApplyGlass(0.2)
			if self._bg.match then
				self:_matchGather()
			end
		end
	end)
end

-- makes cards, bars and rows see-through (or solid again when no background)
function Library:_bgApplyGlass(duration)
	local bg = self._bg
	local theme = self.Theme
	local glass = bg and bg.glassUsed or 0
	local seen = self._glassed
	for _, d in ipairs(self._main:GetDescendants()) do
		if d.Name ~= "Scrim" and (d.ClassName == "Frame" or d.ClassName == "TextButton" or d.ClassName == "CanvasGroup" or d.ClassName == "ScrollingFrame") then
			local inBackdrop = self._backdrop ~= nil and d:IsDescendantOf(self._backdrop)
			if not inBackdrop and d ~= self._main then
				local isBar = d.Name == "TopBar" or d.Name == "Sidebar"
				local c = d.BackgroundColor3
				local eligible = isBar or c == theme.Element or c == theme.ElementHover or d.Name == "SettingsPanel"
					or (d.Name == "Option" and c == theme.Background)
				if d.BackgroundTransparency == 0 or seen[d] then
					if eligible or seen[d] then
						if eligible and not seen[d] and bg then
							seen[d] = true
						end
						if seen[d] then
							local t = glass
							if isBar then
								t = glass * 0.7 -- bars carry the title and tabs: keep them a bit more solid
							end
							if d.ClassName == "TextButton" and d.Name == "Tab" then
								t = 1
							end
							tween(d, duration or 0, { BackgroundTransparency = t })
							if not bg then
								seen[d] = nil
							end
						end
					end
				end
			end
		end
	end
end

local function ensureBackdrop(win)
	if win._backdrop then
		return win._backdrop
	end
	local theme = win.Theme
	win._backdrop = create("CanvasGroup", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = win._main,
	}, { corner(14) })
	win._scrim = create("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = win._backdrop,
	})
	return win._backdrop
end

local function clearMedia(win)
	if win._bgMedia then
		win._bgMedia:Destroy()
		win._bgMedia = nil
		win._bgVideo = nil
	end
	win._bgAnim = nil
end

-- Colour matching ---------------------------------------------------------

function Library:_matchGather()
	local theme = self.Theme
	local recs = self._matchRecs
	for _, d in ipairs(self._main:GetDescendants()) do
		if not recs[d] and not (self._backdrop and d:IsDescendantOf(self._backdrop)) then
			local cls = d.ClassName
			if cls == "Frame" or cls == "TextButton" or cls == "CanvasGroup" then
				local isBar = d.Name == "TopBar" or d.Name == "Sidebar"
				if d.BackgroundTransparency < 1 then
					if isBar and d.BackgroundColor3 == theme.Panel then
						recs[d] = { kind = "Panel", last = d.BackgroundColor3 }
					elseif d.BackgroundColor3 == theme.Element and d.Name ~= "Track" then
						recs[d] = { kind = "Element", last = d.BackgroundColor3 }
					end
				end
			end
			if (cls == "TextLabel" or cls == "TextButton" or cls == "TextBox") and d.TextColor3 == theme.Text then
				recs[d] = { kind = "Text", last = d.TextColor3 }
			end
		end
	end
end

function Library:_matchRestore()
	local theme = self.Theme
	for inst, rec in pairs(self._matchRecs) do
		if inst.Parent ~= nil then
			if rec.kind == "Text" then
				tween(inst, 0.25, { TextColor3 = theme.Text })
			else
				tween(inst, 0.25, { BackgroundColor3 = rec.kind == "Panel" and theme.Panel or theme.Element })
			end
		end
	end
	self._matchRecs = setmetatable({}, { __mode = "k" })
end

local function backgroundBehind(inst, main)
	local p = inst.Parent
	while p and p ~= main do
		if p.BackgroundTransparency ~= nil and p.BackgroundTransparency < 0.5 and p.Name ~= "Backdrop" then
			return p
		end
		p = p.Parent
	end
	return nil
end

function Library:_matchStep()
	local bg = self._bg
	if not (bg and bg.match and bg.map and self._backdrop) or self._destroyed then
		return
	end
	local map = bg.map
	local frame = 1
	if (self._bgVideo or self._bgAnim) and #map.Frames > 1 then
		local tp
		if self._bgVideo then
			tp = self._bgVideo.TimePosition
		else
			tp = self._bgAnim.t
		end
		if type(tp) == "number" then
			frame = math.floor(tp / (map.Interval or 0.5)) % #map.Frames + 1
		end
	end
	local theme = self.Theme
	local main = self._main
	local mp, ms = main.AbsolutePosition, main.AbsoluteSize
	if ms.X <= 0 or ms.Y <= 0 then
		return
	end
	local tinted = {}
	for inst, rec in pairs(self._matchRecs) do
		if inst.Parent == nil then
			self._matchRecs[inst] = nil
		elseif rec.kind ~= "Text" then
			local cur = inst.BackgroundColor3
			if cur == rec.last or cur == theme.Element or cur == theme.ElementHover or cur == theme.Panel then
				local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
				local u = clamp((pos.X + size.X / 2 - mp.X) / ms.X, 0, 1)
				local v = clamp((pos.Y + size.Y / 2 - mp.Y) / ms.Y, 0, 1)
				local sample = mapCell(map, frame, u, v)
				local base = rec.kind == "Panel" and theme.Panel or theme.Element
				local goal = base
				if sample then
					for _, strength in ipairs(MATCH_STRENGTHS) do
						goal = mix(base, sample, strength)
						-- the text colour must still read on the tinted card
						if strength == 0 or contrastRatio(theme.Text, goal) >= 4.5 then
							break
						end
					end
					rec.sample = sample
				end
				rec.last = goal
				tinted[inst] = goal
				tween(inst, MATCH_STEP, { BackgroundColor3 = goal })
			end
		end
	end
	for inst, rec in pairs(self._matchRecs) do
		if rec.kind == "Text" and inst.Parent ~= nil then
			local cur = inst.TextColor3
			if cur == rec.last or cur == theme.Text then
				local host = backgroundBehind(inst, main)
				local hostColor = host and (tinted[host] or host.BackgroundColor3) or theme.Background
				local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
				local u = clamp((pos.X + size.X / 2 - mp.X) / ms.X, 0, 1)
				local v = clamp((pos.Y + size.Y / 2 - mp.Y) / ms.Y, 0, 1)
				local sample = mapCell(map, frame, u, v)
				local goal = theme.Text
				if sample then
					goal = legible(mix(theme.Text, sample, 0.30), hostColor, 4.5)
				end
				rec.last = goal
				tween(inst, MATCH_STEP, { TextColor3 = goal })
			end
		end
	end
end

function Library:_matchEnable(on)
	if on then
		self._matchRecs = self._matchRecs or setmetatable({}, { __mode = "k" })
		self:_matchGather()
		if not self._matchConn then
			local acc = 0
			self._matchConn = self:_connect(RunService.Heartbeat, function(dt)
				acc = acc + (tonumber(dt) or 0)
				if acc >= MATCH_STEP then
					acc = 0
					if self.Visible and not self._closing then
						self:_matchStep()
					end
				end
			end)
		end
		self:_matchStep()
	else
		if self._matchRecs then
			self:_matchRestore()
		end
	end
end

-- Public API ----------------------------------------------------------------

-- SetBackground(nil)                          remove it
-- SetBackground({ Video = id | link, Dim = 0.62, Glass = 0.2, Match = false, ColorMap = {...} })
-- SetBackground({ Image = id | link, ... })   a still picture
-- SetBackground({ Pixels = { W, H, Data }, ... })   a small embedded picture, no downloads at all
-- SetBackground({ Animation = "intro.anim.txt" })   pictures flipped like a video (tools/novaui_tool.py anim)
-- A string ending in .webm/.mp4 is a Video, .png/.jpg/.jpeg an Image, .anim.txt an Animation.
-- Returns true when accepted. Media may still load later (asynchronously); failures never throw.
function Library:SetBackground(spec)
	if self._destroyed then
		return false
	end
	if spec == nil or spec == false then
		self:ClearBackground()
		return true
	end
	if type(spec) == "string" or type(spec) == "number" then
		local lower = type(spec) == "string" and string.lower(string.match(spec, "^[^%?#]*") or "") or ""
		if string.match(lower, "%.anim%.txt$") then
			spec = { Animation = spec }
		elseif string.match(lower, "%.webm$") or string.match(lower, "%.mp4$") then
			spec = { Video = spec }
		elseif string.match(lower, "%.png$") or string.match(lower, "%.jpe?g$") then
			spec = { Image = spec }
		else
			warn("[NovaUI] SetBackground: say what it is, e.g. { Video = ... } or { Image = ... }")
			return false
		end
	end
	if type(spec) ~= "table" then
		warn("[NovaUI] SetBackground expects a table")
		return false
	end
	local kind, source
	if spec.Video ~= nil then
		kind, source = "video", spec.Video
	elseif spec.Image ~= nil then
		kind, source = "image", spec.Image
	elseif spec.Animation ~= nil then
		kind, source = "anim", spec.Animation
		local _, fileKind = localBgFile(source)
		if fileKind ~= "anim" then
			warn("[NovaUI] SetBackground: Animation must be a file name like intro.anim.txt from workspace/" .. BG_FOLDER)
			return false
		end
	elseif spec.Pixels ~= nil then
		kind, source = "pixels", spec.Pixels
		if not validPixels(source) then
			warn("[NovaUI] SetBackground: Pixels must be { W, H, Data } with W*H*6 hex digits (max 64 x 64)")
			return false
		end
	else
		warn("[NovaUI] SetBackground: give Video, Image, Animation or Pixels")
		return false
	end
	local sidecarMap, mapFile, mapProblem
	if kind ~= "pixels" then
		local fullPath = localBgFile(source)
		if fullPath then
			source = fullPath -- "intro.webm" is remembered (and saved in background presets) as NovaUI/backgrounds/intro.webm
			if spec.ColorMap == nil then
				-- intro.map.txt next to intro.webm is its colour map (a ColorMap given in the call wins)
				sidecarMap, mapFile, mapProblem = loadSidecar(fullPath)
				if mapProblem then
					warn("[NovaUI] background: " .. mapProblem)
				end
			end
		end
	end
	local map = nil
	if spec.ColorMap ~= nil then
		if validMap(spec.ColorMap) then
			map = spec.ColorMap
		else
			warn("[NovaUI] SetBackground: ColorMap is not valid, colour matching stays off")
		end
	elseif sidecarMap then
		map = sidecarMap
	elseif kind == "pixels" then
		map = { Cols = source.W, Rows = source.H, Interval = 1, Frames = { source.Data } }
	end

	local theme = self.Theme
	local dim, glass = clampLevels(theme, spec.Dim, spec.Glass)
	local first = self._bg == nil
	self._bgToken = (self._bgToken or 0) + 1
	local token = self._bgToken
	local state = {
		kind = kind,
		source = kind ~= "pixels" and source or nil,
		dim = dim,
		glass = glass,
		glassUsed = glass,
		match = spec.Match == true and map ~= nil, -- "on" without a map would only look on
		map = map,
		mapFile = sidecarMap and mapFile or nil,
		mapProblem = mapProblem,
		status = "loading",
	}
	self._bg = state
	self._glassed = self._glassed or setmetatable({}, { __mode = "k" })
	self._matchRecs = self._matchRecs or setmetatable({}, { __mode = "k" })

	local backdrop = ensureBackdrop(self)
	clearMedia(self)
	tween(self._scrim, first and 0.4 or 0.2, { BackgroundTransparency = 1 - dim })
	self:_bgApplyGlass(first and 0.4 or 0.2)

	local function show(asset)
		if self._destroyed or self._bgToken ~= token then
			return -- replaced or removed while loading
		end
		clearMedia(self)
		if kind == "anim" then
			local meta = asset.meta
			local holder = create("Frame", {
				Name = "BgAnim",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 1,
				Parent = backdrop,
			})
			local labels = {}
			for i, sheetAsset in ipairs(asset.sheets) do
				labels[i] = create("ImageLabel", {
					Name = "Sheet" .. i,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = sheetAsset,
					ImageTransparency = i == 1 and 0 or 1, -- every sheet is loaded up front; only one is visible
					ImageRectOffset = Vector2.new(0, 0),
					ImageRectSize = Vector2.new(meta.fw, meta.fh),
					ScaleType = Enum.ScaleType.Crop,
					ZIndex = 1,
					Parent = holder,
				})
			end
			self._bgMedia = holder
			self._bgAnim = { meta = meta, labels = labels, t = 0, idx = 0, shown = 1 }
			AnimBG.ensureLoop(self)
		elseif kind == "video" then
			local v = create("VideoFrame", {
				Name = "BgVideo",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Video = asset,
				Looped = true,
				Volume = 0,
				ZIndex = 1,
				Parent = backdrop,
			})
			self._bgMedia, self._bgVideo = v, v
			v.Playing = true
			pcall(function()
				v:Play()
			end)
			-- Roblox plays only some codecs: say so when the video has not loaded after 10 seconds
			task.delay(10, function()
				if self._destroyed or self._bgToken ~= token or self._bgVideo ~= v then
					return
				end
				local okLoaded, loaded = pcall(function()
					return v.IsLoaded
				end)
				if okLoaded and loaded == false then
					state.note = "Roblox has not loaded this video after 10 s. If the window stays plain, convert it to .webm (VP8 or VP9, up to 720p, no audio, under 40 MB)."
					warn("[NovaUI] background: " .. state.note)
					if self._bgStatus then
						self._bgStatus("slow")
					end
				end
			end)
		elseif kind == "image" then
			self._bgMedia = create("ImageLabel", {
				Name = "BgImage",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = asset,
				ScaleType = Enum.ScaleType.Crop,
				ZIndex = 1,
				Parent = backdrop,
			})
		else
			self._bgMedia = renderPixels(backdrop, source)
			self._bgMedia.ZIndex = 1
		end
		state.status = "ready"
		state.asset = asset
		if self._bgStatus then
			self._bgStatus(state.status)
		end
		self:_bgQueueGlass()
	end
	local function fail(reason)
		if self._destroyed or self._bgToken ~= token then
			return
		end
		state.status = "failed: " .. tostring(reason)
		warn("[NovaUI] background: " .. tostring(reason))
		if self._bgStatus then
			self._bgStatus(state.status)
		end
	end
	local function handle(asset, reason)
		if asset then
			show(asset)
		else
			fail(reason)
		end
	end
	if kind == "anim" then
		AnimBG.resolve(source, function(meta, assets, why)
			handle(meta and { meta = meta, sheets = assets } or nil, why)
		end)
	elseif kind == "video" then
		resolveVideo(source, handle)
	elseif kind == "image" then
		resolveImageAny(source, function(asset, why, px)
			handle(asset, why or (px and "for an embedded picture use Pixels = ... instead of Image = ..." or nil))
		end)
	else
		show(nil)
	end

	if state.match and state.map then
		self:_matchEnable(true)
	else
		self:_matchEnable(false)
	end
	if self._bgSync then
		self:_bgSync()
	end
	return true
end

function Library:ClearBackground()
	if self._destroyed then
		return
	end
	self._bgToken = (self._bgToken or 0) + 1
	if self._matchRecs then
		self:_matchRestore()
	end
	local had = self._bg
	self._bg = nil
	if had then
		self:_bgApplyGlass(0.25)
	end
	if self._scrim then
		tween(self._scrim, 0.25, { BackgroundTransparency = 1 })
	end
	clearMedia(self)
	if self._bgSync then
		self:_bgSync()
	end
end

function Library:GetBackground()
	local bg = self._bg
	if not bg then
		return nil
	end
	return { Type = bg.kind, Source = bg.source, Dim = bg.dim, Glass = bg.glass, Match = bg.match, HasColorMap = bg.map ~= nil, MapFile = bg.mapFile, Status = bg.status }
end

-- Dim / Glass / Match can be changed live without reloading the media.
function Library:SetBackgroundLevels(dim, glass)
	local bg = self._bg
	if not bg then
		return
	end
	bg.dim, bg.glass = clampLevels(self.Theme, dim ~= nil and dim or bg.dim, glass ~= nil and glass or bg.glass)
	bg.glassUsed = bg.glass
	tween(self._scrim, 0.2, { BackgroundTransparency = 1 - bg.dim })
	self:_bgApplyGlass(0.2)
end

function Library:SetBackgroundMatch(on)
	local bg = self._bg
	if not bg then
		return false
	end
	on = on == true
	if on and not bg.map then
		return false -- nothing to read colours from
	end
	bg.match = on
	self:_matchEnable(on)
	return true
end

-- A background preset keeps the type, source and levels. Only a file name, asset id or link fits: a Pixels
-- picture or a Game/User icon is a table, and colour maps are too big (a folder file finds its own .map.txt).
function Library:_bgEncode()
	local bg = self._bg
	if not bg or (type(bg.source) ~= "string" and type(bg.source) ~= "number") then
		return nil
	end
	return table.concat({ bg.kind, urlEncode(tostring(bg.source)), string.format("%.2f", bg.dim), string.format("%.2f", bg.glass), bg.match and "1" or "0" }, "|")
end

-- kind, source (still url-encoded), dim, glass, match | nil
local function parseBgCode(code)
	local kind, src, dim, glass, match = string.match(tostring(code), "^(%a+)|([^|]*)|([%d%.]+)|([%d%.]+)|([01])$")
	if not kind or (kind ~= "video" and kind ~= "image" and kind ~= "anim") or not tonumber(dim) or not tonumber(glass) then
		return nil
	end
	return kind, src, tonumber(dim), tonumber(glass), match == "1"
end

function Library:_bgDecode(code)
	local kind, src, dim, glass, match = parseBgCode(code)
	if not kind then
		return false
	end
	-- Match is asked for here; SetBackground keeps it only when the new background has a map (sidecar or kept)
	local spec = { Dim = dim, Glass = glass, Match = match }
	local source = urlDecode(src)
	if string.match(source, "^%d+$") then
		source = tonumber(source)
	end
	if kind == "video" then
		spec.Video = source
	elseif kind == "anim" then
		spec.Animation = source
	else
		spec.Image = source
	end
	self:_bgKeepMap(spec, source)
	return self:SetBackground(spec)
end

-- A colour map belongs to one video. When the same background is set again (a background preset, the Source box) the
-- map in use is kept; a different one never inherits it (a folder file finds its own intro.map.txt instead).
function Library:_bgKeepMap(spec, source)
	local bg = self._bg
	if bg and bg.map and spec.ColorMap == nil then
		local path = localBgFile(source)
		if bg.source == (path or source) then
			spec.ColorMap = bg.map
		end
	end
end

function Library:_onRecolor()
	local bg = self._bg
	if self._scrim then
		self._scrim.BackgroundColor3 = self.Theme.Background
	end
	if bg then
		bg.dim, bg.glass = clampLevels(self.Theme, bg.dim, bg.glass)
		bg.glassUsed = bg.glass
		self._scrim.BackgroundTransparency = 1 - bg.dim
		self:_bgApplyGlass(0)
		if bg.match and bg.map then
			self:_matchGather()
			self:_matchStep()
		end
	end
end

-- Background presets ----------------------------------------------------------
-- The only presets NovaUI has: a name for a background (type, source, dim, glass, match). They live in
-- workspace/NovaUI/bg_presets.txt, one "name<TAB>code" per line; "@auto<TAB>name" marks the preset that
-- loads by itself whenever the UI is created. Shared by every window of the session.
local BGP_FILE = "NovaUI/bg_presets.txt"
local BGP_MAX = 40
local BGP_MAX_NAME = 24
local bgpStore = nil

local function cleanBgPresetName(text)
	text = string.gsub(tostring(text or ""), "[%c@]", "") -- tabs / newlines, and @ (kept for the auto marker)
	text = string.gsub(text, "^%s+", "")
	text = string.sub(text, 1, BGP_MAX_NAME)
	return (string.gsub(text, "%s+$", ""))
end

local function bgPresets()
	if bgpStore then
		return bgpStore
	end
	bgpStore = { names = {}, codes = {}, auto = nil }
	-- no file yet is normal (first run); only a function that exists but throws is blamed on the executor
	local text = nil
	local okExists, exists = uncRun("background presets", "isfile", true, BGP_FILE)
	if okExists and exists == false then
		return bgpStore
	end
	if okExists or not uncFn("isfile") then
		local read = uncFn("readfile")
		if read then
			local okRead, body
			if okExists then
				okRead, body = uncRun("background presets", "readfile", true, BGP_FILE)
			else
				okRead, body = pcall(read, BGP_FILE) -- isfile is missing: a failed read just means no file yet
			end
			if okRead and type(body) == "string" then
				text = body
			end
		end
	end
	if text then
		local auto = nil
		for line in string.gmatch(text, "[^\r\n]+") do
			local name, code = string.match(line, "^([^\t]+)\t(.+)$")
			if name == "@auto" then
				auto = code
			elseif name and #bgpStore.names < BGP_MAX and cleanBgPresetName(name) == name and parseBgCode(code) then
				if not bgpStore.codes[name] then
					table.insert(bgpStore.names, name)
				end
				bgpStore.codes[name] = code
			end
		end
		if auto and bgpStore.codes[auto] then
			bgpStore.auto = auto
		end
	end
	return bgpStore
end

-- returns true, or false + a plain-words reason that names the executor function at fault
local function persistBgPresets()
	local store = bgPresets()
	local lines = {}
	for _, name in ipairs(store.names) do
		table.insert(lines, name .. "\t" .. store.codes[name])
	end
	if store.auto and store.codes[store.auto] then
		table.insert(lines, "@auto\t" .. store.auto)
	end
	local okFolder, hasFolder = uncRun("background presets", "isfolder", true, "NovaUI")
	if not (okFolder and hasFolder) then
		uncRun("background presets", "makefolder", true, "NovaUI") -- a failure is recorded; writefile below says whether it mattered
	end
	local ok, _, why = uncRun("background presets", "writefile", false, BGP_FILE, table.concat(lines, "\n"))
	return ok, why
end

local function keptNote(ok, why)
	return ok and " (kept on disk)" or (" (this session only: " .. tostring(why or "your executor has no file access") .. ")")
end

-- Window:GetBackgroundPresets() -> { names }          Window:GetAutoBackgroundPreset() -> name | nil
-- Window:SaveBackgroundPreset(name) / LoadBackgroundPreset(name) / DeleteBackgroundPreset(name)
-- Window:SetAutoBackgroundPreset(name | nil)           (nil = off)
-- The last four return ok, message (the message is what the settings page shows).
function Library:GetBackgroundPresets()
	local out = {}
	for i, name in ipairs(bgPresets().names) do
		out[i] = name
	end
	return out
end

function Library:GetAutoBackgroundPreset()
	return bgPresets().auto
end

function Library:SaveBackgroundPreset(name)
	name = cleanBgPresetName(name)
	if name == "" then
		return false, "Type a preset name first."
	end
	local code = self:_bgEncode()
	if not code then
		return false, self._bg and "Only a file, asset id or link can be kept in a preset (not a Pixels picture or an icon)." or "Set a background first, then save it."
	end
	local store = bgPresets()
	if not store.codes[name] then
		if #store.names >= BGP_MAX then
			return false, "Preset limit reached (" .. BGP_MAX .. "). Delete one first."
		end
		table.insert(store.names, name)
	end
	store.codes[name] = code
	self._bgPresetSelected = name
	local ok, why = persistBgPresets()
	return true, "Saved '" .. name .. "'" .. keptNote(ok, why)
end

function Library:LoadBackgroundPreset(name)
	local code = bgPresets().codes[name]
	if not code then
		return false, "There is no preset called '" .. tostring(name) .. "'."
	end
	self._bgPresetSelected = name
	if self:_bgDecode(code) then
		return true, "Loaded '" .. name .. "'"
	end
	return false, "Could not apply '" .. name .. "'."
end

function Library:DeleteBackgroundPreset(name)
	local store = bgPresets()
	if not name or not store.codes[name] then
		return false, "Pick a preset in 'Load preset' first."
	end
	store.codes[name] = nil
	for i, n in ipairs(store.names) do
		if n == name then
			table.remove(store.names, i)
			break
		end
	end
	if store.auto == name then
		store.auto = nil
	end
	if self._bgPresetSelected == name then
		self._bgPresetSelected = nil
	end
	local ok, why = persistBgPresets()
	return true, "Deleted '" .. name .. "'" .. (ok and "" or keptNote(ok, why))
end

function Library:SetAutoBackgroundPreset(name)
	local store = bgPresets()
	if not name then
		store.auto = nil
		local ok, why = persistBgPresets()
		return true, "Auto-load is off" .. (ok and "" or keptNote(ok, why))
	end
	if not store.codes[name] then
		return false, "There is no preset called '" .. tostring(name) .. "'."
	end
	store.auto = name
	local ok, why = persistBgPresets()
	return true, "'" .. name .. "' will load by itself when the UI opens" .. keptNote(ok, why)
end

-- called while the window is built: the auto preset (the user's own choice) replaces a script's default Background
function Library:_autoLoadBackground()
	local store = bgPresets()
	local name = store.auto
	if not name or not store.codes[name] then
		return false
	end
	self._bgPresetSelected = name
	return self:_bgDecode(store.codes[name])
end

-- Settings controls ----------------------------------------------------------

function Library:_buildBackgroundSettings(host, S)
	local win = self
	host:Section("Background  (video / image)")
	S.bgNote = host:Label("Drop a .png / .jpg / .anim.txt (picture animation) or .webm into workspace/" .. BG_FOLDER .. ", press Refresh, pick it below.")

	-- the folder: created on demand, listed through the executor's listfiles
	local function ensureFolder(path)
		local okF, has = uncRun("background folder", "isfolder", true, path)
		if not (okF and has) then
			uncRun("background folder", "makefolder", true, path)
		end
	end
	local function listBgFiles()
		local names = {}
		if not uncFn("listfiles") then
			return names, "this executor has no listfiles: type the file name in Source instead"
		end
		ensureFolder("NovaUI")
		ensureFolder(BG_FOLDER)
		local ok, list, why = uncRun("background folder", "listfiles", false, BG_FOLDER)
		if not ok then
			return names, why
		end
		if type(list) ~= "table" then
			return names, "executor function 'listfiles' returned " .. type(list) .. " instead of a list"
		end
		local seen = {}
		for _, entry in ipairs(list) do
			local name = string.match(tostring(entry), "([^/\\]+)$")
			if name and not seen[name] and localBgFile(name) and not string.match(string.lower(name), "%.anim%d+%.jpe?g$") and #names < 100 then
				seen[name] = true
				table.insert(names, name)
			end
		end
		table.sort(names, function(a, b)
			return string.lower(a) < string.lower(b)
		end)
		return names
	end
	local function useFile(name)
		local path, fileKind = localBgFile(name)
		if not path then
			S.bgNote:Set("That is not a usable file name (letters, digits, space - . _ ( ) and .webm .mp4 .png .jpg .anim.txt).")
			return
		end
		local spec = { Dim = win._bg and win._bg.dim, Glass = win._bg and win._bg.glass, Match = win._bg and win._bg.match }
		spec[fileKind == "video" and "Video" or fileKind == "anim" and "Animation" or "Image"] = path
		win:_bgKeepMap(spec, path)
		-- say "Loading" first: a folder file resolves at once, and its "ready" / error note must not be overwritten
		S.bgNote:Set("Loading " .. name .. "...")
		win:SetBackground(spec)
	end
	S.bgFiles = host:Dropdown("Files in folder", {}, function(name)
		useFile(name)
	end)
	function S.refreshFiles()
		local names, why = listBgFiles()
		S.bgFiles:Refresh(names)
		if why then
			S.bgNote:Set("Could not list the folder: " .. tostring(why))
		elseif #names == 0 then
			S.bgNote:Set("No files yet. Put a .anim.txt / .png / .jpg / .webm in workspace/" .. BG_FOLDER .. ", then press Refresh files.")
		else
			S.bgNote:Set(#names .. " file(s) found in workspace/" .. BG_FOLDER .. ". Pick one in 'Files in folder'.")
		end
	end
	host:Button("Refresh files", function()
		S.refreshFiles()
	end, { Hotkey = false })

	local kindNow = "Video"
	S.bgType = host:Dropdown("Type (for links / ids)", { "Video", "Image" }, function(v)
		kindNow = v
	end)
	S.bgSource = host:Input("Source", "file name, asset id or https link, press Enter", function(text)
		text = trimText(text)
		if text == "" then
			return
		end
		if localBgFile(text) then
			return useFile(string.match(text, "([^/]+)$"))
		end
		local spec = { Dim = win._bg and win._bg.dim, Glass = win._bg and win._bg.glass, Match = win._bg and win._bg.match }
		local source = string.match(text, "^%d+$") and tonumber(text) or text
		spec[kindNow] = source
		win:_bgKeepMap(spec, source)
		S.bgNote:Set("Loading " .. string.lower(kindNow) .. "...")
		win:SetBackground(spec)
	end)
	S.bgDim = host:Slider("Dim (readability)", math.floor(BG_MIN_DIM * 100), math.floor(BG_MAX_DIM * 100), math.floor(BG_DEFAULT_DIM * 100), function(v)
		if not S.syncing then
			win:SetBackgroundLevels(v / 100, nil)
		end
	end, { Suffix = "%" })
	S.bgGlass = host:Slider("Glass (see-through buttons)", 0, math.floor(BG_MAX_GLASS * 100), math.floor(BG_DEFAULT_GLASS * 100), function(v)
		if not S.syncing then
			win:SetBackgroundLevels(nil, v / 100)
		end
	end, { Suffix = "%" })
	S.bgMatch = host:Toggle("Match colours [beta]", false, function(on)
		if S.syncing then
			return
		end
		if not win:SetBackgroundMatch(on) then
			S.syncing = true
			S.bgMatch:Set(false, true)
			S.syncing = false
			local bg = win._bg
			local path = bg and bg.source and localBgFile(bg.source)
			local mapName = path and select(2, sidecarPathFor(path))
			if bg and bg.mapProblem then
				S.bgNote:Set("Colour matching is off: " .. bg.mapProblem)
			elseif mapName then
				S.bgNote:Set("No colour map next to this file. Run  python3 tools/novaui_tool.py colormap " .. string.match(path, "([^/]+)$") .. " --sidecar  and put " .. mapName .. " in the same folder, then pick the file again.")
			else
				S.bgNote:Set(bg and "Colour matching needs a colour map for this video/image: make one with tools/novaui_tool.py (see INSTRUCTIONS.md), or use a Pixels picture." or "Set a background first.")
			end
		else
			S.bgNote:Set(on and "Buttons and text now follow the colours behind them (beta)." or "Colour matching off.")
		end
	end, { Hotkey = false })
	host:Button("Remove background", function()
		win:ClearBackground()
		S.bgNote:Set("Background removed.")
	end, { Hotkey = false })

	-- background presets: save the current background under a name, load it later, optionally by itself
	host:Section("Background presets")
	S.bgPresetNote = host:Label("Save the current background under a name, load it later, or let one load by itself.")
	local presetName = ""
	S.bgPresetName = host:Input("Preset name", "e.g. Night city", function(text)
		presetName = text
	end, { FireOnBlur = true })
	local function autoText()
		local auto = win:GetAutoBackgroundPreset()
		return auto and ("Auto-load: '" .. auto .. "'.") or "Auto-load: off."
	end
	function S.refreshBgPresets()
		S.bgPresetList:Refresh(win:GetBackgroundPresets())
		local auto = win:GetAutoBackgroundPreset()
		S.syncing = true
		S.bgAuto:Set(auto ~= nil and auto == win._bgPresetSelected, true)
		S.syncing = false
	end
	S.bgPresetList = host:Dropdown("Load preset", win:GetBackgroundPresets(), function(name)
		local _, msg = win:LoadBackgroundPreset(name)
		S.refreshBgPresets()
		S.bgPresetNote:Set(msg .. ". " .. autoText())
	end)
	S.bgAuto = host:Toggle("Auto-load this preset on start", false, function(on)
		if S.syncing then
			return
		end
		if on then
			local pick = win._bgPresetSelected
			local ok, msg = false, nil
			if pick then
				ok, msg = win:SetAutoBackgroundPreset(pick)
			end
			S.bgPresetNote:Set(ok and msg or "Pick or save a preset first.")
		else
			local _, msg = win:SetAutoBackgroundPreset(nil)
			S.bgPresetNote:Set(msg)
		end
		S.refreshBgPresets()
	end, { Hotkey = false })
	host:Button("Save background preset", function()
		local _, msg = win:SaveBackgroundPreset(presetName ~= "" and presetName or S.bgPresetName:Get())
		S.refreshBgPresets()
		S.bgPresetNote:Set(msg .. " " .. autoText())
	end, { Hotkey = false })
	host:Button("Delete selected preset", function()
		local _, msg = win:DeleteBackgroundPreset(win._bgPresetSelected)
		S.refreshBgPresets()
		S.bgPresetNote:Set(msg .. " " .. autoText())
	end, { Hotkey = false })
	if win._bgPresetSelected then
		S.bgPresetList:Set(win._bgPresetSelected, true)
	end
	S.refreshBgPresets()
	self._bgStatus = function(status)
		if string.sub(status, 1, 6) == "failed" then
			S.bgNote:Set("Could not load it (" .. string.sub(status, 9) .. ")")
		elseif status == "ready" then
			local bg = win._bg
			if bg and bg.mapFile then
				S.bgNote:Set("Background ready. Colour map found (" .. bg.mapFile .. "): Match colours [beta] can be switched on.")
			elseif bg and bg.mapProblem then
				S.bgNote:Set("Background ready, but " .. bg.mapProblem)
			else
				S.bgNote:Set("Background ready.")
			end
		elseif status == "slow" then
			S.bgNote:Set(win._bg and win._bg.note or "Roblox is still loading the video.")
		end
	end
	S.refreshFiles()
end

function Library:_bgSync()
	local S = self._settings
	if not S or not S.bgDim then
		return
	end
	S.syncing = true
	local bg = self._bg
	if bg then
		S.bgDim:Set(math.floor(bg.dim * 100 + 0.5), true)
		S.bgGlass:Set(math.floor(bg.glass * 100 + 0.5), true)
		S.bgMatch:Set(bg.match == true, true)
	else
		S.bgMatch:Set(false, true)
	end
	S.syncing = false
end

----------------------------------------------------------------------
-- Kavo-style API (same calls as Kavo UI Library)
----------------------------------------------------------------------

local function tipFor(name, info)
	if type(info) == "string" and info ~= "" then
		return { Title = tostring(name), Text = info }
	end
	return nil
end

local Section = {}
Section.__index = Section
local KavoTab = {}
KavoTab.__index = KavoTab

-- CreateLib(title, theme [, options])
--   theme: "DarkTheme" | "LightTheme" | "GrapeTheme" | "BloodTheme" | "Ocean" | "Midnight" | "Sentinel" | "Synapse"
--          or a colour table { SchemeColor, Background, Header, TextColor, ElementColor }
--   options (NovaUI extra): { Loader = false, Parent = gui, ToggleKey = Enum.KeyCode.X, OnEnter = fn }
function Library.CreateLib(title, theme, options)
	local opts = {}
	if type(options) == "table" then
		for k, v in pairs(options) do
			opts[k] = v
		end
	end
	opts.Title = opts.Title or tostring(title or "NovaUI")
	if theme ~= nil and opts.Scheme == nil then
		if type(theme) == "string" then
			opts.Scheme = SCHEMES[theme]
			if not opts.Scheme then
				warn("[NovaUI] unknown theme '" .. theme .. "', using DarkTheme")
			end
		elseif type(theme) == "table" and theme.R == nil then
			opts.Scheme = theme
		else
			opts.Scheme = { SchemeColor = theme } -- a lone Color3 = accent colour
		end
	end
	return Library.new(opts)
end

function Library:NewTab(name)
	return setmetatable({ _tab = self:Tab(name) }, KavoTab)
end

local function targetWindow(self)
	if self ~= Library and type(self) == "table" and self._main then
		return self
	end
	return liveWindows[#liveWindows]
end

-- Works as Library:ToggleUI() (last window) and Window:ToggleUI().
function Library.ToggleUI(self)
	local win = targetWindow(self)
	if win and not win._destroyed then
		win:ToggleVisible()
	end
end

-- Re-colours a live window to `newScheme` in one pass. Instances are matched by their current
-- colour; the Header colour is only ever used by TopBar/Sidebar, so a theme whose Header and
-- Element colours happen to be equal (Ocean, Sentinel) still maps each to its own new colour.
function Library._recolor(win, newScheme)
	local old = {}
	for k, v in pairs(win.Theme) do
		old[k] = v
	end
	for _, key in ipairs(SCHEME_KEYS) do
		if newScheme[key] ~= nil then
			win._scheme[key] = newScheme[key]
		end
	end
	applyScheme(win.Theme, win._scheme)

	local changes = {}
	for k, newValue in pairs(win.Theme) do
		if old[k] ~= newValue then
			table.insert(changes, { key = k, old = old[k], new = newValue })
		end
	end
	if #changes == 0 then
		return
	end
	local props = { "BackgroundColor3", "TextColor3", "ScrollBarImageColor3", "PlaceholderColor3", "Color" }
	for _, d in ipairs(win.Gui:GetDescendants()) do
		local isPanel = d.Name == "TopBar" or d.Name == "Sidebar"
		for _, prop in ipairs(props) do
			local ok, value = pcall(function()
				return d[prop]
			end)
			if ok and value ~= nil then
				for _, change in ipairs(changes) do
					if value == change.old and ((change.key == "Panel") == (isPanel and prop == "BackgroundColor3")) then
						pcall(function()
							d[prop] = change.new
						end)
						break
					end
				end
			end
		end
	end
	if win._onRecolor then
		win:_onRecolor()
	end
end

-- Library:ChangeColor("SchemeColor" | "Background" | "Header" | "TextColor" | "ElementColor", Color3)
function Library.ChangeColor(self, key, color)
	local win = targetWindow(self)
	if not win or win._destroyed then
		return
	end
	if win._scheme[key] == nil then
		warn("[NovaUI] ChangeColor: unknown key '" .. tostring(key) .. "'")
		return
	end
	Library._recolor(win, { [key] = color })
end

function KavoTab:NewSection(name)
	local tab = self._tab
	tab._order = tab._order + 1
	local body = create("Frame", {
		Name = "SectionBody",
		LayoutOrder = tab._order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = tab.Page,
	}, { listLayout(8) })
	-- a tab-shaped host whose page is this section's body: elements land inside the section
	local host = setmetatable({ Window = tab.Window, Name = tab.Name, Page = body, _order = 0 }, Tab)
	return setmetatable({ _tab = host, _header = host:Section(name) }, Section)
end

function Section:UpdateSection(newTitle)
	self._header:Set(newTitle)
end

-- Optional last argument (NovaUI extra): { Hotkey = Enum.KeyCode.F | false, OnHotkeyChanged = fn }
local function kavoOpts(name, info, extra)
	local o = { Tooltip = tipFor(name, info) }
	if type(extra) == "table" then
		for k, v in pairs(extra) do
			o[k] = v
		end
	end
	return o
end

function Section:NewButton(name, info, callback, extra)
	local obj = self._tab:Button(name, callback, kavoOpts(name, info, extra))
	return {
		UpdateButton = function(_, newText)
			obj:SetText(newText)
		end,
		SetHotkey = function(_, key)
			return obj:SetHotkey(key)
		end,
		GetHotkey = function()
			return obj:GetHotkey()
		end,
	}
end

function Section:NewToggle(name, info, callback, extra)
	local obj = self._tab:Toggle(name, false, callback, kavoOpts(name, info, extra))
	return {
		SetHotkey = function(_, key)
			return obj:SetHotkey(key)
		end,
		GetHotkey = function()
			return obj:GetHotkey()
		end,
		-- UpdateToggle(newText [, isOn]) - text only if isOn is omitted
		UpdateToggle = function(_, newText, isOn)
			if newText ~= nil then
				obj:SetText(newText)
			end
			if isOn ~= nil then
				obj:Set(isOn == true, true)
			end
		end,
	}
end

-- Kavo argument order: (name, info, maxValue, minValue, callback)
function Section:NewSlider(name, info, maxValue, minValue, callback)
	minValue = tonumber(minValue) or 0
	local obj = self._tab:Slider(name, minValue, maxValue, minValue, callback, { Tooltip = tipFor(name, info) })
	return {
		UpdateSlider = function(_, newText, value)
			if newText ~= nil then
				obj:SetText(newText)
			end
			if value ~= nil then
				obj:Set(value, true)
			end
		end,
	}
end

function Section:NewLabel(text)
	local obj = self._tab:Label(text)
	return {
		UpdateLabel = function(_, newText)
			obj:Set(newText)
		end,
	}
end

function Section:NewTextBox(name, info, callback)
	self._tab:Input(name, "type here", callback, { Tooltip = tipFor(name, info) })
end

function Section:NewKeybind(name, info, key, callback)
	self._tab:Keybind(name, key, callback, { Tooltip = tipFor(name, info) })
end

function Section:NewDropdown(name, info, list, callback)
	return self._tab:Dropdown(name, list, callback, { Tooltip = tipFor(name, info) })
end

function Section:NewColorPicker(name, info, default, callback)
	self._tab:ColorPicker(name, default, callback, { Tooltip = tipFor(name, info) })
end

----------------------------------------------------------------------
-- Executor (UNC) check. Library.UNCTest() runs the executor functions NovaUI relies on, one by one,
-- and says for each: PASS, FAIL (exists but broken), MISSING or SKIP, with the reason in plain words.
-- A FAIL here is the executor's problem (its UNC implementation), never NovaUI's code.
-- Options: Quiet = true (no printing), Print = function (default print).
----------------------------------------------------------------------
function Library.UNCTest(options)
	options = options or {}
	local out = options.Print or print
	local results, counts, byName, created = {}, { PASS = 0, FAIL = 0, MISSING = 0, SKIP = 0 }, {}, {}
	local function add(name, status, note, optional)
		local r = { Name = name, Status = status, Note = note, Optional = optional == true }
		table.insert(results, r)
		byName[name] = r
		counts[status] = counts[status] + 1
		if options.Quiet ~= true then
			out("[NovaUI UNC] " .. status .. string.rep(" ", 8 - #status) .. name .. " - " .. note)
		end
	end
	-- returns "missing" | "error", raw, hint, usedName | "ok", value
	local function call(name, ...)
		local fn, used = uncFn(name)
		if not fn then
			return "missing"
		end
		local ok, v = pcall(fn, ...)
		if not ok then
			return "error", v, uncHint(v), used
		end
		return "ok", v, nil, used
	end
	local function failed(name, kind, raw, hint, used, optional)
		if kind == "missing" then
			add(name, "MISSING", "this executor has no '" .. name .. "' function" .. (optional and " (optional)" or ""), optional)
		else
			add(name, "FAIL", "executor function '" .. tostring(used or name) .. "' raised an error: " .. tostring(hint) .. ". Raw error: " .. tostring(raw), optional)
		end
	end
	local function baseName(path)
		return string.match(tostring(path), "([^/\\]+)$") or tostring(path)
	end

	-- plain presence / sanity checks
	do
		local kind, v, hint, used = call("getgenv")
		if kind == "ok" and type(v) == "table" then
			add("getgenv", "PASS", "returns the executor's global table")
		elseif kind == "ok" then
			add("getgenv", "FAIL", "getgenv() did not return a table (got " .. type(v) .. ")")
		else
			failed("getgenv", kind, v, hint, used)
		end
	end
	do
		local kind, v, hint, used = call("loadstring", "return 41 + 1")
		if kind == "ok" and type(v) == "function" then
			local okRun, value = pcall(v)
			if okRun and value == 42 then
				add("loadstring", "PASS", "compiles and runs a test chunk")
			else
				add("loadstring", "FAIL", "loadstring compiled a chunk but running it gave the wrong result")
			end
		elseif kind == "ok" then
			add("loadstring", "FAIL", "loadstring returned " .. type(v) .. " instead of a function (the executor may block loadstring)")
		else
			failed("loadstring", kind, v, hint, used)
		end
	end
	do
		local okGame, hasGet = pcall(function()
			return typeof(game.HttpGet) == "function"
		end)
		if okGame and hasGet then
			add("HttpGet", "PASS", "game:HttpGet exists (not called, so no network is used)")
		else
			add("HttpGet", "MISSING", "game:HttpGet is not available, so loadstring(game:HttpGet(url)) cannot work on this executor")
		end
	end
	do
		local kind = call("request")
		if kind == "missing" then
			add("request", "MISSING", "no request / http_request function (optional: NovaUI falls back to game:HttpGet)", true)
		else
			add("request", "PASS", "request / http_request exists (not called)", true)
		end
	end
	do
		local kind = call("setclipboard")
		if kind == "missing" then
			add("setclipboard", "MISSING", "no setclipboard / toclipboard (optional: only the key-link button needs it)", true)
		else
			add("setclipboard", "PASS", "setclipboard / toclipboard exists (not called, so your clipboard is untouched)", true)
		end
	end
	do
		local okHui, ui = pcall(function()
			return gethui and gethui()
		end)
		if okHui and ui then
			add("gethui", "PASS", "returns a hidden GUI container", true)
		else
			add("gethui", "MISSING", "no gethui (optional: NovaUI uses CoreGui or PlayerGui instead)", true)
		end
	end

	-- file system: folder, text, binary, listing
	local DIR = "NovaUI"
	local TXT, BIN, PNG, WEBM, MP4 = DIR .. "/_unc_test.txt", DIR .. "/_unc_test.bin", DIR .. "/_unc_test.png", DIR .. "/_unc_test.webm", DIR .. "/_unc_test.mp4"
	do
		local kind, v, hint, used = call("isfolder", DIR)
		local existed = kind == "ok" and v == true
		if kind ~= "ok" then
			failed("isfolder", kind, v, hint, used)
		end
		if existed then
			add("isfolder", "PASS", "sees the '" .. DIR .. "' folder")
			add("makefolder", "SKIP", "not needed: '" .. DIR .. "' already exists")
		else
			local mk, raw, mkHint, mkUsed = call("makefolder", DIR)
			if mk ~= "ok" then
				failed("makefolder", mk, raw, mkHint, mkUsed)
			else
				local again, there = call("isfolder", DIR)
				if again == "ok" and there == true then
					add("makefolder", "PASS", "created '" .. DIR .. "'")
					if kind == "ok" then
						add("isfolder", "PASS", "sees the folder makefolder just created")
					end
				elseif again == "ok" then
					add("makefolder", "FAIL", "makefolder ran without error but isfolder still says '" .. DIR .. "' does not exist (executor bug)")
				else
					add("makefolder", "PASS", "ran without error (isfolder is unavailable to confirm it)")
				end
			end
		end
	end

	local function put(path, data)
		local kind, raw, hint, used = call("writefile", path, data)
		if kind == "ok" then
			table.insert(created, path)
		end
		return kind, raw, hint, used
	end

	local textBody = "hello NovaUI"
	local wrote = false
	do
		local kind, raw, hint, used = put(TXT, textBody)
		if kind == "ok" then
			wrote = true
			add("writefile", "PASS", "wrote a text file into '" .. DIR .. "'")
		else
			failed("writefile", kind, raw, hint, used)
		end
	end
	if not wrote then
		add("isfile", "SKIP", "needs writefile to work first")
		add("readfile", "SKIP", "needs writefile to work first")
		add("readfile (binary)", "SKIP", "needs writefile to work first")
		add("listfiles", "SKIP", "needs writefile to work first")
	else
		do
			local kind, v, hint, used = call("isfile", TXT)
			if kind == "ok" and v == true then
				add("isfile", "PASS", "sees the file writefile created")
			elseif kind == "ok" then
				add("isfile", "FAIL", "isfile returned " .. tostring(v) .. " for a file writefile just created (executor bug)")
			else
				failed("isfile", kind, v, hint, used)
			end
		end
		do
			local kind, v, hint, used = call("readfile", TXT)
			if kind == "ok" and v == textBody then
				add("readfile", "PASS", "reads back exactly what was written")
			elseif kind == "ok" then
				add("readfile", "FAIL", "readfile returned different text than writefile stored (executor bug)")
			else
				failed("readfile", kind, v, hint, used)
			end
		end
		do
			local bytes = "\0\1\2\255\254\r\n\26\0" .. string.rep("\200", 64)
			local wk, raw, hint, used = put(BIN, bytes)
			if wk ~= "ok" then
				failed("readfile (binary)", wk, raw, hint, used)
			else
				local kind, v, rh, ru = call("readfile", BIN)
				if kind == "ok" and v == bytes then
					add("readfile (binary)", "PASS", "binary data survives a write and read (needed for images and videos)")
				elseif kind == "ok" then
					add("readfile (binary)", "FAIL", "binary data came back changed (" .. tostring(type(v) == "string" and #v or type(v)) .. " bytes instead of " .. #bytes .. "): the executor mangles non-text files")
				else
					failed("readfile (binary)", kind, v, rh, ru)
				end
			end
		end
		do
			local kind, v, hint, used = call("listfiles", DIR)
			if kind == "ok" and type(v) == "table" then
				local found = false
				for _, entry in ipairs(v) do
					if baseName(entry) == "_unc_test.txt" then
						found = true
					end
				end
				if found then
					add("listfiles", "PASS", "lists files in '" .. DIR .. "' (needed for the background picker)")
				else
					add("listfiles", "FAIL", "listfiles('" .. DIR .. "') did not include the file just written (executor bug)")
				end
			elseif kind == "ok" then
				add("listfiles", "FAIL", "listfiles returned " .. type(v) .. " instead of a table")
			else
				failed("listfiles", kind, v, hint, used)
			end
		end
	end

	-- getcustomasset per file type (videos and images from the folder go through this)
	local function assetCheck(label, path, bytes, optional)
		local name = "getcustomasset (" .. label .. ")"
		local wk = put(path, bytes)
		if wk ~= "ok" then
			add(name, "SKIP", "needs writefile to work first", optional)
			return
		end
		local kind, v, h, u = call("getcustomasset", path)
		if kind == "ok" and type(v) == "string" and v ~= "" then
			add(name, "PASS", "turns a ." .. label .. " file into an asset id", optional)
		elseif kind == "ok" then
			add(name, "FAIL", "getcustomasset returned " .. (type(v) == "string" and "an empty string" or type(v)) .. " for a ." .. label .. " file (executor bug)", optional)
		else
			failed(name, kind, v, h, u, optional)
		end
	end
	assetCheck("png", PNG, "\137PNG\r\n\26\n" .. string.rep("\0", 16), false)
	assetCheck("webm", WEBM, "\26\69\223\163" .. string.rep("\0", 16), false)
	assetCheck("mp4", MP4, "\0\0\0\24ftypmp42" .. string.rep("\0", 16), true)

	-- clean up (optional function; leftovers are named _unc_test.*)
	if #created > 0 then
		local badKind, badRaw, badHint, badUsed
		for _, path in ipairs(created) do
			local kind, raw, hint, used = call("delfile", path)
			if kind ~= "ok" and not badKind then
				badKind, badRaw, badHint, badUsed = kind, raw, hint, used
			end
		end
		if badKind then
			if badKind == "missing" then
				add("delfile", "MISSING", "no delfile (optional): test files named _unc_test.* were left in '" .. DIR .. "', delete them by hand", true)
			else
				failed("delfile", badKind, badRaw, badHint, badUsed, true)
			end
		else
			local kind, there = call("isfile", created[1])
			if kind == "ok" and there == true then
				add("delfile", "FAIL", "delfile ran without error but the file is still there (executor bug)", true)
			else
				add("delfile", "PASS", "removed the test files", true)
			end
		end
	end

	-- what each NovaUI feature needs, in plain words
	local features = {}
	local function feature(title, needs, fallback)
		local problems = {}
		for _, name in ipairs(needs) do
			local r = byName[name]
			if r and (r.Status == "FAIL" or r.Status == "MISSING" or (r.Status == "SKIP" and string.sub(r.Note, 1, 5) == "needs")) then
				table.insert(problems, name .. " (" .. string.lower(r.Status) .. ")")
			end
		end
		local entry = { Name = title, Ok = #problems == 0, Problems = problems }
		entry.Note = entry.Ok and "works" or ("limited by your executor: " .. table.concat(problems, ", ") .. ". " .. fallback)
		table.insert(features, entry)
		if options.Quiet ~= true then
			out("[NovaUI UNC] feature  " .. title .. ": " .. entry.Note)
		end
	end
	feature("Background presets saved to disk", { "writefile", "readfile", "isfile" }, "Background presets still work for this session only, and cannot auto-load next time.")
	feature("Backgrounds from the NovaUI/backgrounds folder", { "getcustomasset (webm)", "getcustomasset (png)", "isfile" }, "You can still use asset ids or Pixels backgrounds.")
	feature("File picker for the folder", { "listfiles" }, "Type the file name in the Source box instead.")
	feature("Images / videos from links", { "writefile", "getcustomasset (png)" }, "Use asset ids or the folder instead.")

	local problemNames = {}
	for _, r in ipairs(results) do
		if r.Status == "FAIL" or (r.Status == "MISSING" and not r.Optional) then
			table.insert(problemNames, r.Name .. " (" .. string.lower(r.Status) .. ")")
		end
	end
	local summary = "UNC check: " .. counts.PASS .. " passed, " .. counts.FAIL .. " failed, " .. counts.MISSING .. " missing. "
	if #problemNames > 0 then
		summary = summary .. "Executor problems: " .. table.concat(problemNames, ", ") .. ". These come from your executor, not NovaUI."
	else
		summary = summary .. "Everything NovaUI needs works."
	end
	if options.Quiet ~= true then
		out("[NovaUI UNC] " .. summary)
	end
	return { Results = results, Counts = counts, Features = features, Summary = summary, Healthy = #problemNames == 0 }
end

-- Problems NovaUI hit while calling executor functions this session (one entry per function and cause).
function Library.GetExecutorIssues()
	local copy = {}
	for i, issue in ipairs(uncIssues) do
		copy[i] = issue
	end
	return copy
end

-- Library.HashKey("hello123") -> "nv1$..." string for KeySystem.KeyHash, so the plain key never has to sit in a script.
function Library.HashKey(key, salt)
	return hashKey(key, salt)
end

return Library
