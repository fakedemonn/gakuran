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
	local refreshTimingList = ctx.refreshTimingList

	ctx.SaveManager:LoadAutoloadConfig()

	Store.init()

	if not FS.available then
		notify("No filesystem access - timings will not persist this session", 6)
	end

	if not Input.available then
		notify("No input backend found - parry cannot fire", 6)
	end

	----------------------------------------------------------------------------
	-- Databases
	--
	-- Local first, always. The file on this machine is the one you have been
	-- tuning, and nothing about starting the script should be allowed to
	-- overwrite it. The repo copy is only the seed for a machine that has never
	-- run here before - and it is written straight to disk so the very next
	-- launch is instant and offline.
	----------------------------------------------------------------------------

	if FS.isFile(Store.path("default")) then
		local ok, err = Store.load("default")
		if ok then
			notify(string.format("Loaded %d timings from disk", Store.count()), 4)
		else
			notify("Local timings unreadable (" .. tostring(err) .. "), pulling from the repo", 5)
			if Store.fetch() then
				Store.save("default")
			end
		end
	else
		local fetched, err = Store.fetch()
		if fetched then
			Store.save("default")
			notify(string.format("First run here - saved %d timings to disk", Store.count()), 4)
		else
			notify("No timings for this place (" .. tostring(err) .. ")", 5)
		end
	end

	if FS.isFile(Effects.path()) then
		Effects.load()
	elseif Effects.fetch() then
		Effects.save()
	end

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

	notify(string.format("Fleur v%s loaded for place %d", ctx.VERSION, game.PlaceId), 4)

	-- Says which folders are actually being listened to. A game that keeps
	-- players and mobs in separate folders is the normal case, and silently
	-- watching only one of them looks exactly like the script being broken.
	notify("Watching: " .. Hooks.sources(), 5)

	return true
end
