--[[
	features/Entities.lua
	Where the combat characters live, and whether one is worth parrying.

	This module is what makes the script game-agnostic. Nothing above it knows a
	game's folder names; Auto mode probes the handful of names most Roblox combat
	games use, and Custom lets you name the folders outright when a game does
	something unusual.

	Auto resolves to a LIST, not a single folder, because plenty of games split
	their combatants: players in one folder, mobs in another. Returning only the
	first match meant every attack from the other folder was invisible - no
	animator in it was ever hooked, so nothing about it could reach the logger.
]]

return function(ctx)
	local Util, Workspace, Players, LocalPlayer = ctx.Util, ctx.Workspace, ctx.Players, ctx.LocalPlayer

	local Entities = {}

	-- Probed in order by Auto mode. Every one that exists is used, not just the
	-- first. "Players" is last because when a game has both, the mob folder is
	-- the more specific signal about how that game is laid out.
	Entities.CANDIDATES = { "Live", "Characters", "Enemies", "Mobs", "NPCs", "Players" }

	---Split a Custom folder field on commas, so two folders can be named at once.
	---@param raw string
	---@return table
	local function parseCustom(raw)
		local out = {}

		for name in tostring(raw):gmatch("[^,]+") do
			local trimmed = name:match("^%s*(.-)%s*$")
			if trimmed ~= "" then
				local found = Workspace:FindFirstChild(trimmed)
				if found then
					table.insert(out, found)
				end
			end
		end

		return out
	end

	---Every container that holds combat characters.
	---@return table
	function Entities.containers()
		local Options = ctx.Options
		local mode = Options and Options.EntitySource and Options.EntitySource.Value or "Auto"

		if mode == "Workspace" then
			return { Workspace }
		end

		if mode == "Custom" then
			local found = parseCustom(Options and Options.EntityFolder and Options.EntityFolder.Value or "")
			return #found > 0 and found or { Workspace }
		end

		local out = {}
		for _, candidate in ipairs(Entities.CANDIDATES) do
			local found = Workspace:FindFirstChild(candidate)
			if found then
				table.insert(out, found)
			end
		end

		-- No named folder anywhere: the game keeps characters loose in workspace.
		return #out > 0 and out or { Workspace }
	end

	---First container. Kept for callers that only need somewhere to start.
	---@return Instance
	function Entities.container()
		return Entities.containers()[1] or Workspace
	end

	---@param instance Instance
	---@return boolean
	local function isRig(instance)
		return instance:IsA("Model") and instance:FindFirstChildWhichIsA("Humanoid") ~= nil
	end

	-- Entities.list runs from Hitbox.step, which is on the render step, and from
	-- Effects.creatorAt, which runs per spawned instance. Both would otherwise
	-- rebuild this table hundreds of times a second for a set that changes on the
	-- order of seconds.
	local cache, cacheClock = {}, 0
	local CACHE_SECONDS = 0.25

	---Drop the cached rig list. Call after anything that changes the containers.
	function Entities.invalidate()
		cacheClock = 0
	end

	---Every rig in every container, humanoid only.
	---@return table
	function Entities.list()
		if os.clock() - cacheClock < CACHE_SECONDS then
			return cache
		end

		local out, seen = {}, {}

		local function add(instance)
			if not seen[instance] and isRig(instance) then
				seen[instance] = true
				table.insert(out, instance)
			end
		end

		for _, container in ipairs(Entities.containers()) do
			for _, child in ipairs(container:GetChildren()) do
				add(child)

				-- One level deeper, but only through Folders. A container of
				-- containers is how games nest this; a character is a Model, so
				-- descending into every Model would walk accessories and gear for
				-- nothing. Workspace mode leans on this to reach Workspace.Players
				-- without a full descendant walk of the whole map.
				if child:IsA("Folder") then
					for _, nested in ipairs(child:GetChildren()) do
						add(nested)
					end
				end
			end
		end

		cache, cacheClock = out, os.clock()
		return out
	end

	---Is this entity a valid parry target right now?
	---@param entity Model
	---@return boolean, string
	function Entities.valid(entity)
		local Toggles, Options = ctx.Toggles, ctx.Options
		local character = LocalPlayer.Character

		if not character then
			return false, "no local character"
		end

		if entity == character then
			return false, "self"
		end

		if not Util.alive(entity) then
			return false, "dead"
		end

		local isPlayer = Players:GetPlayerFromCharacter(entity) ~= nil

		if isPlayer and Toggles.IgnorePlayers and Toggles.IgnorePlayers.Value then
			return false, "players ignored"
		end

		if not isPlayer and Toggles.IgnoreNPCs and Toggles.IgnoreNPCs.Value then
			return false, "npcs ignored"
		end

		if Toggles.OnlyWhenTargeted and Toggles.OnlyWhenTargeted.Value then
			local target = entity:FindFirstChild("Target")
			if target and target:IsA("ObjectValue") and target.Value ~= character then
				return false, "not targeting us"
			end
		end

		if Toggles.RequireFacing and Toggles.RequireFacing.Value then
			local dot = Util.facing(entity, character)
			local minimum = (Options.FacingDot and Options.FacingDot.Value or 0.4)
			if not dot or dot < minimum then
				return false, "not facing us"
			end
		end

		return true, "ok"
	end

	ctx.Entities = Entities
	return Entities
end
