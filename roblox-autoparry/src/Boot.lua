--[[
	Boot.lua
	Last module in the chain. Restores settings, loads the timing and effect
	databases, hooks every animator currently in the world, and says hello.

	Order matters here and nowhere else in the codebase: the saved settings come
	back first, because where the databases are loaded from depends on one of
	them.
]]

return function(ctx)
	local Store, FS, Input, Hooks = ctx.Store, ctx.FS, ctx.Input, ctx.Hooks
	local Effects = ctx.Effects
	local notify, LocalPlayer = ctx.notify, ctx.LocalPlayer
	local configList, refreshTimingList = ctx.configList, ctx.refreshTimingList

	-- Before anything reads a setting, not after. This restores Write To Disk,
	-- and every decision below branches on it - loading it afterwards would mean
	-- the first launch of every session ignored the value you saved.
	ctx.SaveManager:LoadAutoloadConfig()

	local caching = Store.cacheEnabled()

	-- Only carve out folders when something is actually allowed to write to them.
	if caching then
		Store.init()
	end

	if caching and not FS.available then
		notify("No filesystem access - timings will not persist", 6)
	end

	if not Input.available then
		notify("No input backend found - parry cannot fire", 6)
	end

	----------------------------------------------------------------------------
	-- Databases
	--
	-- Remote first by default. With Write To Disk off there is nothing local to
	-- prefer, and pulling every launch means a repo fix reaches you without you
	-- doing anything. With it on, the local copy wins, because that one is the
	-- one you have been tuning and an update must never overwrite your work.
	----------------------------------------------------------------------------

	if caching and FS.isFile(Store.path("default")) then
		Store.load("default")
	else
		local fetched, err = Store.fetch()
		if fetched then
			if caching then
				Store.save("default")
			end
			notify(string.format("Loaded %d timings from the repo", Store.count()), 4)
		else
			notify("No timings for this place (" .. tostring(err) .. ")", 5)
		end
	end

	if caching and FS.isFile(Effects.path()) then
		Effects.load()
	else
		Effects.fetch()
	end

	configList:SetValues(caching and Store.list() or {})
	configList:Display()
	refreshTimingList()
	ctx.refreshEffectList()

	-- Attach only when something wants the workspace firehose; the Effects tab
	-- toggles re-evaluate this whenever either flag changes.
	if ctx.Toggles.LogEffects.Value or ctx.Toggles.EffectReact.Value then
		Effects.attach()
	end

	Hooks.sweep()

	-- Re-sweep on respawn, since a new character means a new animator tree.
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		Hooks.sweep()
	end)

	notify(string.format("AutoParry v%s loaded for place %d", ctx.VERSION, game.PlaceId), 4)

	-- Says which folders are actually being listened to. A game that keeps
	-- players and mobs in separate folders is the normal case, and silently
	-- watching only one of them looks exactly like the script being broken.
	notify("Watching: " .. Hooks.sources(), 5)

	return true
end
