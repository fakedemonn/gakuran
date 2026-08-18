--[[
	features/Dodge.lua
	Directional dashing, and the fallback that runs when parry is unavailable.

	Two dash styles, because Roblox combat games are split on it:

	  Key + Direction  hold W/A/S/D, tap the dash key, release. What most games
	                   with a dedicated dash bind expect.
	  Double Tap       tap the direction key twice inside the game's own
	                   double-tap window. What games with no dash bind expect.

	Direction resolution is deliberately live: "Auto" reads whichever movement
	key you are already holding, so a dash fired mid-fight goes where you were
	already going instead of throwing you somewhere you did not ask for.
]]

return function(ctx)
	local Input, UserInputService = ctx.Input, ctx.UserInputService
	local LocalPlayer, notify = ctx.LocalPlayer, ctx.notify

	local Dodge = {}

	local KEYS = { Forward = "W", Backward = "S", Left = "A", Right = "D" }

	-- Movement keys are checked in this order when resolving "Auto", so a
	-- diagonal resolves to the forward/back component rather than at random.
	local PRIORITY = { "Forward", "Backward", "Left", "Right" }

	Dodge.DIRECTIONS = { "Auto", "Forward", "Backward", "Left", "Right" }

	Dodge.lastDash = 0
	Dodge.dashes = 0

	---Which way a dash should go right now.
	---@param requested string?
	---@return string
	function Dodge.resolve(requested)
		local Options = ctx.Options

		if requested and requested ~= "Auto" and KEYS[requested] then
			return requested
		end

		for _, name in ipairs(PRIORITY) do
			local ok, held = pcall(function()
				return UserInputService:IsKeyDown(Enum.KeyCode[KEYS[name]])
			end)
			if ok and held then
				return name
			end
		end

		-- Standing still: fall back to whatever the user picked as the default,
		-- and only then to Backward, which is the safe direction against a swing
		-- you were not able to parry.
		local fallback = Options and Options.DashFallback and Options.DashFallback.Value
		if fallback and KEYS[fallback] then
			return fallback
		end

		return "Backward"
	end

	---Can we dash at all?
	---@return boolean, string
	function Dodge.ready()
		local Options = ctx.Options

		local character = LocalPlayer.Character
		if not character then
			return false, "no character"
		end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false, "dead"
		end

		local cooldown = (Options and Options.DashCooldown and Options.DashCooldown.Value or 400) / 1000
		if os.clock() - Dodge.lastDash < cooldown then
			return false, "dash cooldown"
		end

		return true, "ok"
	end

	---Fire one dash.
	---@param requested string? direction, or nil / "Auto" to read the movement keys
	---@param keyOverride string? dash key for this one dash, e.g. a timing's own
	---@return boolean, string
	function Dodge.dash(requested, keyOverride)
		local Toggles, Options = ctx.Toggles, ctx.Options

		local ok, reason = Dodge.ready()
		if not ok then
			return false, reason
		end

		local direction = Dodge.resolve(requested)
		local moveKey = KEYS[direction]
		local mode = Options and Options.DashMode and Options.DashMode.Value or "Key + Direction"

		if mode == "Double Tap" then
			-- Two taps with a gap the game will read as a double tap. Held slightly
			-- longer than a single frame so a 60Hz input poll cannot miss either one.
			Input.tap(moveKey, 0.05)
			task.delay(0.09, function()
				Input.tap(moveKey, 0.05)
			end)
		else
			-- A timing can name its own dash key, for games where the roll and the
			-- dash are different binds. Falls through to the global one.
			local dashKey = keyOverride
			if not dashKey or dashKey == "" or dashKey == "Default" then
				dashKey = Options and Options.DashKey and Options.DashKey.Value or "Q"
			end
			local hold = (Options and Options.DashHold and Options.DashHold.Value or 120) / 1000

			-- Direction goes down first and comes up last: the game reads the
			-- movement vector at the instant the dash key registers, so releasing
			-- the direction early turns a side dash into a neutral one.
			Input.down(moveKey)
			task.delay(0.02, function()
				Input.tap(dashKey, hold)
			end)
			task.delay(hold + 0.08, function()
				Input.up(moveKey)
			end)
		end

		Dodge.lastDash = os.clock()
		Dodge.dashes = Dodge.dashes + 1

		if Toggles and Toggles.NotifyOnDash and Toggles.NotifyOnDash.Value then
			notify("Dashed " .. direction, 1.2)
		end

		return true, direction
	end

	-- Refusals worth dashing through. "disabled" and "dead" are deliberately not
	-- here: dashing when the whole feature is off, or when you are a corpse, is
	-- noise. "missed" is the humanised Miss Chance drop - the parry is not coming
	-- but the hit still is, which is exactly when a dash is worth more.
	local DASHABLE = {
		["cooldown"] = true,
		["key held manually"] = true,
		["missed"] = true,
	}

	---Parry will not happen; should we dash instead, and if so, do it.
	---@param reason string the refusal from State.canParry, or "missed"
	---@param timing table? the timing that wanted to fire
	---@return boolean
	function Dodge.fallback(reason, timing)
		local Toggles = ctx.Toggles

		if not (Toggles and Toggles.AutoDodgeOnCooldown and Toggles.AutoDodgeOnCooldown.Value) then
			return false
		end

		if not DASHABLE[reason] then
			return false
		end

		-- "Back" is the pre-rework spelling and "None" means the timing had no
		-- opinion; both fall through to Auto, which reads the keys you are holding.
		local requested = timing and timing.dodgeDir
		if requested == "Back" then
			requested = "Backward"
		elseif requested == "None" then
			requested = nil
		end

		local fired = Dodge.dash(requested, timing and timing.dodgeKey)
		return fired
	end

	---Manual dash bind. Wired in ui/Wiring.lua.
	function Dodge.manual()
		local Options = ctx.Options
		local direction = Options and Options.DashDirection and Options.DashDirection.Value or "Auto"
		Dodge.dash(direction)
	end

	ctx.Dodge = Dodge
	return Dodge
end
