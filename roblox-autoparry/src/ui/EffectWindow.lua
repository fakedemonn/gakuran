--[[
	ui/EffectWindow.lua
	The Unknown Effect Logger, with a 3D preview of whatever row you click.

	Same shape as ui/LoggerWindow.lua - a column-driven list whose status is
	resolved live from features/Effects.lua rather than cached on the row - plus
	a ViewportFrame on the right.

	The preview clones the instance rather than reparenting it. Reparenting a
	live projectile into a ViewportFrame removes it from the game, which at best
	makes the effect vanish for you and at worst desyncs you from the server.
]]

return function(ctx)
	local Library, Effects, LocalPlayer = ctx.Library, ctx.Effects, ctx.LocalPlayer

	local EffectGui = {}

	local screen = Instance.new("ScreenGui")
	screen.Name = "AP_EffectLogger"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 997
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
	outer.Position = UDim2.new(0, 20, 0, 500)
	outer.Size = UDim2.new(0, 640, 0, 250)
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
	title.Text = "Unknown Effect Logger"
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 15
	title.Position = UDim2.new(0, 6, 0, 4)
	title.Size = UDim2.new(0, 200, 0, 18)
	title.Parent = inner

	local countLabel = Instance.new("TextLabel")
	countLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	countLabel.TextColor3 = Library.FontColor
	countLabel.Text = "0 effects"
	countLabel.BackgroundTransparency = 1
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextSize = 13
	countLabel.Position = UDim2.new(0, 200, 0, 5)
	countLabel.Size = UDim2.new(0, 160, 0, 16)
	countLabel.Parent = inner

	local clearButton = Instance.new("TextButton")
	clearButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	clearButton.TextColor3 = Library.FontColor
	clearButton.BackgroundColor3 = Library.BackgroundColor
	clearButton.BorderColor3 = Library.OutlineColor
	clearButton.AutoButtonColor = false
	clearButton.Text = "Clear"
	clearButton.TextSize = 12
	clearButton.Position = UDim2.new(1, -56, 0, 5)
	clearButton.Size = UDim2.new(0, 50, 0, 16)
	clearButton.Parent = inner
	Library:AddToRegistry(clearButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

	-- Column geometry shared by the header and every row, so they cannot drift.
	local COLUMNS = {
		{ key = "time", title = "Time", x = 0, w = 58 },
		{ key = "name", title = "Effect", x = 60, w = 130 },
		{ key = "className", title = "Type", x = 192, w = 92 },
		{ key = "creator", title = "Creator", x = 286, w = 96 },
		{ key = "distance", title = "Dist", x = 384, w = 36 },
		{ key = "count", title = "N", x = 422, w = 26 },
	}

	local LIST_W = 452

	local header = Instance.new("Frame")
	header.BackgroundColor3 = Library.BackgroundColor
	header.BorderSizePixel = 0
	header.Position = UDim2.new(0, 4, 0, 24)
	header.Size = UDim2.new(0, LIST_W, 0, 16)
	header.Parent = inner
	Library:AddToRegistry(header, { BackgroundColor3 = "BackgroundColor" }, true)

	for _, column in ipairs(COLUMNS) do
		local label = Instance.new("TextLabel")
		label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
		label.TextColor3 = Library.AccentColor
		label.Text = column.title
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextSize = 12
		label.Position = UDim2.new(0, column.x + 4, 0, 0)
		label.Size = UDim2.new(0, column.w, 1, 0)
		label.Parent = header
		Library:AddToRegistry(label, { TextColor3 = "AccentColor" }, true)
	end

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 4, 0, 42)
	list.Size = UDim2.new(0, LIST_W, 1, -46)
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = Library.AccentColor
	list.CanvasSize = UDim2.new()
	list.Parent = inner

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = list

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end)

	----------------------------------------------------------------------------
	-- 3D preview
	----------------------------------------------------------------------------

	local PREVIEW_X = LIST_W + 10

	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundColor3 = Library.BackgroundColor
	viewport.BorderColor3 = Library.OutlineColor
	viewport.Position = UDim2.new(0, PREVIEW_X, 0, 24)
	viewport.Size = UDim2.new(0, 170, 0, 150)
	viewport.Parent = inner

	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local camera = Instance.new("Camera")
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 60
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local viewMessage = Instance.new("TextLabel")
	viewMessage.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	viewMessage.TextColor3 = Library.FontColor
	viewMessage.Text = "Click an effect"
	viewMessage.BackgroundTransparency = 1
	viewMessage.TextWrapped = true
	viewMessage.TextSize = 12
	viewMessage.Size = UDim2.new(1, -8, 1, 0)
	viewMessage.Position = UDim2.new(0, 4, 0, 0)
	viewMessage.Parent = viewport

	local detail = Instance.new("TextLabel")
	detail.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	detail.TextColor3 = Library.FontColor
	detail.Text = ""
	detail.BackgroundTransparency = 1
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextWrapped = true
	detail.TextSize = 12
	detail.Position = UDim2.new(0, PREVIEW_X, 0, 180)
	detail.Size = UDim2.new(0, 170, 0, 62)
	detail.Parent = inner

	local spin = 0

	---Show one logged effect in the viewport.
	---@param entry table?
	function EffectGui.preview(entry)
		world:ClearAllChildren()
		spin = 0

		if not entry then
			viewMessage.Visible = true
			viewMessage.Text = "Click an effect"
			detail.Text = ""
			return
		end

		detail.Text = string.format(
			"%s\n%s in %s\nfrom %s (%.0fm)\nseen %dx, last %.0fm",
			entry.name,
			entry.className,
			entry.parent or "?",
			entry.creator or "?",
			entry.creatorDistance or 0,
			entry.count or 1,
			entry.distance or 0
		)

		local instance = entry.instance

		if not instance or not instance.Parent then
			viewMessage.Visible = true
			viewMessage.Text = "Instance is gone.\nMost effects are destroyed within a second of spawning."
			return
		end

		-- Sounds and emitters have no geometry of their own. Show the part they
		-- are attached to, which is the thing you would actually recognise.
		local subject = instance
		if not instance:IsA("BasePart") then
			subject = instance.Parent and instance.Parent:IsA("BasePart") and instance.Parent or nil
		end

		if not subject then
			viewMessage.Visible = true
			viewMessage.Text = entry.className .. " has no geometry to draw"
			return
		end

		-- Some games clear Archivable to block exactly this. Flip it back for the
		-- duration of the clone, then restore so we do not alter the live game.
		local restore = {}
		if not subject.Archivable then
			subject.Archivable = true
			table.insert(restore, subject)
		end

		local ok, clone = pcall(function()
			return subject:Clone()
		end)

		for _, target in ipairs(restore) do
			pcall(function()
				target.Archivable = false
			end)
		end

		if not ok or not clone then
			viewMessage.Visible = true
			viewMessage.Text = "Could not clone that instance"
			return
		end

		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BaseScript") then
				descendant:Destroy()
			end
		end

		clone.Anchored = true
		clone.CFrame = CFrame.new(0, 0, 0)
		clone.Parent = world

		local reach = math.max(clone.Size.Magnitude, 1) * 2.2
		camera.CFrame = CFrame.lookAt(Vector3.new(reach * 0.7, reach * 0.4, reach * 0.7), Vector3.zero)

		viewMessage.Visible = false
	end

	---Turntable, so a flat decal or a thin beam is not a single invisible line.
	---@param delta number
	function EffectGui.step(delta)
		if not screen.Enabled then
			return
		end

		local model = world:FindFirstChildWhichIsA("BasePart")
		if not model then
			return
		end

		spin = (spin + delta * 0.6) % (math.pi * 2)
		model.CFrame = CFrame.Angles(0, spin, 0)
	end

	Library:MakeDraggable(outer)
	Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
	Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
	Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)
	Library:AddToRegistry(viewport, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" }, true)

	local rows = {}

	local STATUS_NEW = Color3.fromRGB(200, 200, 200)
	local STATUS_SAVED = Color3.fromRGB(255, 190, 70)
	local STATUS_ACTIVE = Color3.fromRGB(90, 230, 120)

	---@param name string
	---@return Color3
	local function tint(name)
		local profile = Effects.profiles[name]
		if not profile then
			return STATUS_NEW
		end
		return profile.enabled and STATUS_ACTIVE or STATUS_SAVED
	end

	function EffectGui.visible(state)
		screen.Enabled = state
	end

	clearButton.MouseButton1Click:Connect(function()
		Effects.clear()
		for _, row in ipairs(rows) do
			row.Frame.Visible = false
		end
		countLabel.Text = "0 effects"
		EffectGui.preview(nil)
	end)

	---Build one row: a click target plus one label per column.
	local function makeRow(index)
		local frame = Instance.new("TextButton")
		frame.BackgroundColor3 = Library.BackgroundColor
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.AutoButtonColor = false
		frame.Text = ""
		frame.Size = UDim2.new(1, 0, 0, 16)
		frame.LayoutOrder = index
		frame.Parent = list

		local cells = {}
		for _, column in ipairs(COLUMNS) do
			local label = Instance.new("TextLabel")
			label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			label.TextColor3 = Library.FontColor
			label.BackgroundTransparency = 1
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.TextSize = 12
			label.Text = ""
			label.Position = UDim2.new(0, column.x + 4, 0, 0)
			label.Size = UDim2.new(0, column.w, 1, 0)
			label.Parent = frame
			cells[column.key] = label
		end

		local row = { Frame = frame, Cells = cells }
		rows[index] = row

		frame.MouseButton1Click:Connect(function()
			local name = frame:GetAttribute("EffectName")
			if not name then
				return
			end

			Effects.selected = name
			EffectGui.preview(Effects.get(name))

			-- Clicking a row is the whole gesture: it also loads the builder, the
			-- same way clicking an animation row loads the timing editor.
			if ctx.loadEffectIntoBuilder then
				ctx.loadEffectIntoBuilder(name)
			end

			EffectGui.refresh()
		end)

		frame.MouseEnter:Connect(function()
			if frame:GetAttribute("EffectName") ~= Effects.selected then
				frame.BackgroundTransparency = 0.7
			end
		end)

		frame.MouseLeave:Connect(function()
			if frame:GetAttribute("EffectName") ~= Effects.selected then
				frame.BackgroundTransparency = 1
			end
		end)

		return row
	end

	---Rebuild the row list from the effect log.
	function EffectGui.refresh()
		if not screen.Enabled then
			return
		end

		countLabel.Text = string.format(
			"%d %s | %d profiles | %d triggers",
			#Effects.entries,
			#Effects.entries == 1 and "effect" or "effects",
			Effects.count(),
			Effects.triggers
		)

		for index, entry in ipairs(Effects.entries) do
			local row = rows[index] or makeRow(index)
			local frame, cells = row.Frame, row.Cells

			frame.LayoutOrder = index
			frame.Visible = true
			frame:SetAttribute("EffectName", entry.name)

			local selected = entry.name == Effects.selected
			frame.BackgroundTransparency = selected and 0.4 or 1
			frame.BackgroundColor3 = selected and Library.AccentColor or Library.BackgroundColor

			local colour = tint(entry.name)

			cells.time.Text = entry.time or "--:--:--"
			cells.name.Text = entry.name
			cells.className.Text = entry.className
			cells.creator.Text = entry.creator or "?"
			cells.distance.Text = string.format("%.0f", entry.distance or 0)
			cells.count.Text = tostring(entry.count or 1)

			cells.time.TextColor3 = Library.FontColor
			cells.name.TextColor3 = colour
			cells.className.TextColor3 = Library.FontColor
			cells.creator.TextColor3 = Library.FontColor
			cells.distance.TextColor3 = Library.FontColor
			cells.count.TextColor3 = Library.FontColor
		end

		for index = #Effects.entries + 1, #rows do
			rows[index].Frame.Visible = false
		end
	end

	ctx.EffectGui = EffectGui
	return EffectGui
end
