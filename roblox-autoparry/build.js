/*
 * build.js - generates AutoParry.lua from the modules in src/.
 *
 *   node build.js
 *
 * src/ is the source of truth. AutoParry.lua is a convenience artifact for
 * people who want to paste one file into an executor instead of pointing the
 * loader at a repo. Every module is inlined as an immediately-invoked chunk
 * that yields its function(ctx), which is then called against the shared
 * context table - exactly what init.lua does at runtime, minus the HTTP.
 */

const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const OUTPUT = path.join(ROOT, "AutoParry.lua");

// Same order as init.lua. Kept as a literal list rather than a directory walk
// because load order is a dependency graph, not alphabetical.
const MODULES = [
	"src/core/Config.lua",
	"src/core/FS.lua",
	"src/core/Util.lua",
	"src/core/Input.lua",
	"src/core/Latency.lua",
	"src/core/State.lua",
	"src/core/Notify.lua",

	"src/features/Dodge.lua",
	"src/features/Store.lua",
	"src/features/Log.lua",
	"src/features/Entities.lua",
	"src/features/Engine.lua",
	"src/features/Effects.lua",
	"src/features/Hitbox.lua",
	"src/features/Hooks.lua",

	"src/ui/Library.lua",
	"src/ui/MainTab.lua",
	"src/ui/BuilderTab.lua",
	"src/ui/EffectsTab.lua",
	"src/ui/LoggerWindow.lua",
	"src/ui/VisualizerWindow.lua",
	"src/ui/EffectWindow.lua",
	"src/ui/Wiring.lua",
	"src/ui/Settings.lua",

	"src/Runtime.lua",
	"src/Boot.lua",
];

function indent(text) {
	return text
		.split("\n")
		.map((line) => (line.length ? "\t\t" + line : line))
		.join("\n");
}

const parts = [];

parts.push(`--[[
	AutoParry - single file build
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
`);

for (const modulePath of MODULES) {
	const source = fs.readFileSync(path.join(ROOT, modulePath), "utf8").replace(/\s+$/, "");

	parts.push(`
--------------------------------------------------------------------------------
-- ${modulePath}
--------------------------------------------------------------------------------

do
	local factory = (function()
${indent(source)}
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in ${modulePath}: " .. tostring(err), 0)
	end
end
`);
}

parts.push("\nreturn ctx\n");

fs.writeFileSync(OUTPUT, parts.join("\n"), "utf8");

console.log(`wrote ${path.basename(OUTPUT)} from ${MODULES.length} modules`);
