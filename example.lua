-- NovaUI, Kavo-style. Same calls as Kavo UI Library.
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"))()

local Window = Library.CreateLib("TITLE", "DarkTheme")   -- LightTheme, DarkTheme, GrapeTheme, BloodTheme, Ocean, Midnight, Sentinel, Synapse
-- Optional NovaUI extras as a 3rd argument: { Loader = false, ToggleKey = Enum.KeyCode.RightControl, Parent = someGui }

local Tab = Window:NewTab("TabName")
local Section = Tab:NewSection("Section Name")
Section:UpdateSection("Section New Title")

local label = Section:NewLabel("LabelText")
label:UpdateLabel("New Text")

local button = Section:NewButton("ButtonText", "ButtonInfo", function()
	print("Clicked")
end)
button:UpdateButton("New Text")

getgenv().Toggled = false
local toggle = Section:NewToggle("Toggle", "Info", function(state)
	getgenv().Toggled = state
end)
game:GetService("RunService").RenderStepped:Connect(function()
	if getgenv().Toggled then
		toggle:UpdateToggle("Toggle On")
	else
		toggle:UpdateToggle("Toggle Off")
	end
end)

Section:NewSlider("SliderText", "SliderInfo", 500, 0, function(s) -- 500 (MaxValue) | 0 (MinValue)
	game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = s
end)

Section:NewTextBox("TextboxText", "TextboxInfo", function(txt)
	print(txt)
end)

Section:NewKeybind("KeybindText", "KeybindInfo", Enum.KeyCode.F, function()
	Library:ToggleUI()
end)

local oldList = { "2019", "2020" }
local newList = { "2021", "2022" }
local dropdown = Section:NewDropdown("Dropdown", "Info", oldList, function(currentOption)
	print(currentOption)
end)
Section:NewButton("Update Dropdown", "Refreshes Dropdown", function()
	dropdown:Refresh(newList)
end)

Section:NewColorPicker("Color Text", "Color Info", Color3.fromRGB(0, 0, 0), function(color)
	print(color)
end)

-- Fully customizable UI: a colour picker per theme key, recolouring the UI live
local ThemeTab = Window:NewTab("Theme")
local ThemeSection = ThemeTab:NewSection("Colours")
local themes = {
	SchemeColor = Color3.fromRGB(150, 120, 255),
	Background = Color3.fromRGB(13, 13, 18),
	Header = Color3.fromRGB(19, 19, 26),
	TextColor = Color3.fromRGB(236, 236, 246),
	ElementColor = Color3.fromRGB(26, 26, 35),
}
for theme, color in pairs(themes) do
	ThemeSection:NewColorPicker(theme, "Change your " .. theme, color, function(color3)
		Library:ChangeColor(theme, color3)
	end)
end
