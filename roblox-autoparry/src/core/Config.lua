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
