--[[
	Fleur - single file build
	Roblox / Luau, executor script.

	GENERATED FILE - do not edit. Edit the modules in src/ and run:
		node build.js

	Run this:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/gakuran/main/roblox-autoparry/AutoParry.lua"))()

	Modules are inlined in dependency order and each is called with one shared
	context table, so ctx.Store, ctx.Engine and friends resolve the same way
	they do under init.lua.
]]

-- Single instance: unload whatever is already running before starting over.
do
	local existing = rawget(getgenv(), "AutoParryContext")
	if existing and existing.Library and not existing.Library.Unloaded then
		pcall(function()
			existing.Library:Unload()
		end)
		task.wait(0.2)
	end
end

local ctx = {}
getgenv().AutoParryContext = ctx


--------------------------------------------------------------------------------
-- src/core/Config.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Config.lua
			Constants, services and the folder layout every other module reads from.
		]]

		return function(ctx)
			ctx.VERSION = "1.0.0"
			ctx.LIB_REPO = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

			-- Where the bundled timing databases are fetched from when a place has no
			-- local one yet. Must end in a slash.
			ctx.DATA_REPO = "https://raw.githubusercontent.com/fakedemonn/gakuran/main/roblox-autoparry/"

			-- Folder layout inside the executor workspace:
			--   AutoParry/
			--     timings/<PlaceId>/<config>.json   the timing databases
			--     effects/<PlaceId>/default.json    the effect / projectile profiles
			--     settings/                         LinoriaLib UI config
			--     themes/                           LinoriaLib themes
			-- These three used to be sliders on the Auto Parry tab. Hold time is a
			-- per-timing field now, and the other two are floors rather than knobs, so
			-- they live here instead of taking up UI space.
			ctx.PARRY_COOLDOWN = 60 -- ms, minimum gap between two parries
			ctx.PARRY_HOLD = 120 -- ms, fallback when a timing has no holdTime

			-- Full round trip, always. Stats "Data Ping" is a round trip: the attacker's
			-- animation started one one-way-delay ago and our keypress needs another to
			-- reach the server, so subtracting all of it is the correct default rather
			-- than a number worth exposing. Timing Offset is the knob now.
			ctx.PING_COMPENSATION = 1.0

			-- Enemy hitboxes are drawn across the damage window only, not the whole
			-- swing. The window opens LEAD ms before the hit lands and closes TAIL ms
			-- after the parry hold has run out, so what you see on screen is the span
			-- where being inside the box actually costs you something.
			ctx.HITBOX_WINDOW_LEAD = 80 -- ms before the hit
			ctx.HITBOX_WINDOW_TAIL = 60 -- ms after the hold expires
			ctx.HITBOX_WINDOW_MIN = 0.1 -- seconds, floor so a fast move still registers

			ctx.ROOT_FOLDER = "AutoParry"
			ctx.TIMINGS_FOLDER = "AutoParry/timings"
			ctx.SETTINGS_FOLDER = "AutoParry/settings"
			ctx.EFFECTS_FOLDER = "AutoParry/effects"

			ctx.Players = game:GetService("Players")
			ctx.RunService = game:GetService("RunService")
			ctx.HttpService = game:GetService("HttpService")
			ctx.UserInputService = game:GetService("UserInputService")
			ctx.Stats = game:GetService("Stats")
			ctx.Workspace = game:GetService("Workspace")

			ctx.LocalPlayer = ctx.Players.LocalPlayer
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/Config.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/FS.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/FS.lua
			Thin wrapper over the executor filesystem API.

			Every call is pcall'd and every failure is a return value, never a throw, so a
			missing executor function degrades the script instead of killing it. Check
			FS.available before promising the user their timings will persist.
		]]

		return function(ctx)
			local FS = {}

			local w, r, i, mf, isf, lf =
				rawget(getgenv(), "writefile") or writefile,
				rawget(getgenv(), "readfile") or readfile,
				rawget(getgenv(), "isfile") or isfile,
				rawget(getgenv(), "makefolder") or makefolder,
				rawget(getgenv(), "isfolder") or isfolder,
				rawget(getgenv(), "listfiles") or listfiles

			FS.available = (w and r and i and mf and isf and lf) ~= nil

			function FS.write(path, data)
				if not FS.available then
					return false
				end
				return pcall(w, path, data)
			end

			function FS.read(path)
				if not FS.available then
					return nil
				end
				local ok, data = pcall(r, path)
				return ok and data or nil
			end

			function FS.isFile(path)
				if not FS.available then
					return false
				end
				local ok, res = pcall(i, path)
				return ok and res or false
			end

			function FS.isFolder(path)
				if not FS.available then
					return false
				end
				local ok, res = pcall(isf, path)
				return ok and res or false
			end

			function FS.makeFolder(path)
				if not FS.available then
					return false
				end
				if FS.isFolder(path) then
					return true
				end
				return pcall(mf, path)
			end

			---Create a nested path one level at a time.
			---Plenty of executors will not create intermediate folders for you, so
			---writing to "AutoParry/timings/123" fails silently unless we walk it.
			---@param path string
			function FS.makeTree(path)
				local built = nil

				for segment in tostring(path):gmatch("[^/\\]+") do
					built = built and (built .. "/" .. segment) or segment
					FS.makeFolder(built)
				end

				return FS.isFolder(path)
			end

			function FS.list(path)
				if not FS.available or not FS.isFolder(path) then
					return {}
				end
				local ok, res = pcall(lf, path)
				return ok and res or {}
			end

			function FS.delete(path)
				local d = rawget(getgenv(), "delfile") or delfile
				if not d then
					return false
				end
				return pcall(d, path)
			end

			ctx.FS = FS
			return FS
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/FS.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Util.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Util.lua
			Small pure helpers. No state, no dependencies.
		]]

		return function(ctx)
			local Util = {}

			---Round a number to n decimal places.
			function Util.round(n, places)
				local mult = 10 ^ (places or 0)
				return math.floor(n * mult + 0.5) / mult
			end

			---Strip an AnimationId down to its numeric part for display.
			function Util.shortId(animationId)
				return (tostring(animationId):gsub("rbxassetid://", ""):gsub("http://www.roblox.com/asset/%?id=", ""))
			end

			---Safe distance between two models.
			function Util.distance(a, b)
				local ra = a and a:FindFirstChild("HumanoidRootPart")
				local rb = b and b:FindFirstChild("HumanoidRootPart")
				if not ra or not rb then
					return nil
				end
				return (ra.Position - rb.Position).Magnitude
			end

			---Dot product of A's look vector against the direction to B. 1 = facing directly.
			function Util.facing(a, b)
				local ra = a and a:FindFirstChild("HumanoidRootPart")
				local rb = b and b:FindFirstChild("HumanoidRootPart")
				if not ra or not rb then
					return nil
				end
				local dir = (rb.Position - ra.Position)
				if dir.Magnitude < 0.001 then
					return 1
				end
				return ra.CFrame.LookVector:Dot(dir.Unit)
			end

			---Is this model alive?
			function Util.alive(model)
				local hum = model and model:FindFirstChildWhichIsA("Humanoid")
				return hum ~= nil and hum.Health > 0
			end

			---The part everything else measures from.
			---One place to look so the engine, the preview and the effect logger cannot
			---disagree about what "the rig's position" means.
			---@param model Model?
			---@return BasePart?
			function Util.root(model)
				if not model or not model.Parent then
					return nil
				end
				return model.PrimaryPart
					or model:FindFirstChild("HumanoidRootPart")
					or model:FindFirstChildWhichIsA("BasePart")
			end

			---World Y of the rig's feet.
			---Taken from the bounding box rather than HipHeight + root size, because R6,
			---R15 and custom NPC rigs all disagree about those two and none of them
			---disagree about where the lowest part is.
			---@param model Model
			---@return number?
			function Util.groundY(model)
				if not model then
					return nil
				end
				local ok, cf, size = pcall(function()
					local a, b = model:GetBoundingBox()
					return a, b
				end)
				if not ok or not cf then
					return nil
				end
				return cf.Position.Y - (size.Y / 2)
			end

			ctx.Util = Util
			return Util
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/Util.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Input.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Input.lua
			Keyboard output.

			VirtualInputManager is preferred because it goes through Roblox's own input
			pipeline, so the game sees a normal key event. keypress/keyrelease is the
			fallback for executors that block VIM; it needs Windows virtual key codes,
			which is why the VK table exists.
		]]

		return function(ctx)
			local Input = {}

			-- Windows virtual key codes for the keys we let the user bind.
			local VK = {
				A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
				H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
				O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
				V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,
				One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, Five = 0x35,
				Space = 0x20, LeftShift = 0xA0, LeftControl = 0xA2, LeftAlt = 0xA4,
			}

			local vim = nil
			pcall(function()
				vim = game:GetService("VirtualInputManager")
			end)

			local kp = rawget(getgenv(), "keypress") or keypress
			local kr = rawget(getgenv(), "keyrelease") or keyrelease

			Input.keys = {}
			for name in pairs(VK) do
				table.insert(Input.keys, name)
			end
			table.sort(Input.keys)

			Input.available = (vim ~= nil) or (kp ~= nil and kr ~= nil)

			---Press a key down.
			---@param keyName string
			function Input.down(keyName)
				local enum = Enum.KeyCode[keyName]
				if vim then
					pcall(function()
						vim:SendKeyEvent(true, enum, false, game)
					end)
					return
				end
				if kp and VK[keyName] then
					pcall(kp, VK[keyName])
				end
			end

			---Release a key.
			---@param keyName string
			function Input.up(keyName)
				local enum = Enum.KeyCode[keyName]
				if vim then
					pcall(function()
						vim:SendKeyEvent(false, enum, false, game)
					end)
					return
				end
				if kr and VK[keyName] then
					pcall(kr, VK[keyName])
				end
			end

			---Press and hold a key for a duration, then release.
			---@param keyName string
			---@param holdSeconds number
			function Input.tap(keyName, holdSeconds)
				Input.down(keyName)
				task.delay(math.max(holdSeconds, 0.01), function()
					Input.up(keyName)
				end)
			end

			ctx.Input = Input
			return Input
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/Input.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Latency.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Latency.lua
			Network timing.

			Stats "Data Ping" is a ROUND TRIP measurement, not one-way. Getting this
			backwards is the single most common way an auto parry ends up firing at
			double the intended offset, so the two functions are named to make the
			distinction impossible to miss at the call site.
		]]

		return function(ctx)
			local Latency = {}

			---Round trip time in seconds.
			function Latency.rtt()
				local network = ctx.Stats:FindFirstChild("Network")
				local item = network and network:FindFirstChild("ServerStatsItem")
				local ping = item and item:FindFirstChild("Data Ping")
				if not ping then
					return 0
				end
				local ok, value = pcall(function()
					return ping:GetValue()
				end)
				return ok and (value / 1000) or 0
			end

			---One-way delay in seconds.
			function Latency.half()
				return math.max(Latency.rtt() / 2, 0)
			end

			ctx.Latency = Latency
			return Latency
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/Latency.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/State.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/State.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Notify.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Notify.lua
			One notification entry point.

			Deliberately safe to call before the UI exists: modules further down load
			before ui/Library.lua, and a notification during boot should be a no-op
			rather than an error.
		]]

		return function(ctx)
			local function notify(text, duration)
				local Library = ctx.Library
				if Library and Library.Notify then
					Library:Notify(text, duration or 2)
				end
			end

			ctx.notify = notify
			return notify
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/core/Notify.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Dodge.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Dodge.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Store.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			features/Store.lua
			The timing database.

			One folder per PlaceId under AutoParry/timings/, so a build for one game can
			never bleed into another. There is exactly one file per place - default.json -
			and it is written the instant anything changes rather than on a timer or on a
			button. Named configs and manual Save/Load are gone: the whole
			build-as-you-play workflow falls apart the moment persistence is something
			you can forget to press.
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
			---The second argument used to be an opt-in. It is ignored now - a timing that
			---exists in memory but not on disk is a timing you lose to a crash, and there
			---was never a good reason to want that.
			---@param timing table
			function Store.create(timing)
				Store.timings[timing.id] = timing
				Store.dirty = true
				Store.autosave()
				return timing
			end

			---Remove a timing.
			function Store.remove(animationId)
				Store.timings[animationId] = nil
				Store.dirty = true
				Store.autosave()
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
			---The old answer was "only if a toggle says so", which meant tuning could be
			---lost silently. Now the only thing that can say no is the executor itself
			---not exposing writefile.
			---@return boolean
			function Store.cacheEnabled()
				return FS.available == true
			end

			---Serialize the whole database to a config file.
			---@return boolean, string?
			function Store.save(name)
				if not FS.available then
					return false, "no filesystem access"
				end

				Store.init()

				local encoded, err = Store.encode()
				if not encoded then
					return false, err
				end

				local written = FS.write(Store.path(name or Store.configName), encoded)
				if written then
					Store.dirty = false
				end
				return written == true, written and nil or "write failed"
			end

			---Write the one file this place has, right now.
			---
			---Everything that mutates a timing calls this: creating a stub, editing in the
			---builder, applying a hitbox, saving from the visualizer, deleting. Debounced
			---by a scheduled flush rather than a timer, so a burst of edits in one frame
			---is one write instead of six, while still landing on disk the same frame the
			---UI says it did.
			---@return boolean, string?
			function Store.autosave()
				if not FS.available then
					return false, "no filesystem access"
				end

				if Store.flushQueued then
					return true
				end

				Store.flushQueued = true
				task.defer(function()
					Store.flushQueued = false
					local ok, err = Store.save(Store.configName)
					if not ok and ctx.notify then
						ctx.notify("Timings not saved: " .. tostring(err), 4)
					end
				end)

				return true
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Store.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Log.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Log.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Entities.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Entities.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Engine.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			features/Engine.lua
			The auto parry itself.

			Timing model
			------------
			Stats "Data Ping" is a round trip. The attacker's animation started roughly
			one one-way-delay ago, and our keypress needs another one-way-delay to reach
			the server, so subtracting the FULL rtt puts the input on the server at the
			moment the hit lands:

			    wait = (delay / 1000) - (rtt * compensation) - offset + jitter

			Everything is revalidated inside the delayed callback rather than trusted
			from schedule time, because a wind-up is long enough for the target to die,
			despawn, or walk out of range.
		]]

		return function(ctx)
			local Util, Input, Latency = ctx.Util, ctx.Input, ctx.Latency
			local Store, Log, Entities, State = ctx.Store, ctx.Log, ctx.Entities, ctx.State
			local LocalPlayer, notify = ctx.LocalPlayer, ctx.notify

			local Engine = {}

			-- "Back" is the old spelling. Databases saved before the dodge rework still
			-- carry it, so it maps to the same key rather than silently becoming a
			-- neutral parry on every timing you already tuned.
			local DODGE_KEYS = { Left = "A", Right = "D", Backward = "S", Back = "S", Forward = "W" }

			---Debug notification, only when the toggle is on.
			local function debug(fmt, ...)
				local Toggles = ctx.Toggles
				if Toggles.ShowDebug and Toggles.ShowDebug.Value then
					notify(string.format(fmt, ...), 2)
				end
			end

			----------------------------------------------------------------------------
			-- Hitbox geometry
			--
			-- Size and placement live here, and features/Hitbox.lua draws with the exact
			-- same two functions. That is the whole point: the picture on screen cannot
			-- drift out of agreement with the gate, because there is only one copy of the
			-- maths for either of them to drift from.
			----------------------------------------------------------------------------

			---Outer dimensions of the gate, padding included.
			---@param timing table
			---@return Vector3
			function Engine.hitboxSize(timing)
				local hitbox = timing.hitbox or {}
				local pad = (timing.hso or 0) * 2

				return Vector3.new((hitbox.X or 0) + pad, (hitbox.Y or 0) + pad, (hitbox.Z or 0) + pad)
			end

			---Where the gate actually sits, in world space.
			---
			---Roblox look vectors point down -Z, so "in front of the attacker" is
			---NEGATIVE local Z. faceForward pushes the volume out by half its depth so
			---its back face lands on the root instead of the volume straddling it, which
			---is what you want for a swing: nothing behind the attacker counts.
			---@param timing table
			---@param entity Model
			---@return CFrame?
			function Engine.hitboxCFrame(timing, entity)
				local root = Util.root(entity)
				if not root then
					return nil
				end

				local size = Engine.hitboxSize(timing)
				local forward = timing.forwardOffset or 0

				if timing.faceForward then
					forward = forward + (size.Z / 2)
				end

				local cf = root.CFrame * CFrame.new(0, 0, -forward)

				-- Ground align: drop the volume so its underside sits on the rig's feet
				-- rather than on the root, which is chest height on most humanoids.
				if timing.groundAlign then
					local feet = Util.groundY(entity)
					if feet then
						local position = cf.Position
						cf = CFrame.new(position.X, feet + (size.Y / 2), position.Z) * (cf - position)
					end
				end

				return cf
			end

			---Is the player inside this timing's hitbox?
			---Measured in the attacker's local space, so a wide horizontal sweep and a
			---narrow forward thrust are not forced to share one distance number.
			---@param timing table
			---@param entity Model
			---@return boolean
			function Engine.inHitbox(timing, entity)
				if type(timing.hitbox) ~= "table" then
					return true
				end

				local character = LocalPlayer.Character
				local ourRoot = character and character:FindFirstChild("HumanoidRootPart")
				local cf = Engine.hitboxCFrame(timing, entity)

				if not cf or not ourRoot then
					return true
				end

				local half = Engine.hitboxSize(timing) / 2
				local point = cf:PointToObjectSpace(ourRoot.Position)
				local shape = timing.shape or "Block"

				if shape == "Sphere" then
					-- One radius, so the largest axis wins. A sphere cannot describe a
					-- reach that is longer than it is wide; that is what Block is for.
					local radius = math.max(half.X, half.Y, half.Z)
					return point.Magnitude <= radius
				end

				if shape == "Cylinder" then
					-- Upright: round in the ground plane, flat top and bottom.
					local radius = math.max(half.X, half.Z)
					return math.abs(point.Y) <= half.Y and Vector2.new(point.X, point.Z).Magnitude <= radius
				end

				return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y and math.abs(point.Z) <= half.Z
			end

			---Fire the parry input once.
			---@param timing table
			function Engine.fire(timing)
				local Toggles, Options = ctx.Toggles, ctx.Options

				-- Dodge instead of parry. This attack is one a parry does nothing about,
				-- so it never touches the parry cooldown - Dodge.ready does the dead check
				-- and the dash cooldown on its own.
				if timing.dodge and ctx.Dodge then
					if not (Toggles.AutoParry and Toggles.AutoParry.Value) then
						debug("[skip] %s - disabled", timing.name)
						return
					end

					local dashed, why = ctx.Dodge.dash(timing.dodgeDir, timing.dodgeKey)
					if dashed then
						debug("[dodge] %s - %s", timing.name, why)
					else
						debug("[skip] %s - dodge %s", timing.name, why)
					end
					return
				end

				local ok, reason = State.canParry()
				if not ok then
					-- Parry is unavailable, but the hit still lands. Dashing out of it is
					-- strictly better than eating it, so offer the swap before giving up.
					if ctx.Dodge and ctx.Dodge.fallback(reason, timing) then
						debug("[dodge] %s - parry %s", timing.name, reason)
						return
					end

					debug("[skip] %s - %s", timing.name, reason)
					return
				end

				local key = Options.ParryKey and Options.ParryKey.Value or "F"
				local hold = (timing.holdTime or ctx.PARRY_HOLD) / 1000

				-- Directional dodge: hold the movement key across the parry so the game
				-- reads a directional roll rather than a neutral block.
				local dodge = DODGE_KEYS[timing.dodgeDir or "None"]
				if dodge then
					Input.down(dodge)
					task.delay(hold + 0.02, function()
						Input.up(dodge)
					end)
				end

				Input.tap(key, hold)

				State.lastParry = os.clock()
				State.parries = State.parries + 1

				if Toggles.NotifyOnParry and Toggles.NotifyOnParry.Value then
					notify(string.format("Parried %s (%dms)", timing.name, timing.delay), 1.5)
				end
			end

			---Fire, then repeat for multi-hit attacks.
			---@param timing table
			function Engine.fireSequence(timing)
				Engine.fire(timing)

				local count = math.max(math.floor(timing.repeatCount or 1), 1)
				if count <= 1 then
					return
				end

				local gap = math.max(timing.repeatDelay or 0.35, 0.05)

				task.spawn(function()
					for _ = 2, count do
						task.wait(gap)
						-- Cooldown would otherwise eat every follow-up hit in the chain.
						State.lastParry = 0
						Engine.fire(timing)
					end
				end)
			end

			---Schedule a parry for a track that just started.
			---@param timing table
			---@param entity Model
			---@param track AnimationTrack
			function Engine.schedule(timing, entity, track)
				local Toggles, Options = ctx.Toggles, ctx.Options

				-- Humanised miss.
				local missChance = Options.MissChance and Options.MissChance.Value or 0
				if missChance > 0 and Random.new():NextNumber(0, 100) <= missChance then
					State.misses = State.misses + 1

					-- The parry is being dropped on purpose, but the hit is still coming.
					-- This is the one place the script knows in advance that a parry it
					-- should have made will not happen, so it is the honest trigger for
					-- "dodge on a missed parry".
					if ctx.Dodge and ctx.Dodge.fallback("missed", timing) then
						debug("[dodge] %s - parry missed", timing.name)
					else
						debug("[miss] %s (intentional)", timing.name)
					end
					return
				end

				local compensation = ctx.PING_COMPENSATION
				local offset = (Options.TimingOffset and Options.TimingOffset.Value or 0) / 1000

				local jitter = 0
				if Toggles.RandomizeOffset and Toggles.RandomizeOffset.Value then
					local range = (Options.RandomRange and Options.RandomRange.Value or 20) / 1000
					jitter = Random.new():NextNumber(-range, range)
				end

				local wait = (timing.delay / 1000) - (Latency.rtt() * compensation) - offset + jitter
				wait = math.max(wait, 0)

				State.pending = State.pending + 1

				task.delay(wait, function()
					State.pending = math.max(State.pending - 1, 0)

					-- Revalidate at fire time; a lot can change during the wind-up.
					if not track.IsPlaying and not (timing.ignoreEnd == true) then
						debug("[skip] %s - animation stopped", timing.name)
						return
					end

					if not Entities.valid(entity) then
						return
					end

					local distance = Util.distance(entity, LocalPlayer.Character)
					if not distance then
						return
					end

					if distance < (timing.minDistance or 0) then
						return
					end

					if timing.maxDistance and timing.maxDistance > 0 and distance > timing.maxDistance then
						return
					end

					if not Engine.inHitbox(timing, entity) then
						debug("[skip] %s - outside hitbox", timing.name)
						return
					end

					Engine.fireSequence(timing)
				end)
			end

			---Handle one animation starting on one entity.
			---@param entity Model
			---@param track AnimationTrack
			function Engine.onAnimation(entity, track)
				local Toggles, Options = ctx.Toggles, ctx.Options

				if not track.Animation then
					return
				end

				local animationId = tostring(track.Animation.AnimationId)
				if animationId == "" then
					return
				end

				local character = LocalPlayer.Character
				if not character or entity == character then
					return
				end

				local distance = Util.distance(entity, character)
				if not distance then
					return
				end

				local timing = Store.get(animationId)

				-- Logging gate.
				local logMin = Options.LogMinDistance and Options.LogMinDistance.Value or 0
				local logMax = Options.LogMaxDistance and Options.LogMaxDistance.Value or 0
				local inLogRange = distance >= logMin and (logMax <= 0 or distance <= logMax)
				local onlyUnknown = Toggles.LogOnlyUnknown and Toggles.LogOnlyUnknown.Value

				if inLogRange and (not onlyUnknown or not timing) then
					Log.push({
						id = animationId,
						-- Track name is what the game's own animator calls it. Usually far
						-- more readable than the asset id when hunting one specific move.
						animName = (track.Name ~= "" and track.Name) or "Animation",
						assetId = animationId:match("(%d+)") or "?",
						time = os.date("%H:%M:%S"),
						entity = entity.Name,
						model = entity,
						distance = Util.round(distance, 1),
						length = Util.round(track.Length, 3),
						speed = Util.round(track.Speed, 2),
						priority = track.Priority.Name,
						known = timing ~= nil,
						ping = math.floor(Latency.rtt() * 1000),
						clock = os.clock(),
					})

					-- Always record. Gating this on the visualizer being open meant you had
					-- to predict which animation you wanted to inspect before it played.
					Log.record(animationId, entity, track)
				end

				-- Auto-create a stub for anything we have never seen.
				if not timing and Toggles.AutoCreateTimings and Toggles.AutoCreateTimings.Value then
					if Entities.valid(entity) and inLogRange then
						timing = Store.template(animationId, track.Length, entity.Name)
						timing.enabled = Toggles.AutoEnableNewTimings and Toggles.AutoEnableNewTimings.Value or false

						-- Written to disk the instant it is created, not on a timer.
						Store.create(timing)

						if Toggles.NotifyOnNewTiming and Toggles.NotifyOnNewTiming.Value then
							notify(string.format("New timing: %s [%s]", timing.name, Util.shortId(animationId)), 3)
						end
					end
				end

				-- Schedule this attack's gate on the attacker. Hitbox.flash works out the
				-- damage window from the timing and only shows the box across that, so
				-- what appears on screen is the span where being inside it costs you
				-- something rather than the whole two-second swing.
				--
				-- Done for every KNOWN timing, not just enabled ones, because the whole
				-- point is watching an untuned box fail to line up before you enable it.
				if timing and ctx.Hitbox and ctx.Hitbox.flash then
					ctx.Hitbox.flash(entity, timing, track)
				end

				if not timing or not timing.enabled then
					return
				end

				if not Entities.valid(entity) then
					return
				end

				if distance < (timing.minDistance or 0) then
					return
				end

				if timing.maxDistance and timing.maxDistance > 0 and distance > timing.maxDistance then
					return
				end

				Engine.schedule(timing, entity, track)
			end

			ctx.Engine = Engine
			return Engine
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Engine.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Effects.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Effects.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Hitbox.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			features/Hitbox.lua
			Draws parry hitboxes and the max-distance ring in the world.

			Three load-bearing decisions:

			1. Geometry comes from Engine.hitboxSize / Engine.hitboxCFrame, never from a
			   local copy of the maths. The picture cannot drift out of agreement with
			   the gate because there is only one set of numbers for either to drift
			   from. Colour comes from Engine.inHitbox for the same reason.

			2. Updates run on BindToRenderStep at Camera + 1, not RenderStepped. The
			   camera moves during the render step; a part positioned before the camera
			   updates is one frame stale relative to what you are looking at, which is
			   exactly the wiggle you see when strafing. Binding after the camera fixes
			   it. Properties are only written when they actually change, so the
			   SelectionBox is not rebuilt 240 times a second for no reason.

			3. Parts live under Workspace.CurrentCamera. Anything parented there renders
			   but never replicates, so the preview is not something the game's own code
			   can see.

			Enemy boxes are drawn across the damage window only
			---------------------------------------------------
			An attack animation is mostly wind-up and recovery. Drawing the gate for the
			whole track meant a box on screen for two seconds when the part that can
			actually hurt you is a fraction of that, and it made every attacker in a
			crowd look permanently dangerous. The window runs from HITBOX_WINDOW_LEAD ms
			before the hit to HITBOX_WINDOW_TAIL ms after the parry hold expires, and the
			box is hidden the frame it closes - or the frame the swing is interrupted.

			Real sizes, when the game gives us one
			--------------------------------------
			If the game spawns a client-visible part for its hitbox, Hitbox.measure finds
			it and draws THAT, at its real size and CFrame, instead of the tuned box. Not
			every game does - plenty run the hit as a server-side raycast or an
			OverlapParams query with nothing on the client to look at - so this is a
			best-effort upgrade with the saved box as the fallback, never a requirement.
		]]

		return function(ctx)
			local Workspace, LocalPlayer, RunService = ctx.Workspace, ctx.LocalPlayer, ctx.RunService
			local Entities, Util = ctx.Entities, ctx.Util

			local Hitbox = {}

			-- Used until the sliders exist, and whenever one is missing.
			local FALLBACK = {
				X = 11,
				Y = 10,
				Z = 30.5,
				hso = 3,
				maxDistance = 85,
				shape = "Block",
				forwardOffset = 0,
			}

			local INSIDE = Color3.fromRGB(90, 230, 120)
			local OUTSIDE = Color3.fromRGB(255, 90, 90)
			local ENEMY = Color3.fromRGB(255, 170, 60)
			local RING = Color3.fromRGB(120, 170, 255)

			Hitbox.SHAPES = { "Block", "Sphere", "Cylinder" }

			local folder, ringPart
			local preview
			local enemyPool = {}
			local active = {}
			local measureConnection

			Hitbox.distance = nil
			Hitbox.inside = false
			Hitbox.anchorName = nil

			----------------------------------------------------------------------------
			-- Volumes
			----------------------------------------------------------------------------

			---One drawable volume: a part plus its wireframe.
			---@param name string
			---@return table
			local function makeVolume(name)
				local part = Instance.new("Part")
				part.Name = name
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Material = Enum.Material.ForceField
				part.Color = OUTSIDE
				part.Transparency = 1
				part.Size = Vector3.one
				part.Parent = folder

				-- The fill alone reads as mush at a distance; the wireframe is what makes
				-- the shape legible while you drag a slider.
				local outline = Instance.new("SelectionBox")
				outline.Adornee = part
				outline.LineThickness = 0.04
				outline.SurfaceTransparency = 1
				outline.Color3 = OUTSIDE
				outline.Visible = false
				outline.Parent = part

				return { part = part, outline = outline, shape = nil, size = nil, colour = nil, visible = false }
			end

			---Point a volume at a shape, size and CFrame, writing only what changed.
			---
			---Roblox cylinders run along their own local X, so an upright one needs a 90
			---degree roll and its size axes swapped. Spheres take one diameter, so the
			---largest axis wins - matching what Engine.inHitbox does for the same shape.
			---@param volume table
			---@param shape string
			---@param size Vector3
			---@param cf CFrame
			local function shapeVolume(volume, shape, size, cf)
				local part = volume.part

				if volume.shape ~= shape then
					volume.shape = shape
					part.Shape = shape == "Sphere" and Enum.PartType.Ball
						or shape == "Cylinder" and Enum.PartType.Cylinder
						or Enum.PartType.Block
					-- A wireframe box around a ball is noise, not information.
					volume.outline.Visible = volume.visible and shape == "Block"
				end

				local target, rotate
				if shape == "Sphere" then
					local diameter = math.max(size.X, size.Y, size.Z)
					target, rotate = Vector3.new(diameter, diameter, diameter), false
				elseif shape == "Cylinder" then
					local diameter = math.max(size.X, size.Z)
					target, rotate = Vector3.new(size.Y, diameter, diameter), true
				else
					target, rotate = size, false
				end

				if volume.size ~= target then
					volume.size = target
					part.Size = target
				end

				part.CFrame = rotate and (cf * CFrame.Angles(0, 0, math.rad(90))) or cf
			end

			---@param volume table
			---@param colour Color3
			local function colourVolume(volume, colour)
				if volume.colour == colour then
					return
				end
				volume.colour = colour
				volume.part.Color = colour
				volume.outline.Color3 = colour
			end

			---@param volume table
			---@param state boolean
			---@param transparency number?
			local function showVolume(volume, state, transparency)
				if volume.visible == state then
					if state then
						volume.part.Transparency = transparency or 0.8
					end
					return
				end
				volume.visible = state
				volume.part.Transparency = state and (transparency or 0.8) or 1
				volume.outline.Visible = state and volume.shape == "Block"
			end

			---Create the parts once, and re-create them if something wiped them.
			---@return boolean
			local function ensureParts()
				if folder and folder.Parent then
					return true
				end

				local camera = Workspace.CurrentCamera
				if not camera then
					return false
				end

				folder = Instance.new("Folder")
				folder.Name = "AP_HitboxPreview"

				preview = makeVolume("Preview")
				enemyPool = {}

				ringPart = Instance.new("Part")
				ringPart.Name = "MaxDistance"
				ringPart.Shape = Enum.PartType.Cylinder
				ringPart.Anchored = true
				ringPart.CanCollide = false
				ringPart.CanQuery = false
				ringPart.CanTouch = false
				ringPart.CastShadow = false
				ringPart.Material = Enum.Material.Neon
				ringPart.Color = RING
				ringPart.Transparency = 1
				ringPart.Size = Vector3.one
				ringPart.Parent = folder

				folder.Parent = camera
				return true
			end

			----------------------------------------------------------------------------
			-- Preview
			----------------------------------------------------------------------------

			---Live values straight off the sliders, shaped like a timing so they can be
			---handed to the same Engine functions a real timing goes through.
			---@return table
			function Hitbox.values()
				local Toggles, Options = ctx.Toggles, ctx.Options

				local function number(name, fallback)
					local option = Options and Options[name]
					if option and type(option.Value) == "number" then
						return option.Value
					end
					return fallback
				end

				local function flag(name)
					local toggle = Toggles and Toggles[name]
					return (toggle and toggle.Value) == true
				end

				return {
					hitbox = {
						X = number("HB_X", FALLBACK.X),
						Y = number("HB_Y", FALLBACK.Y),
						Z = number("HB_Z", FALLBACK.Z),
					},
					hso = number("HB_HSO", FALLBACK.hso),
					maxDistance = number("HB_MaxDistance", FALLBACK.maxDistance),
					forwardOffset = number("HB_ForwardOffset", FALLBACK.forwardOffset),
					shape = (Options and Options.HitboxShape and Options.HitboxShape.Value) or FALLBACK.shape,
					faceForward = flag("HB_FaceForward"),
					groundAlign = flag("HB_GroundAlign"),
				}
			end

			---Which rig the preview is drawn on.
			---@return Model?
			function Hitbox.anchor()
				local Options = ctx.Options
				local mode = Options and Options.HitboxAnchor and Options.HitboxAnchor.Value or "Nearest Enemy"
				local character = LocalPlayer.Character

				if mode == "Self" then
					return character
				end

				local best, bestDistance = nil, math.huge

				for _, entity in ipairs(Entities.list()) do
					if entity ~= character and Util.alive(entity) then
						local distance = Util.distance(entity, character)
						if distance and distance < bestDistance then
							best, bestDistance = entity, distance
						end
					end
				end

				-- Nothing alive nearby: fall back to your own rig so there is still a box
				-- to size against, rather than the preview silently vanishing.
				return best or character
			end

			----------------------------------------------------------------------------
			-- Enemy hitboxes
			----------------------------------------------------------------------------

			-- Names games actually give the part that carries a melee hit. Matched
			-- case-insensitively as a substring, so "SwordHitbox" and "M1_HitPart" both
			-- land. Deliberately narrow: a false positive draws a box around a decoration.
			local HITBOX_NAMES = {
				"hitbox",
				"hitpart",
				"hurtbox",
				"damagepart",
				"damagebox",
				"attackpart",
				"attackbox",
				"swinghitbox",
			}

			-- The template's box. A timing still sitting on exactly these numbers has
			-- never been tuned, so a measured size may overwrite it. Anything else is
			-- something you dialled in by hand and is left alone.
			local TEMPLATE_BOX = { X = 11, Y = 10, Z = 30.5, hso = 3 }

			---Does this part look like a hitbox rather than scenery?
			---@param part BasePart
			---@return boolean
			local function looksLikeHitbox(part)
				-- A real hitbox never blocks movement and is almost never rendered. Both
				-- together throw out nearly all the workspace churn for two field reads.
				if part.CanCollide then
					return false
				end

				local name = part.Name:lower()
				for _, pattern in ipairs(HITBOX_NAMES) do
					if name:find(pattern, 1, true) then
						return true
					end
				end

				return false
			end

			---A part just appeared. Does it belong to an attack we are drawing?
			---@param part BasePart
			local function considerPart(part)
				if #active == 0 or not part:IsA("BasePart") or not looksLikeHitbox(part) then
					return
				end

				local now = os.clock()
				local best, bestDistance

				for _, entry in ipairs(active) do
					-- Parented inside the attacker's own rig is the strongest possible
					-- signal, so it wins outright without a distance check.
					if part:IsDescendantOf(entry.entity) then
						best, bestDistance = entry, 0
						break
					end

					local root = Util.root(entry.entity)
					if root and now < entry.closes then
						local distance = (part.Position - root.Position).Magnitude
						-- Generous, because a long weapon's hitbox spawns at the far end of
						-- the swing rather than on the attacker's chest.
						local reach = 12 + part.Size.Magnitude
						if distance <= reach and (not bestDistance or distance < bestDistance) then
							best, bestDistance = entry, distance
						end
					end
				end

				if not best then
					return
				end

				best.measured = part
				Hitbox.adoptMeasured(best.timing, part)
			end

			---Write a measured size back into the timing, but only over an untouched one.
			---@param timing table
			---@param part BasePart
			function Hitbox.adoptMeasured(timing, part)
				local Toggles = ctx.Toggles
				if not (Toggles and Toggles.MeasureHitboxes and Toggles.MeasureHitboxes.Value) then
					return
				end

				local box = timing.hitbox
				if type(box) ~= "table" then
					return
				end

				local untouched = box.X == TEMPLATE_BOX.X
					and box.Y == TEMPLATE_BOX.Y
					and box.Z == TEMPLATE_BOX.Z
					and (timing.hso or 0) == TEMPLATE_BOX.hso

				if not untouched then
					return
				end

				local size = part.Size
				timing.hitbox = { X = Util.round(size.X, 2), Y = Util.round(size.Y, 2), Z = Util.round(size.Z, 2) }
				-- The measurement is the real volume. Padding it would put the gate back
				-- out of agreement with the game.
				timing.hso = 0
				timing.shape = part.Shape == Enum.PartType.Ball and "Sphere"
					or part.Shape == Enum.PartType.Cylinder and "Cylinder"
					or "Block"
				-- The part is already where the game wants it, so the offsets that exist
				-- to reposition a guessed box have nothing left to correct.
				timing.faceForward = false
				timing.forwardOffset = 0
				timing.groundAlign = false

				ctx.Store.timings[timing.id] = timing
				ctx.Store.dirty = true
				ctx.Store.autosave()

				if ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
					ctx.notify(string.format("Measured %s: %s", timing.name, tostring(size)), 3)
				end
			end

			---Listen for spawned hitbox parts only while an attack window is open.
			---A permanent DescendantAdded on the workspace is the single most expensive
			---thing this script could do; one that exists for 200ms per swing is not.
			local function armMeasure()
				local Toggles = ctx.Toggles
				local want = #active > 0 and (Toggles and Toggles.ShowEnemyHitboxes and Toggles.ShowEnemyHitboxes.Value)

				if want and not measureConnection then
					measureConnection = Workspace.DescendantAdded:Connect(function(instance)
						local ok, err = pcall(considerPart, instance)
						if not ok and Toggles and Toggles.ShowDebug and Toggles.ShowDebug.Value then
							warn("[Fleur] measure: " .. tostring(err))
						end
					end)
				elseif not want and measureConnection then
					measureConnection:Disconnect()
					measureConnection = nil
				end
			end

			---Show a timing's gate on an attacker across its damage window.
			---Called by Engine.onAnimation for every known animation the moment the track
			---starts, so the box is scheduled here and only becomes visible once the
			---swing actually reaches the part that hurts.
			---@param entity Model
			---@param timing table
			---@param track AnimationTrack?
			function Hitbox.flash(entity, timing, track)
				if not entity or not timing then
					return
				end

				local now = os.clock()
				local speed = math.max((track and track.Speed) or 1, 0.01)

				-- The delay is authored against the animation at normal speed. A track
				-- playing at 1.5x reaches its hit frame proportionally sooner.
				local hit = ((timing.delay or 0) / 1000) / speed
				local hold = (timing.holdTime or ctx.PARRY_HOLD) / 1000

				local opens = now + math.max(hit - (ctx.HITBOX_WINDOW_LEAD / 1000), 0)
				local closes = now + hit + hold + (ctx.HITBOX_WINDOW_TAIL / 1000)

				if closes - opens < ctx.HITBOX_WINDOW_MIN then
					closes = opens + ctx.HITBOX_WINDOW_MIN
				end

				-- Re-arming an entry rather than appending keeps a spammed animation from
				-- growing the active list without bound.
				for _, entry in ipairs(active) do
					if entry.entity == entity and entry.timing.id == timing.id then
						entry.opens, entry.closes, entry.track = opens, closes, track
						entry.measured = nil
						armMeasure()
						return
					end
				end

				table.insert(active, {
					entity = entity,
					timing = timing,
					track = track,
					opens = opens,
					closes = closes,
					measured = nil,
				})

				armMeasure()
			end

			---@return table
			local function enemyVolume(index)
				local volume = enemyPool[index]
				if not volume then
					volume = makeVolume("Enemy" .. index)
					enemyPool[index] = volume
				end
				return volume
			end

			---Is this attack over before its window even opened?
			---A swing that gets stunned out mid wind-up never lands, so the box it was
			---going to draw should never appear.
			---@param entry table
			---@param now number
			---@return boolean
			local function interrupted(entry, now)
				if entry.timing.ignoreEnd == true or not entry.track then
					return false
				end
				-- Only before the window opens. Once the hit is out, plenty of games stop
				-- the track while the damage is still resolving.
				return now < entry.opens and not entry.track.IsPlaying
			end

			---Draw every attack that is currently inside its damage window, and retire
			---everything that has closed, been interrupted, or lost its attacker.
			---@param enabled boolean
			local function stepEnemies(enabled)
				local now = os.clock()
				local drawn = 0

				for index = #active, 1, -1 do
					local entry = active[index]
					if now >= entry.closes or not entry.entity.Parent or interrupted(entry, now) then
						table.remove(active, index)
					end
				end

				if enabled then
					for _, entry in ipairs(active) do
						-- Not open yet: scheduled, but the hit is still in the wind-up.
						if now >= entry.opens then
							local part = entry.measured
							-- A measured part that has been despawned is stale. Dropping the
							-- reference falls straight back to the tuned box.
							if part and not part.Parent then
								part, entry.measured = nil, nil
							end

							local cf, size, shape
							if part then
								-- The game's own volume, drawn exactly as it exists.
								cf, size = part.CFrame, part.Size
								shape = part.Shape == Enum.PartType.Ball and "Sphere"
									or part.Shape == Enum.PartType.Cylinder and "Cylinder"
									or "Block"
							elseif ctx.Engine then
								cf = ctx.Engine.hitboxCFrame(entry.timing, entry.entity)
								size = cf and ctx.Engine.hitboxSize(entry.timing)
								shape = entry.timing.shape or "Block"
							end

							if cf and size then
								drawn = drawn + 1
								local volume = enemyVolume(drawn)
								local inside = ctx.Engine and ctx.Engine.inHitbox(entry.timing, entry.entity) == true

								shapeVolume(volume, shape, size, cf)
								-- Inverted against the preview on purpose: on an enemy's box,
								-- being inside is the dangerous state, so inside is red.
								colourVolume(volume, inside and OUTSIDE or ENEMY)
								showVolume(volume, true, 0.86)
							end
						end
					end
				end

				-- Everything past the drawn count is hidden this same frame, which is what
				-- makes a closing window disappear instantly rather than on a timer.
				for index = drawn + 1, #enemyPool do
					showVolume(enemyPool[index], false)
				end

				armMeasure()
			end

			----------------------------------------------------------------------------
			-- Per-frame
			----------------------------------------------------------------------------

			---Redraw everything. Bound to render step; bails cheaply when off.
			function Hitbox.step()
				local Toggles = ctx.Toggles
				local Engine = ctx.Engine

				if not ensureParts() then
					return
				end

				local showEnemies = (Toggles and Toggles.ShowEnemyHitboxes and Toggles.ShowEnemyHitboxes.Value) == true
				stepEnemies(showEnemies and Engine ~= nil)

				local on = (Toggles and Toggles.ShowHitbox and Toggles.ShowHitbox.Value) == true

				if not on or not Engine then
					Hitbox.distance = nil
					Hitbox.inside = false
					showVolume(preview, false)
					ringPart.Transparency = 1
					return
				end

				local anchor = Hitbox.anchor()
				local values = Hitbox.values()
				local cf = anchor and Engine.hitboxCFrame(values, anchor)

				if not cf then
					Hitbox.distance = nil
					Hitbox.inside = false
					showVolume(preview, false)
					ringPart.Transparency = 1
					return
				end

				local inside = Engine.inHitbox(values, anchor) == true

				shapeVolume(preview, values.shape, Engine.hitboxSize(values), cf)
				colourVolume(preview, inside and INSIDE or OUTSIDE)
				showVolume(preview, true, 0.8)

				Hitbox.inside = inside
				Hitbox.distance = Util.distance(anchor, LocalPlayer.Character)
				Hitbox.anchorName = anchor.Name

				local ringOn = (Toggles and Toggles.ShowMaxDistance and Toggles.ShowMaxDistance.Value) == true

				if ringOn and values.maxDistance > 0 then
					-- A cylinder's own axis is local X, so rotate it upright to get a flat
					-- disc on the ground instead of a barrel on its side.
					--
					-- The real max-distance check is a 3D root-to-root magnitude, so this
					-- disc is its ground-plane projection: accurate on level ground, and
					-- slightly generous when the attacker is above or below you.
					local root = Util.root(anchor)
					local feet = Util.groundY(anchor) or (root and root.Position.Y - 3)

					ringPart.Size = Vector3.new(0.15, values.maxDistance * 2, values.maxDistance * 2)
					ringPart.CFrame = CFrame.new(root.Position.X, feet + 0.1, root.Position.Z)
						* CFrame.Angles(0, 0, math.rad(90))
					ringPart.Transparency = 0.88
				else
					ringPart.Transparency = 1
				end
			end

			---One line for the Builder tab label.
			---@return string
			function Hitbox.status()
				local Toggles = ctx.Toggles

				if not (Toggles and Toggles.ShowHitbox and Toggles.ShowHitbox.Value) then
					return #active > 0 and string.format("Preview off | %d enemy box(es)", #active) or "Preview off"
				end

				if not Hitbox.distance then
					return "No rig to draw on"
				end

				local values = Hitbox.values()

				return string.format(
					"%s | %.1fm | %s | %s | max %dm",
					Hitbox.anchorName or "?",
					Hitbox.distance,
					Hitbox.inside and "INSIDE" or "outside",
					values.shape,
					math.floor(values.maxDistance)
				)
			end

			---Push a timing's geometry into the preview controls.
			---Called whenever the visualizer paints a new timing, so clicking a logger
			---row draws that animation's box in the world without a second click.
			---@param timing table?
			function Hitbox.adopt(timing)
				local Toggles, Options = ctx.Toggles, ctx.Options
				if not timing or not Options or not Options.HB_X then
					return
				end

				local hitbox = timing.hitbox
				if type(hitbox) ~= "table" then
					return
				end

				Options.HB_X:SetValue(hitbox.X or FALLBACK.X)
				Options.HB_Y:SetValue(hitbox.Y or FALLBACK.Y)
				Options.HB_Z:SetValue(hitbox.Z or FALLBACK.Z)
				Options.HB_HSO:SetValue(timing.hso or FALLBACK.hso)
				Options.HB_MaxDistance:SetValue(timing.maxDistance or FALLBACK.maxDistance)
				Options.HB_ForwardOffset:SetValue(timing.forwardOffset or 0)
				Options.HitboxShape:SetValue(timing.shape or FALLBACK.shape)
				Toggles.HB_FaceForward:SetValue(timing.faceForward == true)
				Toggles.HB_GroundAlign:SetValue(timing.groundAlign == true)
			end

			----------------------------------------------------------------------------
			-- Lifecycle
			----------------------------------------------------------------------------

			local BIND = "AP_HitboxRender"

			---Bind the redraw after the camera has been updated for this frame.
			---Doing it before - which is what a plain RenderStepped connection does -
			---leaves the box one camera frame behind, and that lag is the jitter.
			function Hitbox.bind()
				pcall(function()
					RunService:UnbindFromRenderStep(BIND)
				end)

				RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
					local ok, err = pcall(Hitbox.step)
					if not ok and ctx.Toggles and ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
						warn("[Fleur] hitbox: " .. tostring(err))
					end
				end)
			end

			---Tear the preview down. Called from Runtime's unload handler.
			function Hitbox.destroy()
				pcall(function()
					RunService:UnbindFromRenderStep(BIND)
				end)

				if measureConnection then
					pcall(function()
						measureConnection:Disconnect()
					end)
					measureConnection = nil
				end

				if folder then
					pcall(function()
						folder:Destroy()
					end)
				end

				folder, ringPart, preview = nil, nil, nil
				enemyPool = {}
				active = {}
			end

			ctx.Hitbox = Hitbox
			return Hitbox
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Hitbox.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Hooks.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			features/Hooks.lua
			Animator.AnimationPlayed listeners.

			sweep() is safe to call repeatedly. It walks every container Entities
			resolves, not just one, because a game that keeps players in one folder and
			mobs in another would otherwise have half its attacks never hooked at all.

			The per-container DescendantAdded listeners are stored separately and
			replaced rather than appended, because sweep gets re-run on respawn and on
			every entity-source change; stacking them was quietly multiplying every
			animation event.
		]]

		return function(ctx)
			local Entities = ctx.Entities

			local Hooks = {
				connections = {},
				hooked = {},
				containerConnections = {},
			}

			---Hook a single animator.
			---@param animator Animator
			function Hooks.attach(animator)
				if Hooks.hooked[animator] then
					return
				end

				local entity = animator:FindFirstAncestorWhichIsA("Model")
				if not entity then
					return
				end

				Hooks.hooked[animator] = true

				local connection = animator.AnimationPlayed:Connect(function(track)
					local ok, err = pcall(ctx.Engine.onAnimation, entity, track)
					if not ok and ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
						warn("[Fleur] " .. tostring(err))
					end
				end)

				table.insert(Hooks.connections, connection)

				table.insert(
					Hooks.connections,
					animator.AncestryChanged:Connect(function(_, parent)
						if not parent then
							Hooks.hooked[animator] = nil
							connection:Disconnect()
						end
					end)
				)
			end

			---Sweep every container and hook the animators in all of them.
			function Hooks.sweep()
				-- Replaced, never appended: sweep re-runs on respawn and on every entity
				-- source change, and stacking these was quietly multiplying every event.
				for _, connection in ipairs(Hooks.containerConnections) do
					pcall(function()
						connection:Disconnect()
					end)
				end
				Hooks.containerConnections = {}

				Entities.invalidate()
				local containers = Entities.containers()

				for _, container in ipairs(containers) do
					for _, descendant in ipairs(container:GetDescendants()) do
						if descendant:IsA("Animator") then
							Hooks.attach(descendant)
						end
					end

					table.insert(
						Hooks.containerConnections,
						container.DescendantAdded:Connect(function(descendant)
							if descendant:IsA("Animator") then
								Hooks.attach(descendant)
							end
						end)
					)
				end

				return #containers
			end

			---Names of the containers currently being watched, for the UI.
			---@return string
			function Hooks.sources()
				local names = {}
				for _, container in ipairs(Entities.containers()) do
					table.insert(names, container.Name)
				end
				return #names > 0 and table.concat(names, ", ") or "none"
			end

			function Hooks.detach()
				for _, connection in ipairs(Hooks.connections) do
					pcall(function()
						connection:Disconnect()
					end)
				end

				for _, connection in ipairs(Hooks.containerConnections) do
					pcall(function()
						connection:Disconnect()
					end)
				end

				Hooks.containerConnections = {}
				Hooks.connections = {}
				Hooks.hooked = {}
			end

			ctx.Hooks = Hooks
			return Hooks
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/features/Hooks.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/Library.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/Library.lua
			Loads LinoriaLib and builds the window + tabs.

			This is the first module that publishes ctx.Toggles / ctx.Options. Every
			module loaded before this one reads those two through ctx at call time
			rather than at load time, which is why none of them capture them locally.
		]]

		return function(ctx)
			local Library = loadstring(game:HttpGet(ctx.LIB_REPO .. "Library.lua"))()
			local ThemeManager = loadstring(game:HttpGet(ctx.LIB_REPO .. "addons/ThemeManager.lua"))()
			local SaveManager = loadstring(game:HttpGet(ctx.LIB_REPO .. "addons/SaveManager.lua"))()

			local Window = Library:CreateWindow({
				Title = "Fleur",
				Center = true,
				AutoShow = true,
				TabPadding = 8,
				MenuFadeTime = 0.2,
			})

			local Tabs = {
				Main = Window:AddTab("Main"),
				Builder = Window:AddTab("Builder"),
				Effects = Window:AddTab("Effects"),
				["UI Settings"] = Window:AddTab("UI Settings"),
			}

			ctx.Library = Library
			ctx.ThemeManager = ThemeManager
			ctx.SaveManager = SaveManager
			ctx.Window = Window
			ctx.Tabs = Tabs

			-- Linoria publishes these as globals when Library.lua runs. Everything below
			-- this module reads ctx.Toggles / ctx.Options, so resolve them once here and
			-- fail loudly rather than letting a nil index surface ten modules later.
			local env = getgenv and getgenv() or {}
			ctx.Toggles = env.Toggles or Toggles
			ctx.Options = env.Options or Options

			if not ctx.Toggles or not ctx.Options then
				error("[Fleur] LinoriaLib did not publish Toggles/Options", 0)
			end

			return Library
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/Library.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/MainTab.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/MainTab.lua
			Tab 1: the auto parry itself, targeting rules, humanisation, notifications.
		]]

		return function(ctx)
			local Tabs, Input, Dodge = ctx.Tabs, ctx.Input, ctx.Dodge

			local ParryBox = Tabs.Main:AddLeftGroupbox("Auto Parry")

			ParryBox:AddToggle("AutoParry", {
				Text = "Enable Auto Parry",
				Default = false,
				Tooltip = "Schedules a parry keypress for every enabled timing that fires",
			}):AddKeyPicker("AutoParryKey", {
				Default = "N/A",
				SyncToggleState = true,
				Mode = "Toggle",
				Text = "Auto Parry",
			})

			ParryBox:AddDropdown("ParryKey", {
				Values = Input.keys,
				Default = "F",
				Text = "Parry Key",
				Tooltip = "The key pressed to parry or block",
			})

			-- Hold Time and Cooldown used to live here; they are a per-timing field and a
			-- fixed floor now. Ping Compensation was a percentage of your round trip,
			-- which is a number with exactly one correct value - all of it - so it is a
			-- constant in Config and this is the knob that replaced it.
			ParryBox:AddSlider("TimingOffset", {
				Text = "Timing Offset",
				Default = 0,
				Min = 0,
				Max = 150,
				Rounding = 0,
				Suffix = "ms",
				Tooltip = "Parry this many milliseconds earlier. Raise it if you are getting hit just before the parry lands",
			})

			ParryBox:AddDivider()

			ParryBox:AddToggle("AutoDodgeOnCooldown", {
				Text = "Auto Dodge if Parry Cooldown",
				Default = false,
				Tooltip = "When an attack fires and the parry cannot go out - on cooldown, key held, or dropped by Miss Chance - dash out of it instead",
			})

			local TargetBox = Tabs.Main:AddLeftGroupbox("Targeting")

			TargetBox:AddDropdown("EntitySource", {
				Values = { "Auto", "Workspace", "Custom" },
				Default = "Auto",
				Text = "Entity Source",
				Tooltip = "Auto uses every one of Live, Characters, Enemies, Mobs, NPCs, Players that exists, and falls back to workspace",
			})

			-- Not wrapped in a dependency box on purpose: Linoria's Depbox:Update only
			-- evaluates dependencies whose element Type is 'Toggle', so a dropdown
			-- dependency would never actually hide anything.
			TargetBox:AddInput("EntityFolder", {
				Default = "",
				Text = "Folder Name",
				Placeholder = "only used when source is Custom",
				Finished = true,
				Tooltip = "Name of a direct child of workspace holding the characters. Comma-separate for more than one, e.g. Players,NPCs",
			})

			TargetBox:AddToggle("IgnorePlayers", { Text = "Ignore Players", Default = false })
			TargetBox:AddToggle("IgnoreNPCs", { Text = "Ignore NPCs", Default = false })
			TargetBox:AddToggle("OnlyWhenTargeted", {
				Text = "Only When Targeted",
				Default = false,
				Tooltip = "Requires an ObjectValue named Target on the entity pointing at you",
			})

			local facingToggle = TargetBox:AddToggle("RequireFacing", {
				Text = "Require Facing",
				Default = false,
				Tooltip = "Only parry attackers that are looking at you",
			})

			local facingDep = TargetBox:AddDependencyBox()
			facingDep:AddSlider("FacingDot", {
				Text = "Facing Threshold",
				Default = 0.4,
				Min = -1,
				Max = 1,
				Rounding = 2,
				Tooltip = "1 is dead-on, 0 is perpendicular",
			})

			----------------------------------------------------------------------------
			-- Dodging
			--
			-- Two styles because games are split on it. "Key + Direction" holds a
			-- movement key, taps the dash bind, then releases - the direction has to go
			-- down first and come up last, because the game samples the movement vector
			-- at the instant the dash key registers. "Double Tap" taps one movement key
			-- twice, for games with no dedicated dash bind at all.
			----------------------------------------------------------------------------
			local DodgeBox = Tabs.Main:AddLeftGroupbox("Dodging")

			DodgeBox:AddDropdown("DashMode", {
				Values = { "Key + Direction", "Double Tap" },
				Default = "Key + Direction",
				Text = "Dash Style",
			})

			DodgeBox:AddDropdown("DashKey", {
				Values = Input.keys,
				Default = "Q",
				Text = "Dash Key",
				Tooltip = "Ignored in Double Tap mode",
			})

			DodgeBox:AddDropdown("DashDirection", {
				Values = Dodge.DIRECTIONS,
				Default = "Auto",
				Text = "Manual Direction",
				Tooltip = "Auto dashes whichever way you are already holding",
			})

			DodgeBox:AddDropdown("DashFallback", {
				Values = { "Forward", "Backward", "Left", "Right" },
				Default = "Backward",
				Text = "Standing Still",
				Tooltip = "Direction used when Auto has no held key to read",
			})

			DodgeBox:AddSlider("DashHold", {
				Text = "Dash Hold",
				Default = 120,
				Min = 10,
				Max = 600,
				Rounding = 0,
				Suffix = "ms",
			})

			DodgeBox:AddSlider("DashCooldown", {
				Text = "Dash Cooldown",
				Default = 400,
				Min = 0,
				Max = 3000,
				Rounding = 0,
				Suffix = "ms",
				Tooltip = "Minimum gap between two dashes",
			})

			-- The "dash instead of parrying" toggle lives in the Auto Parry box, next to
			-- the thing it reacts to, rather than here.
			DodgeBox:AddToggle("NotifyOnDash", { Text = "Notify On Dash", Default = false })

			-- KeyPickers only fire their click callback in Toggle mode, so this is a
			-- Toggle whose toggled state nobody reads: every press is one dash.
			DodgeBox:AddLabel("Manual Dash"):AddKeyPicker("DashBind", {
				Default = "N/A",
				Mode = "Toggle",
				Text = "Manual Dash",
			})

			local SafetyBox = Tabs.Main:AddRightGroupbox("Humanisation")

			SafetyBox:AddToggle("DisableWhileHolding", {
				Text = "Skip If Key Held",
				Default = true,
				Tooltip = "Do not fight your own manual input",
			})

			local randomToggle = SafetyBox:AddToggle("RandomizeOffset", {
				Text = "Randomise Offset",
				Default = true,
				Tooltip = "Adds jitter so every parry is not frame-identical",
			})

			local randomDep = SafetyBox:AddDependencyBox()
			randomDep:AddSlider("RandomRange", {
				Text = "Jitter Range",
				Default = 20,
				Min = 1,
				Max = 120,
				Rounding = 0,
				Suffix = "ms",
			})

			SafetyBox:AddSlider("MissChance", {
				Text = "Miss Chance",
				Default = 0,
				Min = 0,
				Max = 100,
				Rounding = 0,
				Suffix = "%",
				Tooltip = "Chance to intentionally drop a parry",
			})

			local NotifyBox = Tabs.Main:AddRightGroupbox("Notifications")

			NotifyBox:AddToggle("NotifyOnParry", { Text = "Notify On Parry", Default = false })
			NotifyBox:AddToggle("NotifyOnNewTiming", { Text = "Notify On New Timing", Default = true })
			NotifyBox:AddToggle("ShowDebug", { Text = "Debug Messages", Default = false })

			local StatsLabel = NotifyBox:AddLabel("Parries: 0 | Pending: 0 | Ping: 0ms", true)

			facingDep:SetupDependencies({ { facingToggle, true } })
			randomDep:SetupDependencies({ { randomToggle, true } })

			-- Runtime.lua updates this every second.
			ctx.StatsLabel = StatsLabel

			return StatsLabel
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/MainTab.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/BuilderTab.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/BuilderTab.lua
			Tab 2: logger controls, visualizer toggle, timing editor, save management.

			The dropdowns here are populated once at build time and refreshed by
			ui/Wiring.lua whenever the store changes.
		]]

		return function(ctx)
			local Tabs, Store, Log, Hitbox = ctx.Tabs, ctx.Store, ctx.Log, ctx.Hitbox

			local LoggerBox = Tabs.Builder:AddLeftGroupbox("Info Logger")

			LoggerBox:AddToggle("ShowLoggerWindow", {
				Text = "Show Logger Window",
				Default = false,
			}):AddKeyPicker("LoggerKey", {
				Default = "N/A",
				SyncToggleState = true,
				Mode = "Toggle",
				Text = "Logger Window",
			})

			LoggerBox:AddToggle("LogOnlyUnknown", {
				Text = "Only Log Unknown",
				Default = false,
				Tooltip = "Hide animations that already have a timing",
			})

			LoggerBox:AddToggle("DedupeLog", {
				Text = "One Row Per Animation",
				Default = true,
				Tooltip = "Replays refresh the existing row instead of pushing a new one",
			})

			LoggerBox:AddSlider("LogMinDistance", {
				Text = "Min Distance",
				Default = 0,
				Min = 0,
				Max = 200,
				Rounding = 0,
				Suffix = "m",
			})

			LoggerBox:AddSlider("LogMaxDistance", {
				Text = "Max Distance",
				Default = 80,
				Min = 0,
				Max = 500,
				Rounding = 0,
				Suffix = "m",
				Tooltip = "0 disables the upper bound",
			})

			LoggerBox:AddButton("Clear Log", function()
				Log.clear()
			end)

			local VisualBox = Tabs.Builder:AddLeftGroupbox("Animation Visualizer")

			VisualBox:AddToggle("ShowAnimationVisualizer", {
				Text = "Show Visualizer",
				Default = false,
			}):AddKeyPicker("VisualizerKey", {
				-- Same default as the parry key on purpose is a bad idea, but F is what
				-- was asked for. Rebind it here if you parry on F too.
				Default = "F",
				SyncToggleState = true,
				Mode = "Toggle",
				Text = "Visualizer",
			})

			-- Its own groupbox on purpose: these sliders drive the drawing only. Nothing
			-- here touches a saved timing until you press Apply, so you can drag them
			-- around mid-fight without corrupting a tuned entry.
			local HitboxBox = Tabs.Builder:AddLeftGroupbox("Hitbox Preview")

			HitboxBox:AddToggle("ShowHitbox", {
				Text = "Show Hitbox",
				Default = false,
				Tooltip = "Green while you are inside the gate, red while you are not",
			}):AddKeyPicker("HitboxKey", {
				Default = "N/A",
				SyncToggleState = true,
				Mode = "Toggle",
				Text = "Hitbox Preview",
			})

			HitboxBox:AddDropdown("HitboxAnchor", {
				Values = { "Nearest Enemy", "Self" },
				Default = "Nearest Enemy",
				Text = "Draw On",
				Tooltip = "The box is measured in the attacker's frame, so it is drawn on them",
			})

			HitboxBox:AddDropdown("HitboxShape", {
				Values = Hitbox.SHAPES,
				Default = "Block",
				Text = "Hitbox Shape",
				Tooltip = "All three are real gates, not just different drawings",
			})

			HitboxBox:AddSlider("HB_X", {
				Text = "Hitbox X",
				Default = 11,
				Min = 0,
				Max = 120,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Attacker's left/right width",
			})

			HitboxBox:AddSlider("HB_Y", {
				Text = "Hitbox Y",
				Default = 10,
				Min = 0,
				Max = 120,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Height",
			})

			HitboxBox:AddSlider("HB_Z", {
				Text = "Hitbox Z",
				Default = 30.5,
				Min = 0,
				Max = 250,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Attacker's forward/back reach",
			})

			HitboxBox:AddSlider("HB_HSO", {
				Text = "HSO",
				Default = 3,
				Min = 0,
				Max = 40,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Studs added to every side before the check",
			})

			-- Facing controls. Off, the volume is centred on the attacker's root and half
			-- of it covers their back, which is why a 30 stud Z used to gate hits from
			-- behind. On, it starts at their root and extends forward only.
			HitboxBox:AddToggle("HB_FaceForward", {
				Text = "Face Forward",
				Default = false,
				Tooltip = "Push the volume out in front of the attacker instead of centring it on them",
			})

			HitboxBox:AddSlider("HB_ForwardOffset", {
				Text = "Shift Offset",
				Default = 0,
				Min = -60,
				Max = 60,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Extra nudge along their look vector. Negative pulls the volume back",
			})

			HitboxBox:AddToggle("HB_GroundAlign", {
				Text = "Ground Align",
				Default = false,
				Tooltip = "Sit the volume on the rig's feet rather than on their root, which is chest height",
			})

			HitboxBox:AddToggle("ShowEnemyHitboxes", {
				Text = "Show Enemy Hitboxes",
				Default = false,
				Tooltip = "Draw each attacker's gate across the damage window only, then hide it the frame the window closes",
			})

			HitboxBox:AddToggle("MeasureHitboxes", {
				Text = "Measure Real Hitboxes",
				Default = true,
				Tooltip = "If the game spawns a visible hitbox part, draw that at its true size and save it over an untuned box",
			})

			HitboxBox:AddToggle("ShowMaxDistance", {
				Text = "Show Max Distance",
				Default = false,
				Tooltip = "Flat ring at the distance cut-off",
			})

			HitboxBox:AddSlider("HB_MaxDistance", {
				Text = "Max Distance",
				Default = 85,
				Min = 0,
				Max = 400,
				Rounding = 0,
				Suffix = "m",
			})

			local HitboxLabel = HitboxBox:AddLabel("Preview off", true)

			local BuilderBox = Tabs.Builder:AddRightGroupbox("Timing Builder")

			local timingList = BuilderBox:AddDropdown("TimingList", {
				Values = Store.display(),
				Default = nil,
				AllowNull = true,
				Text = "Timing",
			})

			BuilderBox:AddInput("T_Name", { Default = "", Text = "Name", Finished = true })

			BuilderBox:AddSlider("T_Delay", {
				Text = "Parry Delay",
				Default = 400,
				Min = 0,
				Max = 4000,
				Rounding = 0,
				Suffix = "ms",
				Tooltip = "How far into the animation the hit lands",
			})

			BuilderBox:AddSlider("T_HoldTime", {
				Text = "Hold Time",
				Default = 120,
				Min = 10,
				Max = 600,
				Rounding = 0,
				Suffix = "ms",
			})

			BuilderBox:AddSlider("T_MinDistance", {
				Text = "Min Distance",
				Default = 0,
				Min = 0,
				Max = 200,
				Rounding = 0,
				Suffix = "m",
			})

			BuilderBox:AddSlider("T_MaxDistance", {
				Text = "Max Distance",
				Default = 60,
				Min = 0,
				Max = 500,
				Rounding = 0,
				Suffix = "m",
			})

			BuilderBox:AddToggle("T_Enabled", { Text = "Enabled", Default = false })

			-- Named configs, Config Name, Save Config / Load Config / Delete Config and
			-- the Write To Disk switch all used to live here. There is one file per place
			-- now and it is written on every change, so none of them had anything left to
			-- decide. What is left is the two questions that are still genuinely yours:
			-- do you want stubs made automatically, and should they be live on arrival.
			local StoreBox = Tabs.Builder:AddRightGroupbox("Timing Storage")

			StoreBox:AddToggle("AutoCreateTimings", {
				Text = "Auto Create Timings",
				Default = true,
				Tooltip = "Make a stub for every unseen animation, saved to disk immediately",
			})

			StoreBox:AddToggle("AutoEnableNewTimings", {
				Text = "Auto Enable New",
				Default = false,
				Tooltip = "Off by default so fresh guesses do not parry at random",
			})

			local StoreLabel = StoreBox:AddLabel("Timings: 0", true)

			ctx.BuilderBox = BuilderBox
			ctx.StoreBox = StoreBox
			ctx.HitboxBox = HitboxBox
			ctx.HitboxLabel = HitboxLabel
			ctx.timingList = timingList
			ctx.StoreLabel = StoreLabel

			return BuilderBox
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/BuilderTab.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/EffectsTab.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/EffectsTab.lua
			Tab 3: the unknown effect logger and the profiles built from it.

			Deliberately mirrors the Builder tab: a logger groupbox on the left that only
			watches, and a builder on the right that only edits. Nothing typed here
			touches a live profile until Save Effect is pressed, so you can poke at the
			fields mid-fight without breaking a rule that already works.

			Buttons that need Options live in ui/Wiring.lua, same as the Builder tab.
		]]

		return function(ctx)
			local Tabs, Effects, Dodge = ctx.Tabs, ctx.Effects, ctx.Dodge

			local LogBox = Tabs.Effects:AddLeftGroupbox("Effect Logger")

			LogBox:AddToggle("ShowEffectWindow", {
				Text = "Show Effect Window",
				Default = false,
			}):AddKeyPicker("EffectWindowKey", {
				Default = "N/A",
				SyncToggleState = true,
				Mode = "Toggle",
				Text = "Effect Window",
			})

			LogBox:AddToggle("LogEffects", {
				Text = "Log Effects",
				Default = false,
				Tooltip = "Watch the workspace for parts, sounds and emitters spawning near you",
			})

			LogBox:AddToggle("LogOnlyUnknownEffects", {
				Text = "Only Log Unknown",
				Default = false,
				Tooltip = "Hide effects that already have a profile",
			})

			LogBox:AddSlider("EffectLogRange", {
				Text = "Log Range",
				Default = 120,
				Min = 10,
				Max = 400,
				Rounding = 0,
				Suffix = "m",
				Tooltip = "Anything spawning further away than this is someone else's fight",
			})

			LogBox:AddButton("Clear Effect Log", function()
				Effects.clear()
			end)

			local EffectLabel = LogBox:AddLabel("Effects: 0 | Profiles: 0", true)

			local BuildBox = Tabs.Effects:AddRightGroupbox("Effect Builder")

			local effectList = BuildBox:AddDropdown("EffectList", {
				Values = Effects.display(),
				Default = nil,
				AllowNull = true,
				Text = "Profile",
			})

			BuildBox:AddInput("E_Name", {
				Default = "",
				Text = "Effect Name",
				Finished = true,
				Tooltip = "Matched against the instance's Name, exactly",
			})

			BuildBox:AddSlider("E_TriggerDistance", {
				Text = "Trigger Distance",
				Default = 60,
				Min = 0,
				Max = 150,
				Rounding = 0,
				Suffix = " studs",
				Tooltip = "How close the effect has to spawn before this rule fires",
			})

			local dodgeToggle = BuildBox:AddToggle("E_Dodge", {
				Text = "Dodge Instead Of Parry",
				Default = false,
				Tooltip = "For projectiles and ground slams that a parry does nothing about",
			})

			local dodgeDep = BuildBox:AddDependencyBox()
			dodgeDep:AddDropdown("E_DodgeDir", {
				Values = Dodge.DIRECTIONS,
				Default = "Auto",
				Text = "Dodge Direction",
				Tooltip = "Auto reads whichever movement key you are already holding",
			})

			BuildBox:AddSlider("E_Delay", {
				Text = "React Delay",
				Default = 0,
				Min = 0,
				Max = 3000,
				Rounding = 0,
				Suffix = "ms",
				Tooltip = "Wait this long after the effect appears. Telegraph decals land well before their hit",
			})

			BuildBox:AddSlider("E_HoldTime", {
				Text = "Hold Time",
				Default = 120,
				Min = 10,
				Max = 600,
				Rounding = 0,
				Suffix = "ms",
			})

			BuildBox:AddToggle("E_Enabled", { Text = "Enabled", Default = false })

			local StoreBox = Tabs.Effects:AddRightGroupbox("Effect Saves")

			StoreBox:AddToggle("EffectReact", {
				Text = "React To Effects",
				Default = false,
				Tooltip = "Master switch. Off means profiles are recorded but never fire",
			})

			dodgeDep:SetupDependencies({ { dodgeToggle, true } })

			ctx.EffectBuildBox = BuildBox
			ctx.EffectStoreBox = StoreBox
			ctx.effectList = effectList
			ctx.EffectLabel = EffectLabel

			return BuildBox
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/EffectsTab.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/LoggerWindow.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/LoggerWindow.lua
			The Info Logger: Time | Animation | ID | Enemy | Dist | Status.

			Status is resolved live from the store on every refresh rather than cached
			on the log entry, so a row that appeared as NEW flips to KNOWN the moment a
			timing exists for it, and to IN AP the moment that timing is enabled.

			Clicking a row is the whole gesture: it selects, opens the visualizer if it
			is closed, and loads the animation. Loads before ui/VisualizerWindow.lua, so
			it reaches the visualizer through ctx at click time.
		]]

		return function(ctx)
			local Library, Store, Log, LocalPlayer = ctx.Library, ctx.Store, ctx.Log, ctx.LocalPlayer

			local LoggerGui = {}

			local screen = Instance.new("ScreenGui")
			screen.Name = "AP_InfoLogger"
			screen.ResetOnSpawn = false
			screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			screen.DisplayOrder = 999
			screen.Enabled = false

			pcall(function()
				if syn and syn.protect_gui then
					syn.protect_gui(screen)
				end
				screen.Parent = gethui and gethui() or game:GetService("CoreGui")
			end)

			if not screen.Parent then
				screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
			end

			local outer = Instance.new("Frame")
			outer.Name = "Outer"
			outer.BackgroundColor3 = Color3.new(0, 0, 0)
			outer.BorderSizePixel = 0
			outer.Position = UDim2.new(0, 20, 0, 200)
			outer.Size = UDim2.new(0, 470, 0, 280)
			outer.Parent = screen

			local inner = Instance.new("Frame")
			inner.Name = "Inner"
			inner.BackgroundColor3 = Library.MainColor
			inner.BorderColor3 = Library.OutlineColor
			inner.BorderMode = Enum.BorderMode.Inset
			inner.Size = UDim2.new(1, -2, 1, -2)
			inner.Position = UDim2.new(0, 1, 0, 1)
			inner.Parent = outer

			local accent = Instance.new("Frame")
			accent.BackgroundColor3 = Library.AccentColor
			accent.BorderSizePixel = 0
			accent.Size = UDim2.new(1, 0, 0, 2)
			accent.Parent = inner

			local title = Instance.new("TextLabel")
			title.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			title.TextColor3 = Library.AccentColor
			title.Text = "Info Logger"
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextSize = 15
			title.Position = UDim2.new(0, 6, 0, 4)
			title.Size = UDim2.new(0, 110, 0, 18)
			title.Parent = inner

			local countLabel = Instance.new("TextLabel")
			countLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			countLabel.TextColor3 = Library.FontColor
			countLabel.Text = "0 entries"
			countLabel.BackgroundTransparency = 1
			countLabel.TextXAlignment = Enum.TextXAlignment.Left
			countLabel.TextSize = 13
			countLabel.Position = UDim2.new(0, 120, 0, 5)
			countLabel.Size = UDim2.new(0, 120, 0, 16)
			countLabel.Parent = inner

			local clearButton = Instance.new("TextButton")
			clearButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			clearButton.TextColor3 = Library.FontColor
			clearButton.BackgroundColor3 = Library.BackgroundColor
			clearButton.BorderColor3 = Library.OutlineColor
			clearButton.AutoButtonColor = false
			clearButton.Text = "Clear"
			clearButton.TextSize = 12
			clearButton.Position = UDim2.new(1, -56, 0, 5)
			clearButton.Size = UDim2.new(0, 50, 0, 16)
			clearButton.Parent = inner
			Library:AddToRegistry(clearButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			-- Column geometry shared by the header and every row, so they cannot drift.
			local COLUMNS = {
				{ key = "time", title = "Time", x = 0, w = 58 },
				{ key = "animName", title = "Animation", x = 60, w = 110 },
				{ key = "assetId", title = "ID", x = 172, w = 96 },
				{ key = "entity", title = "Enemy", x = 270, w = 96 },
				{ key = "dist", title = "Dist", x = 368, w = 40 },
				{ key = "status", title = "Status", x = 410, w = 46 },
			}

			local header = Instance.new("Frame")
			header.BackgroundColor3 = Library.BackgroundColor
			header.BorderSizePixel = 0
			header.Position = UDim2.new(0, 4, 0, 24)
			header.Size = UDim2.new(1, -8, 0, 16)
			header.Parent = inner
			Library:AddToRegistry(header, { BackgroundColor3 = "BackgroundColor" }, true)

			for _, column in ipairs(COLUMNS) do
				local label = Instance.new("TextLabel")
				label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				label.TextColor3 = Library.AccentColor
				label.Text = column.title
				label.BackgroundTransparency = 1
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextSize = 12
				label.Position = UDim2.new(0, column.x + 4, 0, 0)
				label.Size = UDim2.new(0, column.w, 1, 0)
				label.Parent = header
				Library:AddToRegistry(label, { TextColor3 = "AccentColor" }, true)
			end

			local list = Instance.new("ScrollingFrame")
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.Position = UDim2.new(0, 4, 0, 42)
			list.Size = UDim2.new(1, -8, 1, -46)
			list.ScrollBarThickness = 3
			list.ScrollBarImageColor3 = Library.AccentColor
			list.CanvasSize = UDim2.new()
			list.Parent = inner

			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 1)
			layout.Parent = list

			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
			end)

			Library:MakeDraggable(outer)

			Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
			Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
			Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)

			local rows = {}

			local STATUS_NEW = Color3.fromRGB(200, 200, 200)
			local STATUS_KNOWN = Color3.fromRGB(255, 190, 70)
			local STATUS_ACTIVE = Color3.fromRGB(90, 230, 120)

			---Status is read live from the store, never cached on the entry, so a row
			---logged as NEW flips to IN AP the moment you save a timing for it.
			---@param animationId string
			---@return string, Color3
			local function statusOf(animationId)
				local timing = Store.get(animationId)
				if not timing then
					return "NEW", STATUS_NEW
				end
				if timing.enabled then
					return "IN AP", STATUS_ACTIVE
				end
				return "KNOWN", STATUS_KNOWN
			end

			---Set window visibility.
			function LoggerGui.visible(state)
				screen.Enabled = state
			end

			clearButton.MouseButton1Click:Connect(function()
				Log.clear()
				for _, row in ipairs(rows) do
					row.Frame.Visible = false
				end
				countLabel.Text = "0 entries"
			end)

			---Build one row: a click target plus one label per column.
			local function makeRow(index)
				local frame = Instance.new("TextButton")
				frame.BackgroundColor3 = Library.BackgroundColor
				frame.BackgroundTransparency = 1
				frame.BorderSizePixel = 0
				frame.AutoButtonColor = false
				frame.Text = ""
				frame.Size = UDim2.new(1, 0, 0, 16)
				frame.LayoutOrder = index
				frame.Parent = list

				local cells = {}
				for _, column in ipairs(COLUMNS) do
					local label = Instance.new("TextLabel")
					label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
					label.TextColor3 = Library.FontColor
					label.BackgroundTransparency = 1
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextTruncate = Enum.TextTruncate.AtEnd
					label.TextSize = 12
					label.Text = ""
					label.Position = UDim2.new(0, column.x + 4, 0, 0)
					label.Size = UDim2.new(0, column.w, 1, 0)
					label.Parent = frame
					cells[column.key] = label
				end

				local row = { Frame = frame, Cells = cells }
				rows[index] = row

				frame.MouseButton1Click:Connect(function()
					local Toggles = ctx.Toggles
					local Visualizer = ctx.Visualizer

					Log.selected = frame:GetAttribute("AnimationId")
					if not Log.selected then
						return
					end

					-- Clicking a row is the whole gesture: open the visualizer if it is
					-- closed, then load. Otherwise the click looks dead.
					if Visualizer and Visualizer.load then
						if Toggles.ShowAnimationVisualizer and not Toggles.ShowAnimationVisualizer.Value then
							Toggles.ShowAnimationVisualizer:SetValue(true)
						end
						Visualizer.load(Log.selected)
					end

					LoggerGui.refresh()
				end)

				frame.MouseEnter:Connect(function()
					if frame:GetAttribute("AnimationId") ~= Log.selected then
						frame.BackgroundTransparency = 0.7
					end
				end)

				frame.MouseLeave:Connect(function()
					if frame:GetAttribute("AnimationId") ~= Log.selected then
						frame.BackgroundTransparency = 1
					end
				end)

				return row
			end

			---Rebuild the row list from the log.
			function LoggerGui.refresh()
				if not screen.Enabled then
					return
				end

				countLabel.Text = string.format("%d %s", #Log.entries, #Log.entries == 1 and "entry" or "entries")

				for index, entry in ipairs(Log.entries) do
					local row = rows[index] or makeRow(index)
					local frame, cells = row.Frame, row.Cells

					frame.LayoutOrder = index
					frame.Visible = true
					frame:SetAttribute("AnimationId", entry.id)

					local selected = entry.id == Log.selected
					frame.BackgroundTransparency = selected and 0.4 or 1
					frame.BackgroundColor3 = selected and Library.AccentColor or Library.BackgroundColor

					local statusText, statusColor = statusOf(entry.id)

					cells.time.Text = entry.time or "--:--:--"
					cells.animName.Text = entry.animName or "Animation"
					cells.assetId.Text = entry.assetId or "?"
					cells.entity.Text = entry.entity or "?"
					cells.dist.Text = string.format("%.0f", entry.distance or 0)
					cells.status.Text = statusText
					cells.status.TextColor3 = statusColor

					-- Tint the whole row too, so a screen full of entries reads at a glance
					-- instead of forcing you to scan the last column.
					local bodyColor = statusText == "NEW" and Library.FontColor or statusColor
					cells.time.TextColor3 = Library.FontColor
					cells.animName.TextColor3 = bodyColor
					cells.assetId.TextColor3 = bodyColor
					cells.entity.TextColor3 = Library.FontColor
					cells.dist.TextColor3 = Library.FontColor
				end

				for index = #Log.entries + 1, #rows do
					rows[index].Frame.Visible = false
				end
			end

			ctx.LoggerGui = LoggerGui
			return LoggerGui
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/LoggerWindow.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/VisualizerWindow.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/VisualizerWindow.lua
			Animation Visualizer & Editor.

			Left half is a ViewportFrame playing the animation on a cloned rig, with a
			scrub bar and a red marker at the current parry delay. Right half is the
			Quick Edit Timing panel, which writes straight into features/Store.lua and
			persists on Save & Apply.

			The panel talks in seconds because that is how animations read; the store
			stays in milliseconds because that is what the scheduler needs. Conversion
			happens in readEditor/syncEditor and nowhere else.
		]]

		return function(ctx)
			local Library, Store, Log, Util = ctx.Library, ctx.Store, ctx.Log, ctx.Util
			local Entities, LoggerGui, notify = ctx.Entities, ctx.LoggerGui, ctx.notify
			local LocalPlayer, UserInputService, RunService = ctx.LocalPlayer, ctx.UserInputService, ctx.RunService

			local Visualizer = {}

			-- Published immediately: the logger's row click reads ctx.Visualizer, and
			-- nothing below this line needs to have run for that lookup to resolve.
			ctx.Visualizer = Visualizer

			local screen = Instance.new("ScreenGui")
			screen.Name = "AP_Visualizer"
			screen.ResetOnSpawn = false
			screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			screen.DisplayOrder = 998
			screen.Enabled = false

			pcall(function()
				if syn and syn.protect_gui then
					syn.protect_gui(screen)
				end
				screen.Parent = gethui and gethui() or game:GetService("CoreGui")
			end)

			if not screen.Parent then
				screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
			end

			local outer = Instance.new("Frame")
			outer.BackgroundColor3 = Color3.new(0, 0, 0)
			outer.BorderSizePixel = 0
			outer.Position = UDim2.new(0, 510, 0, 200)
			-- Height is driven by the Quick Edit panel on the right, which is the taller
			-- of the two columns. The left column's absolute layout stops at 302.
			outer.Size = UDim2.new(0, 570, 0, 412)
			outer.Parent = screen

			local inner = Instance.new("Frame")
			inner.BackgroundColor3 = Library.MainColor
			inner.BorderColor3 = Library.OutlineColor
			inner.BorderMode = Enum.BorderMode.Inset
			inner.Size = UDim2.new(1, -2, 1, -2)
			inner.Position = UDim2.new(0, 1, 0, 1)
			inner.Parent = outer

			local accent = Instance.new("Frame")
			accent.BackgroundColor3 = Library.AccentColor
			accent.BorderSizePixel = 0
			accent.Size = UDim2.new(1, 0, 0, 2)
			accent.Parent = inner

			local title = Instance.new("TextLabel")
			title.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			title.TextColor3 = Library.AccentColor
			title.Text = "Animation Visualizer & Editor"
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextSize = 15
			title.Position = UDim2.new(0, 6, 0, 4)
			title.Size = UDim2.new(0, 300, 0, 18)
			title.Parent = inner

			local closeButton = Instance.new("TextButton")
			closeButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			closeButton.TextColor3 = Library.FontColor
			closeButton.BackgroundTransparency = 1
			closeButton.AutoButtonColor = false
			closeButton.Text = "X"
			closeButton.TextSize = 14
			closeButton.Position = UDim2.new(1, -22, 0, 4)
			closeButton.Size = UDim2.new(0, 18, 0, 18)
			closeButton.Parent = inner

			local viewport = Instance.new("ViewportFrame")
			viewport.BackgroundColor3 = Library.BackgroundColor
			viewport.BorderColor3 = Library.OutlineColor
			viewport.Position = UDim2.new(0, 5, 0, 48)
			viewport.Size = UDim2.new(0, 300, 0, 190)
			viewport.Parent = inner

			local world = Instance.new("WorldModel")
			world.Parent = viewport

			local camera = Instance.new("Camera")
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 70
			camera.Parent = viewport
			viewport.CurrentCamera = camera

			local message = Instance.new("TextLabel")
			message.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			message.TextColor3 = Library.FontColor
			message.Text = "Waiting for animation ID"
			message.BackgroundTransparency = 1
			message.TextWrapped = true
			message.TextSize = 13
			message.Size = UDim2.new(1, -10, 1, 0)
			message.Position = UDim2.new(0, 5, 0, 0)
			message.Parent = viewport

			local speedLabel = Instance.new("TextLabel")
			speedLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			speedLabel.TextColor3 = Library.FontColor
			speedLabel.Text = "Speed 0.00"
			speedLabel.BackgroundTransparency = 1
			speedLabel.TextXAlignment = Enum.TextXAlignment.Left
			speedLabel.TextSize = 12
			speedLabel.Position = UDim2.new(0, 4, 0, 2)
			speedLabel.Size = UDim2.new(0, 100, 0, 16)
			speedLabel.Parent = viewport

			local idBox = Instance.new("TextBox")
			idBox.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			idBox.TextColor3 = Library.FontColor
			idBox.BackgroundColor3 = Library.BackgroundColor
			idBox.BorderColor3 = Library.OutlineColor
			idBox.Text = "rbxassetid://0"
			idBox.TextSize = 13
			idBox.Position = UDim2.new(0, 5, 0, 26)
			idBox.Size = UDim2.new(0, 300, 0, 18)
			idBox.Parent = inner

			local sliderOuter = Instance.new("Frame")
			sliderOuter.BackgroundColor3 = Library.BackgroundColor
			sliderOuter.BorderColor3 = Library.OutlineColor
			sliderOuter.Position = UDim2.new(0, 5, 0, 242)
			sliderOuter.Size = UDim2.new(0, 300, 0, 16)
			sliderOuter.Parent = inner

			local sliderFill = Instance.new("Frame")
			sliderFill.BackgroundColor3 = Library.AccentColor
			sliderFill.BorderSizePixel = 0
			sliderFill.Size = UDim2.new(0, 0, 1, 0)
			sliderFill.Parent = sliderOuter

			local sliderText = Instance.new("TextLabel")
			sliderText.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			sliderText.TextColor3 = Library.FontColor
			sliderText.Text = "0.000 / 0.000"
			sliderText.BackgroundTransparency = 1
			sliderText.TextSize = 12
			sliderText.ZIndex = 5
			sliderText.Size = UDim2.new(1, 0, 1, 0)
			sliderText.Parent = sliderOuter

			local function button(text, x, width)
				local b = Instance.new("TextButton")
				b.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				b.TextColor3 = Library.FontColor
				b.BackgroundColor3 = Library.BackgroundColor
				b.BorderColor3 = Library.OutlineColor
				b.AutoButtonColor = false
				b.Text = text
				b.TextSize = 12
				b.Position = UDim2.new(0, x, 0, 262)
				b.Size = UDim2.new(0, width, 0, 18)
				b.Parent = inner
				Library:AddToRegistry(b, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)
				return b
			end

			local prevButton = button("<<", 5, 45)
			local playButton = button("Play", 54, 64)
			local nextButton = button(">>", 122, 45)
			local loadButton = button("From Log", 171, 134)

			local delayLine = Instance.new("Frame")
			delayLine.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
			delayLine.BorderSizePixel = 0
			delayLine.Size = UDim2.new(0, 1, 1, 0)
			delayLine.ZIndex = 6
			delayLine.Visible = false
			delayLine.Parent = sliderOuter

			local statusLabel = Instance.new("TextLabel")
			statusLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			statusLabel.TextColor3 = Library.FontColor
			statusLabel.Text = "Not in parry list"
			statusLabel.BackgroundTransparency = 1
			statusLabel.TextXAlignment = Enum.TextXAlignment.Left
			statusLabel.TextSize = 12
			statusLabel.Position = UDim2.new(0, 5, 0, 286)
			statusLabel.Size = UDim2.new(0, 300, 0, 16)
			statusLabel.Parent = inner

			----------------------------------------------------------------------------
			-- Quick Edit Timing panel
			----------------------------------------------------------------------------

			local PANEL_X = 312
			local PANEL_W = 250

			local divider = Instance.new("Frame")
			divider.BackgroundColor3 = Library.OutlineColor
			divider.BorderSizePixel = 0
			divider.Position = UDim2.new(0, PANEL_X - 6, 0, 26)
			divider.Size = UDim2.new(0, 1, 0, 276)
			divider.Parent = inner
			Library:AddToRegistry(divider, { BackgroundColor3 = "OutlineColor" }, true)

			local editorTitle = Instance.new("TextLabel")
			editorTitle.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			editorTitle.TextColor3 = Library.AccentColor
			editorTitle.Text = "Quick Edit Timing"
			editorTitle.BackgroundTransparency = 1
			editorTitle.TextXAlignment = Enum.TextXAlignment.Center
			editorTitle.TextSize = 14
			editorTitle.Position = UDim2.new(0, PANEL_X, 0, 26)
			editorTitle.Size = UDim2.new(0, PANEL_W, 0, 18)
			editorTitle.Parent = inner
			Library:AddToRegistry(editorTitle, { TextColor3 = "AccentColor" }, true)

			-- Same vocabulary the Dodge module uses, so a direction means one thing
			-- everywhere instead of "Back" here and "Backward" there.
			local DODGE_DIRS = { "None", "Forward", "Backward", "Left", "Right" }
			-- "Default" means "use the global Dash Key". The rest are the binds games
			-- actually put a dash or roll on.
			local DODGE_KEYS = { "Default", "Q", "E", "F", "R", "V", "C", "X", "Z", "LeftShift", "LeftControl", "Space" }
			local SHAPES = { "Block", "Sphere", "Cylinder" }
			local BOOLS = { "Off", "On" }
			local YESNO = { "No", "Yes" }

			-- kind drives parsing on save and formatting on load; choice fields cycle
			-- through their own list on click rather than trusting anyone to type
			-- "Cylinder" correctly at three in the morning.
			local FIELDS = {
				{ key = "delay", label = "Delay (s)", kind = "seconds" },
				{ key = "hitboxX", label = "Hitbox X", kind = "number" },
				{ key = "hitboxY", label = "Hitbox Y", kind = "number" },
				{ key = "hitboxZ", label = "Hitbox Z", kind = "number" },
				{ key = "hso", label = "HSO", kind = "number" },
				{ key = "shape", label = "Shape", kind = "choice", choices = SHAPES },
				{ key = "faceForward", label = "Face Fwd", kind = "choice", choices = BOOLS },
				{ key = "forwardOffset", label = "Shift Ofs", kind = "number" },
				{ key = "groundAlign", label = "Ground", kind = "choice", choices = BOOLS },
				{ key = "maxDistance", label = "Max Dist", kind = "number" },
				{ key = "repeatCount", label = "Repeat", kind = "int" },
				{ key = "repeatDelay", label = "Rep Delay", kind = "number" },
				{ key = "dodge", label = "Dodge", kind = "choice", choices = YESNO },
				{ key = "dodgeKey", label = "Dodge Key", kind = "choice", choices = DODGE_KEYS },
				{ key = "dodgeDir", label = "Dodge Dir", kind = "choice", choices = DODGE_DIRS },
			}

			local inputs = {}

			for index, field in ipairs(FIELDS) do
				local y = 46 + (index - 1) * 20

				local label = Instance.new("TextLabel")
				label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				label.TextColor3 = Library.FontColor
				label.Text = field.label
				label.BackgroundTransparency = 1
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextSize = 12
				label.Position = UDim2.new(0, PANEL_X + 4, 0, y)
				label.Size = UDim2.new(0, 92, 0, 18)
				label.Parent = inner
				Library:AddToRegistry(label, { TextColor3 = "FontColor" }, true)

				local control
				if field.kind == "choice" then
					local choices = field.choices
					control = Instance.new("TextButton")
					control.AutoButtonColor = false
					control.Text = choices[1]
					control.MouseButton1Click:Connect(function()
						local current = table.find(choices, control.Text) or 1
						control.Text = choices[(current % #choices) + 1]
					end)
				else
					control = Instance.new("TextBox")
					control.ClearTextOnFocus = false
					control.Text = "0"
				end

				control.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				control.TextColor3 = Library.FontColor
				control.BackgroundColor3 = Library.BackgroundColor
				control.BorderColor3 = Library.OutlineColor
				control.TextSize = 12
				control.Position = UDim2.new(0, PANEL_X + 100, 0, y)
				control.Size = UDim2.new(0, PANEL_W - 104, 0, 18)
				control.Parent = inner
				Library:AddToRegistry(control, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

				inputs[field.key] = control
			end

			local saveButton = Instance.new("TextButton")
			saveButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			saveButton.TextColor3 = Library.FontColor
			saveButton.BackgroundColor3 = Library.BackgroundColor
			saveButton.BorderColor3 = Library.OutlineColor
			saveButton.AutoButtonColor = false
			saveButton.Text = "Save & Apply"
			saveButton.TextSize = 13
			saveButton.Position = UDim2.new(0, PANEL_X, 0, 356)
			saveButton.Size = UDim2.new(0, PANEL_W, 0, 22)
			saveButton.Parent = inner
			Library:AddToRegistry(saveButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			local toggleButton = Instance.new("TextButton")
			toggleButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			toggleButton.TextColor3 = Library.FontColor
			toggleButton.BackgroundColor3 = Library.BackgroundColor
			toggleButton.BorderColor3 = Library.OutlineColor
			toggleButton.AutoButtonColor = false
			toggleButton.Text = "Add To Parry List"
			toggleButton.TextSize = 13
			toggleButton.Position = UDim2.new(0, PANEL_X, 0, 380)
			toggleButton.Size = UDim2.new(0, PANEL_W, 0, 22)
			toggleButton.Parent = inner
			Library:AddToRegistry(toggleButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			Library:MakeDraggable(outer)
			Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
			Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
			Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)
			Library:AddToRegistry(sliderFill, { BackgroundColor3 = "AccentColor" }, true)

			local currentTrack = nil
			local currentId = nil
			local paused = false
			local elapsed = 0

			function Visualizer.visible(state)
				screen.Enabled = state
			end

			function Visualizer.say(text)
				message.Visible = true
				message.Text = text
				world:ClearAllChildren()
			end

			closeButton.MouseButton1Click:Connect(function()
				local Toggles = ctx.Toggles
				if Toggles.ShowAnimationVisualizer then
					Toggles.ShowAnimationVisualizer:SetValue(false)
				else
					screen.Enabled = false
				end
			end)

			---Read the panel back out as a plain table.
			local function readEditor()
				local function num(key, fallback)
					return tonumber(inputs[key].Text) or fallback
				end

				return {
					-- Panel is in seconds because that is how animations read; the store
					-- stays in milliseconds because that is what the scheduler needs.
					delay = math.max(num("delay", 0) * 1000, 0),
					hitbox = {
						X = math.abs(num("hitboxX", 11)),
						Y = math.abs(num("hitboxY", 10)),
						Z = math.abs(num("hitboxZ", 30.5)),
					},
					hso = num("hso", 3),
					shape = inputs.shape.Text,
					faceForward = inputs.faceForward.Text == "On",
					forwardOffset = num("forwardOffset", 0),
					groundAlign = inputs.groundAlign.Text == "On",
					maxDistance = math.max(num("maxDistance", 85), 0),
					repeatCount = math.max(math.floor(num("repeatCount", 1)), 1),
					repeatDelay = math.max(num("repeatDelay", 0.35), 0),
					dodge = inputs.dodge.Text == "Yes",
					dodgeKey = inputs.dodgeKey.Text,
					dodgeDir = inputs.dodgeDir.Text,
				}
			end

			---Paint the panel and the parry-list indicator for an animation id.
			---Falls back to template defaults so an unsaved animation still shows sane
			---starting numbers rather than a grid of zeroes.
			---@param animationId string
			function Visualizer.syncEditor(animationId)
				local timing = Store.get(animationId)
				local source = timing

				if not source then
					local length = (Log.playback[animationId] and Log.playback[animationId].length)
						or (currentTrack and currentTrack.Length)
						or 1
					source = Store.template(animationId, length, "Unnamed")
				end

				source = Store.normalise(source)

				inputs.delay.Text = string.format("%.3f", (source.delay or 0) / 1000)
				inputs.hitboxX.Text = tostring(source.hitbox.X)
				inputs.hitboxY.Text = tostring(source.hitbox.Y)
				inputs.hitboxZ.Text = tostring(source.hitbox.Z)
				inputs.hso.Text = tostring(source.hso)
				inputs.shape.Text = source.shape or "Block"
				inputs.faceForward.Text = source.faceForward and "On" or "Off"
				inputs.forwardOffset.Text = tostring(source.forwardOffset or 0)
				inputs.groundAlign.Text = source.groundAlign and "On" or "Off"
				inputs.maxDistance.Text = tostring(source.maxDistance)
				inputs.repeatCount.Text = tostring(source.repeatCount)
				inputs.repeatDelay.Text = tostring(source.repeatDelay)
				inputs.dodge.Text = source.dodge and "Yes" or "No"
				inputs.dodgeKey.Text = source.dodgeKey or "Default"
				-- "Back" is the old spelling; show it as the word the dropdown actually
				-- offers, or the cycle button starts from a value not in its own list.
				inputs.dodgeDir.Text = (source.dodgeDir == "Back" and "Backward") or source.dodgeDir or "None"

				-- Keep the world preview showing the timing that is on screen. Read
				-- through ctx: this module loads before the sliders exist.
				if ctx.Hitbox then
					ctx.Hitbox.adopt(source)
				end

				if timing and timing.enabled then
					statusLabel.Text = "In parry list"
					statusLabel.TextColor3 = Color3.fromRGB(90, 230, 120)
					toggleButton.Text = "Remove From Parry List"
				elseif timing then
					statusLabel.Text = "Saved, not enabled"
					statusLabel.TextColor3 = Color3.fromRGB(255, 190, 70)
					toggleButton.Text = "Add To Parry List"
				else
					statusLabel.Text = "Not in parry list"
					statusLabel.TextColor3 = Library.FontColor
					toggleButton.Text = "Add To Parry List"
				end

				delayLine.Visible = timing ~= nil
				if timing and currentTrack and currentTrack.Length > 0 then
					delayLine.Position = UDim2.new(math.clamp((timing.delay / 1000) / currentTrack.Length, 0, 1), 0, 0, 0)
				end
			end

			---Write the panel into the store and persist.
			---@param enable boolean? force the enabled flag, otherwise keep what it was
			local function applyEditor(enable)
				if not currentId then
					return notify("Load an animation first", 2)
				end

				local values = readEditor()
				local timing = Store.get(currentId)

				if not timing then
					local length = (currentTrack and currentTrack.Length) or values.delay / 1000
					timing = Store.template(currentId, length, idBox:GetAttribute("EntityName") or "Unnamed")
					Store.create(timing)
				end

				for key, value in pairs(values) do
					timing[key] = value
				end

				if enable ~= nil then
					timing.enabled = enable
				end

				Store.timings[currentId] = timing
				Store.dirty = true

				-- The timing is live either way; ok only says whether it also reached a
				-- file, which it will not on an executor with no writefile.
				local ok, err = Store.autosave()
				notify(
					string.format(
						"Saved %s (%s)%s",
						Util.shortId(currentId),
						timing.enabled and "in parry list" or "off",
						ok and "" or " - " .. tostring(err)
					),
					2
				)

				Visualizer.syncEditor(currentId)
				LoggerGui.refresh()
			end

			saveButton.MouseButton1Click:Connect(function()
				applyEditor(nil)
			end)

			toggleButton.MouseButton1Click:Connect(function()
				if not currentId then
					return notify("Load an animation first", 2)
				end
				local timing = Store.get(currentId)
				applyEditor(not (timing and timing.enabled))
			end)

			---Pick a rig to play the animation on.
			---The entity that threw the animation is preferred, but it dies, despawns and
			---streams out constantly, so fall back rather than refusing to draw anything.
			---@param animationId string
			---@return Model?
			local function sourceRig(animationId)
				local data = Log.playback[animationId]
				if data and data.entity and data.entity.Parent then
					return data.entity
				end

				for _, entry in ipairs(Log.entries) do
					if entry.id == animationId and entry.model and entry.model.Parent then
						return entry.model
					end
				end

				-- Any live rig will do; the skeleton is what plays the animation.
				local rigs = Entities.list()
				if rigs[1] then
					return rigs[1]
				end

				return LocalPlayer.Character
			end

			---Load an animation id into the viewport.
			---@param animationId string
			function Visualizer.load(animationId)
				currentTrack = nil
				currentId = nil
				elapsed = 0
				paused = false

				if type(animationId) ~= "string" or animationId == "" then
					return Visualizer.say("No animation id")
				end

				local rig = sourceRig(animationId)
				if not rig then
					return Visualizer.say("No rig available.\nSpawn in, or get near an NPC, then click again.")
				end

				world:ClearAllChildren()

				-- Some games clear Archivable to block exactly this. Flip it back for the
				-- duration of the clone, then restore so we do not alter the live game.
				local restore = {}
				if not rig.Archivable then
					rig.Archivable = true
					table.insert(restore, rig)
				end
				for _, descendant in ipairs(rig:GetDescendants()) do
					if not descendant.Archivable then
						descendant.Archivable = true
						table.insert(restore, descendant)
					end
				end

				local ok, clone = pcall(function()
					return rig:Clone()
				end)

				for _, instance in ipairs(restore) do
					pcall(function()
						instance.Archivable = false
					end)
				end

				if not ok or not clone then
					return Visualizer.say("Could not clone the rig")
				end

				-- Strip scripts so nothing from the rig runs inside the viewport.
				for _, descendant in ipairs(clone:GetDescendants()) do
					if descendant:IsA("BaseScript") then
						descendant:Destroy()
					end
				end

				clone.Parent = world

				if not clone.PrimaryPart then
					clone.PrimaryPart = clone:FindFirstChild("HumanoidRootPart")
				end

				if not clone.PrimaryPart then
					clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
				end

				if not clone.PrimaryPart then
					return Visualizer.say("Rig has no parts to display")
				end

				clone:PivotTo(CFrame.new(0, 0, 0))

				-- Frame the bounding box centre, not the pivot: the pivot sits at the
				-- waist, and a sword swing needs headroom above it.
				local box, size = clone:GetBoundingBox()
				local focus = box.Position
				camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, size.Y * 0.15, -size.Magnitude * 1.6), focus)

				local animator = clone:FindFirstChildWhichIsA("Animator", true)

				-- Plenty of NPCs only carry an Animator server side, so the clone has a
				-- Humanoid and nothing to drive it. Make one.
				if not animator then
					local controller = clone:FindFirstChildWhichIsA("Humanoid")
						or clone:FindFirstChildWhichIsA("AnimationController")

					if not controller then
						controller = Instance.new("AnimationController")
						controller.Parent = clone
					end

					animator = Instance.new("Animator")
					animator.Parent = controller
				end

				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end

				local animation = Instance.new("Animation")
				animation.AnimationId = animationId

				local loaded, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)

				if not loaded or not track then
					return Visualizer.say("Could not load that animation id")
				end

				track.Priority = Enum.AnimationPriority.Action
				track.Looped = true
				track:Play(0, 100, 1)

				track.DidLoop:Connect(function()
					elapsed = 0
				end)

				currentTrack = track
				currentId = animationId
				message.Visible = false
				idBox.Text = animationId
				idBox:SetAttribute("EntityName", rig.Name)

				Visualizer.syncEditor(animationId)

				-- Length is 0 until Roblox finishes fetching the asset, so the delay
				-- marker cannot be placed on the first frame. Wait for it.
				task.spawn(function()
					local deadline = os.clock() + 5

					while track.Length <= 0 and os.clock() < deadline do
						task.wait(0.05)
					end

					if currentTrack ~= track then
						return
					end

					if track.Length <= 0 then
						return Visualizer.say(
							"Animation asset never loaded.\n" .. Util.shortId(animationId) .. "\nIt may be private or deleted."
						)
					end

					-- Re-sync now that Length is real: this is what places the delay marker.
					Visualizer.syncEditor(animationId)
				end)
			end

			idBox.FocusLost:Connect(function(enter)
				if enter then
					Visualizer.load(idBox.Text)
				end
			end)

			playButton.MouseButton1Click:Connect(function()
				if not currentTrack then
					return
				end
				paused = not paused
				playButton.Text = paused and "Paused" or "Play"
			end)

			prevButton.MouseButton1Click:Connect(function()
				if not currentTrack then
					return
				end
				paused = true
				playButton.Text = "Paused"
				currentTrack.TimePosition = math.max(currentTrack.TimePosition - 0.01, 0)
			end)

			nextButton.MouseButton1Click:Connect(function()
				if not currentTrack then
					return
				end
				paused = true
				playButton.Text = "Paused"
				currentTrack.TimePosition = math.min(currentTrack.TimePosition + 0.01, currentTrack.Length)
			end)

			loadButton.MouseButton1Click:Connect(function()
				if not Log.selected then
					return notify("Click a row in the logger window first", 2)
				end
				Visualizer.load(Log.selected)
			end)

			-- Scrubbing.
			sliderOuter.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end
				if not currentTrack then
					return
				end

				paused = true
				playButton.Text = "Paused"

				-- Mouse rather than GetMouseLocation: the library's own drag code uses
				-- Mouse against AbsolutePosition, so the two agree about the topbar inset.
				local mouse = LocalPlayer:GetMouse()

				while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					if not currentTrack then
						break
					end
					local width = sliderOuter.AbsoluteSize.X
					local x = math.clamp(mouse.X - sliderOuter.AbsolutePosition.X, 0, width)
					currentTrack.TimePosition = (x / width) * currentTrack.Length
					RunService.RenderStepped:Wait()
				end
			end)

			---Per-frame playback update.
			---@param delta number
			function Visualizer.step(delta)
				if not screen.Enabled then
					return
				end

				if not currentTrack or not currentTrack.IsPlaying then
					sliderText.Text = "0.000 / 0.000"
					sliderFill.Size = UDim2.new(0, 0, 1, 0)
					return
				end

				local fraction = currentTrack.Length > 0 and (currentTrack.TimePosition / currentTrack.Length) or 0
				sliderFill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
				local timing = Store.get(currentId)
				sliderText.Text = timing
						and string.format(
							"%.3f / %.3f (%dms)",
							currentTrack.TimePosition,
							currentTrack.Length,
							math.floor(timing.delay)
						)
					or string.format("%.3f / %.3f", currentTrack.TimePosition, currentTrack.Length)

				if paused then
					currentTrack:AdjustSpeed(0)
					speedLabel.Text = string.format("Speed %.2f", Log.speedAt(currentId, currentTrack.TimePosition))
					return
				end

				elapsed = elapsed + delta

				-- Replay at the speed the animation was actually played at us, not 1x.
				local speed = Log.speedAt(currentId, elapsed)
				currentTrack:AdjustSpeed(speed)
				speedLabel.Text = string.format("Speed %.2f", speed)
			end

			return Visualizer
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/VisualizerWindow.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/EffectWindow.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/EffectWindow.lua
			The Unknown Effect Logger, with a 3D preview of whatever row you click.

			Same shape as ui/LoggerWindow.lua - a column-driven list whose status is
			resolved live from features/Effects.lua rather than cached on the row - plus
			a ViewportFrame on the right.

			The preview clones the instance rather than reparenting it. Reparenting a
			live projectile into a ViewportFrame removes it from the game, which at best
			makes the effect vanish for you and at worst desyncs you from the server.
		]]

		return function(ctx)
			local Library, Effects, LocalPlayer = ctx.Library, ctx.Effects, ctx.LocalPlayer

			local EffectGui = {}

			local screen = Instance.new("ScreenGui")
			screen.Name = "AP_EffectLogger"
			screen.ResetOnSpawn = false
			screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			screen.DisplayOrder = 997
			screen.Enabled = false

			pcall(function()
				if syn and syn.protect_gui then
					syn.protect_gui(screen)
				end
				screen.Parent = gethui and gethui() or game:GetService("CoreGui")
			end)

			if not screen.Parent then
				screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
			end

			local outer = Instance.new("Frame")
			outer.BackgroundColor3 = Color3.new(0, 0, 0)
			outer.BorderSizePixel = 0
			outer.Position = UDim2.new(0, 20, 0, 500)
			outer.Size = UDim2.new(0, 640, 0, 250)
			outer.Parent = screen

			local inner = Instance.new("Frame")
			inner.BackgroundColor3 = Library.MainColor
			inner.BorderColor3 = Library.OutlineColor
			inner.BorderMode = Enum.BorderMode.Inset
			inner.Size = UDim2.new(1, -2, 1, -2)
			inner.Position = UDim2.new(0, 1, 0, 1)
			inner.Parent = outer

			local accent = Instance.new("Frame")
			accent.BackgroundColor3 = Library.AccentColor
			accent.BorderSizePixel = 0
			accent.Size = UDim2.new(1, 0, 0, 2)
			accent.Parent = inner

			local title = Instance.new("TextLabel")
			title.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			title.TextColor3 = Library.AccentColor
			title.Text = "Unknown Effect Logger"
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextSize = 15
			title.Position = UDim2.new(0, 6, 0, 4)
			title.Size = UDim2.new(0, 200, 0, 18)
			title.Parent = inner

			local countLabel = Instance.new("TextLabel")
			countLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			countLabel.TextColor3 = Library.FontColor
			countLabel.Text = "0 effects"
			countLabel.BackgroundTransparency = 1
			countLabel.TextXAlignment = Enum.TextXAlignment.Left
			countLabel.TextSize = 13
			countLabel.Position = UDim2.new(0, 200, 0, 5)
			countLabel.Size = UDim2.new(0, 160, 0, 16)
			countLabel.Parent = inner

			local clearButton = Instance.new("TextButton")
			clearButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			clearButton.TextColor3 = Library.FontColor
			clearButton.BackgroundColor3 = Library.BackgroundColor
			clearButton.BorderColor3 = Library.OutlineColor
			clearButton.AutoButtonColor = false
			clearButton.Text = "Clear"
			clearButton.TextSize = 12
			clearButton.Position = UDim2.new(1, -56, 0, 5)
			clearButton.Size = UDim2.new(0, 50, 0, 16)
			clearButton.Parent = inner
			Library:AddToRegistry(clearButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			-- Column geometry shared by the header and every row, so they cannot drift.
			local COLUMNS = {
				{ key = "time", title = "Time", x = 0, w = 58 },
				{ key = "name", title = "Effect", x = 60, w = 130 },
				{ key = "className", title = "Type", x = 192, w = 92 },
				{ key = "creator", title = "Creator", x = 286, w = 96 },
				{ key = "distance", title = "Dist", x = 384, w = 36 },
				{ key = "count", title = "N", x = 422, w = 26 },
			}

			local LIST_W = 452

			local header = Instance.new("Frame")
			header.BackgroundColor3 = Library.BackgroundColor
			header.BorderSizePixel = 0
			header.Position = UDim2.new(0, 4, 0, 24)
			header.Size = UDim2.new(0, LIST_W, 0, 16)
			header.Parent = inner
			Library:AddToRegistry(header, { BackgroundColor3 = "BackgroundColor" }, true)

			for _, column in ipairs(COLUMNS) do
				local label = Instance.new("TextLabel")
				label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				label.TextColor3 = Library.AccentColor
				label.Text = column.title
				label.BackgroundTransparency = 1
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextSize = 12
				label.Position = UDim2.new(0, column.x + 4, 0, 0)
				label.Size = UDim2.new(0, column.w, 1, 0)
				label.Parent = header
				Library:AddToRegistry(label, { TextColor3 = "AccentColor" }, true)
			end

			local list = Instance.new("ScrollingFrame")
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.Position = UDim2.new(0, 4, 0, 42)
			list.Size = UDim2.new(0, LIST_W, 1, -46)
			list.ScrollBarThickness = 3
			list.ScrollBarImageColor3 = Library.AccentColor
			list.CanvasSize = UDim2.new()
			list.Parent = inner

			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 1)
			layout.Parent = list

			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
			end)

			----------------------------------------------------------------------------
			-- 3D preview
			----------------------------------------------------------------------------

			local PREVIEW_X = LIST_W + 10

			local viewport = Instance.new("ViewportFrame")
			viewport.BackgroundColor3 = Library.BackgroundColor
			viewport.BorderColor3 = Library.OutlineColor
			viewport.Position = UDim2.new(0, PREVIEW_X, 0, 24)
			viewport.Size = UDim2.new(0, 170, 0, 150)
			viewport.Parent = inner

			local world = Instance.new("WorldModel")
			world.Parent = viewport

			local camera = Instance.new("Camera")
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 60
			camera.Parent = viewport
			viewport.CurrentCamera = camera

			local viewMessage = Instance.new("TextLabel")
			viewMessage.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			viewMessage.TextColor3 = Library.FontColor
			viewMessage.Text = "Click an effect"
			viewMessage.BackgroundTransparency = 1
			viewMessage.TextWrapped = true
			viewMessage.TextSize = 12
			viewMessage.Size = UDim2.new(1, -8, 1, 0)
			viewMessage.Position = UDim2.new(0, 4, 0, 0)
			viewMessage.Parent = viewport

			local detail = Instance.new("TextLabel")
			detail.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			detail.TextColor3 = Library.FontColor
			detail.Text = ""
			detail.BackgroundTransparency = 1
			detail.TextXAlignment = Enum.TextXAlignment.Left
			detail.TextYAlignment = Enum.TextYAlignment.Top
			detail.TextWrapped = true
			detail.TextSize = 12
			detail.Position = UDim2.new(0, PREVIEW_X, 0, 180)
			detail.Size = UDim2.new(0, 170, 0, 62)
			detail.Parent = inner

			local spin = 0

			---Show one logged effect in the viewport.
			---@param entry table?
			function EffectGui.preview(entry)
				world:ClearAllChildren()
				spin = 0

				if not entry then
					viewMessage.Visible = true
					viewMessage.Text = "Click an effect"
					detail.Text = ""
					return
				end

				detail.Text = string.format(
					"%s\n%s in %s\nfrom %s (%.0fm)\nseen %dx, last %.0fm",
					entry.name,
					entry.className,
					entry.parent or "?",
					entry.creator or "?",
					entry.creatorDistance or 0,
					entry.count or 1,
					entry.distance or 0
				)

				local instance = entry.instance

				if not instance or not instance.Parent then
					viewMessage.Visible = true
					viewMessage.Text = "Instance is gone.\nMost effects are destroyed within a second of spawning."
					return
				end

				-- Sounds and emitters have no geometry of their own. Show the part they
				-- are attached to, which is the thing you would actually recognise.
				local subject = instance
				if not instance:IsA("BasePart") then
					subject = instance.Parent and instance.Parent:IsA("BasePart") and instance.Parent or nil
				end

				if not subject then
					viewMessage.Visible = true
					viewMessage.Text = entry.className .. " has no geometry to draw"
					return
				end

				-- Some games clear Archivable to block exactly this. Flip it back for the
				-- duration of the clone, then restore so we do not alter the live game.
				local restore = {}
				if not subject.Archivable then
					subject.Archivable = true
					table.insert(restore, subject)
				end

				local ok, clone = pcall(function()
					return subject:Clone()
				end)

				for _, target in ipairs(restore) do
					pcall(function()
						target.Archivable = false
					end)
				end

				if not ok or not clone then
					viewMessage.Visible = true
					viewMessage.Text = "Could not clone that instance"
					return
				end

				for _, descendant in ipairs(clone:GetDescendants()) do
					if descendant:IsA("BaseScript") then
						descendant:Destroy()
					end
				end

				clone.Anchored = true
				clone.CFrame = CFrame.new(0, 0, 0)
				clone.Parent = world

				local reach = math.max(clone.Size.Magnitude, 1) * 2.2
				camera.CFrame = CFrame.lookAt(Vector3.new(reach * 0.7, reach * 0.4, reach * 0.7), Vector3.zero)

				viewMessage.Visible = false
			end

			---Turntable, so a flat decal or a thin beam is not a single invisible line.
			---@param delta number
			function EffectGui.step(delta)
				if not screen.Enabled then
					return
				end

				local model = world:FindFirstChildWhichIsA("BasePart")
				if not model then
					return
				end

				spin = (spin + delta * 0.6) % (math.pi * 2)
				model.CFrame = CFrame.Angles(0, spin, 0)
			end

			Library:MakeDraggable(outer)
			Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
			Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
			Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)
			Library:AddToRegistry(viewport, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" }, true)

			local rows = {}

			local STATUS_NEW = Color3.fromRGB(200, 200, 200)
			local STATUS_SAVED = Color3.fromRGB(255, 190, 70)
			local STATUS_ACTIVE = Color3.fromRGB(90, 230, 120)

			---@param name string
			---@return Color3
			local function tint(name)
				local profile = Effects.profiles[name]
				if not profile then
					return STATUS_NEW
				end
				return profile.enabled and STATUS_ACTIVE or STATUS_SAVED
			end

			function EffectGui.visible(state)
				screen.Enabled = state
			end

			clearButton.MouseButton1Click:Connect(function()
				Effects.clear()
				for _, row in ipairs(rows) do
					row.Frame.Visible = false
				end
				countLabel.Text = "0 effects"
				EffectGui.preview(nil)
			end)

			---Build one row: a click target plus one label per column.
			local function makeRow(index)
				local frame = Instance.new("TextButton")
				frame.BackgroundColor3 = Library.BackgroundColor
				frame.BackgroundTransparency = 1
				frame.BorderSizePixel = 0
				frame.AutoButtonColor = false
				frame.Text = ""
				frame.Size = UDim2.new(1, 0, 0, 16)
				frame.LayoutOrder = index
				frame.Parent = list

				local cells = {}
				for _, column in ipairs(COLUMNS) do
					local label = Instance.new("TextLabel")
					label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
					label.TextColor3 = Library.FontColor
					label.BackgroundTransparency = 1
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextTruncate = Enum.TextTruncate.AtEnd
					label.TextSize = 12
					label.Text = ""
					label.Position = UDim2.new(0, column.x + 4, 0, 0)
					label.Size = UDim2.new(0, column.w, 1, 0)
					label.Parent = frame
					cells[column.key] = label
				end

				local row = { Frame = frame, Cells = cells }
				rows[index] = row

				frame.MouseButton1Click:Connect(function()
					local name = frame:GetAttribute("EffectName")
					if not name then
						return
					end

					Effects.selected = name
					EffectGui.preview(Effects.get(name))

					-- Clicking a row is the whole gesture: it also loads the builder, the
					-- same way clicking an animation row loads the timing editor.
					if ctx.loadEffectIntoBuilder then
						ctx.loadEffectIntoBuilder(name)
					end

					EffectGui.refresh()
				end)

				frame.MouseEnter:Connect(function()
					if frame:GetAttribute("EffectName") ~= Effects.selected then
						frame.BackgroundTransparency = 0.7
					end
				end)

				frame.MouseLeave:Connect(function()
					if frame:GetAttribute("EffectName") ~= Effects.selected then
						frame.BackgroundTransparency = 1
					end
				end)

				return row
			end

			---Rebuild the row list from the effect log.
			function EffectGui.refresh()
				if not screen.Enabled then
					return
				end

				countLabel.Text = string.format(
					"%d %s | %d profiles | %d triggers",
					#Effects.entries,
					#Effects.entries == 1 and "effect" or "effects",
					Effects.count(),
					Effects.triggers
				)

				for index, entry in ipairs(Effects.entries) do
					local row = rows[index] or makeRow(index)
					local frame, cells = row.Frame, row.Cells

					frame.LayoutOrder = index
					frame.Visible = true
					frame:SetAttribute("EffectName", entry.name)

					local selected = entry.name == Effects.selected
					frame.BackgroundTransparency = selected and 0.4 or 1
					frame.BackgroundColor3 = selected and Library.AccentColor or Library.BackgroundColor

					local colour = tint(entry.name)

					cells.time.Text = entry.time or "--:--:--"
					cells.name.Text = entry.name
					cells.className.Text = entry.className
					cells.creator.Text = entry.creator or "?"
					cells.distance.Text = string.format("%.0f", entry.distance or 0)
					cells.count.Text = tostring(entry.count or 1)

					cells.time.TextColor3 = Library.FontColor
					cells.name.TextColor3 = colour
					cells.className.TextColor3 = Library.FontColor
					cells.creator.TextColor3 = Library.FontColor
					cells.distance.TextColor3 = Library.FontColor
					cells.count.TextColor3 = Library.FontColor
				end

				for index = #Effects.entries + 1, #rows do
					rows[index].Frame.Visible = false
				end
			end

			ctx.EffectGui = EffectGui
			return EffectGui
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/EffectWindow.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/Wiring.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
			local BuilderBox, StoreBox, HitboxBox = ctx.BuilderBox, ctx.StoreBox, ctx.HitboxBox
			local EffectBuildBox, EffectStoreBox = ctx.EffectBuildBox, ctx.EffectStoreBox
			local timingList, StoreLabel = ctx.timingList, ctx.StoreLabel
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
				StoreLabel:SetText(
					string.format("Timings: %d | %s", Store.count(), FS.available and "saved locally" or "no disk access")
				)
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

			-- Save Config, Load Config, Refresh Lists and Delete Config used to sit here.
			-- With one auto-written file per place there is nothing for them to name,
			-- pick, refresh or delete. The two that survive are the ones that move data
			-- between this machine and the repo, which auto-save cannot do for you.
			StoreBox:AddButton({
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/Wiring.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/Settings.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/Settings.lua
			Tab 3: unload button, menu keybind, Linoria's own theme and config managers.

			SaveManager here stores UI state (slider positions, toggles). It is a
			separate thing from features/Store.lua, which stores the timing database.
			They live in different folders on purpose.
		]]

		return function(ctx)
			local Library, Tabs = ctx.Library, ctx.Tabs
			local ThemeManager, SaveManager = ctx.ThemeManager, ctx.SaveManager
			local Options = ctx.Options

			local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

			MenuGroup:AddButton("Unload", function()
				Library:Unload()
			end)

			MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
				Default = "End",
				NoUI = true,
				Text = "Menu keybind",
			})

			Library.ToggleKeybind = Options.MenuKeybind

			ThemeManager:SetLibrary(Library)
			SaveManager:SetLibrary(Library)
			SaveManager:IgnoreThemeSettings()
			SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
			-- Linoria's BuildFolderTree only makefolder()s the paths it is given, so the
			-- intermediate AutoParry/settings has to exist before it is handed a nested
			-- path. FS.makeTree walks it segment by segment.
			local settingsFolder = ctx.SETTINGS_FOLDER .. "/" .. tostring(game.PlaceId)
			ctx.FS.makeTree(settingsFolder)

			ThemeManager:SetFolder(ctx.ROOT_FOLDER)
			SaveManager:SetFolder(settingsFolder)
			SaveManager:BuildConfigSection(Tabs["UI Settings"])
			ThemeManager:ApplyToTab(Tabs["UI Settings"])

			return MenuGroup
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/ui/Settings.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/Runtime.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/Runtime.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/Boot.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[Fleur] error in src/Boot.lua: " .. tostring(err), 0)
	end
end


return ctx
