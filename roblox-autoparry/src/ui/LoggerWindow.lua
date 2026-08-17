--[[
	ui/LoggerWindow.lua
	The Info Logger: Time | Animation | ID | Enemy | Dist | Status.

	Status is resolved live from the store on every refresh rather than cached
	on the log entry, so a row that appeared as NEW flips to KNOWN the moment a
	timing exists for it, and to IN AP the moment that timing is enabled.

	Clicking a row is the whole gesture: it selects, opens the visualizer if it
	is closed, and loads the animation. Loads before ui/VisualizerWindow.lua, so
	it reaches the visualizer through ctx at click time.
]]

return function(ctx)
	local Library, Store, Log, LocalPlayer = ctx.Library, ctx.Store, ctx.Log, ctx.LocalPlayer

	local LoggerGui = {}

	local screen = Instance.new("ScreenGui")
	screen.Name = "AP_InfoLogger"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 999
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
	outer.Name = "Outer"
	outer.BackgroundColor3 = Color3.new(0, 0, 0)
	outer.BorderSizePixel = 0
	outer.Position = UDim2.new(0, 20, 0, 200)
	outer.Size = UDim2.new(0, 470, 0, 280)
	outer.Parent = screen

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
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
	title.Text = "Info Logger"
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 15
	title.Position = UDim2.new(0, 6, 0, 4)
	title.Size = UDim2.new(0, 110, 0, 18)
	title.Parent = inner

	local countLabel = Instance.new("TextLabel")
	countLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	countLabel.TextColor3 = Library.FontColor
	countLabel.Text = "0 entries"
	countLabel.BackgroundTransparency = 1
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextSize = 13
	countLabel.Position = UDim2.new(0, 120, 0, 5)
	countLabel.Size = UDim2.new(0, 120, 0, 16)
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
		{ key = "animName", title = "Animation", x = 60, w = 110 },
		{ key = "assetId", title = "ID", x = 172, w = 96 },
		{ key = "entity", title = "Enemy", x = 270, w = 96 },
		{ key = "dist", title = "Dist", x = 368, w = 40 },
		{ key = "status", title = "Status", x = 410, w = 46 },
	}

	local header = Instance.new("Frame")
	header.BackgroundColor3 = Library.BackgroundColor
	header.BorderSizePixel = 0
	header.Position = UDim2.new(0, 4, 0, 24)
	header.Size = UDim2.new(1, -8, 0, 16)
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
	list.Size = UDim2.new(1, -8, 1, -46)
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

	Library:MakeDraggable(outer)

	Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
	Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
	Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)

	local rows = {}

	local STATUS_NEW = Color3.fromRGB(200, 200, 200)
	local STATUS_KNOWN = Color3.fromRGB(255, 190, 70)
	local STATUS_ACTIVE = Color3.fromRGB(90, 230, 120)

	---Status is read live from the store, never cached on the entry, so a row
	---logged as NEW flips to IN AP the moment you save a timing for it.
	---@param animationId string
	---@return string, Color3
	local function statusOf(animationId)
		local timing = Store.get(animationId)
		if not timing then
			return "NEW", STATUS_NEW
		end
		if timing.enabled then
			return "IN AP", STATUS_ACTIVE
		end
		return "KNOWN", STATUS_KNOWN
	end

	---Set window visibility.
	function LoggerGui.visible(state)
		screen.Enabled = state
	end

	clearButton.MouseButton1Click:Connect(function()
		Log.clear()
		for _, row in ipairs(rows) do
			row.Frame.Visible = false
		end
		countLabel.Text = "0 entries"
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
			local Toggles = ctx.Toggles
			local Visualizer = ctx.Visualizer

			Log.selected = frame:GetAttribute("AnimationId")
			if not Log.selected then
				return
			end

			-- Clicking a row is the whole gesture: open the visualizer if it is
			-- closed, then load. Otherwise the click looks dead.
			if Visualizer and Visualizer.load then
				if Toggles.ShowAnimationVisualizer and not Toggles.ShowAnimationVisualizer.Value then
					Toggles.ShowAnimationVisualizer:SetValue(true)
				end
				Visualizer.load(Log.selected)
			end

			LoggerGui.refresh()
		end)

		frame.MouseEnter:Connect(function()
			if frame:GetAttribute("AnimationId") ~= Log.selected then
				frame.BackgroundTransparency = 0.7
			end
		end)

		frame.MouseLeave:Connect(function()
			if frame:GetAttribute("AnimationId") ~= Log.selected then
				frame.BackgroundTransparency = 1
			end
		end)

		return row
	end

	---Rebuild the row list from the log.
	function LoggerGui.refresh()
		if not screen.Enabled then
			return
		end

		countLabel.Text = string.format("%d %s", #Log.entries, #Log.entries == 1 and "entry" or "entries")

		for index, entry in ipairs(Log.entries) do
			local row = rows[index] or makeRow(index)
			local frame, cells = row.Frame, row.Cells

			frame.LayoutOrder = index
			frame.Visible = true
			frame:SetAttribute("AnimationId", entry.id)

			local selected = entry.id == Log.selected
			frame.BackgroundTransparency = selected and 0.4 or 1
			frame.BackgroundColor3 = selected and Library.AccentColor or Library.BackgroundColor

			local statusText, statusColor = statusOf(entry.id)

			cells.time.Text = entry.time or "--:--:--"
			cells.animName.Text = entry.animName or "Animation"
			cells.assetId.Text = entry.assetId or "?"
			cells.entity.Text = entry.entity or "?"
			cells.dist.Text = string.format("%.0f", entry.distance or 0)
			cells.status.Text = statusText
			cells.status.TextColor3 = statusColor

			-- Tint the whole row too, so a screen full of entries reads at a glance
			-- instead of forcing you to scan the last column.
			local bodyColor = statusText == "NEW" and Library.FontColor or statusColor
			cells.time.TextColor3 = Library.FontColor
			cells.animName.TextColor3 = bodyColor
			cells.assetId.TextColor3 = bodyColor
			cells.entity.TextColor3 = Library.FontColor
			cells.dist.TextColor3 = Library.FontColor
		end

		for index = #Log.entries + 1, #rows do
			rows[index].Frame.Visible = false
		end
	end

	ctx.LoggerGui = LoggerGui
	return LoggerGui
end
