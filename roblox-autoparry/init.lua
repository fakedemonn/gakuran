--[[
	AutoParry - loader
	Roblox / Luau, executor script.

	Run this:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/gakuran/main/roblox-autoparry/init.lua"))()

	How it works
	------------
	Every file in src/ is a module of the shape `return function(ctx) ... end`.
	This loader builds one shared context table, fetches each module in
	dependency order, and calls it with that table. A module publishes what it
	exports onto ctx (ctx.Store, ctx.Engine, ...), so later modules just read
	fields off ctx instead of using globals.

	Order matters: core first, then features, then UI, then runtime and boot.
	Modules loaded before ui/Library.lua read ctx.Toggles / ctx.Options at call
	time rather than capturing them, because the UI does not exist yet.
]]

-- The modules live in a subfolder of the repo, so BASE has to include it.
-- If you move them to the repo root, drop the "roblox-autoparry/" segment.
local BRANCH = "main"
local REPO = "https://raw.githubusercontent.com/fakedemonn/gakuran/" .. BRANCH .. "/"
local BASE = REPO .. "roblox-autoparry/"

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

local MODULES = {
	-- core: no dependencies on anything above them
	"src/core/Config.lua",
	"src/core/FS.lua",
	"src/core/Util.lua",
	"src/core/Input.lua",
	"src/core/Latency.lua",
	"src/core/State.lua",
	"src/core/Notify.lua",

	-- features: the actual behaviour
	"src/features/Dodge.lua",
	"src/features/Store.lua",
	"src/features/Log.lua",
	"src/features/Entities.lua",
	"src/features/Engine.lua",
	"src/features/Effects.lua",
	-- After Engine: the preview colours itself with Engine.inHitbox.
	"src/features/Hitbox.lua",
	"src/features/Hooks.lua",

	-- ui: Library.lua must come first, it publishes Toggles and Options
	"src/ui/Library.lua",
	"src/ui/MainTab.lua",
	"src/ui/BuilderTab.lua",
	"src/ui/EffectsTab.lua",
	"src/ui/LoggerWindow.lua",
	"src/ui/VisualizerWindow.lua",
	"src/ui/EffectWindow.lua",
	-- Wiring last of the UI: it connects controls the tabs and windows above
	-- have to exist for.
	"src/ui/Wiring.lua",
	"src/ui/Settings.lua",

	-- loops last, then boot
	"src/Runtime.lua",
	"src/Boot.lua",
}

local ctx = {}
getgenv().AutoParryContext = ctx

---Fetch, compile and run one module against the shared context.
---@param path string
local function loadModule(path)
	local fetched, source = pcall(game.HttpGet, game, BASE .. path)
	if not fetched then
		error(string.format("[AutoParry] could not fetch %s: %s", path, tostring(source)), 0)
	end

	local chunk, syntaxError = loadstring(source, "@" .. path)
	if not chunk then
		error(string.format("[AutoParry] syntax error in %s: %s", path, tostring(syntaxError)), 0)
	end

	local built, factory = pcall(chunk)
	if not built then
		error(string.format("[AutoParry] error running %s: %s", path, tostring(factory)), 0)
	end

	if type(factory) ~= "function" then
		error(string.format("[AutoParry] %s did not return a function(ctx)", path), 0)
	end

	local ran, err = pcall(factory, ctx)
	if not ran then
		error(string.format("[AutoParry] error in %s: %s", path, tostring(err)), 0)
	end
end

for _, path in ipairs(MODULES) do
	loadModule(path)
end

return ctx
