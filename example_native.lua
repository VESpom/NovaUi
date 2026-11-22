-- LocalScript (StarterPlayerScripts). NovaUI goes in ReplicatedStorage as a ModuleScript named "NovaUI".
local NovaUI = require(game:GetService("ReplicatedStorage"):WaitForChild("NovaUI"))

local Window = NovaUI.new({
	Title = "My Hub",
	Subtitle = "v1.0",
	-- Accent = Color3.fromRGB(80, 160, 255),  -- change the whole theme colour
	-- ToggleKey = Enum.KeyCode.RightControl,  -- default is RightShift
	-- Loader = false,                         -- skip the Enter screen
	OnEnter = function(window) -- runs after the loading screen; receives the window
		window:Notify("Welcome", "Press RightShift to hide/show the menu.", 5)
	end,
})

-- Each Window:Tab() adds a tab in the sidebar. Everything you add to it appears underneath, in order.
local Main = Window:Tab("Main")
local Settings = Window:Tab("Settings")

Main:Section("Buttons")

-- Button(text, function() ...your code... end, style)
Main:Button("Default button", function()
	print("clicked!")
end)

Main:Button("Open settings tab", function()
	Window:SelectTab("Settings") -- a button that opens another tab
end, { Style = "Sweep", Icon = ">" })

Main:Button("Pill button", function()
	Window:Notify("Pill", "Hover me for the expanding effect", 3)
end, { Style = "Pill", Icon = "+" })

Main:Button("Push button", function()
	print("pushed")
end, { Style = "Push", Tooltip = { Title = "Info", Text = "Tooltips work on any style." } })

Main:Button("Glow button", function()
	print("glow")
end, "Glow")

Main:Section("Toggles")

-- Toggle(text, default, function(isOn) ...your code... end)
local fly = Main:Toggle("Fly", false, function(isOn)
	print("Fly:", isOn)
end)

Main:Toggle("Another toggle", true, function(isOn)
	print("Another:", isOn)
end, { Tooltip = "Starts switched on." })

Main:Section("Sliders and inputs")

-- Slider(text, min, max, default, function(value) ...your code... end, { Step = 1, Suffix = "" })
Main:Slider("WalkSpeed", 16, 100, 16, function(value)
	local character = game:GetService("Players").LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = value
	end
end, { Suffix = " sp" })

Main:Slider("Opacity", 0, 1, 0.5, function(value)
	print("Opacity:", value)
end, { Step = 0.05 })

Main:Input("Player name", "type and press Enter", function(text)
	print("Typed:", text)
end)

Settings:Label("Anything you add to this tab shows up here.")
Settings:Toggle("Fly (mirrors the Main toggle)", false, function(isOn)
	fly:Set(isOn, true) -- true = update the switch without re-running its callback
end)
Settings:Button("Close menu", function()
	Window:Close()
end, "Push")
