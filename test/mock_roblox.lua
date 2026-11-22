-- Minimal, STRICT Roblox API mock so NovaUI can be tested on plain Lua 5.2 (which has bit32 like Roblox).
-- Strict on purpose: unknown properties, wrong value types and properties that belong to another class
-- (e.g. GroupTransparency on a Frame) raise errors, the way Roblox does.
-- Time is virtual: nothing moves until M.advance(dt), which runs task.wait/delay threads and tweens.

local M = {}
local unpack = table.unpack or unpack

----------------------------------------------------------------------
-- value types
----------------------------------------------------------------------
local function typed(tag, mt, fields)
	fields.__t = tag
	return setmetatable(fields, mt)
end

local function near(a, b)
	return math.abs(a - b) < 1e-9
end

local C3 = {}
C3.__index = C3
C3.__eq = function(a, b)
	return rawget(a, "__t") == "Color3" and rawget(b, "__t") == "Color3" and near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B)
end
local Color3 = {}
function Color3.new(r, g, b)
	return typed("Color3", C3, { R = r or 0, G = g or 0, B = b or 0 })
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

local UD = {}
UD.__index = UD
UD.__eq = function(a, b)
	return rawget(a, "__t") == "UDim" and rawget(b, "__t") == "UDim" and near(a.Scale, b.Scale) and near(a.Offset, b.Offset)
end
local UDim = {}
function UDim.new(s, o)
	return typed("UDim", UD, { Scale = s or 0, Offset = o or 0 })
end

local UD2 = {}
UD2.__index = UD2
UD2.__eq = function(a, b)
	return rawget(a, "__t") == "UDim2" and rawget(b, "__t") == "UDim2" and a.X == b.X and a.Y == b.Y
end
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then
		return typed("UDim2", UD2, { X = xs, Y = xo })
	end
	return typed("UDim2", UD2, { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) })
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end

local V2 = {}
V2.__index = V2
V2.__eq = function(a, b)
	return rawget(a, "__t") == "Vector2" and rawget(b, "__t") == "Vector2" and near(a.X, b.X) and near(a.Y, b.Y)
end
V2.__add = function(a, b)
	return typed("Vector2", V2, { X = a.X + b.X, Y = a.Y + b.Y })
end
V2.__sub = function(a, b)
	return typed("Vector2", V2, { X = a.X - b.X, Y = a.Y - b.Y })
end
local Vector2 = {}
function Vector2.new(x, y)
	return typed("Vector2", V2, { X = x or 0, Y = y or 0 })
end

local plain = {}
plain.__index = plain
local TweenInfo = {}
function TweenInfo.new(time, style, dir)
	return typed("TweenInfo", plain, { Time = time or 1, EasingStyle = style, EasingDirection = dir })
end
local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, v)
	return typed("ColorSequenceKeypoint", plain, { Time = t, Value = v })
end
local ColorSequence = {}
function ColorSequence.new(a, b)
	if b ~= nil then
		return typed("ColorSequence", plain, {
			Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) },
		})
	end
	if type(a) == "table" and a.__t == "Color3" then
		return typed("ColorSequence", plain, {
			Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, a) },
		})
	end
	return typed("ColorSequence", plain, { Keypoints = a })
end
local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, v)
	return typed("NumberSequenceKeypoint", plain, { Time = t, Value = v })
end
local NumberSequence = {}
function NumberSequence.new(a, b)
	if type(a) == "table" then
		return typed("NumberSequence", plain, { Keypoints = a })
	end
	return typed("NumberSequence", plain, {
		Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) },
	})
end

local function typeofValue(v)
	local t = type(v)
	if t == "table" then
		return rawget(v, "__t") or "table"
	end
	return t
end

----------------------------------------------------------------------
-- Enum (auto-created, identity-cached items)
----------------------------------------------------------------------
local Enum = setmetatable({}, {
	__index = function(t, enumName)
		local e
		e = setmetatable({}, {
			__index = function(t2, itemName)
				local item = { Name = itemName, EnumType = e, __t = "EnumItem" }
				rawset(t2, itemName, item)
				return item
			end,
		})
		rawset(t, enumName, e)
		return e
	end,
})

----------------------------------------------------------------------
-- signals
----------------------------------------------------------------------
M.errors = {}
M.warnings = {}

local clockNow = 0
local threads, seq = {}, 0
local activeTweens = {}

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(M.errors, tostring(err))
	end
	return ok
end

local function schedule(co, at)
	seq = seq + 1
	table.insert(threads, { time = at, seq = seq, co = co })
end

local task = {}
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.delay(t, fn, ...)
	local args = { ... }
	local co = coroutine.create(function()
		fn(unpack(args))
	end)
	schedule(co, clockNow + (t or 0))
	return co
end
function task.defer(fn, ...)
	return task.delay(0, fn, ...)
end
function task.wait(t)
	local co, isMain = coroutine.running()
	if isMain or not co then
		error("task.wait on the main test thread; run the code inside task.spawn")
	end
	t = t or 0.03
	schedule(co, clockNow + t)
	coroutine.yield()
	return t
end
function task.cancel(co)
	for i, th in ipairs(threads) do
		if th.co == co then
			table.remove(threads, i)
			return
		end
	end
end

local function newSignal()
	local sig = { _conns = {} }
	function sig:Connect(fn)
		local conn = { Connected = true, _fn = fn }
		function conn:Disconnect()
			self.Connected = false
		end
		table.insert(self._conns, conn)
		return conn
	end
	function sig:Fire(...)
		local live = {}
		for _, c in ipairs(self._conns) do
			if c.Connected then
				table.insert(live, c)
			end
		end
		self._conns = live
		local args = { ... }
		for _, c in ipairs({ unpack(live) }) do
			if c.Connected then
				task.spawn(function()
					c._fn(unpack(args))
				end)
			end
		end
	end
	function sig:Count()
		local n = 0
		for _, c in ipairs(self._conns) do
			if c.Connected then
				n = n + 1
			end
		end
		return n
	end
	return sig
end

----------------------------------------------------------------------
-- tweens (linear in time; easing style is ignored)
----------------------------------------------------------------------
local function lerp(a, b, t)
	return a + (b - a) * t
end

local function interpolate(a, b, t)
	local tag = typeofValue(a)
	if tag == "number" then
		return lerp(a, b, t)
	elseif tag == "Color3" then
		return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
	elseif tag == "UDim" then
		return UDim.new(lerp(a.Scale, b.Scale, t), lerp(a.Offset, b.Offset, t))
	elseif tag == "UDim2" then
		return UDim2.new(
			lerp(a.X.Scale, b.X.Scale, t), lerp(a.X.Offset, b.X.Offset, t),
			lerp(a.Y.Scale, b.Y.Scale, t), lerp(a.Y.Offset, b.Y.Offset, t)
		)
	elseif tag == "Vector2" then
		return Vector2.new(lerp(a.X, b.X, t), lerp(a.Y, b.Y, t))
	end
	return t >= 1 and b or a
end

local function stepTweens(now)
	local keep = {}
	for _, tw in ipairs(activeTweens) do
		if tw.state == "Playing" then
			local alpha = tw.info.Time <= 0 and 1 or math.min(1, (now - tw.start) / tw.info.Time)
			for prop, goal in pairs(tw.props) do
				tw.inst[prop] = interpolate(tw.from[prop], goal, alpha)
			end
			if alpha >= 1 then
				tw.state = "Completed"
				tw.Completed:Fire()
			else
				table.insert(keep, tw)
			end
		end
	end
	activeTweens = keep
end

local TweenService = {}
function TweenService:Create(inst, info, props)
	local tw = { inst = inst, info = info, props = props, state = "Created", Completed = newSignal() }
	function tw:Play()
		self.start = clockNow
		self.from = {}
		for prop in pairs(self.props) do
			self.from[prop] = self.inst[prop]
		end
		self.state = "Playing"
		table.insert(activeTweens, self)
		stepTweens(clockNow)
	end
	function tw:Cancel()
		self.state = "Cancelled"
	end
	M.tweensCreated = (M.tweensCreated or 0) + 1
	return tw
end

function M.advance(dt)
	local target = clockNow + dt
	while true do
		local best, bi
		for i, th in ipairs(threads) do
			if th.time <= target and (not best or th.time < best.time or (th.time == best.time and th.seq < best.seq)) then
				best, bi = th, i
			end
		end
		if not best then
			break
		end
		table.remove(threads, bi)
		if best.time > clockNow then
			clockNow = best.time
			stepTweens(clockNow)
		end
		resume(best.co)
	end
	clockNow = target
	stepTweens(clockNow)
end

function M.now()
	return clockNow
end

function M.pending()
	return #threads
end

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------
local PROP_TYPES = {
	Position = "UDim2", Size = "UDim2", AnchorPoint = "Vector2", CanvasSize = "UDim2",
	BackgroundColor3 = "Color3", TextColor3 = "Color3", PlaceholderColor3 = "Color3",
	ScrollBarImageColor3 = "Color3", Color = nil,
	BackgroundTransparency = "number", GroupTransparency = "number", Transparency = nil,
	TextTransparency = "number", BorderSizePixel = "number", ZIndex = "number", LayoutOrder = "number",
	Visible = "boolean", ClipsDescendants = "boolean", AutoButtonColor = "boolean", TextWrapped = "boolean",
	ClearTextOnFocus = "boolean", ResetOnSpawn = "boolean", IgnoreGuiInset = "boolean",
	Image = "string", ImageTransparency = "number", Text = "string", PlaceholderText = "string", Name = "string",
	TextSize = "number", Scale = "number", Thickness = "number", ScrollBarThickness = "number",
	DisplayOrder = "number", Rotation = "number",
	AbsolutePosition = "Vector2", AbsoluteSize = "Vector2", ViewportSize = "Vector2",
	CornerRadius = "UDim", Padding = "UDim",
	PaddingLeft = "UDim", PaddingTop = "UDim", PaddingRight = "UDim", PaddingBottom = "UDim",
}

local function set(list)
	local s = {}
	for _, k in ipairs(list) do
		s[k] = true
	end
	return s
end

local GUI_PROPS = {
	"Name", "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
	"Visible", "ZIndex", "LayoutOrder", "ClipsDescendants", "AutomaticSize", "AbsolutePosition", "AbsoluteSize",
	"Active", "Rotation",
}
local TEXT_PROPS = {
	"Text", "TextColor3", "TextSize", "Font", "TextXAlignment", "TextYAlignment", "TextWrapped", "TextTruncate",
	"TextTransparency", "RichText",
}
local function join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do
			table.insert(out, v)
		end
	end
	return out
end

local GUI_SIGNALS = { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved" }
local BUTTON_SIGNALS = join(GUI_SIGNALS, { "MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "Activated" })
local BOX_SIGNALS = join(GUI_SIGNALS, { "Focused", "FocusLost" })

local function guiDefaults()
	return {
		Visible = true, Position = UDim2.new(), Size = UDim2.new(0, 100, 0, 100), AnchorPoint = Vector2.new(),
		BackgroundColor3 = Color3.new(0.64, 0.64, 0.64), BackgroundTransparency = 0, BorderSizePixel = 1,
		ZIndex = 1, LayoutOrder = 0, ClipsDescendants = false, AutomaticSize = Enum.AutomaticSize.None,
		AbsolutePosition = Vector2.new(), AbsoluteSize = Vector2.new(), Active = false, Rotation = 0,
	}
end
local function textDefaults(d)
	d.Text = ""
	d.TextColor3 = Color3.new(0, 0, 0)
	d.TextSize = 14
	d.TextWrapped = false
	d.TextTransparency = 0
	return d
end

local CLASSES = {
	Frame = { props = set(GUI_PROPS), signals = set(GUI_SIGNALS), defaults = guiDefaults },
	CanvasGroup = {
		props = set(join(GUI_PROPS, { "GroupTransparency", "GroupColor3" })), signals = set(GUI_SIGNALS),
		defaults = function()
			local d = guiDefaults()
			d.GroupTransparency = 0
			return d
		end,
	},
	TextLabel = {
		props = set(join(GUI_PROPS, TEXT_PROPS)), signals = set(GUI_SIGNALS),
		defaults = function()
			return textDefaults(guiDefaults())
		end,
	},
	TextButton = {
		props = set(join(GUI_PROPS, TEXT_PROPS, { "AutoButtonColor" })), signals = set(BUTTON_SIGNALS),
		defaults = function()
			local d = textDefaults(guiDefaults())
			d.AutoButtonColor = true
			return d
		end,
	},
	ImageLabel = {
		props = set(join(GUI_PROPS, { "Image", "ImageTransparency", "ImageColor3", "ScaleType" })), signals = set(GUI_SIGNALS),
		defaults = function()
			local d = guiDefaults()
			d.Image = ""
			d.ImageTransparency = 0
			return d
		end,
	},
	TextBox = {
		props = set(join(GUI_PROPS, TEXT_PROPS, { "PlaceholderText", "PlaceholderColor3", "ClearTextOnFocus", "TextEditable", "MultiLine" })),
		signals = set(BOX_SIGNALS),
		defaults = function()
			local d = textDefaults(guiDefaults())
			d.PlaceholderText = ""
			d.PlaceholderColor3 = Color3.new(0.7, 0.7, 0.7)
			d.ClearTextOnFocus = true
			return d
		end,
	},
	ScrollingFrame = {
		props = set(join(GUI_PROPS, { "ScrollBarThickness", "ScrollBarImageColor3", "CanvasSize", "AutomaticCanvasSize", "CanvasPosition", "ScrollingDirection" })),
		signals = set(GUI_SIGNALS),
		defaults = function()
			local d = guiDefaults()
			d.CanvasSize = UDim2.new(0, 0, 2, 0)
			d.ScrollBarThickness = 12
			d.CanvasPosition = Vector2.new()
			return d
		end,
	},
	ScreenGui = {
		props = set({ "Name", "ResetOnSpawn", "IgnoreGuiInset", "ZIndexBehavior", "DisplayOrder", "Enabled" }), signals = {},
		defaults = function()
			return { ResetOnSpawn = true, IgnoreGuiInset = false, DisplayOrder = 0, Enabled = true }
		end,
	},
	UICorner = { props = set({ "Name", "CornerRadius" }), signals = {}, defaults = function() return { CornerRadius = UDim.new(0, 8) } end },
	UIStroke = {
		props = set({ "Name", "Color", "Transparency", "Thickness", "ApplyStrokeMode", "LineJoinMode" }), signals = {},
		defaults = function() return { Color = Color3.new(0, 0, 0), Transparency = 0, Thickness = 1 } end,
	},
	UIPadding = {
		props = set({ "Name", "PaddingLeft", "PaddingTop", "PaddingRight", "PaddingBottom" }), signals = {},
		defaults = function()
			return { PaddingLeft = UDim.new(), PaddingTop = UDim.new(), PaddingRight = UDim.new(), PaddingBottom = UDim.new() }
		end,
	},
	UIListLayout = {
		props = set({ "Name", "Padding", "SortOrder", "VerticalAlignment", "HorizontalAlignment", "FillDirection" }), signals = {},
		defaults = function() return { Padding = UDim.new() } end,
	},
	UIScale = { props = set({ "Name", "Scale" }), signals = {}, defaults = function() return { Scale = 1 } end },
	UIGradient = {
		props = set({ "Name", "Color", "Transparency", "Rotation", "Offset" }), signals = {},
		defaults = function() return { Color = ColorSequence.new(Color3.new(1, 1, 1)), Rotation = 0 } end,
	},
	Folder = { props = set({ "Name" }), signals = {}, defaults = function() return {} end },
	Camera = { props = set({ "Name", "ViewportSize" }), signals = {}, defaults = function() return { ViewportSize = Vector2.new(1280, 720) } end },
}

local InstMT = {}
local methods = {}

local function removeChild(parent, child)
	for i, c in ipairs(parent._children) do
		if c == child then
			table.remove(parent._children, i)
			return
		end
	end
end

local function signalOf(obj, name)
	local s = obj._signals[name]
	if not s then
		s = newSignal()
		obj._signals[name] = s
	end
	return s
end

local function setParent(obj, parent)
	local old = rawget(obj, "_parent")
	if old then
		removeChild(old, obj)
	end
	rawset(obj, "_parent", parent)
	if parent then
		table.insert(parent._children, obj)
		signalOf(parent, "ChildAdded"):Fire(obj)
	end
end

function methods.Destroy(self)
	if self._destroyed then
		return
	end
	self._destroyed = true
	signalOf(self, "Destroying"):Fire()
	for _, child in ipairs({ unpack(self._children) }) do
		child:Destroy()
	end
	setParent(self, nil)
	for _, sig in pairs(self._signals) do
		for _, c in ipairs(sig._conns) do
			c.Connected = false
		end
	end
end
function methods.GetChildren(self)
	return { unpack(self._children) }
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, c in ipairs(node._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(self._children) do
		if c._props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(self._children) do
			local found = methods.FindFirstChild(c, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	return methods.FindFirstChild(self, name)
end
function methods.IsA(self, className)
	return self._class == className
end
function methods.IsDescendantOf(self, other)
	local p = rawget(self, "_parent")
	while p do
		if p == other then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end
function methods.GetPropertyChangedSignal(self, prop)
	return signalOf(self, "Changed:" .. prop)
end
function methods.CaptureFocus(self)
	self._focused = true
	signalOf(self, "Focused"):Fire()
end
function methods.ReleaseFocus(self, submitted)
	if self._focused then
		self._focused = false
		signalOf(self, "FocusLost"):Fire(submitted == true)
	end
end

InstMT.__index = function(self, key)
	local def = CLASSES[rawget(self, "_class")]
	if methods[key] then
		return methods[key]
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "ClassName" then
		return rawget(self, "_class")
	end
	if def.signals[key] or key == "Destroying" or key == "ChildAdded" then
		return signalOf(self, key)
	end
	local value = self._props[key]
	if value ~= nil then
		return value
	end
	if def.props[key] then
		return nil
	end
	local child = methods.FindFirstChild(self, key)
	if child then
		return child
	end
	error(tostring(key) .. " is not a valid member of " .. rawget(self, "_class"), 2)
end

InstMT.__newindex = function(self, key, value)
	local def = CLASSES[rawget(self, "_class")]
	if key == "Parent" then
		setParent(self, value)
		return
	end
	if not def.props[key] then
		error(tostring(key) .. " is not a valid member of " .. rawget(self, "_class") .. " (cannot set)", 2)
	end
	if value == nil then
		error("cannot set " .. key .. " to nil", 2)
	end
	local expected = PROP_TYPES[key]
	if expected and typeofValue(value) ~= expected then
		error(key .. " expects " .. expected .. ", got " .. typeofValue(value), 2)
	end
	if key == "Transparency" or key == "Scale" then
		if type(value) ~= "number" and typeofValue(value) ~= "NumberSequence" then
			error(key .. " expects number, got " .. typeofValue(value), 2)
		end
	end
	if key == "Color" and typeofValue(value) ~= "Color3" and typeofValue(value) ~= "ColorSequence" then
		error("Color expects Color3 or ColorSequence, got " .. typeofValue(value), 2)
	end
	local old = self._props[key]
	self._props[key] = value
	if old ~= value then
		local sig = self._signals["Changed:" .. key]
		if sig then
			sig:Fire()
		end
	end
end

local Instance = {}
function Instance.new(className)
	local def = CLASSES[className]
	if not def then
		error("Unable to create an Instance of type '" .. tostring(className) .. "'")
	end
	local obj = { _class = className, _props = def.defaults(), _children = {}, _signals = {}, _destroyed = false }
	obj._props.Name = className
	return setmetatable(obj, InstMT)
end

----------------------------------------------------------------------
-- services + globals
----------------------------------------------------------------------
function M.input(kind, key, x, y)
	return {
		UserInputType = Enum.UserInputType[kind],
		KeyCode = key and Enum.KeyCode[key] or Enum.KeyCode.Unknown,
		Position = { X = x or 0, Y = y or 0, Z = 0 },
	}
end

function M.reset()
	clockNow = 0
	threads, seq, activeTweens = {}, 0, {}
	M.errors, M.warnings = {}, {}
	M.tweensCreated = 0
	M.genv = {}
	M.focused = nil

	local camera = Instance.new("Camera")
	local services = {
		TweenService = TweenService,
		UserInputService = {
			InputBegan = newSignal(), InputChanged = newSignal(), InputEnded = newSignal(),
			GetFocusedTextBox = function() return M.focused end,
		},
		Workspace = { CurrentCamera = camera },
		RunService = { RenderStepped = newSignal(), Heartbeat = newSignal() },
		Players = nil,
		CoreGui = Instance.new("Folder"),
	}
	local playerGui = Instance.new("Folder")
	services.Players = {
		LocalPlayer = {
			PlayerGui = playerGui,
			WaitForChild = function(self, name)
				return self.PlayerGui
			end,
		},
	}
	M.services = services
	M.camera = camera
	M.playerGui = playerGui
	M.game = {
		GetService = function(_, name)
			local s = services[name]
			if not s then
				error("mock: service " .. tostring(name) .. " not provided")
			end
			return s
		end,
		HttpGet = function()
			error("mock: HttpGet not available")
		end,
	}
	_G.game = M.game
	_G.getgenv = function()
		return M.genv
	end
	_G.gethui = nil
	_G.setclipboard = nil
	_G.toclipboard = nil
end

function M.install()
	_G.Enum = Enum
	_G.Instance = Instance
	_G.Color3 = Color3
	_G.UDim = UDim
	_G.UDim2 = UDim2
	_G.Vector2 = Vector2
	_G.TweenInfo = TweenInfo
	_G.ColorSequence = ColorSequence
	_G.ColorSequenceKeypoint = ColorSequenceKeypoint
	_G.NumberSequence = NumberSequence
	_G.NumberSequenceKeypoint = NumberSequenceKeypoint
	_G.task = task
	_G.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(M.warnings, table.concat(parts, " "))
	end
	_G.typeof = typeofValue
	os.clock = function()
		return clockNow
	end
	M.reset()
end

M.Enum = Enum
M.Color3 = Color3
M.UDim2 = UDim2
M.Vector2 = Vector2
M.Instance = Instance
M.typeof = typeofValue

return M
