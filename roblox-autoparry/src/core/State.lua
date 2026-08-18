--[[
	core/State.lua
	Runtime counters and the single gate that decides whether a parry may fire.

	Every reason to refuse lives here rather than being scattered through the
	engine, so "why didn't it parry" has exactly one place to look.
]]

return function(ctx)
	local LocalPlayer, UserInputService = ctx.LocalPlayer, ctx.UserInputService

	local State = {
		lastParry = 0,
		parries = 0,
		misses = 0,
		pending = 0,
	}

	---Are we allowed to fire a parry at this instant?
	---@return boolean, string
	function State.canParry()
		local Toggles, Options = ctx.Toggles, ctx.Options

		if not Toggles.AutoParry or not Toggles.AutoParry.Value then
			return false, "disabled"
		end

		local character = LocalPlayer.Character
		if not character then
			return false, "no character"
		end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false, "dead"
		end

		-- No slider any more: this is a floor that stops one animation event from
		-- firing the key twice, not a tuning knob. Multi-hit chains bypass it by
		-- resetting lastParry in Engine.fireSequence.
		local cooldown = ctx.PARRY_COOLDOWN / 1000
		if os.clock() - State.lastParry < cooldown then
			return false, "cooldown"
		end

		if Toggles.DisableWhileHolding and Toggles.DisableWhileHolding.Value then
			local key = Options.ParryKey and Options.ParryKey.Value or "F"
			local ok, held = pcall(function()
				return UserInputService:IsKeyDown(Enum.KeyCode[key])
			end)
			if ok and held then
				return false, "key held manually"
			end
		end

		return true, "ok"
	end

	ctx.State = State
	return State
end
