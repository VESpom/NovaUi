-- NovaUI executor (UNC) check.
-- Paste this into your executor and run it (no window is opened). It tests the file / asset functions
-- NovaUI uses, one by one, and prints PASS / FAIL / MISSING / SKIP for each in the console (F9 / dev console).
-- A FAIL or MISSING means your EXECUTOR's function is broken or absent, not NovaUI's code.

local URL = "https://raw.githubusercontent.com/VESpom/NovaUi/main/source.lua"

local okGet, body = pcall(function()
	return game:HttpGet(URL)
end)
if not okGet or type(body) ~= "string" or body == "" then
	warn("[NovaUI UNC] game:HttpGet failed: " .. tostring(body) .. "  (executor / network problem, not NovaUI)")
	return
end

local compile = loadstring
if type(compile) ~= "function" then
	warn("[NovaUI UNC] this executor has no loadstring (executor problem, not NovaUI)")
	return
end
local chunk, compileErr = compile(body)
if not chunk then
	warn("[NovaUI UNC] loadstring could not compile the library: " .. tostring(compileErr))
	return
end
local okRun, Library = pcall(chunk)
if not okRun or type(Library) ~= "table" or type(Library.UNCTest) ~= "function" then
	warn("[NovaUI UNC] could not start the library: " .. tostring(Library))
	return
end

local report = Library.UNCTest() -- prints every line
return report
