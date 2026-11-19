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
]==]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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

local FONT_REGULAR = Enum.Font.Gotham
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local TOPBAR_H = 44
local SIDEBAR_W = 150

local STYLE_QUAD = Enum.EasingStyle.Quad
local STYLE_QUART = Enum.EasingStyle.Quart
local STYLE_BACK = Enum.EasingStyle.Back
local DIR_OUT = Enum.EasingDirection.Out
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

function Library:_updateScale()
	local vp = viewport()
	local s = math.min(1, (vp.X - 24) / self._size.X, (vp.Y - 24) / self._size.Y)
	self._uiScale.Scale = math.max(s, 0.4)
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

function Library:_makeDraggable(handle, target)
	local dragging = false
	local dragInput = nil
	local startX, startY, startPos = 0, 0, nil

	self:_connect(handle.InputBegan, function(input)
		if isPress(input) then
			dragging = true
			dragInput = input
			startX, startY = input.Position.X, input.Position.Y
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
		-- keep the window's centre on screen so it can never be lost
		local cx = clamp(vp.X * startPos.X.Scale + startPos.X.Offset + dx, 0, vp.X)
		local cy = clamp(vp.Y * startPos.Y.Scale + startPos.Y.Offset + dy, 0, vp.Y)
		target.Position = UDim2.new(startPos.X.Scale, cx - vp.X * startPos.X.Scale, startPos.Y.Scale, cy - vp.Y * startPos.Y.Scale)
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if not dragging then
			return
		end
		if input == dragInput or (input.UserInputType == Enum.UserInputType.MouseButton1 and dragInput.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
		end
	end)
end

function Library:_expand()
	if self._destroyed then
		return
	end
	local main = self._main
	self._token = (self._token or 0) + 1
	main.Visible = true
	self.Visible = true
	main.Size = UDim2.fromOffset(self._size.X * 0.7, TOPBAR_H)
	local height = self.Minimized and TOPBAR_H or self._size.Y
	tween(main, 0.45, { Size = UDim2.fromOffset(self._size.X, height) }, STYLE_BACK)
end

function Library:_collapse()
	if self._destroyed then
		return
	end
	self._token = (self._token or 0) + 1
	local token = self._token
	self.Visible = false
	self:_hideTip()
	tween(self._main, 0.2, { Size = UDim2.fromOffset(self._size.X * 0.7, 0) })
	task.delay(0.2, function()
		if not self._destroyed and self._token == token then
			self._main.Visible = false
		end
	end)
end

function Library:SetVisible(visible)
	if self._destroyed or not self._opened then
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
end

function Library:_buildLoader(options)
	local theme = self.Theme
	local card = create("CanvasGroup", {
		Name = "Loader",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 196),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		Parent = self.Gui,
	}, { corner(16), stroke(theme.Stroke, 0.9, 1) })
	create("UIScale", { Scale = 1, Parent = card })

	textLabel({
		Name = "Title",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 24),
		Text = options.Title or "NovaUI",
		Font = FONT_BOLD,
		TextSize = 20,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})
	textLabel({
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 18),
		Text = options.Subtitle or "Press enter to continue",
		TextSize = 13,
		Font = FONT_REGULAR,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})

	local buttonHolder = create("Frame", {
		Name = "EnterHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(240, 42),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local enterBtn, setText = STYLES.Glow(self, buttonHolder, "Enter")

	local barBack = create("Frame", {
		Name = "BarBack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 152),
		Size = UDim2.fromOffset(240, 4),
		BackgroundColor3 = theme.Off,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = card,
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
		Position = UDim2.fromOffset(0, 162),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		TextSize = 12,
		Font = FONT_REGULAR,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})

	local entering = false
	self:_connect(enterBtn.Activated, function()
		if entering then
			return
		end
		entering = true
		setText("Loading...")
		barBack.BackgroundTransparency = 0
		tween(barFill, 1.65, { Size = UDim2.fromScale(1, 1) }, STYLE_QUAD, DIR_INOUT)
		task.spawn(function()
			local steps = { "Loading modules", "Building interface", "Almost ready" }
			for _, step in ipairs(steps) do
				if self._destroyed then
					return
				end
				status.Text = step
				task.wait(0.55)
			end
			if self._destroyed then
				return
			end
			tween(card, 0.25, { GroupTransparency = 1 })
			task.wait(0.25)
			if self._destroyed then
				return
			end
			card.Visible = false
			self._opened = true
			self:_expand()
			safe(options.OnEnter, self)
		end)
	end)

	return card
end

function Library.new(options)
	options = options or {}
	local self = setmetatable({}, Library)

	self.Theme = {}
	for key, value in pairs(DEFAULT_THEME) do
		self.Theme[key] = value
	end
	if options.Accent then
		self.Theme.Accent = options.Accent
	end
	local theme = self.Theme

	self._conns = {}
	self.Tabs = {}
	self._tabsByName = {}
	self._size = options.Size or Vector2.new(580, 380)
	self._destroyed = false
	self._opened = false
	self.Visible = false
	self.Minimized = false

	local parent = options.Parent
	if not parent then
		local player = Players.LocalPlayer
		parent = player and player:WaitForChild("PlayerGui")
	end

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
		Size = UDim2.new(1, -140, 1, 0),
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
			Position = UDim2.new(1, -84, 0.5, 0),
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
	self._minButton = windowButton("Minimize", "–", -44, theme.Text)
	local closeButton = windowButton("Close", "×", -10, Color3.fromRGB(255, 95, 110))
	self:_connect(self._minButton.Activated, function()
		self:SetMinimized(not self.Minimized)
	end)
	self:_connect(closeButton.Activated, function()
		self:Destroy()
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
	}, { listLayout(4), padding(8, 10, 8, 10) })
	self._content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_W, 0),
		Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = body,
	})

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
	self:_connect(UserInputService.InputBegan, function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == toggleKey then
			self:ToggleVisible()
		end
	end)

	if options.Loader == false then
		self._opened = true
		self:_expand()
		safe(options.OnEnter, self)
	else
		self._loader = self:_buildLoader(options)
	end

	return self
end

Library.CreateWindow = Library.new

function Library:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
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

local function styleTab(tab, selected)
	local theme = tab.Window.Theme
	tween(tab._button, 0.15, {
		BackgroundTransparency = selected and 0 or 1,
		TextColor3 = selected and theme.Text or theme.Muted,
	})
	tween(tab._bar, 0.15, { BackgroundTransparency = selected and 0 or 1 })
end

function Library:Tab(name, icon)
	local theme = self.Theme
	name = tostring(name or "Tab")
	local tab = setmetatable({ Window = self, Name = name, _order = 0 }, Tab)

	tab._button = create("TextButton", {
		Name = "Tab_" .. name,
		LayoutOrder = #self.Tabs + 1,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = theme.Element,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = FONT_MEDIUM,
		TextSize = 14,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = (icon and (icon .. "  ") or "") .. name,
		Parent = self._tabList,
	}, { corner(8), padding(16, 0, 8, 0) })
	tab._bar = create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -12, 0.5, 0),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = tab._button,
	}, { pillCorner() })

	tab.Page = create("ScrollingFrame", {
		Name = "Page_" .. name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self._content,
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

function Library:SelectTab(target)
	local tab = target
	if type(target) == "string" then
		tab = self._tabsByName[target]
	end
	if not tab or tab.Window ~= self then
		warn("[NovaUI] SelectTab: unknown tab " .. tostring(target))
		return
	end
	self:_hideTip()
	for _, other in ipairs(self.Tabs) do
		local isSelected = other == tab
		other.Page.Visible = isSelected
		styleTab(other, isSelected)
	end
	self._selected = tab
	tab.Page.Position = UDim2.fromOffset(0, 10)
	tween(tab.Page, 0.2, { Position = UDim2.fromOffset(0, 0) })
end

----------------------------------------------------------------------
-- Elements
----------------------------------------------------------------------

function Tab:_row(height, name)
	self._order = self._order + 1
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

-- opts: string style, or { Style, Icon, Tooltip }
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
	local clickable, setText = builder(win, row, tostring(text), opts)

	win:_connect(clickable.Activated, function()
		safe(callback)
	end)
	win:_attachTip(clickable, opts.Tooltip)

	return {
		Instance = row,
		SetText = function(_, newText)
			setText(tostring(newText))
		end,
	}
end

function Tab:Toggle(text, default, callback, opts)
	opts = opts or {}
	local win = self.Window
	local theme = win.Theme
	local state = default == true
	local row = self:_row(40, "Toggle")
	local btn = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = row,
	}, { corner(8), stroke(theme.Stroke, 0.93, 1) })
	textLabel({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Text = tostring(text),
		TextColor3 = theme.Text,
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
			safe(callback, state)
		end
	end

	function obj.Get()
		return state
	end

	win:_connect(btn.Activated, function()
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
	textLabel({
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
			safe(callback, value)
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
			safe(callback, box.Text)
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
-- Kavo-style API (drop-in shape for scripts written against Kavo UI)
--   local Library = loadstring(...)()
--   local Window  = Library.CreateLib("TITLE", "DarkTheme")
--   local Tab     = Window:NewTab("Main")
--   local Section = Tab:NewSection("Section")
--   Section:NewButton("Text", "Info", function() end)
----------------------------------------------------------------------

local KAVO_THEMES = {
	DarkTheme = Color3.fromRGB(150, 120, 255),
	LightTheme = Color3.fromRGB(70, 130, 255),
	GrapeTheme = Color3.fromRGB(170, 70, 220),
	BloodTheme = Color3.fromRGB(215, 45, 55),
	Ocean = Color3.fromRGB(40, 160, 225),
	Midnight = Color3.fromRGB(95, 85, 215),
	Sentinel = Color3.fromRGB(235, 90, 90),
	Synapse = Color3.fromRGB(70, 205, 165),
}

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

-- CreateLib(title, theme [, options]) - theme is a Kavo theme name or a Color3 accent.
function Library.CreateLib(title, theme, options)
	local opts = {}
	if type(options) == "table" then
		for k, v in pairs(options) do
			opts[k] = v
		end
	end
	opts.Title = opts.Title or tostring(title or "NovaUI")
	if theme ~= nil and opts.Accent == nil then
		if type(theme) == "string" then
			opts.Accent = KAVO_THEMES[theme]
			if not opts.Accent then
				warn("[NovaUI] unknown theme '" .. theme .. "', using DarkTheme")
			end
		else
			opts.Accent = theme -- assume Color3
		end
	end
	return Library.new(opts)
end

function Library:NewTab(name)
	return setmetatable({ _tab = self:Tab(name) }, KavoTab)
end

Library.ToggleUI = Library.ToggleVisible

function KavoTab:NewSection(name)
	self._tab:Section(name)
	return setmetatable({ _tab = self._tab }, Section)
end

function Section:NewButton(name, info, callback)
	local obj = self._tab:Button(name, callback, { Tooltip = tipFor(name, info) })
	return {
		UpdateButton = function(_, newText)
			obj:SetText(newText)
		end,
	}
end

function Section:NewToggle(name, info, callback)
	local obj = self._tab:Toggle(name, false, callback, { Tooltip = tipFor(name, info) })
	return {
		UpdateToggle = function(_, _, state)
			obj:Set(state == true)
		end,
	}
end

-- Kavo argument order: (name, info, maxValue, minValue, callback)
function Section:NewSlider(name, info, maxValue, minValue, callback)
	minValue = tonumber(minValue) or 0
	local obj = self._tab:Slider(name, minValue, maxValue, minValue, callback, { Tooltip = tipFor(name, info) })
	return {
		UpdateSlider = function(_, _, value)
			obj:Set(value)
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

return Library
