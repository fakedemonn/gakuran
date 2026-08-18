--[[
	Runtime.lua
	Watermark, the per-frame visualizer step, the stats loop, and unload.

	Two loops on purpose: the visualizer needs RenderStepped so scrubbing and
	playback stay smooth, but redrawing the logger 240 times a second is pure
	waste, so text updates run on their own 0.15s timer.
]]

return function(ctx)
	local Library, RunService = ctx.Library, ctx.RunService
	local Latency, State, Store, Hooks = ctx.Latency, ctx.State, ctx.Store, ctx.Hooks
	local LoggerGui, Visualizer, StatsLabel = ctx.LoggerGui, ctx.Visualizer, ctx.StatsLabel
	local Hitbox, HitboxLabel = ctx.Hitbox, ctx.HitboxLabel
	local Effects, EffectGui, EffectLabel = ctx.Effects, ctx.EffectGui, ctx.EffectLabel

	Library:SetWatermarkVisibility(true)

	local frameTimer = os.clock()
	local frameCount = 0
	local fps = 60

	local renderConnection = RunService.RenderStepped:Connect(function(delta)
		frameCount = frameCount + 1
		if os.clock() - frameTimer >= 1 then
			fps = frameCount
			frameTimer = os.clock()
			frameCount = 0
		end

		Library:SetWatermark(
			string.format(
				"Fleur v%s | %d fps | %d ms | %d parries",
				ctx.VERSION,
				fps,
				math.floor(Latency.rtt() * 1000),
				State.parries
			)
		)

		Visualizer.step(delta)
		EffectGui.step(delta)
	end)

	-- The hitbox deliberately does NOT run here. RenderStepped fires before the
	-- camera is updated for the frame, so a part positioned from it is one camera
	-- frame stale - that lag is the wiggle. Hitbox.bind puts it just after the
	-- camera instead.
	Hitbox.bind()

	task.spawn(function()
		while not Library.Unloaded do
			LoggerGui.refresh()

			StatsLabel:SetText(
				string.format(
					"Parries: %d | Pending: %d | Missed: %d | Ping: %dms",
					State.parries,
					State.pending,
					State.misses,
					math.floor(Latency.rtt() * 1000)
				)
			)

			HitboxLabel:SetText(Hitbox.status())

			EffectGui.refresh()
			EffectLabel:SetText(
				string.format(
					"Effects: %d | Profiles: %d | Fired: %d | Dashes: %d",
					#Effects.entries,
					Effects.count(),
					Effects.triggers,
					ctx.Dodge.dashes
				)
			)

			task.wait(0.15)
		end
	end)

	Library:OnUnload(function()
		renderConnection:Disconnect()
		Hooks.detach()
		Effects.detach()
		Hitbox.destroy()

		if Store.dirty then
			-- Autosave defers its write, so unloading in the same frame as an edit
			-- would drop it. This is the synchronous backstop.
			-- warn, not notify: the notification GUI is about to be destroyed along
			-- with the rest of the library, so a notification would flash and vanish.
			local ok, err = Store.save(Store.configName)
			if not ok then
				warn("[Fleur] Timings not written on unload: " .. tostring(err))
			end
		end

		Library.Unloaded = true
		print("[Fleur] Unloaded.")
	end)

	return renderConnection
end
