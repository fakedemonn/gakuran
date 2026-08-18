--[[
	ui/Wiring.lua
	Connects the Builder tab controls to the store, the windows and the hooks.

	Everything here is a callback, so it runs long after load and can capture
	ctx.Toggles / ctx.Options directly.
]]

return function(ctx)
	local Toggles, Options = ctx.Toggles, ctx.Options
	local Store, Log, Util, FS, Hooks = ctx.Store, ctx.Log, ctx.Util, ctx.FS, ctx.Hooks
	local LoggerGui, Visualizer, notify = ctx.LoggerGui, ctx.Visualizer, ctx.notify
	local Effects, EffectGui, Dodge = ctx.Effects, ctx.EffectGui, ctx.Dodge
	local BuilderBox, HitboxBox = ctx.BuilderBox, ctx.HitboxBox
	local EffectBuildBox, EffectStoreBox = ctx.EffectBuildBox, ctx.EffectStoreBox
	local timingList = ctx.timingList
	local effectList = ctx.effectList

	---Push the selected timing into the builder fields.
	local function loadTimingIntoBuilder(timing)
		if not timing then
			return
		end
		Options.T_Name:SetValue(timing.name or "")
		Options.T_Delay:SetValue(timing.delay or 0)
		Options.T_HoldTime:SetValue(timing.holdTime or 120)
		Options.T_MinDistance:SetValue(timing.minDistance or 0)
		Options.T_MaxDistance:SetValue(timing.maxDistance or 60)
		Toggles.T_Enabled:SetValue(timing.enabled == true)
	end

	---Refresh the timing dropdown, keeping the current selection where possible.
	local function refreshTimingList()
		timingList:SetValues(Store.display())
		timingList:Display()
	end

	-- Boot.lua calls this once the database is on disk.
	ctx.refreshTimingList = refreshTimingList
	ctx.loadTimingIntoBuilder = loadTimingIntoBuilder

	Options.TimingList:OnChanged(function()
		local timing = Store.fromDisplay(Options.TimingList.Value)
		loadTimingIntoBuilder(timing)
	end)

	BuilderBox:AddButton({
		Text = "Save Timing",
		Tooltip = "Write the builder fields back to the selected timing",
		Func = function()
			local timing = Store.fromDisplay(Options.TimingList.Value)
			if not timing then
				return notify("Select a timing first", 2)
			end

			timing.name = Options.T_Name.Value ~= "" and Options.T_Name.Value or timing.name
			timing.delay = Options.T_Delay.Value
			timing.holdTime = Options.T_HoldTime.Value
			timing.minDistance = Options.T_MinDistance.Value
			timing.maxDistance = Options.T_MaxDistance.Value
			timing.enabled = Toggles.T_Enabled.Value

			Store.autosave()
			refreshTimingList()
			notify("Saved " .. timing.name, 2)
		end,
	}):AddButton({
		Text = "Delete Timing",
		DoubleClick = true,
		Func = function()
			local timing = Store.fromDisplay(Options.TimingList.Value)
			if not timing then
				return notify("Select a timing first", 2)
			end
			Store.remove(timing.id)
			Options.TimingList:SetValue(nil)
			refreshTimingList()
			notify("Deleted " .. timing.name, 2)
		end,
	})

	BuilderBox:AddButton("Create From Selected Log", function()
		if not Log.selected then
			return notify("Click a row in the logger window first", 2)
		end

		local existing = Store.get(Log.selected)
		if existing then
			Options.TimingList:SetValue(
				string.format(
					"%s [%s]%s",
					existing.name,
					Util.shortId(existing.id),
					existing.enabled and "" or " (off)"
				)
			)
			return notify("That animation already has a timing", 2)
		end

		local length = Log.playback[Log.selected] and Log.playback[Log.selected].length or 1
		local entityName = "Unnamed"

		for _, entry in ipairs(Log.entries) do
			if entry.id == Log.selected then
				entityName = entry.entity
				length = entry.length
				break
			end
		end

		local timing = Store.template(Log.selected, length, entityName)
		Store.create(timing)
		refreshTimingList()
		loadTimingIntoBuilder(timing)
		notify("Created timing for " .. entityName, 2)
	end)

	BuilderBox:AddButton({
		Text = "Download Timings",
		DoubleClick = true,
		Tooltip = "Replace your local database with the one bundled for this place",
		Func = function()
			-- Double click, because this overwrites your local file with the repo's
			-- copy. Boot only does it when there is nothing local yet; this is the
			-- manual escape hatch for when you want to start over.
			local ok, err = Store.fetch()
			if not ok then
				return notify("Download failed: " .. tostring(err), 3)
			end

			Store.autosave()
			Options.TimingList:SetValue(nil)
			refreshTimingList()
			notify(string.format("Downloaded %d timings", Store.count()), 3)
		end,
	}):AddButton({
		Text = "Copy Database",
		Tooltip = "Whole timing database to the clipboard, ready to paste into the repo",
		Func = function()
			local ok, err = Store.copy()
			notify(ok and string.format("Copied %d timings", Store.count()) or ("Copy failed: " .. tostring(err)), 3)
		end,
	})

	----------------------------------------------------------------------------
	-- Hitbox preview <-> timing database
	----------------------------------------------------------------------------

	---Which timing the preview buttons act on.
	---The logger selection wins, because if the visualizer is open that is the
	---animation you are actually looking at; the dropdown is the fallback for
	---when you are tuning without the logger up.
	local function previewTarget()
		if Log.selected then
			local fromLog = Store.get(Log.selected)
			if fromLog then
				return fromLog
			end
		end
		return Store.fromDisplay(Options.TimingList.Value)
	end

	HitboxBox:AddButton({
		Text = "Load From Selected",
		Tooltip = "Pull the hitbox off the selected timing into these sliders",
		Func = function()
			local timing = previewTarget()
			if not timing then
				return notify("Select a timing, or click a logger row", 2)
			end

			timing = Store.normalise(timing)

			-- One place does this, and it is Hitbox.adopt, so the visualizer and
			-- this button cannot end up filling in different subsets of the fields.
			ctx.Hitbox.adopt(timing)

			notify("Loaded hitbox from " .. timing.name, 2)
		end,
	}):AddButton({
		Text = "Apply To Selected",
		Tooltip = "Write these sliders back and save",
		Func = function()
			local timing = previewTarget()
			if not timing then
				return notify("Select a timing, or click a logger row", 2)
			end

			timing.hitbox = {
				X = Options.HB_X.Value,
				Y = Options.HB_Y.Value,
				Z = Options.HB_Z.Value,
			}
			timing.hso = Options.HB_HSO.Value
			timing.maxDistance = Options.HB_MaxDistance.Value
			timing.forwardOffset = Options.HB_ForwardOffset.Value
			timing.shape = Options.HitboxShape.Value
			timing.faceForward = Toggles.HB_FaceForward.Value
			timing.groundAlign = Toggles.HB_GroundAlign.Value

			Store.timings[timing.id] = timing
			Store.dirty = true

			local ok, err = Store.autosave()

			-- The visualizer's Quick Edit panel shows the same numbers, so repaint
			-- it rather than leaving two views of one timing disagreeing.
			if Visualizer.syncEditor then
				pcall(Visualizer.syncEditor, timing.id)
			end

			refreshTimingList()
			-- "Applied" either way: the timing is live in memory whether or not it
			-- reached a file. The suffix says which.
			notify(
				string.format("Applied hitbox to %s%s", timing.name, ok and "" or " (" .. tostring(err) .. ")"),
				2
			)
		end,
	})

	----------------------------------------------------------------------------
	-- Effect profiles
	----------------------------------------------------------------------------

	---Push a profile into the effect builder fields.
	local function loadEffectIntoBuilder(name)
		local profile = Effects.profiles[name]

		-- No profile yet is the common case: you clicked a row to start writing
		-- one. Fill the fields from a blank template so the name is already typed
		-- in and Save Effect is the only thing left to press.
		if not profile then
			profile = Effects.template(name)
		end

		Options.E_Name:SetValue(profile.name or name)
		Options.E_TriggerDistance:SetValue(profile.triggerDistance or 60)
		Options.E_Delay:SetValue(profile.delay or 0)
		Options.E_HoldTime:SetValue(profile.holdTime or 120)
		Options.E_DodgeDir:SetValue(profile.dodgeDir or "Auto")
		Toggles.E_Dodge:SetValue(profile.dodge == true)
		Toggles.E_Enabled:SetValue(profile.enabled == true)
	end

	local function refreshEffectList()
		effectList:SetValues(Effects.display())
		effectList:Display()
	end

	ctx.loadEffectIntoBuilder = loadEffectIntoBuilder
	ctx.refreshEffectList = refreshEffectList

	Options.EffectList:OnChanged(function()
		local profile = Effects.fromDisplay(Options.EffectList.Value)
		if profile then
			loadEffectIntoBuilder(profile.name)
		end
	end)

	EffectBuildBox:AddButton({
		Text = "Save Effect",
		Tooltip = "Write the builder fields into a profile keyed on the effect name",
		Func = function()
			local name = Options.E_Name.Value
			if not name or name == "" then
				return notify("Give the effect a name, or click a row in the effect window", 2)
			end

			local profile = Effects.profiles[name] or Effects.template(name)

			profile.name = name
			profile.triggerDistance = Options.E_TriggerDistance.Value
			profile.delay = Options.E_Delay.Value
			profile.holdTime = Options.E_HoldTime.Value
			profile.dodge = Toggles.E_Dodge.Value
			profile.dodgeDir = Options.E_DodgeDir.Value
			profile.enabled = Toggles.E_Enabled.Value

			Effects.set(profile)
			Effects.save()
			refreshEffectList()
			notify(string.format("Saved %s [%s]", name, profile.dodge and "dodge" or "parry"), 2)
		end,
	}):AddButton({
		Text = "Delete Effect",
		DoubleClick = true,
		Func = function()
			local profile = Effects.fromDisplay(Options.EffectList.Value)
			if not profile then
				return notify("Pick a profile", 2)
			end
			Effects.remove(profile.name)
			Effects.save()
			Options.EffectList:SetValue(nil)
			refreshEffectList()
			notify("Deleted " .. profile.name, 2)
		end,
	})

	EffectStoreBox:AddButton({
		Text = "Save Effects",
		Func = function()
			local ok, err = Effects.save()
			notify(ok and string.format("Saved %d profiles", Effects.count()) or ("Not saved: " .. tostring(err)), 2)
		end,
	}):AddButton({
		Text = "Copy Effects",
		Tooltip = "Whole profile set to the clipboard, ready to paste into the repo",
		Func = function()
			local ok, err = Effects.copy()
			notify(ok and string.format("Copied %d profiles", Effects.count()) or ("Copy failed: " .. tostring(err)), 3)
		end,
	})

	EffectStoreBox:AddButton({
		Text = "Download Effects",
		DoubleClick = true,
		Tooltip = "Replace the loaded profiles with the ones bundled for this place",
		Func = function()
			local ok, err = Effects.fetch()
			if not ok then
				return notify("Download failed: " .. tostring(err), 3)
			end
			Options.EffectList:SetValue(nil)
			refreshEffectList()
			notify(string.format("Downloaded %d profiles", Effects.count()), 3)
		end,
	})

	Toggles.ShowEffectWindow:OnChanged(function()
		EffectGui.visible(Toggles.ShowEffectWindow.Value)
	end)

	Toggles.LogEffects:OnChanged(function()
		-- The workspace listener is the expensive part, so it only exists while
		-- something wants it. React needs it too, hence both flags.
		if Toggles.LogEffects.Value or Toggles.EffectReact.Value then
			Effects.attach()
		else
			Effects.detach()
		end
	end)

	Toggles.EffectReact:OnChanged(function()
		if Toggles.LogEffects.Value or Toggles.EffectReact.Value then
			Effects.attach()
		else
			Effects.detach()
		end
	end)

	----------------------------------------------------------------------------
	-- Dodging
	----------------------------------------------------------------------------

	Options.DashBind:OnClick(function()
		Dodge.manual()
	end)

	Toggles.ShowLoggerWindow:OnChanged(function()
		LoggerGui.visible(Toggles.ShowLoggerWindow.Value)
	end)

	Toggles.ShowAnimationVisualizer:OnChanged(function()
		Visualizer.visible(Toggles.ShowAnimationVisualizer.Value)
	end)

	-- Both re-resolve the containers, so the cached rig list has to go with them
	-- or the hitbox anchor keeps pointing at a rig from the old source.
	local function resweep()
		Hooks.detach()
		ctx.Entities.invalidate()
		task.defer(function()
			local count = Hooks.sweep()
			notify(string.format("Watching %d container(s): %s", count, Hooks.sources()), 4)
		end)
	end

	Options.EntitySource:OnChanged(resweep)
	Options.EntityFolder:OnChanged(resweep)

	return refreshTimingList
end
