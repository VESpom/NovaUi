-- NovaUI tests on the strict Roblox mock (Lua 5.2 + bit32). Run with: python3 test/run_tests.py
-- Globals provided by the runner: SRC_DIR, py_sha256(str) -> hex, py_kdf(key, salt, rounds) -> hex

local M = require("mock_roblox")
M.install()

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local srcText = readFile(SRC_DIR .. "/source.lua")
local TAIL = "\nreturn Library\n"
assert(srcText:sub(-#TAIL) == TAIL, "source.lua must end with 'return Library'")

-- The shipped file exposes no internals; the tests inject a hook just before the final return.
local HOOK = [[
Library.__test = {
	gate = gate, liveWindows = liveWindows, runGated = runGated, checkKey = checkKey,
	prepareKeySystem = prepareKeySystem, readableFill = readableFill, contrastRatio = contrastRatio,
	sha256 = sha256, deriveKey = deriveKey, constantTimeEquals = constantTimeEquals, parseKeyHash = parseKeyHash, isUnlocked = isUnlocked,
}
]]

local function loadLib(text)
	M.reset()
	local code = (text or srcText):sub(1, -#TAIL - 1) .. "\n" .. HOOK .. TAIL
	local f = assert(load(code, "=source"))
	local lib = f()
	return lib
end

----------------------------------------------------------------------
-- tiny harness
----------------------------------------------------------------------
local passed, failed, failures, currentTest = 0, 0, {}, "?"
local expectErrors = false

local function check(cond, msg)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		table.insert(failures, currentTest .. ": " .. tostring(msg))
	end
end
local function eq(a, b, msg)
	check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function near(a, b, eps, msg)
	check(type(a) == "number" and math.abs(a - b) <= eps, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function has(str, part, msg)
	check(type(str) == "string" and string.find(str, part, 1, true) ~= nil, tostring(msg) .. " (got '" .. tostring(str) .. "', want to contain '" .. part .. "')")
end
local function test(name, fn)
	currentTest = name
	expectErrors = false
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		failed = failed + 1
		table.insert(failures, name .. ": CRASH " .. tostring(err))
	end
	if not expectErrors and #M.errors > 0 then
		failed = failed + 1
		table.insert(failures, name .. ": unexpected thread error: " .. M.errors[1])
	end
end

----------------------------------------------------------------------
-- instance helpers
----------------------------------------------------------------------
local function findByName(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function findByText(root, text)
	for _, d in ipairs(root:GetDescendants()) do
		if d._props.Text == text then
			return d
		end
	end
end
local function currentGui()
	local kids = M.services.CoreGui:GetChildren()
	if #kids == 0 then
		kids = M.playerGui:GetChildren()
	end
	return kids[#kids]
end
local function btnIn(row)
	for _, d in ipairs(row:GetDescendants()) do
		if d._class == "TextButton" then
			return d
		end
	end
end
local function uis()
	return M.services.UserInputService
end
local function visibleHolders(win)
	local n, which = 0, nil
	for _, tab in ipairs(win.Tabs) do
		if tab._holder.Visible then
			n = n + 1
			which = tab
		end
	end
	return n, which
end

-- Runs CreateLib in its own thread (it blocks while a key is required).
local function startKey(Lib, keysystem, extra)
	local r = { done = false }
	local opts = { KeySystem = keysystem }
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	task.spawn(function()
		local ok, a, b = pcall(Lib.CreateLib, "Hub", "DarkTheme", opts)
		r.done, r.ok = true, ok
		if ok then
			r.win, r.payload = a, b
		else
			r.err = a
		end
	end)
	return r
end
local function keyUI(gui)
	return {
		box = findByName(gui, "KeyBox"),
		verify = findByText(gui, "Verify") or findByText(gui, "Checking..."),
		msg = findByName(findByName(gui, "KeyStage"), "Message"),
		stage = findByName(gui, "KeyStage"),
	}
end
local function submit(gui, text)
	local ui = keyUI(gui)
	ui.box.Text = text
	ui.verify.Activated:Fire()
	return ui
end
local function enterThenKeyStage(gui)
	findByText(gui, "Enter  ›").Activated:Fire()
	M.advance(0.5)
end

----------------------------------------------------------------------
-- 1. SHA-256 and key derivation against Python's hashlib
----------------------------------------------------------------------
test("sha256 official vectors", function()
	local Lib = loadLib()
	local sha = Lib.__test.sha256
	eq(sha(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty")
	eq(sha("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "abc")
	eq(sha("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "448-bit")
end)

test("sha256 matches hashlib for every length 0..200 and binary data", function()
	local Lib = loadLib()
	local sha = Lib.__test.sha256
	for n = 0, 200 do
		local s = string.rep("a", n)
		if sha(s) ~= py_sha256(s) then
			check(false, "length " .. n .. " differs")
			return
		end
	end
	check(true, "lengths ok")
	local bytes = {}
	for i = 1, 3000 do
		bytes[i] = string.char((i * 73 + math.floor(i / 7)) % 256)
	end
	local blob = table.concat(bytes)
	eq(sha(blob), py_sha256(blob), "3000 bytes incl. values >= 128")
end)

test("deriveKey matches an independent Python implementation", function()
	local Lib = loadLib()
	local derive = Lib.__test.deriveKey
	for _, case in ipairs({
		{ "hello123", "00112233aabbccdd", 1 },
		{ "hello123", "00112233aabbccdd", 2 },
		{ "hello123", "00112233aabbccdd", 3 },
		{ "", "deadbeefdeadbeef", 50 },
		{ "pässwörd ✓", "0123456789abcdef0123", 1000 },
	}) do
		eq(derive(case[1], case[2], case[3]), py_kdf(case[1], case[2], case[3]), "kdf " .. case[1] .. "/" .. case[3])
	end
end)

test("HashKey format, determinism with a salt, fresh salt otherwise", function()
	local Lib = loadLib()
	local h = Lib.HashKey("hello123", "00112233aabbccdd")
	eq(h, "nv1$1000$00112233aabbccdd$" .. py_kdf("hello123", "00112233aabbccdd", 1000), "known salt")
	local a, b = Lib.HashKey("hello123"), Lib.HashKey("hello123")
	check(a ~= b, "random salts differ")
	check(string.match(a, "^nv1%$1000%$%x+%$%x+$") ~= nil, "format")
	check(Lib.__test.parseKeyHash(a) ~= nil, "parseable")
	check(not string.find(a, "hello123", 1, true), "plaintext is not in the hash string")
end)

test("parseKeyHash rejects malformed and abusive values", function()
	local Lib = loadLib()
	local p = Lib.__test.parseKeyHash
	local hex = string.rep("a", 64)
	check(p("nv1$1000$00112233$" .. hex) ~= nil, "valid")
	check(p(nil) == nil and p(5) == nil and p({}) == nil, "non-strings")
	check(p("nv1$0$00112233$" .. hex) == nil, "rounds 0")
	check(p("nv1$99999999$00112233$" .. hex) == nil, "huge rounds (DoS)")
	check(p("nv1$1000$001$" .. hex) == nil, "short salt")
	check(p("nv1$1000$00112233$" .. string.rep("a", 63)) == nil, "short hash")
	check(p("nv1$1000$00112233$" .. string.rep("g", 64)) == nil, "non-hex hash")
	check(p("nv2$1000$00112233$" .. hex) == nil, "wrong version")
end)

----------------------------------------------------------------------
-- 2. KeySystem config + checkKey (unit level)
----------------------------------------------------------------------
test("constantTimeEquals: exact match only, every position counts", function()
	local Lib = loadLib()
	local eqf = Lib.__test.constantTimeEquals
	local h = string.rep("ab12", 16)
	check(eqf(h, h), "equal")
	check(eqf("", ""), "both empty")
	for i = 1, #h do
		local flipped = h:sub(1, i - 1) .. (h:sub(i, i) == "a" and "b" or "a") .. h:sub(i + 1)
		if eqf(h, flipped) then
			check(false, "a difference at position " .. i .. " was missed")
			return
		end
	end
	check(true, "every single-character difference detected")
	check(not eqf(h, h .. "0") and not eqf(h .. "0", h) and not eqf(h, ""), "different lengths")
end)

test("prepareKeySystem + checkKey: plain key, wrong keys, case, whitespace", function()
	local Lib = loadLib()
	local T = Lib.__test
	local cfg = T.prepareKeySystem({ Key = "hello123" })
	check(not cfg.misconfigured, "configured")
	eq(#cfg.entries, 1, "one entry")
	check(T.checkKey(cfg, "hello123"), "right key")
	check(not T.checkKey(cfg, "hello124"), "wrong key")
	check(not T.checkKey(cfg, "HELLO123"), "case sensitive")
	check(not T.checkKey(cfg, "hello123 "), "no silent trimming at this layer")
	check(not T.checkKey(cfg, ""), "empty")
	check(not T.checkKey(cfg, string.rep("a", 300)), "over-long key rejected")
	check(cfg.entries[1].hex ~= "hello123", "stored as hash")
end)

test("prepareKeySystem: Keys list, KeyHash, KeyHashes", function()
	local Lib = loadLib()
	local T = Lib.__test
	local cfg = T.prepareKeySystem({ Keys = { "one", "two", "three" }, KeyHash = Lib.HashKey("four"), KeyHashes = { Lib.HashKey("five") } })
	eq(#cfg.entries, 5, "five entries")
	for _, k in ipairs({ "one", "two", "three", "four", "five" }) do
		check(T.checkKey(cfg, k), "accepts " .. k)
	end
	check(not T.checkKey(cfg, "six"), "rejects six")
end)

test("prepareKeySystem fails CLOSED when misconfigured", function()
	local Lib = loadLib()
	local T = Lib.__test
	for label, bad in pairs({
		nilcfg = false, empty = {}, emptyKey = { Key = "" }, numKey = { Key = 123 }, badHash = { KeyHash = "garbage" },
		badValidate = { Validate = "x" }, longKey = { Key = string.rep("k", 300) }, str = "hello123",
	}) do
		local cfg = T.prepareKeySystem(bad ~= false and bad or nil)
		check(cfg.misconfigured == true, label .. " is flagged misconfigured")
		check(not T.checkKey(cfg, "hello123") and not T.checkKey(cfg, ""), label .. " accepts nothing")
	end
	check(#M.warnings >= 8, "each problem warns")
end)

test("prepareKeySystem clamps MaxAttempts and Timeout", function()
	local Lib = loadLib()
	local T = Lib.__test
	eq(T.prepareKeySystem({ Key = "a", MaxAttempts = 0 }).maxAttempts, 1, "min attempts")
	eq(T.prepareKeySystem({ Key = "a", MaxAttempts = 999 }).maxAttempts, 20, "max attempts")
	eq(T.prepareKeySystem({ Key = "a", MaxAttempts = "x" }).maxAttempts, 5, "default attempts")
	eq(T.prepareKeySystem({ Key = "a", Timeout = 0 }).timeout, 2, "min timeout")
	eq(T.prepareKeySystem({ Key = "a", Timeout = 9999 }).timeout, 120, "max timeout")
end)

test("checkKey Validate: must return exactly true; errors and truthy strings fail", function()
	local Lib = loadLib()
	local T = Lib.__test
	local seen
	local cfg = T.prepareKeySystem({ Validate = function(k) seen = k return k == "good", "payload!" end })
	local ok, payload = T.checkKey(cfg, "good")
	check(ok and payload == "payload!", "true + payload")
	eq(seen, "good", "validate receives the key")
	check(not T.checkKey(cfg, "bad"), "false rejected")
	check(not T.checkKey(T.prepareKeySystem({ Validate = function() return "yes" end }), "x"), "truthy string rejected")
	check(not T.checkKey(T.prepareKeySystem({ Validate = function() return 1 end }), "x"), "truthy number rejected")
	check(not T.checkKey(T.prepareKeySystem({ Validate = function() return {} end }), "x"), "truthy table rejected")
	check(not T.checkKey(T.prepareKeySystem({ Validate = function() error("boom") end }), "x"), "error rejected")
	local found = false
	for _, w in ipairs(M.warnings) do
		if string.find(w, "KeySystem.Validate error", 1, true) then
			found = true
		end
	end
	check(found, "validate error is reported")
end)

test("runGated blocks callbacks while locked, runs them once unlocked", function()
	local Lib = loadLib()
	local T = Lib.__test
	local win = {}
	local n = 0
	T.runGated(win, function() n = n + 1 end)
	eq(n, 0, "locked: not run")
	T.gate[win] = true
	T.runGated(win, function(a) n = n + a end, 5)
	eq(n, 5, "unlocked: run with args")
end)

----------------------------------------------------------------------
-- 3. No key system: behaviour must be unchanged (loads immediately)
----------------------------------------------------------------------
test("no KeySystem: CreateLib returns at once, unlocked, one value", function()
	local Lib = loadLib()
	local win, extra = Lib.CreateLib("Hub", "DarkTheme")
	check(win ~= nil and extra == nil, "single return")
	check(Lib.__test.isUnlocked(win), "unlocked from the start")
	check(not findByName(win.Gui, "KeyStage").Visible, "key stage hidden")
end)

test("no KeySystem: Enter -> loading -> window, OnEnter once", function()
	local Lib = loadLib()
	local entered = 0
	local win = Lib.CreateLib("Hub", "DarkTheme", { OnEnter = function() entered = entered + 1 end })
	local gui = win.Gui
	M.advance(0.1)
	local card = findByName(gui, "Loader")
	check(card.Visible and not win._main.Visible, "card shown, window hidden")
	findByText(gui, "Enter  ›").Activated:Fire()
	M.advance(0.3)
	check(findByName(gui, "LoadStage").Visible, "loading stage shown")
	check(not findByName(gui, "Welcome").Visible, "welcome hidden")
	M.advance(3)
	check(win._main.Visible and win.Visible, "window open")
	check(not card.Visible, "card gone")
	eq(entered, 1, "OnEnter once")
end)

test("no KeySystem: Return key presses Enter, only on the welcome stage", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	uis().InputBegan:Fire(M.input("Keyboard", "Return"), false)
	M.advance(0.3)
	check(findByName(win.Gui, "LoadStage").Visible, "Return started loading")
	uis().InputBegan:Fire(M.input("Keyboard", "Return"), false) -- pressing again must not restart anything
	M.advance(3)
	check(win._main.Visible, "opened once")
end)

test("no KeySystem: Loader=false opens immediately", function()
	local Lib = loadLib()
	local entered = 0
	local win = Lib.CreateLib("Hub", "DarkTheme", { Loader = false, OnEnter = function() entered = entered + 1 end })
	check(win._main.Visible and win.Visible, "open at once")
	eq(entered, 1, "OnEnter ran")
	check(win._loader == nil, "no loader built")
end)

test("no KeySystem: callbacks run (not gated)", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	local tab = win:Tab("Main")
	local hits = 0
	local b = tab:Button("Go", function() hits = hits + 1 end)
	btnIn(b.Instance).Activated:Fire()
	eq(hits, 1, "button callback")
	local state
	local t = tab:Toggle("T", false, function(v) state = v end)
	t:Set(true)
	eq(state, true, "toggle callback")
end)

----------------------------------------------------------------------
-- 4. Key system flow through the real UI
----------------------------------------------------------------------
local function keyScreen(extraOpts, keysystem)
	local Lib = loadLib()
	local r = startKey(Lib, keysystem or { Key = "hello123" }, extraOpts)
	M.advance(0.2)
	local gui = currentGui()
	return Lib, r, gui
end

test("KeySystem: CreateLib blocks, window stays hidden, key stage reached via Enter", function()
	local Lib, r, gui = keyScreen()
	check(not r.done, "still waiting")
	check(not Lib.__test.isUnlocked(Lib.__test.liveWindows[1]), "locked")
	check(findByName(gui, "Welcome").Visible and not findByName(gui, "KeyStage").Visible, "welcome first")
	enterThenKeyStage(gui)
	check(findByName(gui, "KeyStage").Visible and not findByName(gui, "Welcome").Visible, "key stage after Enter")
	check(not Lib.__test.liveWindows[1]._main.Visible, "main window hidden")
	M.advance(5)
	check(not r.done, "still waiting after 5s")
end)

test("KeySystem: right key hello123 unlocks, loads, returns the window", function()
	local Lib, r, gui = keyScreen()
	enterThenKeyStage(gui)
	local ui = submit(gui, "hello123")
	has(ui.msg.Text, "Key accepted", "success message")
	M.advance(0.3)
	check(r.done and r.ok and r.win ~= nil, "CreateLib returned")
	check(Lib.__test.isUnlocked(r.win), "unlocked")
	eq(r.payload, nil, "no payload for a plain key")
	M.advance(3)
	check(r.win._main.Visible and r.win.Visible, "window opened after loading")
	check(not findByName(gui, "Loader").Visible, "card gone")
end)

test("KeySystem: key is trimmed, wrong case and wrong keys rejected", function()
	local Lib, r, gui = keyScreen()
	enterThenKeyStage(gui)
	local ui = submit(gui, "HELLO123")
	has(ui.msg.Text, "Invalid key. 4 attempts left.", "case sensitive + counter")
	submit(gui, "hello12")
	has(ui.msg.Text, "3 attempts left", "counter 3")
	submit(gui, "")
	has(ui.msg.Text, "Type your key first.", "empty key message")
	submit(gui, "   ")
	has(ui.msg.Text, "Type your key first.", "blank key message")
	check(not r.done, "never unlocked")
	submit(gui, "  hello123  ")
	M.advance(0.3)
	check(r.done and r.ok, "trimmed key accepted")
end)

test("KeySystem: singular 'attempt' on the last try, then lockout", function()
	local Lib, r, gui = keyScreen()
	enterThenKeyStage(gui)
	local ui
	for i = 1, 4 do
		ui = submit(gui, "nope" .. i)
	end
	has(ui.msg.Text, "1 attempt left.", "singular")
	check(not string.find(ui.msg.Text, "attempts", 1, true), "no plural")
	ui = submit(gui, "nope5")
	has(ui.msg.Text, "Try again in 30s", "locked 30s")
	ui = submit(gui, "hello123")
	has(ui.msg.Text, "Too many wrong keys", "right key refused during lockout")
	check(not r.done and not Lib.__test.isUnlocked(Lib.__test.liveWindows[1]), "still locked")
	M.advance(10)
	has(ui.msg.Text, "Try again in 2", "countdown ticks (20s left)")
	M.advance(21)
	has(ui.msg.Text, "try again now", "lockout over")
	submit(gui, "hello123")
	M.advance(0.3)
	check(r.done and r.ok, "right key works after lockout")
end)

test("KeySystem: lockout doubles each time (30s then 60s)", function()
	local Lib, r, gui = keyScreen()
	enterThenKeyStage(gui)
	local ui
	for i = 1, 5 do
		ui = submit(gui, "x" .. i)
	end
	has(ui.msg.Text, "30s", "first lock 30s")
	M.advance(31)
	for i = 1, 5 do
		ui = submit(gui, "y" .. i)
	end
	has(ui.msg.Text, "60s", "second lock 60s")
	M.advance(30)
	ui = submit(gui, "hello123")
	has(ui.msg.Text, "Too many wrong keys", "still locked at 30s of 60s")
	check(not r.done, "not unlocked")
end)

test("KeySystem: MaxAttempts is honoured", function()
	local Lib, r, gui = keyScreen(nil, { Key = "hello123", MaxAttempts = 2 })
	enterThenKeyStage(gui)
	local ui = submit(gui, "a")
	has(ui.msg.Text, "1 attempt left", "one left")
	ui = submit(gui, "b")
	has(ui.msg.Text, "Too many wrong keys", "locked after 2")
end)

test("KeySystem: several Keys all work, hashed KeyHash works, plaintext absent from the UI", function()
	for _, case in ipairs({ { "alpha", { Keys = { "alpha", "beta" } } }, { "beta", { Keys = { "alpha", "beta" } } } }) do
		local Lib, r, gui = keyScreen(nil, case[2])
		enterThenKeyStage(gui)
		submit(gui, case[1])
		M.advance(0.3)
		check(r.done and r.ok, "key " .. case[1])
	end
	local Lib0 = loadLib()
	local hashed = Lib0.HashKey("s3cret-Key")
	local Lib, r, gui = keyScreen(nil, { KeyHash = hashed })
	enterThenKeyStage(gui)
	submit(gui, "s3cret-Key")
	M.advance(0.3)
	check(r.done and r.ok, "KeyHash key")
	for _, d in ipairs(gui:GetDescendants()) do
		for _, v in pairs(d._props) do
			if v == "s3cret-Key" and d._class ~= "TextBox" then
				check(false, "plaintext key found in a " .. d._class)
			end
		end
	end
end)

test("KeySystem: Validate gets the key, returns payload to CreateLib", function()
	local got
	local Lib, r, gui = keyScreen(nil, { Validate = function(k) got = k return k == "abc", { token = 42 } end })
	enterThenKeyStage(gui)
	submit(gui, "zzz")
	check(not r.done, "wrong key rejected")
	submit(gui, "abc")
	M.advance(0.3)
	eq(got, "abc", "validate saw the trimmed key")
	check(r.done and r.ok and type(r.payload) == "table" and r.payload.token == 42, "payload returned")
end)

test("KeySystem: Validate returning a truthy non-true value does not unlock", function()
	local Lib, r, gui = keyScreen(nil, { Validate = function() return "yes" end })
	enterThenKeyStage(gui)
	local ui = submit(gui, "anything")
	has(ui.msg.Text, "Invalid key", "rejected")
	check(not r.done, "still locked")
end)

test("KeySystem: a crashing Validate rejects the key and the UI survives", function()
	local Lib, r, gui = keyScreen(nil, { Validate = function() error("server down") end })
	enterThenKeyStage(gui)
	local ui = submit(gui, "anything")
	has(ui.msg.Text, "Invalid key", "rejected")
	check(ui.box.Visible and findByText(gui, "Verify") ~= nil, "UI still usable")
	check(not r.done, "locked")
end)

test("KeySystem: a slow Validate shows Checking..., and a hung one times out without unlocking", function()
	local Lib, r, gui = keyScreen(nil, { Timeout = 3, Validate = function() task.wait(10) return true end })
	enterThenKeyStage(gui)
	local ui = submit(gui, "anything")
	eq(findByText(gui, "Checking...") ~= nil, true, "button shows Checking...")
	has(ui.msg.Text, "Checking", "status shows checking")
	local before = findByText(gui, "Checking...")
	before.Activated:Fire() -- second click while busy must do nothing
	M.advance(3.5)
	has(ui.msg.Text, "No answer from the key server", "timeout message")
	check(findByText(gui, "Verify") ~= nil, "button back to Verify")
	M.advance(10) -- the abandoned check finally says true: it must NOT unlock
	check(not r.done and not Lib.__test.isUnlocked(Lib.__test.liveWindows[1]), "late answer is ignored")
end)

test("KeySystem: misconfigured key system stays locked and says so", function()
	local Lib, r, gui = keyScreen(nil, {})
	enterThenKeyStage(gui)
	local ui = keyUI(gui)
	has(ui.msg.Text, "not set up correctly", "shown on the key stage")
	submit(gui, "hello123")
	submit(gui, "")
	M.advance(5)
	check(not r.done and not Lib.__test.isUnlocked(Lib.__test.liveWindows[1]), "never opens")
end)

test("KeySystem: Loader=false skips Enter/loading but never skips the key", function()
	local Lib, r, gui = keyScreen({ Loader = false })
	check(findByName(gui, "KeyStage").Visible and not findByName(gui, "Welcome").Visible, "starts on the key stage")
	check(not r.done, "locked")
	submit(gui, "nope")
	check(not r.done, "wrong key")
	submit(gui, "hello123")
	M.advance(1.5)
	check(r.done and r.ok and r.win._main.Visible, "opens directly after the key")
end)

test("KeySystem: OnEnter does not fire before the key is accepted", function()
	local entered = 0
	local Lib, r, gui = keyScreen({ OnEnter = function() entered = entered + 1 end })
	enterThenKeyStage(gui)
	submit(gui, "bad")
	M.advance(5)
	eq(entered, 0, "no OnEnter while locked")
	submit(gui, "hello123")
	M.advance(4)
	eq(entered, 1, "OnEnter after unlock")
end)

test("KeySystem: closing the window while locked ends CreateLib with an error", function()
	local Lib, r, gui = keyScreen()
	M.genv.__NovaUI:Destroy()
	M.advance(0.5)
	check(r.done and r.ok == false, "CreateLib raised")
	has(tostring(r.err), "closed before a valid key", "clear message")
end)

test("KeySystem: RightShift / ToggleUI cannot reveal a locked window", function()
	local Lib, r, gui = keyScreen()
	local win = Lib.__test.liveWindows[1]
	uis().InputBegan:Fire(M.input("Keyboard", "RightShift"), false)
	M.advance(1)
	check(not win._main.Visible and not win.Visible, "RightShift ignored")
	Lib:ToggleUI()
	win:SetVisible(true)
	win:_expand()
	M.advance(1)
	check(not win._main.Visible and not win.Visible, "ToggleUI / SetVisible / _expand ignored")
end)

test("KeySystem: element callbacks are gated until the key is accepted", function()
	local Lib, r, gui = keyScreen({ Loader = false })
	local win = Lib.__test.liveWindows[1]
	local tab = win:Tab("Main")
	local hits = { button = 0, toggle = 0, slider = 0, input = 0, drop = 0, color = 0, key = 0 }
	local b = tab:Button("Go", function() hits.button = hits.button + 1 end)
	local t = tab:Toggle("T", false, function() hits.toggle = hits.toggle + 1 end)
	local s = tab:Slider("S", 0, 10, 5, function() hits.slider = hits.slider + 1 end)
	local i = tab:Input("I", "p", function() hits.input = hits.input + 1 end)
	local d = tab:Dropdown("D", { "a", "b" }, function() hits.drop = hits.drop + 1 end)
	local function pickItem(text)
		local buttons = {}
		for _, x in ipairs(d.Instance:GetDescendants()) do
			if x._class == "TextButton" then
				table.insert(buttons, x)
			end
		end
		buttons[1].Activated:Fire() -- open the list
		for _, x in ipairs(buttons) do
			if x._props.Text == text then
				x.Activated:Fire()
			end
		end
	end
	btnIn(b.Instance).Activated:Fire()
	t:Set(true)
	s:Set(7)
	pickItem("b")
	for _, k in ipairs({ "button", "toggle", "slider", "drop" }) do
		eq(hits[k], 0, "locked: " .. k .. " callback blocked")
	end
	submit(gui, "hello123")
	M.advance(0.3)
	btnIn(b.Instance).Activated:Fire()
	t:Set(false)
	s:Set(3)
	pickItem("a")
	eq(hits.button, 1, "button runs after unlock")
	eq(hits.toggle, 1, "toggle runs after unlock")
	eq(hits.slider, 1, "slider runs after unlock")
	check(hits.drop >= 1, "dropdown runs after unlock")
end)

test("handle in getgenv() exposes only Destroy; re-running replaces the old window", function()
	local Lib = loadLib()
	local w1 = Lib.CreateLib("A", "DarkTheme")
	local n = 0
	for k in pairs(M.genv.__NovaUI) do
		n = n + 1
		eq(k, "Destroy", "only Destroy is exposed")
	end
	eq(n, 1, "one field")
	local w2 = Lib.CreateLib("B", "DarkTheme")
	check(w1._destroyed and not w2._destroyed, "old window destroyed, new alive")
	M.genv.__NovaUI:Destroy()
	check(w2._destroyed, "handle destroys the window")
	check(M.genv.__NovaUI == nil, "handle cleared")
end)

test("the Library table does not expose any window", function()
	local Lib = loadLib()
	task.spawn(function()
		Lib.CreateLib("A", "DarkTheme", { KeySystem = { Key = "k" } })
	end)
	for k, v in pairs(Lib) do
		check(not (type(v) == "table" and rawget(v, "_main")), "Library." .. tostring(k) .. " is not a window")
	end
	check(rawget(Lib, "_windows") == nil and rawget(Lib, "_lastWindow") == nil, "no window registry on Library")
	M.advance(0.1)
end)

----------------------------------------------------------------------
-- 5. Smooth tab navigation
----------------------------------------------------------------------
local function tabsWindow()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	local a, b, c = win:Tab("A"), win:Tab("B"), win:Tab("C")
	a:Label("a page")
	b:Label("b page")
	c:Label("c page")
	M.advance(1)
	return Lib, win, a, b, c
end
local TAB_TOP, TAB_H, TAB_GAP = 10, 36, 4
local function indicatorY(win)
	return win._tabIndicator.Position.Y.Offset
end

test("tabs: first tab shows in place, indicator on it", function()
	local _, win, a = tabsWindow()
	check(a._holder.Visible and a._holder.GroupTransparency == 0, "first page visible")
	check(win._tabIndicator.Visible, "indicator visible")
	near(indicatorY(win), TAB_TOP, 0.01, "indicator on tab 1")
	local n = visibleHolders(win)
	eq(n, 1, "one visible page")
end)

test("tabs: switching is animated, not instant", function()
	local _, win, a, b = tabsWindow()
	win:SelectTab(b)
	-- t = 0: nothing has jumped yet
	near(indicatorY(win), TAB_TOP, 0.01, "indicator has not teleported")
	eq(b._holder.GroupTransparency, 1, "new page starts transparent")
	check(b._holder.Visible, "new page is mounted so it can fade in")
	check(b.Page.Position.Y.Offset > 0, "new page starts offset below")
	M.advance(0.06)
	local y = indicatorY(win)
	check(y > TAB_TOP + 0.5 and y < TAB_TOP + TAB_H + TAB_GAP - 0.5, "indicator is mid-glide (" .. y .. ")")
	local fade = b._holder.GroupTransparency
	check(fade > 0 and fade < 1, "new page mid-fade (" .. fade .. ")")
	check(a._holder.GroupTransparency > 0 and a._holder.Visible, "old page still fading out, not cut")
	M.advance(0.6)
	near(indicatorY(win), TAB_TOP + TAB_H + TAB_GAP, 0.01, "indicator lands on tab 2")
	eq(b._holder.GroupTransparency, 0, "new page fully visible")
	near(b.Page.Position.Y.Offset, 0, 0.001, "new page settled")
	check(not a._holder.Visible, "old page unmounted")
	local n, which = visibleHolders(win)
	check(n == 1 and which == b, "exactly one visible page")
end)

test("tabs: direction of the slide follows tab order", function()
	local _, win, a, b, c = tabsWindow()
	win:SelectTab(c)
	check(c.Page.Position.Y.Offset > 0, "going down: new page enters from below")
	M.advance(1)
	win:SelectTab(a)
	check(a.Page.Position.Y.Offset < 0, "going up: new page enters from above")
	M.advance(1)
end)

test("tabs: SelectTab by name works, unknown name warns and changes nothing", function()
	local _, win, a, b = tabsWindow()
	win:SelectTab("B")
	M.advance(1)
	check(win._selected == b, "by name")
	local before = #M.warnings
	win:SelectTab("Nope")
	check(#M.warnings == before + 1, "warned")
	M.advance(1)
	check(win._selected == b, "selection unchanged")
	check(select(1, visibleHolders(win)) == 1, "still one page")
end)

test("tabs: re-selecting the current tab does nothing (no restart flicker)", function()
	local _, win, a, b = tabsWindow()
	win:SelectTab(b)
	M.advance(1)
	local before = M.tweensCreated
	win:SelectTab(b)
	eq(M.tweensCreated, before, "no new tweens")
	eq(b._holder.GroupTransparency, 0, "still fully visible")
end)

test("tabs: rapid clicking always ends consistent", function()
	local _, win, a, b, c = tabsWindow()
	local seq = { b, c, a, b, c, b, a, c }
	for _, t in ipairs(seq) do
		win:SelectTab(t)
		M.advance(0.04)
	end
	M.advance(1)
	local n, which = visibleHolders(win)
	check(n == 1 and which == c, "one page, the last clicked")
	eq(c._holder.GroupTransparency, 0, "last page fully visible")
	near(c.Page.Position.Y.Offset, 0, 0.001, "last page settled")
	near(indicatorY(win), TAB_TOP + 2 * (TAB_H + TAB_GAP), 0.01, "indicator on the last tab")
end)

test("tabs: A -> B -> A quickly keeps A visible (pending hide is cancelled)", function()
	local _, win, a, b = tabsWindow()
	win:SelectTab(b)
	M.advance(0.05)
	win:SelectTab(a)
	M.advance(1)
	check(a._holder.Visible and a._holder.GroupTransparency == 0, "A visible")
	check(not b._holder.Visible, "B hidden")
end)

test("tabs: button text colours follow the selection", function()
	local _, win, a, b = tabsWindow()
	win:SelectTab(b)
	M.advance(0.5)
	check(b._button.TextColor3 == win.Theme.Text, "selected tab is bright")
	check(a._button.TextColor3 == win.Theme.Muted, "other tab is muted")
end)

test("tabs: tab buttons are clickable and navigate", function()
	local _, win, a, b = tabsWindow()
	b._button.Activated:Fire()
	M.advance(1)
	check(win._selected == b and b._holder.Visible, "click navigated")
end)

test("tabs: a button in one tab can open another (Window:SelectTab)", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	local main, other = win:Tab("Main"), win:Tab("Other")
	local btn = main:Button("Open", function() win:SelectTab("Other") end)
	btnIn(btn.Instance).Activated:Fire()
	M.advance(1)
	check(win._selected == other, "navigated from a callback")
end)

test("tabs: destroying mid-transition is clean", function()
	local _, win, a, b = tabsWindow()
	win:SelectTab(b)
	M.advance(0.05)
	win:Destroy()
	M.advance(2)
	check(win._destroyed, "destroyed")
end)

test("tabs: tab added after others still gets the right indicator slot", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	local a = win:Tab("A")
	local last
	for i = 1, 5 do
		last = win:Tab("T" .. i)
	end
	win:SelectTab(last)
	M.advance(1)
	near(indicatorY(win), TAB_TOP + 5 * (TAB_H + TAB_GAP), 0.01, "6th tab slot")
end)

test("tabs: Kavo NewTab uses the same smooth navigation", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme", { Loader = false })
	local t1, t2 = win:NewTab("One"), win:NewTab("Two")
	local s = t1:NewSection("Sec")
	s:NewButton("B", "info", function() end)
	t2:NewSection("Sec2")
	win._tabsByName.Two._button.Activated:Fire()
	M.advance(0.05)
	local y = indicatorY(win)
	check(y > TAB_TOP and y < TAB_TOP + TAB_H + TAB_GAP, "animating")
	M.advance(1)
	check(win._selected == win._tabsByName.Two, "landed on Two")
end)

----------------------------------------------------------------------
-- 6. Enter screen: clearer + draggable
----------------------------------------------------------------------
local function placeButtonsForHitTest(gui)
	-- the mock has no layout engine, so give the widgets real screen rectangles
	local card = findByName(gui, "Loader")
	card.AbsolutePosition = M.Vector2.new(460, 200)
	card.AbsoluteSize = M.Vector2.new(360, 262)
	local enter = findByText(gui, "Enter  ›")
	enter.AbsolutePosition = M.Vector2.new(488, 354)
	enter.AbsoluteSize = M.Vector2.new(304, 48)
	return card, enter
end

local function drag(card, fromX, fromY, toX, toY, kind)
	kind = kind or "MouseButton1"
	local began = M.input(kind, nil, fromX, fromY)
	card.InputBegan:Fire(began)
	if kind == "Touch" then
		-- Roblox hands the SAME input object to every event of one touch
		began.Position = { X = toX, Y = toY, Z = 0 }
		uis().InputChanged:Fire(began)
		uis().InputEnded:Fire(began)
		return
	end
	uis().InputChanged:Fire(M.input("MouseMovement", nil, toX, toY))
	uis().InputEnded:Fire(M.input(kind, nil, toX, toY))
end

test("enter screen: the Enter button is clear (bold, large, white label on its own fill)", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	local enter = findByText(win.Gui, "Enter  ›")
	check(enter ~= nil, "button found")
	check(enter.TextColor3 == Color3.fromRGB(255, 255, 255), "white label")
	check(enter.TextSize >= 16, "label size >= 16")
	eq(enter.Font.Name, "GothamBold", "bold font")
	check(enter.BackgroundTransparency == 1, "label is not tinted by a gradient")
	local fill
	for _, ch in ipairs(enter.Parent:GetChildren()) do
		if ch.Name == "Fill" then
			fill = ch
		end
	end
	check(fill ~= nil, "separate fill frame")
	local gradient
	for _, ch in ipairs(fill:GetChildren()) do
		if ch._class == "UIGradient" then
			gradient = ch
		end
	end
	check(gradient ~= nil, "fill colour comes from its gradient")
	for _, kp in ipairs(gradient.Color.Keypoints) do
		check(Lib.__test.contrastRatio(Color3.fromRGB(255, 255, 255), kp.Value) >= 4.5, "white on the gradient end is >= 4.5:1")
	end
	check(findByText(win.Gui, "Drag to move  ·  RightShift hides the menu") ~= nil, "hint explains dragging and the hide key")
end)

test("login: every piece of text is readable (>= 4.5:1) on every theme, all stages", function()
	local names = { "LightTheme", "DarkTheme", "GrapeTheme", "BloodTheme", "Ocean", "Midnight", "Sentinel", "Synapse" }
	for _, name in ipairs(names) do
		local Lib = loadLib()
		local r
		task.spawn(function() r = pcall(Lib.CreateLib, "Hub", name, { KeySystem = { Key = "k", Link = "https://x.y" } }) end)
		M.advance(0.2)
		local gui = currentGui()
		local card = findByName(gui, "Loader")
		local function ratio(fg, bg)
			return Lib.__test.contrastRatio(fg, bg)
		end
		-- labels that sit directly on the card
		for _, label in ipairs({ "Title", "Subtitle", "Hint", "KeyLabel", "Message", "Status", "CardClose" }) do
			local d = findByName(gui, label)
			check(d ~= nil, name .. ": " .. label .. " exists")
			if d then
				local r1 = ratio(d.TextColor3, card.BackgroundColor3)
				check(r1 >= 4.5, name .. ": " .. label .. " contrast " .. string.format("%.2f", r1))
			end
		end
		local box = findByName(gui, "KeyBox")
		check(ratio(box.TextColor3, box.BackgroundColor3) >= 7, name .. ": typed key text >= 7:1")
		check(ratio(box.PlaceholderColor3, box.BackgroundColor3) >= 4.5, name .. ": placeholder >= 4.5:1")
		local link = findByText(gui, "Get Key")
		check(ratio(link.TextColor3, link.BackgroundColor3) >= 7, name .. ": link button text >= 7:1")
		-- error + success message colours
		enterThenKeyStage(gui)
		local ui = submit(gui, "wrong")
		check(ratio(ui.msg.TextColor3, card.BackgroundColor3) >= 4.5, name .. ": error text contrast")
		submit(gui, "k")
		check(ratio(ui.msg.TextColor3, card.BackgroundColor3) >= 4.5, name .. ": success text contrast")
		M.genv.__NovaUI:Destroy()
		M.advance(0.5)
	end
end)

test("login: card is not near-black on dark themes (lifted surface) and has a close button", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	local card = findByName(win.Gui, "Loader")
	check(card.BackgroundColor3.R > win.Theme.Background.R, "card lighter than the raw background")
	check(findByName(win.Gui, "Glow") ~= nil, "accent glow present")
	check(findByName(win.Gui, "CardClose") ~= nil, "close button present")
end)

test("enter screen: card can be dragged by its body", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	local card = placeButtonsForHitTest(win.Gui)
	local x0, y0 = card.Position.X.Offset, card.Position.Y.Offset
	drag(card, 500, 230, 560, 270) -- start on the title area, not on the button
	near(card.Position.X.Offset - x0, 60, 0.01, "moved 60px right")
	near(card.Position.Y.Offset - y0, 40, 0.01, "moved 40px down")
	uis().InputChanged:Fire(M.input("MouseMovement", nil, 900, 900)) -- after release: must not move
	near(card.Position.X.Offset - x0, 60, 0.01, "stops following after release")
end)

test("enter screen: pressing on the Enter button does not start a drag", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	local card = placeButtonsForHitTest(win.Gui)
	local x0 = card.Position.X.Offset
	drag(card, 600, 370, 700, 420) -- inside the button rectangle
	near(card.Position.X.Offset, x0, 0.001, "card did not move")
end)

test("enter screen: touch drag works", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	local card = placeButtonsForHitTest(win.Gui)
	local x0 = card.Position.X.Offset
	drag(card, 500, 230, 530, 230, "Touch")
	near(card.Position.X.Offset - x0, 30, 0.01, "moved with touch")
end)

test("enter screen: window opens where the card was dragged", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	local card = placeButtonsForHitTest(win.Gui)
	drag(card, 500, 230, 560, 280)
	local pos = card.Position
	findByText(win.Gui, "Enter  ›").Activated:Fire()
	M.advance(3.5)
	check(win._main.Visible, "window open")
	check(win._main.Position == pos, "window opened at the dragged position")
end)

test("enter screen: key box and Verify are not drag handles; the rest of the key card is", function()
	local Lib, r, gui = keyScreen()
	enterThenKeyStage(gui)
	local card = findByName(gui, "Loader")
	card.AbsolutePosition = M.Vector2.new(460, 200)
	card.AbsoluteSize = M.Vector2.new(360, 346)
	local ui = keyUI(gui)
	ui.box.AbsolutePosition = M.Vector2.new(488, 376)
	ui.box.AbsoluteSize = M.Vector2.new(304, 46)
	ui.verify.AbsolutePosition = M.Vector2.new(488, 434)
	ui.verify.AbsoluteSize = M.Vector2.new(304, 46)
	local x0 = card.Position.X.Offset
	drag(card, 600, 390, 680, 390) -- on the key box
	near(card.Position.X.Offset, x0, 0.001, "typing area does not drag")
	drag(card, 600, 450, 680, 450) -- on Verify
	near(card.Position.X.Offset, x0, 0.001, "Verify does not drag")
	drag(card, 600, 215, 640, 215) -- on the header
	near(card.Position.X.Offset - x0, 40, 0.01, "header drags")
end)

test("enter screen: dragging is blocked from leaving the viewport", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	local card = placeButtonsForHitTest(win.Gui)
	drag(card, 500, 230, 500 + 50000, 230)
	check(math.abs(card.Position.X.Offset) < 5000, "offset is bounded (" .. card.Position.X.Offset .. ")")
end)

test("enter screen: small screens scale the card down", function()
	local Lib = loadLib()
	M.camera.ViewportSize = M.Vector2.new(320, 480)
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	local scale = win._loaderScale.Scale
	check(scale < 1 and scale >= 0.5, "scaled to fit a 320px phone (" .. scale .. ")")
end)

test("enter screen: stages cross-fade and the card resizes smoothly to the key stage", function()
	local Lib, r, gui = keyScreen()
	local card = findByName(gui, "Loader")
	local h0 = card.Size.Y.Offset
	findByText(gui, "Enter  ›").Activated:Fire()
	M.advance(0.05)
	local h1 = card.Size.Y.Offset
	check(h1 > h0 and h1 < 346, "card height mid-tween (" .. h1 .. ")")
	M.advance(0.5)
	eq(card.Size.Y.Offset, 346, "card is key-stage height")
	eq(findByName(gui, "KeyStage").GroupTransparency, 0, "key stage fully visible")
end)

test("enter screen: Link button copies the link when the executor can", function()
	local Lib = loadLib()
	local copied
	_G.setclipboard = function(s) copied = s end
	local r = startKey(Lib, { Key = "k", Link = "https://example.com/key", LinkText = "Get Key" })
	M.advance(0.2)
	local gui = currentGui()
	enterThenKeyStage(gui)
	local linkBtn = findByText(gui, "Get Key")
	check(linkBtn ~= nil, "link button shown")
	linkBtn.Activated:Fire()
	eq(copied, "https://example.com/key", "link copied")
	_G.setclipboard = nil
	linkBtn.Activated:Fire()
	has(keyUI(gui).msg.Text, "https://example.com/key", "fallback shows the link in the message")
end)

test("enter screen: Note replaces the subtitle on the key stage", function()
	local Lib, r, gui = keyScreen(nil, { Key = "k", Note = "Join our Discord for a key" })
	enterThenKeyStage(gui)
	check(findByText(gui, "Join our Discord for a key") ~= nil, "note shown")
end)

test("enter screen: destroying during each stage leaves no stray errors", function()
	for stage = 1, 4 do
		local Lib = loadLib()
		local r = startKey(Lib, { Key = "k" })
		M.advance(0.2)
		local gui = currentGui()
		if stage >= 2 then
			enterThenKeyStage(gui)
		end
		if stage >= 3 then
			submit(gui, "k")
			M.advance(0.7)
		end
		M.genv.__NovaUI:Destroy()
		M.advance(5)
		expectErrors = false
	end
end)

----------------------------------------------------------------------
-- 6b. Closing and hiding fold the window away (reverse of opening)
----------------------------------------------------------------------
local TOPBAR_H = 44

test("hide: collapses in two smooth phases, not instantly", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	M.advance(1)
	local full = win._main.Size.Y.Offset
	win:SetVisible(false)
	near(win._main.Size.Y.Offset, full, 0.01, "nothing jumps at t=0")
	M.advance(0.1)
	local h = win._main.Size.Y.Offset
	check(h < full and h > TOPBAR_H, "folding (" .. h .. ")")
	M.advance(0.2)
	check(win._main.Size.Y.Offset < TOPBAR_H + 1 and win._main.Visible, "folded to the title bar, still visible")
	M.advance(0.3)
	check(not win._main.Visible, "hidden at the end")
end)

test("hide then quickly show again ends fully open", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	M.advance(1)
	win:SetVisible(false)
	M.advance(0.1)
	win:SetVisible(true)
	M.advance(1.5)
	check(win._main.Visible and win.Visible, "visible")
	near(win._main.Size.Y.Offset, win._size.Y, 0.5, "full height")
end)

test("close button folds the window away, then destroys it", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	M.advance(1)
	local gui = win.Gui
	findByName(gui, "Close").Activated:Fire()
	M.advance(0.1)
	check(not win._destroyed and win._main.Visible, "still animating at 0.1s")
	check(win._main.Size.Y.Offset < win._size.Y, "already shrinking")
	M.advance(0.5)
	check(win._destroyed, "destroyed after the animation")
	check(M.genv.__NovaUI == nil, "handle cleared")
end)

test("close: re-opening or double-closing during the animation does nothing weird", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	M.advance(1)
	win:Close()
	win:Close()
	win:SetVisible(true)
	uis().InputBegan:Fire(M.input("Keyboard", "RightShift"), false)
	M.advance(1)
	check(win._destroyed, "still closes")
end)

test("close while hidden destroys at once", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	M.advance(1)
	win:SetVisible(false)
	M.advance(1)
	win:Close()
	check(win._destroyed, "instant")
end)

test("Window:Destroy() stays instant", function()
	local Lib = loadLib()
	local win = Lib.new({ Loader = false })
	win:Destroy()
	check(win._destroyed, "instant")
end)

test("login card X button fades the card out; on a locked window CreateLib ends with the closed error", function()
	local Lib, r, gui = keyScreen()
	local card = findByName(gui, "Loader")
	findByName(gui, "CardClose").Activated:Fire()
	M.advance(0.1)
	check(not r.done and card.GroupTransparency > 0 and card.GroupTransparency < 1, "fading")
	M.advance(0.5)
	check(r.done and r.ok == false, "CreateLib raised")
	has(tostring(r.err), "closed before a valid key", "clear message")
end)

test("login card X button on an unlocked (no key) window just closes it", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	M.advance(0.1)
	findByName(win.Gui, "CardClose").Activated:Fire()
	M.advance(0.5)
	check(win._destroyed, "closed")
end)

----------------------------------------------------------------------
-- 6c. Custom login image
----------------------------------------------------------------------
local PNG = "\137PNG\r\n\26\n" .. string.rep("x", 40)
local JPG = "\255\216\255\224" .. string.rep("y", 40)

-- Fake executor file API. Returns a table recording what happened.
local function fakeExecutor(data, opts)
	opts = opts or {}
	local rec = { files = {}, gets = 0, folders = {}, urls = {} }
	_G.writefile = function(path, content) rec.files[path] = content end
	_G.isfile = function(path) return rec.files[path] ~= nil end
	_G.makefolder = function(path) table.insert(rec.folders, path) end
	_G.getcustomasset = function(path) return "rbxasset://custom/" .. path end
	M.game.HttpGet = function(_, url)
		rec.gets = rec.gets + 1
		table.insert(rec.urls, url)
		if opts.wait then
			task.wait(opts.wait)
		end
		if opts.fail then
			error("HTTP 404")
		end
		return data
	end
	return rec
end
local function clearExecutor()
	_G.writefile, _G.isfile, _G.makefolder, _G.getcustomasset, _G.getsynasset = nil, nil, nil, nil, nil
	_G.request, _G.http_request = nil, nil
end
local function warned(part)
	for _, w in ipairs(M.warnings) do
		if string.find(w, part, 1, true) then
			return true
		end
	end
	return false
end
local function imageOf(win)
	return findByName(win.Gui, "LogoImage")
end

test("image: asset id (number, digits string, rbxassetid://) shows at once", function()
	for _, src in ipairs({ 12345, "12345", "rbxassetid://12345" }) do
		local Lib = loadLib()
		local win = Lib.CreateLib("Hub", "DarkTheme", { Image = src })
		local img = imageOf(win)
		check(img ~= nil, tostring(src) .. ": image label exists")
		eq(img.Image, "rbxassetid://12345", tostring(src) .. ": asset")
		eq(img.ImageTransparency, 1, "starts transparent (fades in)")
		M.advance(0.5)
		eq(img.ImageTransparency, 0, "faded in")
		eq(findByName(win.Gui, "LogoText").TextTransparency, 1, "letter faded out")
	end
end)

test("image: no Image option builds no image label and keeps the letter", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "DarkTheme")
	check(imageOf(win) == nil, "no image label")
	eq(findByName(win.Gui, "LogoText").TextTransparency, 0, "letter visible")
end)

test("image: https link is downloaded, saved under a hashed name, and shown", function()
	local Lib = loadLib()
	local rec = fakeExecutor(PNG)
	local url = "https://cdn.discordapp.com/attachments/1/2/logo.png?ex=abc&is=def"
	local win = Lib.CreateLib("Hub", "DarkTheme", { Image = url })
	M.advance(0.5)
	eq(rec.gets, 1, "downloaded once")
	eq(rec.urls[1], url, "right url")
	local names = {}
	for path, content in pairs(rec.files) do
		table.insert(names, path)
		eq(content, PNG, "saved the exact bytes")
	end
	eq(#names, 1, "one file")
	check(string.match(names[1], "^NovaUI/img_%x+%.png$") ~= nil, "hash-based name: " .. tostring(names[1]))
	eq(imageOf(win).Image, "rbxasset://custom/" .. names[1], "shown via getcustomasset")
	eq(imageOf(win).ImageTransparency, 0, "visible")
	eq(rec.folders[1], "NovaUI", "folder created")
	clearExecutor()
end)

test("image: second window with the same link uses the cache (no download)", function()
	local Lib = loadLib()
	local rec = fakeExecutor(PNG)
	local url = "https://example.com/logo.png"
	Lib.CreateLib("Hub", "DarkTheme", { Image = url })
	M.advance(0.5)
	local win2 = Lib.CreateLib("Hub", "DarkTheme", { Image = url })
	M.advance(0.5)
	eq(rec.gets, 1, "downloaded only once")
	check(string.find(imageOf(win2).Image, "NovaUI/img_", 1, true) ~= nil, "second window shows it too")
	clearExecutor()
end)

test("image: JPEG is accepted and saved as .jpg", function()
	local Lib = loadLib()
	local rec = fakeExecutor(JPG)
	Lib.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/a.jpg" })
	M.advance(0.5)
	local ok = false
	for path in pairs(rec.files) do
		ok = string.match(path, "%.jpg$") ~= nil
	end
	check(ok, "saved as .jpg")
	clearExecutor()
end)

test("image: executor without file functions falls back to the letter and says why", function()
	local Lib = loadLib()
	clearExecutor()
	M.game.HttpGet = function() error("must not be called") end
	local win = Lib.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/a.png" })
	M.advance(0.5)
	eq(imageOf(win).Image, "", "no image set")
	eq(findByName(win.Gui, "LogoText").TextTransparency, 0, "letter stays")
	check(warned("can't load images from links"), "reason warned")
end)

test("image: webp / gif / html are rejected (magic bytes), letter stays", function()
	for label, data in pairs({ webp = "RIFF\0\0\0\0WEBPVP8 ", gif = "GIF89a" .. string.rep("z", 20), html = "<html><body>404</body></html>" }) do
		local Lib = loadLib()
		local rec = fakeExecutor(data)
		local win = Lib.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/x." .. label })
		M.advance(0.5)
		eq(imageOf(win).Image, "", label .. ": no image")
		check(next(rec.files) == nil, label .. ": nothing written to disk")
		check(warned("not a PNG or JPEG"), label .. ": reason warned")
		clearExecutor()
	end
end)

test("image: oversized download is rejected before touching disk", function()
	local Lib = loadLib()
	local rec = fakeExecutor("\137PNG\r\n\26\n" .. string.rep("a", 8 * 1024 * 1024))
	local win = Lib.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/huge.png" })
	M.advance(0.5)
	check(next(rec.files) == nil, "nothing written")
	check(warned("too large"), "reason warned")
	eq(imageOf(win).Image, "", "no image")
	clearExecutor()
end)

test("image: failing HttpGet falls back to request(); both failing keeps the letter", function()
	local Lib = loadLib()
	local rec = fakeExecutor(nil, { fail = true })
	_G.request = function(req)
		return { StatusCode = 200, Body = PNG, Url = req.Url }
	end
	local win = Lib.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/a.png" })
	M.advance(0.5)
	check(string.find(imageOf(win).Image, "NovaUI/img_", 1, true) ~= nil, "request() fallback worked")
	clearExecutor()
	local Lib2 = loadLib()
	fakeExecutor(nil, { fail = true })
	local win2 = Lib2.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/b.png" })
	M.advance(0.5)
	eq(imageOf(win2).Image, "", "no image")
	check(warned("download failed"), "download failure reported")
	clearExecutor()
end)

test("image: unsafe or invalid sources are never fetched", function()
	for _, bad in ipairs({
		"file:///etc/passwd", "javascript:alert(1)", "ftp://example.com/a.png", "https://exa mple.com/a b.png",
		"data:image/png;base64,AAAA", "", {}, -5, 1.5, 0, true, "https://example.com/\"onerror=1",
		"rbxasset://../../secret.png", "../../etc/passwd",
	}) do
		local Lib = loadLib()
		local rec = fakeExecutor(PNG)
		local win = Lib.CreateLib("Hub", "DarkTheme", { Image = bad })
		M.advance(0.5)
		eq(rec.gets, 0, "no request for " .. tostring(bad))
		check(next(rec.files) == nil, "no file for " .. tostring(bad))
		eq(imageOf(win).Image, "", "no image for " .. tostring(bad))
		clearExecutor()
	end
end)

test("image: file name never contains anything from the link (path traversal)", function()
	local Lib = loadLib()
	local rec = fakeExecutor(PNG)
	Lib.CreateLib("Hub", "DarkTheme", { Image = "https://x.com/../../evil/..%2f..%2fpwn.png" })
	M.advance(0.5)
	for path in pairs(rec.files) do
		check(string.match(path, "^NovaUI/img_%x+%.png$") ~= nil and not string.find(path, "..", 1, true), "safe path: " .. path)
	end
	check(next(rec.files) ~= nil, "it still saved something")
	clearExecutor()
end)

test("image: destroying the window before a slow download ends is clean", function()
	local Lib = loadLib()
	fakeExecutor(PNG, { wait = 2 })
	local win = Lib.CreateLib("Hub", "DarkTheme", { Image = "https://example.com/slow.png" })
	M.advance(0.5)
	local img = imageOf(win)
	win:Destroy()
	M.advance(5)
	check(win._destroyed, "destroyed without errors")
	eq(img.Image, "", "the late download does not touch the destroyed window")
	clearExecutor()
end)

test("image: works on the key screen too, and Logo is an alias", function()
	local Lib = loadLib()
	local r = startKey(Lib, { Key = "k" }, { Logo = 777 })
	M.advance(0.5)
	local gui = currentGui()
	eq(findByName(gui, "LogoImage").Image, "rbxassetid://777", "alias works with a key system")
	check(not r.done, "still locked")
end)

----------------------------------------------------------------------
-- 7. Regression: the Kavo-style example and native API from the repo
----------------------------------------------------------------------
local function runExample(file, expectReturn)
	local Lib = loadLib()
	local src = readFile(SRC_DIR .. "/" .. file)
	_G.loadstring = load
	M.game.HttpGet = function()
		local code = srcText:sub(1, -#TAIL - 1) .. "\n" .. HOOK .. TAIL
		return code
	end
	local chunk = assert(load(src, "=" .. file))
	-- examples pull the library through loadstring(HttpGet(...)): give them a fresh copy each time
	task.spawn(chunk)
	M.advance(0.5)
	return Lib
end

test("regression: example.lua (Kavo API) runs unchanged and survives clicking everything", function()
	runExample("example.lua")
	local gui = currentGui()
	check(gui ~= nil, "window built")
	local enter = findByText(gui, "Enter  ›")
	check(enter ~= nil, "enter screen up")
	enter.Activated:Fire()
	M.advance(4)
	-- click every button, toggle everything via its TextButton
	local clicked = 0
	for _, d in ipairs(gui:GetDescendants()) do
		if d._class == "TextButton" and d.Name ~= "Hit" then
			d.Activated:Fire()
			clicked = clicked + 1
		end
	end
	M.advance(1)
	check(clicked > 5, "clicked several controls (" .. clicked .. ")")
end)

test("example_keysystem.lua: locked until hello123, then builds its tabs", function()
	local Lib = loadLib()
	_G.loadstring = load
	M.game.HttpGet = function()
		return srcText:sub(1, -#TAIL - 1) .. "\n" .. HOOK .. TAIL
	end
	local built = false
	task.spawn(assert(load(readFile(SRC_DIR .. "/example_keysystem.lua"), "=example_keysystem.lua")))
	M.advance(0.3)
	local gui = currentGui()
	check(gui ~= nil and findByName(gui, "Loader") ~= nil, "login card shown")
	check(findByText(gui, "Hello") == nil, "the example's own button does not exist yet")
	findByText(gui, "Enter  ›").Activated:Fire()
	M.advance(0.5)
	submit(gui, "wrong")
	M.advance(0.5)
	check(findByText(gui, "Hello") == nil, "still nothing after a wrong key")
	submit(gui, "hello123")
	M.advance(4)
	check(findByText(gui, "Hello") ~= nil, "tabs/buttons built after the right key")
end)

test("regression: example_native.lua runs unchanged", function()
	local Lib = loadLib()
	-- it requires a ModuleScript: serve the library through game:GetService("ReplicatedStorage")
	M.services.ReplicatedStorage = {
		WaitForChild = function()
			local code = srcText:sub(1, -#TAIL - 1) .. "\n" .. HOOK .. TAIL
			return assert(load(code, "=source"))()
		end,
	}
	_G.require = function(x) return x end
	local src = readFile(SRC_DIR .. "/example_native.lua")
	task.spawn(assert(load(src, "=example_native.lua")))
	M.advance(0.5)
	local gui = currentGui()
	check(gui ~= nil, "native window built")
	findByText(gui, "Enter  ›").Activated:Fire()
	M.advance(4)
	local nav
	for _, d in ipairs(gui:GetDescendants()) do
		if d._class == "TextButton" and string.find(d._props.Text or "", "Open settings tab", 1, true) then
			nav = d
		end
	end
	check(nav ~= nil, "nav button present")
	nav.Activated:Fire()
	M.advance(1)
	_G.require = nil
end)

test("regression: Kavo API surface still complete", function()
	local Lib = loadLib()
	local win = Lib.CreateLib("Hub", "Ocean", { Loader = false })
	local tab = win:NewTab("T")
	local sec = tab:NewSection("S")
	sec:UpdateSection("S2")
	local lbl = sec:NewLabel("L")
	lbl:UpdateLabel("L2")
	local btn = sec:NewButton("B", "i", function() end)
	btn:UpdateButton("B2")
	local tog = sec:NewToggle("T", "i", function() end)
	tog:UpdateToggle("T2", true)
	sec:NewSlider("S", "i", 100, 0, function() end)
	sec:NewTextBox("X", "i", function() end)
	sec:NewKeybind("K", "i", Enum.KeyCode.F, function() end)
	local dd = sec:NewDropdown("D", "i", { "a", "b" }, function() end)
	dd:Refresh({ "c" })
	sec:NewColorPicker("C", "i", Color3.new(1, 0, 0), function() end)
	Lib:ChangeColor("SchemeColor", Color3.fromRGB(10, 200, 90))
	Lib:ToggleUI()
	M.advance(1)
	Lib:ToggleUI()
	M.advance(1)
	check(win.Visible, "ToggleUI round trip")
end)

----------------------------------------------------------------------
print(string.format("RESULT passed=%d failed=%d", passed, failed))
for _, f in ipairs(failures) do
	print("FAIL " .. f)
end
return failed
