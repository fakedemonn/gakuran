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
