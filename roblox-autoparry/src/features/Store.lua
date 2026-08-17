--[[
	features/Store.lua
	The timing database.

	One folder per PlaceId under AutoParry/timings/, so a build for one game can
	never bleed into another. Timings are written the instant they are created
	rather than on a timer, because the whole build-as-you-play workflow falls
	apart if a crash costs you the last twenty minutes of fighting.
]]

return function(ctx)
	local FS, Util, HttpService = ctx.FS, ctx.Util, ctx.HttpService

	local Store = {
		timings = {},
		configName = "default",
		dirty = false,
	}

	Store.placeFolder = ctx.TIMINGS_FOLDER .. "/" .. tostring(game.PlaceId)

	---Ensure the folder tree exists.
	function Store.init()
		FS.makeTree(Store.placeFolder)
	end

	---Path of a named config.
	function Store.path(name)
		return Store.placeFolder .. "/" .. tostring(name) .. ".json"
	end

	---Build a fresh timing from an observed animation track.
	---@param animationId string
	---@param trackLength number
	---@param entityName string
	---@return table
	function Store.template(animationId, trackLength, entityName)
		local length = (trackLength and trackLength > 0) and trackLength or 1.0
		return {
			id = animationId,
			name = entityName or "Unnamed",
			-- Where in the animation the hit lands, in milliseconds. 60% of the
			-- animation is a workable first guess for most swing animations; the
			-- editor exists so you can dial it in from there.
			delay = Util.round(length * 1000 * 0.6, 0),
			length = Util.round(length, 3),
			minDistance = 0,
			maxDistance = 85,
			holdTime = 120,
			enabled = false,
			-- Set true for attacks whose animation stops before the hit lands, so
			-- the fire-time "is it still playing" check is skipped.
			ignoreEnd = false,
			note = "",

			-- Hitbox gate, measured in the attacker's local space, so a wide
			-- horizontal sweep and a narrow forward thrust do not have to share
			-- one distance number.
			hitbox = { X = 11, Y = 10, Z = 30.5 },
			-- Hitbox size offset: studs added to every axis before the check.
			hso = 3,
			-- Block / Sphere / Cylinder. All three are real gates, not just
			-- different drawings; see Engine.inHitbox.
			shape = "Block",
			-- Push the volume out in front of the attacker so its back face lands
			-- on their root. Off keeps the old behaviour, where the volume
			-- straddles them and half of it covers their back.
			faceForward = false,
			-- Extra nudge along their look vector, in studs. Negative pulls back.
			forwardOffset = 0,
			-- Sit the volume on the rig's feet instead of on their root, which is
			-- chest height on a humanoid.
			groundAlign = false,

			-- Multi-hit attacks: parry this many times, this far apart, in seconds.
			repeatCount = 1,
			repeatDelay = 0.35,

			-- Dodge instead of parrying this attack. For moves a parry does
			-- nothing about, where rolling out is the only real answer.
			dodge = false,
			-- Dash key for this one timing. "Default" uses the global Dash Key,
			-- which is what almost every timing wants.
			dodgeKey = "Default",
			-- None / Forward / Backward / Left / Right. Held alongside the parry
			-- key when parrying, and used as the dash direction when dodging.
			dodgeDir = "None",
		}
	end

	---Fill in fields a config saved by an older build will not have.
	---Runs on every load so upgrading never means rebuilding a database by hand.
	---@param timing table
	---@return table
	function Store.normalise(timing)
		local blank = Store.template(timing.id or "", timing.length or 1, timing.name)

		for key, value in pairs(blank) do
			if timing[key] == nil then
				timing[key] = value
			end
		end

		-- Hitbox is nested, so a shallow fill leaves half of it missing.
		if type(timing.hitbox) ~= "table" then
			timing.hitbox = blank.hitbox
		else
			for _, axis in ipairs({ "X", "Y", "Z" }) do
				if type(timing.hitbox[axis]) ~= "number" then
					timing.hitbox[axis] = blank.hitbox[axis]
				end
			end
		end

		return timing
	end

	---Look up a timing.
	function Store.get(animationId)
		return Store.timings[animationId]
	end

	---Insert a timing and write to disk right away.
	---@param timing table
	---@param autoSave boolean
	function Store.create(timing, autoSave)
		Store.timings[timing.id] = timing
		Store.dirty = true
		if autoSave then
			Store.save(Store.configName)
		end
		return timing
	end

	---Remove a timing.
	function Store.remove(animationId)
		Store.timings[animationId] = nil
		Store.dirty = true
	end

	---Serialize the whole database to a JSON string.
	---@return string?, string?
	function Store.encode()
		local payload = {
			version = ctx.VERSION,
			placeId = game.PlaceId,
			timings = {},
		}

		for id, timing in pairs(Store.timings) do
			payload.timings[id] = timing
		end

		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
		if not ok then
			return nil, "encode failed"
		end

		return encoded
	end

	---May we write the database to the executor's disk?
	---Default is no. The database is served from the repo, and a copy sitting in
	---someone's workspace folder is a copy you did not intend to hand out.
	---@return boolean
	function Store.cacheEnabled()
		local Toggles = ctx.Toggles
		return (Toggles and Toggles.LocalCache and Toggles.LocalCache.Value) == true
	end

	---Serialize the whole database to a config file.
	---A no-op when the local cache is off, and it says so rather than reporting a
	---success that never touched the disk.
	---@return boolean, string?
	function Store.save(name)
		if not Store.cacheEnabled() then
			return false, "local cache off"
		end

		Store.init()

		local encoded, err = Store.encode()
		if not encoded then
			return false, err
		end

		local written = FS.write(Store.path(name), encoded)
		if written then
			Store.dirty = false
		end
		return written == true, written and nil or "write failed"
	end

	---Put the whole database on the clipboard, ready to paste into the repo.
	---This is the export path when the local cache is off: your tuning still has
	---somewhere to go, it just does not go to a file on disk by itself.
	---@return boolean, string?
	function Store.copy()
		local encoded, err = Store.encode()
		if not encoded then
			return false, err
		end

		local clip = rawget(getgenv(), "setclipboard") or setclipboard
		if not clip then
			return false, "no setclipboard in this executor"
		end

		local ok = pcall(clip, encoded)
		return ok, ok and nil or "clipboard write failed"
	end

	---Replace the in-memory database from a JSON string.
	---Split out of Store.load so a file on disk and a payload pulled off the repo
	---go through exactly one parsing and normalising path.
	---@param raw string
	---@return boolean, string?
	function Store.adopt(raw)
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or type(decoded) ~= "table" or type(decoded.timings) ~= "table" then
			return false, "corrupt config"
		end

		Store.timings = {}
		for id, timing in pairs(decoded.timings) do
			timing.id = timing.id or id
			Store.timings[id] = Store.normalise(timing)
		end

		return true
	end

	---Load a config file, replacing the in-memory database.
	function Store.load(name)
		local raw = FS.read(Store.path(name))
		if not raw then
			return false, "no such config"
		end

		local ok, err = Store.adopt(raw)
		if not ok then
			return false, err
		end

		Store.configName = name
		Store.dirty = false
		return true
	end

	---Pull the database this script ships with for the current place.
	---Nothing is written to disk here; the caller decides whether to keep it.
	---@return boolean, string?
	function Store.fetch()
		local url = ctx.DATA_REPO .. "timings/" .. tostring(game.PlaceId) .. "/default.json"

		-- A place with no bundled database gets a 404, which executors surface
		-- either as a thrown error or as an HTML body. pcall covers the first,
		-- and Store.adopt failing to decode it covers the second.
		local got, body = pcall(game.HttpGet, game, url)
		if not got or type(body) ~= "string" or body == "" then
			return false, "no bundled timings for this place"
		end

		local ok, err = Store.adopt(body)
		if not ok then
			return false, err
		end

		Store.configName = "default"
		Store.dirty = true
		return true
	end

	---How many timings are loaded.
	function Store.count()
		local n = 0
		for _ in pairs(Store.timings) do
			n = n + 1
		end
		return n
	end

	---List config names for this place.
	function Store.list()
		local out = {}
		for _, file in ipairs(FS.list(Store.placeFolder)) do
			local name = tostring(file):match("([^/\\]+)%.json$")
			if name then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	---Sorted display list of timings for the dropdown.
	function Store.display()
		local out = {}
		for id, timing in pairs(Store.timings) do
			table.insert(
				out,
				string.format("%s [%s]%s", timing.name, Util.shortId(id), timing.enabled and "" or " (off)")
			)
		end
		table.sort(out)
		return out
	end

	---Resolve a display string back to its timing.
	function Store.fromDisplay(display)
		if type(display) ~= "string" then
			return nil
		end

		local short = display:match("%[(%d+)%]")
		if not short then
			return nil
		end

		for id, timing in pairs(Store.timings) do
			if Util.shortId(id) == short then
				return timing
			end
		end
		return nil
	end

	ctx.Store = Store
	return Store
end
