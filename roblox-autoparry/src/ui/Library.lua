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
		Title = string.format("AutoParry v%s", ctx.VERSION),
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
		error("[AutoParry] LinoriaLib did not publish Toggles/Options", 0)
	end

	return Library
end
