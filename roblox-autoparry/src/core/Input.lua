--[[
	core/Input.lua
	Keyboard output.

	VirtualInputManager is preferred because it goes through Roblox's own input
	pipeline, so the game sees a normal key event. keypress/keyrelease is the
	fallback for executors that block VIM; it needs Windows virtual key codes,
	which is why the VK table exists.
]]

return function(ctx)
	local Input = {}

	-- Windows virtual key codes for the keys we let the user bind.
	local VK = {
		A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
		H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
		O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
		V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,
		One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, Five = 0x35,
		Space = 0x20, LeftShift = 0xA0, LeftControl = 0xA2, LeftAlt = 0xA4,
	}

	local vim = nil
	pcall(function()
		vim = game:GetService("VirtualInputManager")
	end)

	local kp = rawget(getgenv(), "keypress") or keypress
	local kr = rawget(getgenv(), "keyrelease") or keyrelease

	Input.keys = {}
	for name in pairs(VK) do
		table.insert(Input.keys, name)
	end
	table.sort(Input.keys)

	Input.available = (vim ~= nil) or (kp ~= nil and kr ~= nil)

	---Press a key down.
	---@param keyName string
	function Input.down(keyName)
		local enum = Enum.KeyCode[keyName]
		if vim then
			pcall(function()
				vim:SendKeyEvent(true, enum, false, game)
			end)
			return
		end
		if kp and VK[keyName] then
			pcall(kp, VK[keyName])
		end
	end

	---Release a key.
	---@param keyName string
	function Input.up(keyName)
		local enum = Enum.KeyCode[keyName]
		if vim then
			pcall(function()
				vim:SendKeyEvent(false, enum, false, game)
			end)
			return
		end
		if kr and VK[keyName] then
			pcall(kr, VK[keyName])
		end
	end

	---Press and hold a key for a duration, then release.
	---@param keyName string
	---@param holdSeconds number
	function Input.tap(keyName, holdSeconds)
		Input.down(keyName)
		task.delay(math.max(holdSeconds, 0.01), function()
			Input.up(keyName)
		end)
	end

	ctx.Input = Input
	return Input
end
