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
