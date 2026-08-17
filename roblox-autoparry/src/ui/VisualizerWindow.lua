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
			Store.create(timing, false)
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
		-- file, which it will not when Write To Disk is off.
		local ok, err = Store.save(Store.configName)
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
