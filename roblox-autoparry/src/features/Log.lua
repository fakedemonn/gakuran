--[[
	features/Log.lua
	Animation info logger, data half.

	A ring buffer of every animation seen, plus a recorded speed curve per
	animation so the visualizer can replay a move at the speed it was actually
	played at you rather than at 1x. Attackers with haste effects are the whole
	reason that distinction matters: the delay you measure at 1.4x is wrong at 1x.

	The window that renders this lives in ui/LoggerWindow.lua.
]]

return function(ctx)
	local RunService = ctx.RunService

	local Log = {
		entries = {},
		playback = {},
		selected = nil,
		max = 150,
		-- animationId -> the entry already on screen for it.
		seen = {},
	}

	---Record one animation event.
	---
	---With dedupe on, an animation id occupies exactly one row for the life of
	---the log: replays refresh that row's time, distance and ping in place
	---instead of pushing a new one. A boss with a four-hit combo used to bury
	---the list in twelve copies of the same four ids inside one fight.
	---@param entry table
	function Log.push(entry)
		local Toggles = ctx.Toggles
		local dedupe = not Toggles or not Toggles.DedupeLog or Toggles.DedupeLog.Value ~= false

		if dedupe and entry.id then
			local existing = Log.seen[entry.id]
			if existing then
				existing.time = entry.time
				existing.distance = entry.distance
				existing.ping = entry.ping
				existing.speed = entry.speed
				existing.clock = entry.clock
				existing.model = entry.model or existing.model
				existing.hits = (existing.hits or 1) + 1
				return existing
			end
			Log.seen[entry.id] = entry
		end

		entry.hits = 1
		table.insert(Log.entries, 1, entry)

		while #Log.entries > Log.max do
			local dropped = table.remove(Log.entries)
			-- Drop it from the seen set too, or the id can never be logged again
			-- once it has scrolled off the bottom.
			if dropped and dropped.id and Log.seen[dropped.id] == dropped then
				Log.seen[dropped.id] = nil
			end
		end

		return entry
	end

	---Wipe the log and the dedupe memory together.
	---Clearing the list without clearing `seen` was the bug that made a cleared
	---logger stay empty: every id was still marked as already shown.
	function Log.clear()
		Log.entries = {}
		Log.seen = {}
		Log.selected = nil
	end

	---Begin recording the speed curve of a track.
	---@param animationId string
	---@param entity Model
	---@param track AnimationTrack
	function Log.record(animationId, entity, track)
		local samples = { { t = 0, speed = track.Speed } }
		local started = os.clock()

		Log.playback[animationId] = {
			entity = entity,
			samples = samples,
			length = track.Length,
		}

		task.spawn(function()
			while track.IsPlaying do
				local elapsed = os.clock() - started
				local last = samples[#samples]
				if math.abs(last.speed - track.Speed) > 0.001 then
					table.insert(samples, { t = elapsed, speed = track.Speed })
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	---Speed at a given elapsed time from the recorded curve.
	---@param animationId string
	---@param elapsed number
	---@return number
	function Log.speedAt(animationId, elapsed)
		local data = Log.playback[animationId]
		if not data then
			return 1
		end

		local speed = data.samples[1] and data.samples[1].speed or 1
		for _, sample in ipairs(data.samples) do
			if sample.t > elapsed then
				break
			end
			speed = sample.speed
		end
		return speed
	end

	ctx.Log = Log
	return Log
end
