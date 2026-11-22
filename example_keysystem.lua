-- NovaUI with a key system. The window stays locked until the right key is typed.
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"))()

-- CreateLib WAITS here until a valid key is entered, so nothing below runs before that.
-- Leave KeySystem out and the UI opens right after Enter, like before.
local Window = Library.CreateLib("My Hub", "DarkTheme", {
	KeySystem = {
		Key = "hello123", -- one key (or Keys = { "a", "b" })
		-- KeyHash = Library.HashKey("hello123"), -- store only a salted hash in your script instead of the plain key
		-- Note = "Join our Discord to get a key",
		-- Link = "https://discord.gg/yourinvite", -- adds a "Get Key" button that copies the link
		-- MaxAttempts = 5,                        -- wrong keys before a timed lockout (30s, then 60s, 120s...)
		-- Validate = function(key) return key == "x", { plan = "pro" } end, -- your own server check; payload = 2nd result
	},
})

local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Unlocked")
Section:NewButton("Hello", "Only reachable with a valid key", function()
	print("hello from a keyed UI")
end)
