/*
 * bundle.js - concatenates every source file into one readable text file.
 *
 *   node bundle.js
 *
 * This is a READING artifact, not a runnable script. Each module is
 * `return function(ctx) ... end`, so 28 of them in one file is 28 top-level
 * returns - Lua stops at the first one. To actually run the script, use
 * AutoParry.lua, which build.js produces by wrapping each module in a do-block.
 *
 * Every banner is a Lua comment and build.js is wrapped in a long-bracket
 * comment, so pasting this into an editor with Lua syntax checking does not
 * light up red at line 1.
 */

const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const OUT = process.argv[2] || "C:/Users/Admin/Desktop/AutoParry-source.txt";

// Dependency order, the same order init.lua loads them.
const ORDER = [
	"init.lua",
	"build.js",
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

const RULE = "-- " + "-".repeat(75);
const BUILT = ["C:", "Users", "Admin", "Downloads", "roblox-autoparry", "AutoParry.lua"].join("\\");

const lines = [];
const push = (s) => lines.push(s === undefined ? "" : s);

push(RULE);
push("-- AutoParry - full source bundle");
push("-- Generated from " + ROOT);
push("--");
push("-- FOR READING, NOT FOR RUNNING. Every module is concatenated here, each");
push("-- wrapped in do ... end so the whole thing is valid Lua - but executing it");
push("-- just runs the loader in the first block and returns. The file you");
push("-- actually run is:");
push("--   " + BUILT);
push(RULE);
push();
push("--[[ CONTENTS");

const present = ORDER.filter((f) => fs.existsSync(path.join(ROOT, f)));
const missing = ORDER.filter((f) => !fs.existsSync(path.join(ROOT, f)));

present.forEach((f, i) => {
	const n = fs.readFileSync(path.join(ROOT, f), "utf8").split("\n").length;
	push(`  ${String(i + 1).padStart(2)}. ${f.padEnd(34)} ${String(n).padStart(5)} lines`);
});
push("]]");

let total = 0;

for (const f of present) {
	const raw = fs.readFileSync(path.join(ROOT, f), "utf8").replace(/\r\n/g, "\n").replace(/\s+$/, "");
	total += raw.split("\n").length;

	push();
	push(RULE);
	push("-- FILE: " + f);
	push(RULE);
	push();

	if (f.endsWith(".js")) {
		// JavaScript inside a .lua-flavoured file. Level-2 long bracket so a
		// stray ]] in the source cannot close the comment early.
		push("--[==[  JavaScript - build tooling, not part of the Roblox script");
		push(raw);
		push("]==]");
	} else {
		// do ... end makes each module its own block, so `return function(ctx)`
		// is the last statement of A block rather than of the FILE. Without it
		// Lua rejects everything after the first module's return.
		push("do");
		push(raw);
		push("end");
	}

	push();
}

push(RULE);
push(`-- end of bundle - ${total} lines across ${present.length} files`);
if (missing.length) {
	push("-- MISSING: " + missing.join(", "));
}
push(RULE);

// CRLF so Notepad renders line breaks instead of one endless line.
fs.writeFileSync(OUT, lines.join("\n").replace(/\n/g, "\r\n"), "utf8");

const kb = (fs.statSync(OUT).size / 1024).toFixed(1);
console.log(`wrote ${OUT} (${kb} KB, ${total} lines across ${present.length} files)`);
if (missing.length) {
	console.log("missing: " + missing.join(", "));
}
