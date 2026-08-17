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

	-- Hold Time, Manual Offset and Cooldown used to live here. They are per-timing
	-- fields now (holdTime in Quick Edit) or fixed constants in Engine/State, so
	-- the box holds only what is genuinely global.
	ParryBox:AddSlider("PingCompensation", {
		Text = "Ping Compensation",
		Default = 100,
		Min = 0,
		Max = 150,
		Rounding = 0,
		Suffix = "%",
		Tooltip = "How much of your round trip time to subtract from the parry delay",
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
