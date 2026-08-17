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
		Tooltip = "Draw each attacker's own saved gate while their attack animation plays",
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

	local StoreBox = Tabs.Builder:AddRightGroupbox("Timing Saves")

	StoreBox:AddToggle("AutoCreateTimings", {
		Text = "Auto Create Timings",
		Default = true,
		Tooltip = "Make a stub for every unseen animation",
	})

	StoreBox:AddToggle("AutoSaveOnCreate", {
		Text = "Save On Create",
		Default = true,
		Tooltip = "Write the database to disk the moment a timing is created",
	})

	StoreBox:AddToggle("AutoEnableNewTimings", {
		Text = "Auto Enable New",
		Default = false,
		Tooltip = "Off by default so fresh guesses do not parry at random",
	})

	-- Off by default. The database is served from the repo; a copy sitting in an
	-- executor's workspace folder is a copy you did not intend to hand out. With
	-- this off, Save On Create and every Save button are no-ops and say so, and
	-- Copy Database is how your tuning gets out.
	StoreBox:AddToggle("LocalCache", {
		Text = "Write To Disk",
		Default = false,
		Tooltip = "Allow the timing and effect databases to be written to local files",
	})

	StoreBox:AddInput("ConfigName", { Default = "default", Text = "Config Name", Finished = true })

	local configList = StoreBox:AddDropdown("ConfigList", {
		Values = Store.list(),
		Default = nil,
		AllowNull = true,
		Text = "Config",
	})

	local StoreLabel = StoreBox:AddLabel("Timings: 0", true)

	ctx.BuilderBox = BuilderBox
	ctx.StoreBox = StoreBox
	ctx.HitboxBox = HitboxBox
	ctx.HitboxLabel = HitboxLabel
	ctx.timingList = timingList
	ctx.configList = configList
	ctx.StoreLabel = StoreLabel

	return BuilderBox
end
