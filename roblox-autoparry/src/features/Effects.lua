--[[
	features/Effects.lua
	Unknown effect logger, and the profiles built from it.

	Some attacks never touch an Animator. Projectiles, ground slams, telegraph
	decals and cast sounds all arrive as new instances in the workspace instead,
	which the animation hooks are structurally blind to. This module watches for
	those instances, logs them, and lets you turn one into a rule: "when a thing
	called Fireball appears within 60 studs, dodge."

	Two things keep the log usable rather than a wall of noise:

	  - The workspace churns constantly. Only instances that appear NEAR you and
	    are plausibly combat effects get through the filter in Effects.consider.
	  - One row per name. A boss that fires forty identical projectiles is one
	    entry with a counter, not forty rows.

	Profiles are matched on name, because that is the only property that is
	stable across spawns. The window that renders this lives in
	ui/EffectWindow.lua.
]]

return function(ctx)
	local Workspace, HttpService = ctx.Workspace, ctx.HttpService
	local FS, Util, Entities, LocalPlayer = ctx.FS, ctx.Util, ctx.Entities, ctx.LocalPlayer

	local Effects = {
		entries = {},
		seen = {},
		profiles = {},
		selected = nil,
		max = 120,
		connections = {},
		triggers = 0,
	}

	Effects.placeFolder = ctx.EFFECTS_FOLDER .. "/" .. tostring(game.PlaceId)

	-- Anything whose name matches one of these is engine furniture, not an
	-- effect. Cheaper and far more reliable than trying to whitelist effects.
	local IGNORE = {
		"^Camera$",
		"^Terrain$",
		"^Baseplate$",
		"Thumbnail",
		"^Handle$",
		"^HumanoidRootPart$",
		"^Head$",
		"^Torso$",
		"^Right",
		"^Left",
		"^UpperTorso$",
		"^LowerTorso$",
	}

	---Is this instance worth a row?
	---@param instance Instance
	---@return boolean
	local function interesting(instance)
		if not (instance:IsA("BasePart") or instance:IsA("Sound") or instance:IsA("ParticleEmitter")) then
			return false
		end

		local name = instance.Name
		if name == "" then
			return false
		end

		for _, pattern in ipairs(IGNORE) do
			if name:match(pattern) then
				return false
			end
		end

		-- Anything inside a rig is that rig's body or gear, not a spawned effect.
		local model = instance:FindFirstAncestorWhichIsA("Model")
		if model and model:FindFirstChildWhichIsA("Humanoid") then
			return false
		end

		return true
	end

	---Where an instance is, if it is anywhere.
	---@param instance Instance
	---@return Vector3?
	local function positionOf(instance)
		if instance:IsA("BasePart") then
			return instance.Position
		end

		local parent = instance.Parent
		if parent and parent:IsA("BasePart") then
			return parent.Position
		end
		if parent and parent:IsA("Model") then
			local root = Util.root(parent)
			return root and root.Position
		end

		return nil
	end

	---Nearest live rig to a point, which is the best guess at who made this.
	---@param position Vector3
	---@return string, number
	local function creatorAt(position)
		local best, bestDistance = "?", math.huge

		for _, entity in ipairs(Entities.list()) do
			local root = Util.root(entity)
			if root and Util.alive(entity) then
				local distance = (root.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = entity.Name, distance
				end
			end
		end

		return best, bestDistance
	end

	----------------------------------------------------------------------------
	-- Logging
	----------------------------------------------------------------------------

	---Consider one newly spawned instance.
	---@param instance Instance
	function Effects.consider(instance)
		local Toggles, Options = ctx.Toggles, ctx.Options

		local logging = (Toggles and Toggles.LogEffects and Toggles.LogEffects.Value) == true
		local reacting = (Toggles and Toggles.EffectReact and Toggles.EffectReact.Value) == true

		-- Reacting without logging is a real configuration: once your profiles are
		-- built, the log is just noise you are paying for every frame.
		if not logging and not reacting then
			return
		end

		if not interesting(instance) then
			return
		end

		local character = LocalPlayer.Character
		local ourRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not ourRoot then
			return
		end

		local position = positionOf(instance)
		if not position then
			return
		end

		local distance = (position - ourRoot.Position).Magnitude
		local range = (Options and Options.EffectLogRange and Options.EffectLogRange.Value) or 120

		if distance > range then
			return
		end

		local known = Effects.profiles[instance.Name] ~= nil
		local onlyUnknown = (Toggles.LogOnlyUnknownEffects and Toggles.LogOnlyUnknownEffects.Value) == true

		if not logging or (onlyUnknown and known) then
			Effects.react(instance, distance)
			return
		end

		local existing = Effects.seen[instance.Name]

		if existing then
			-- One row per name, with a counter. Forty identical projectiles from
			-- one boss is one entry, not forty.
			existing.count = existing.count + 1
			existing.time = os.date("%H:%M:%S")
			existing.distance = Util.round(distance, 1)
			existing.instance = instance
		else
			local creator, creatorDistance = creatorAt(position)

			local entry = {
				name = instance.Name,
				className = instance.ClassName,
				parent = instance.Parent and instance.Parent.Name or "?",
				creator = creator,
				creatorDistance = Util.round(creatorDistance, 1),
				time = os.date("%H:%M:%S"),
				distance = Util.round(distance, 1),
				count = 1,
				instance = instance,
			}

			Effects.seen[instance.Name] = entry
			table.insert(Effects.entries, 1, entry)

			while #Effects.entries > Effects.max do
				local dropped = table.remove(Effects.entries)
				if dropped and Effects.seen[dropped.name] == dropped then
					Effects.seen[dropped.name] = nil
				end
			end
		end

		Effects.react(instance, distance)
	end

	function Effects.clear()
		Effects.entries = {}
		Effects.seen = {}
		Effects.selected = nil
	end

	---Look an entry up by name.
	function Effects.get(name)
		return Effects.seen[name]
	end

	----------------------------------------------------------------------------
	-- Reacting
	----------------------------------------------------------------------------

	---Run the profile for a spawned instance, if it has one and it is in range.
	---@param instance Instance
	---@param distance number
	function Effects.react(instance, distance)
		local Toggles = ctx.Toggles

		if not (Toggles and Toggles.EffectReact and Toggles.EffectReact.Value) then
			return
		end

		local profile = Effects.profiles[instance.Name]
		if not profile or not profile.enabled then
			return
		end

		if distance > (profile.triggerDistance or 60) then
			return
		end

		Effects.triggers = Effects.triggers + 1

		task.delay((profile.delay or 0) / 1000, function()
			if profile.dodge then
				if ctx.Dodge then
					ctx.Dodge.dash(profile.dodgeDir or "Auto")
				end
				return
			end

			-- Reuse the parry path rather than pressing the key directly, so the
			-- cooldown, the dead check and the manual-input guard all still apply.
			if ctx.Engine then
				ctx.Engine.fire({
					name = profile.name,
					delay = profile.delay or 0,
					holdTime = profile.holdTime or 120,
					dodgeDir = "None",
				})
			end
		end)
	end

	----------------------------------------------------------------------------
	-- Profiles
	----------------------------------------------------------------------------

	---A blank profile for an effect name.
	---@param name string
	---@return table
	function Effects.template(name)
		return {
			name = name,
			-- Studs from you at spawn time. Past this, the effect is someone
			-- else's problem.
			triggerDistance = 60,
			-- Dodge instead of parrying. Projectiles you cannot parry are the
			-- whole reason this flag exists.
			dodge = false,
			dodgeDir = "Auto",
			-- Milliseconds between the effect appearing and the reaction. A
			-- telegraph decal lands well before its hit does.
			delay = 0,
			holdTime = 120,
			enabled = false,
		}
	end

	---Insert or replace a profile.
	function Effects.set(profile)
		Effects.profiles[profile.name] = profile
		return profile
	end

	function Effects.remove(name)
		Effects.profiles[name] = nil
	end

	function Effects.count()
		local n = 0
		for _ in pairs(Effects.profiles) do
			n = n + 1
		end
		return n
	end

	---Sorted display list for the dropdown.
	function Effects.display()
		local out = {}
		for name, profile in pairs(Effects.profiles) do
			table.insert(
				out,
				string.format("%s [%s]%s", name, profile.dodge and "dodge" or "parry", profile.enabled and "" or " (off)")
			)
		end
		table.sort(out)
		return out
	end

	---Resolve a display string back to its profile.
	function Effects.fromDisplay(display)
		if type(display) ~= "string" then
			return nil
		end
		local name = display:match("^(.-) %[")
		return name and Effects.profiles[name] or nil
	end

	----------------------------------------------------------------------------
	-- Storage
	----------------------------------------------------------------------------

	function Effects.path()
		return Effects.placeFolder .. "/default.json"
	end

	---@return string?
	function Effects.encode()
		local payload = { version = ctx.VERSION, placeId = game.PlaceId, effects = {} }

		for name, profile in pairs(Effects.profiles) do
			payload.effects[name] = profile
		end

		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
		return ok and encoded or nil
	end

	---Replace the profile table from a JSON string.
	---@param raw string
	---@return boolean, string?
	function Effects.adopt(raw)
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or type(decoded) ~= "table" or type(decoded.effects) ~= "table" then
			return false, "corrupt effects file"
		end

		Effects.profiles = {}
		for name, profile in pairs(decoded.effects) do
			local blank = Effects.template(name)
			for key, value in pairs(blank) do
				if profile[key] == nil then
					profile[key] = value
				end
			end
			profile.name = profile.name or name
			Effects.profiles[name] = profile
		end

		return true
	end

	---Write the profiles to disk. Honours the same local-cache switch the timing
	---database does, so "no local output" means no local output for both.
	---@return boolean, string?
	function Effects.save()
		if not ctx.Store.cacheEnabled() then
			return false, "local cache off"
		end

		FS.makeTree(Effects.placeFolder)

		local encoded = Effects.encode()
		if not encoded then
			return false, "encode failed"
		end

		return FS.write(Effects.path(), encoded) == true, nil
	end

	---@return boolean, string?
	function Effects.load()
		local raw = FS.read(Effects.path())
		if not raw then
			return false, "no effects file"
		end
		return Effects.adopt(raw)
	end

	---Pull the profiles bundled with the script for this place.
	---@return boolean, string?
	function Effects.fetch()
		local url = ctx.DATA_REPO .. "effects/" .. tostring(game.PlaceId) .. "/default.json"

		local got, body = pcall(game.HttpGet, game, url)
		if not got or type(body) ~= "string" or body == "" then
			return false, "no bundled effects for this place"
		end

		return Effects.adopt(body)
	end

	---@return boolean, string?
	function Effects.copy()
		local encoded = Effects.encode()
		if not encoded then
			return false, "encode failed"
		end

		local clip = rawget(getgenv(), "setclipboard") or setclipboard
		if not clip then
			return false, "no setclipboard in this executor"
		end

		return pcall(clip, encoded)
	end

	----------------------------------------------------------------------------
	-- Hooks
	----------------------------------------------------------------------------

	---Start watching the workspace.
	---DescendantAdded on the whole workspace is a firehose, which is why
	---Effects.consider filters hard and returns early on the cheap checks first.
	function Effects.attach()
		Effects.detach()

		table.insert(
			Effects.connections,
			Workspace.DescendantAdded:Connect(function(instance)
				local ok, err = pcall(Effects.consider, instance)
				if not ok and ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
					warn("[Fleur] effects: " .. tostring(err))
				end
			end)
		)
	end

	function Effects.detach()
		for _, connection in ipairs(Effects.connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		Effects.connections = {}
	end

	ctx.Effects = Effects
	return Effects
end

