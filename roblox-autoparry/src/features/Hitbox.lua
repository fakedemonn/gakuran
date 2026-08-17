--[[
	features/Hitbox.lua
	Draws parry hitboxes and the max-distance ring in the world.

	Three load-bearing decisions:

	1. Geometry comes from Engine.hitboxSize / Engine.hitboxCFrame, never from a
	   local copy of the maths. The picture cannot drift out of agreement with
	   the gate because there is only one set of numbers for either to drift
	   from. Colour comes from Engine.inHitbox for the same reason.

	2. Updates run on BindToRenderStep at Camera + 1, not RenderStepped. The
	   camera moves during the render step; a part positioned before the camera
	   updates is one frame stale relative to what you are looking at, which is
	   exactly the wiggle you see when strafing. Binding after the camera fixes
	   it. Properties are only written when they actually change, so the
	   SelectionBox is not rebuilt 240 times a second for no reason.

	3. Parts live under Workspace.CurrentCamera. Anything parented there renders
	   but never replicates, so the preview is not something the game's own code
	   can see.
]]

return function(ctx)
	local Workspace, LocalPlayer, RunService = ctx.Workspace, ctx.LocalPlayer, ctx.RunService
	local Entities, Util = ctx.Entities, ctx.Util

	local Hitbox = {}

	-- Used until the sliders exist, and whenever one is missing.
	local FALLBACK = {
		X = 11,
		Y = 10,
		Z = 30.5,
		hso = 3,
		maxDistance = 85,
		shape = "Block",
		forwardOffset = 0,
	}

	local INSIDE = Color3.fromRGB(90, 230, 120)
	local OUTSIDE = Color3.fromRGB(255, 90, 90)
	local ENEMY = Color3.fromRGB(255, 170, 60)
	local RING = Color3.fromRGB(120, 170, 255)

	Hitbox.SHAPES = { "Block", "Sphere", "Cylinder" }

	local folder, ringPart
	local preview
	local enemyPool = {}
	local active = {}

	Hitbox.distance = nil
	Hitbox.inside = false
	Hitbox.anchorName = nil

	----------------------------------------------------------------------------
	-- Volumes
	----------------------------------------------------------------------------

	---One drawable volume: a part plus its wireframe.
	---@param name string
	---@return table
	local function makeVolume(name)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = OUTSIDE
		part.Transparency = 1
		part.Size = Vector3.one
		part.Parent = folder

		-- The fill alone reads as mush at a distance; the wireframe is what makes
		-- the shape legible while you drag a slider.
		local outline = Instance.new("SelectionBox")
		outline.Adornee = part
		outline.LineThickness = 0.04
		outline.SurfaceTransparency = 1
		outline.Color3 = OUTSIDE
		outline.Visible = false
		outline.Parent = part

		return { part = part, outline = outline, shape = nil, size = nil, colour = nil, visible = false }
	end

	---Point a volume at a shape, size and CFrame, writing only what changed.
	---
	---Roblox cylinders run along their own local X, so an upright one needs a 90
	---degree roll and its size axes swapped. Spheres take one diameter, so the
	---largest axis wins - matching what Engine.inHitbox does for the same shape.
	---@param volume table
	---@param shape string
	---@param size Vector3
	---@param cf CFrame
	local function shapeVolume(volume, shape, size, cf)
		local part = volume.part

		if volume.shape ~= shape then
			volume.shape = shape
			part.Shape = shape == "Sphere" and Enum.PartType.Ball
				or shape == "Cylinder" and Enum.PartType.Cylinder
				or Enum.PartType.Block
			-- A wireframe box around a ball is noise, not information.
			volume.outline.Visible = volume.visible and shape == "Block"
		end

		local target, rotate
		if shape == "Sphere" then
			local diameter = math.max(size.X, size.Y, size.Z)
			target, rotate = Vector3.new(diameter, diameter, diameter), false
		elseif shape == "Cylinder" then
			local diameter = math.max(size.X, size.Z)
			target, rotate = Vector3.new(size.Y, diameter, diameter), true
		else
			target, rotate = size, false
		end

		if volume.size ~= target then
			volume.size = target
			part.Size = target
		end

		part.CFrame = rotate and (cf * CFrame.Angles(0, 0, math.rad(90))) or cf
	end

	---@param volume table
	---@param colour Color3
	local function colourVolume(volume, colour)
		if volume.colour == colour then
			return
		end
		volume.colour = colour
		volume.part.Color = colour
		volume.outline.Color3 = colour
	end

	---@param volume table
	---@param state boolean
	---@param transparency number?
	local function showVolume(volume, state, transparency)
		if volume.visible == state then
			if state then
				volume.part.Transparency = transparency or 0.8
			end
			return
		end
		volume.visible = state
		volume.part.Transparency = state and (transparency or 0.8) or 1
		volume.outline.Visible = state and volume.shape == "Block"
	end

	---Create the parts once, and re-create them if something wiped them.
	---@return boolean
	local function ensureParts()
		if folder and folder.Parent then
			return true
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return false
		end

		folder = Instance.new("Folder")
		folder.Name = "AP_HitboxPreview"

		preview = makeVolume("Preview")
		enemyPool = {}

		ringPart = Instance.new("Part")
		ringPart.Name = "MaxDistance"
		ringPart.Shape = Enum.PartType.Cylinder
		ringPart.Anchored = true
		ringPart.CanCollide = false
		ringPart.CanQuery = false
		ringPart.CanTouch = false
		ringPart.CastShadow = false
		ringPart.Material = Enum.Material.Neon
		ringPart.Color = RING
		ringPart.Transparency = 1
		ringPart.Size = Vector3.one
		ringPart.Parent = folder

		folder.Parent = camera
		return true
	end

	----------------------------------------------------------------------------
	-- Preview
	----------------------------------------------------------------------------

	---Live values straight off the sliders, shaped like a timing so they can be
	---handed to the same Engine functions a real timing goes through.
	---@return table
	function Hitbox.values()
		local Toggles, Options = ctx.Toggles, ctx.Options

		local function number(name, fallback)
			local option = Options and Options[name]
			if option and type(option.Value) == "number" then
				return option.Value
			end
			return fallback
		end

		local function flag(name)
			local toggle = Toggles and Toggles[name]
			return (toggle and toggle.Value) == true
		end

		return {
			hitbox = {
				X = number("HB_X", FALLBACK.X),
				Y = number("HB_Y", FALLBACK.Y),
				Z = number("HB_Z", FALLBACK.Z),
			},
			hso = number("HB_HSO", FALLBACK.hso),
			maxDistance = number("HB_MaxDistance", FALLBACK.maxDistance),
			forwardOffset = number("HB_ForwardOffset", FALLBACK.forwardOffset),
			shape = (Options and Options.HitboxShape and Options.HitboxShape.Value) or FALLBACK.shape,
			faceForward = flag("HB_FaceForward"),
			groundAlign = flag("HB_GroundAlign"),
		}
	end

	---Which rig the preview is drawn on.
	---@return Model?
	function Hitbox.anchor()
		local Options = ctx.Options
		local mode = Options and Options.HitboxAnchor and Options.HitboxAnchor.Value or "Nearest Enemy"
		local character = LocalPlayer.Character

		if mode == "Self" then
			return character
		end

		local best, bestDistance = nil, math.huge

		for _, entity in ipairs(Entities.list()) do
			if entity ~= character and Util.alive(entity) then
				local distance = Util.distance(entity, character)
				if distance and distance < bestDistance then
					best, bestDistance = entity, distance
				end
			end
		end

		-- Nothing alive nearby: fall back to your own rig so there is still a box
		-- to size against, rather than the preview silently vanishing.
		return best or character
	end

	----------------------------------------------------------------------------
	-- Enemy hitboxes
	----------------------------------------------------------------------------

	---Show a timing's own gate on an attacker for a while.
	---Called by Engine.onAnimation for every known animation, so an attack you
	---have a timing for lights up its real box the moment it starts.
	---@param entity Model
	---@param timing table
	---@param duration number
	function Hitbox.flash(entity, timing, duration)
		if not entity or not timing then
			return
		end

		-- Re-arming an entry rather than appending keeps a spammed animation from
		-- growing the active list without bound.
		for _, entry in ipairs(active) do
			if entry.entity == entity and entry.timing.id == timing.id then
				entry.expires = os.clock() + duration
				return
			end
		end

		table.insert(active, { entity = entity, timing = timing, expires = os.clock() + duration })
	end

	---@return table
	local function enemyVolume(index)
		local volume = enemyPool[index]
		if not volume then
			volume = makeVolume("Enemy" .. index)
			enemyPool[index] = volume
		end
		return volume
	end

	---Draw every live attack box, and retire the expired ones.
	---@param enabled boolean
	local function stepEnemies(enabled)
		local now = os.clock()
		local drawn = 0

		for index = #active, 1, -1 do
			local entry = active[index]
			if now >= entry.expires or not entry.entity.Parent then
				table.remove(active, index)
			end
		end

		if enabled then
			for _, entry in ipairs(active) do
				local cf = ctx.Engine and ctx.Engine.hitboxCFrame(entry.timing, entry.entity)
				if cf then
					drawn = drawn + 1
					local volume = enemyVolume(drawn)
					local inside = ctx.Engine.inHitbox(entry.timing, entry.entity) == true

					shapeVolume(volume, entry.timing.shape or "Block", ctx.Engine.hitboxSize(entry.timing), cf)
					-- Inverted against the preview on purpose: on an enemy's box,
					-- being inside is the dangerous state, so inside is red.
					colourVolume(volume, inside and OUTSIDE or ENEMY)
					showVolume(volume, true, 0.86)
				end
			end
		end

		for index = drawn + 1, #enemyPool do
			showVolume(enemyPool[index], false)
		end
	end

	----------------------------------------------------------------------------
	-- Per-frame
	----------------------------------------------------------------------------

	---Redraw everything. Bound to render step; bails cheaply when off.
	function Hitbox.step()
		local Toggles = ctx.Toggles
		local Engine = ctx.Engine

		if not ensureParts() then
			return
		end

		local showEnemies = (Toggles and Toggles.ShowEnemyHitboxes and Toggles.ShowEnemyHitboxes.Value) == true
		stepEnemies(showEnemies and Engine ~= nil)

		local on = (Toggles and Toggles.ShowHitbox and Toggles.ShowHitbox.Value) == true

		if not on or not Engine then
			Hitbox.distance = nil
			Hitbox.inside = false
			showVolume(preview, false)
			ringPart.Transparency = 1
			return
		end

		local anchor = Hitbox.anchor()
		local values = Hitbox.values()
		local cf = anchor and Engine.hitboxCFrame(values, anchor)

		if not cf then
			Hitbox.distance = nil
			Hitbox.inside = false
			showVolume(preview, false)
			ringPart.Transparency = 1
			return
		end

		local inside = Engine.inHitbox(values, anchor) == true

		shapeVolume(preview, values.shape, Engine.hitboxSize(values), cf)
		colourVolume(preview, inside and INSIDE or OUTSIDE)
		showVolume(preview, true, 0.8)

		Hitbox.inside = inside
		Hitbox.distance = Util.distance(anchor, LocalPlayer.Character)
		Hitbox.anchorName = anchor.Name

		local ringOn = (Toggles and Toggles.ShowMaxDistance and Toggles.ShowMaxDistance.Value) == true

		if ringOn and values.maxDistance > 0 then
			-- A cylinder's own axis is local X, so rotate it upright to get a flat
			-- disc on the ground instead of a barrel on its side.
			--
			-- The real max-distance check is a 3D root-to-root magnitude, so this
			-- disc is its ground-plane projection: accurate on level ground, and
			-- slightly generous when the attacker is above or below you.
			local root = Util.root(anchor)
			local feet = Util.groundY(anchor) or (root and root.Position.Y - 3)

			ringPart.Size = Vector3.new(0.15, values.maxDistance * 2, values.maxDistance * 2)
			ringPart.CFrame = CFrame.new(root.Position.X, feet + 0.1, root.Position.Z)
				* CFrame.Angles(0, 0, math.rad(90))
			ringPart.Transparency = 0.88
		else
			ringPart.Transparency = 1
		end
	end

	---One line for the Builder tab label.
	---@return string
	function Hitbox.status()
		local Toggles = ctx.Toggles

		if not (Toggles and Toggles.ShowHitbox and Toggles.ShowHitbox.Value) then
			return #active > 0 and string.format("Preview off | %d enemy box(es)", #active) or "Preview off"
		end

		if not Hitbox.distance then
			return "No rig to draw on"
		end

		local values = Hitbox.values()

		return string.format(
			"%s | %.1fm | %s | %s | max %dm",
			Hitbox.anchorName or "?",
			Hitbox.distance,
			Hitbox.inside and "INSIDE" or "outside",
			values.shape,
			math.floor(values.maxDistance)
		)
	end

	---Push a timing's geometry into the preview controls.
	---Called whenever the visualizer paints a new timing, so clicking a logger
	---row draws that animation's box in the world without a second click.
	---@param timing table?
	function Hitbox.adopt(timing)
		local Toggles, Options = ctx.Toggles, ctx.Options
		if not timing or not Options or not Options.HB_X then
			return
		end

		local hitbox = timing.hitbox
		if type(hitbox) ~= "table" then
			return
		end

		Options.HB_X:SetValue(hitbox.X or FALLBACK.X)
		Options.HB_Y:SetValue(hitbox.Y or FALLBACK.Y)
		Options.HB_Z:SetValue(hitbox.Z or FALLBACK.Z)
		Options.HB_HSO:SetValue(timing.hso or FALLBACK.hso)
		Options.HB_MaxDistance:SetValue(timing.maxDistance or FALLBACK.maxDistance)
		Options.HB_ForwardOffset:SetValue(timing.forwardOffset or 0)
		Options.HitboxShape:SetValue(timing.shape or FALLBACK.shape)
		Toggles.HB_FaceForward:SetValue(timing.faceForward == true)
		Toggles.HB_GroundAlign:SetValue(timing.groundAlign == true)
	end

	----------------------------------------------------------------------------
	-- Lifecycle
	----------------------------------------------------------------------------

	local BIND = "AP_HitboxRender"

	---Bind the redraw after the camera has been updated for this frame.
	---Doing it before - which is what a plain RenderStepped connection does -
	---leaves the box one camera frame behind, and that lag is the jitter.
	function Hitbox.bind()
		pcall(function()
			RunService:UnbindFromRenderStep(BIND)
		end)

		RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
			local ok, err = pcall(Hitbox.step)
			if not ok and ctx.Toggles and ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
				warn("[AutoParry] hitbox: " .. tostring(err))
			end
		end)
	end

	---Tear the preview down. Called from Runtime's unload handler.
	function Hitbox.destroy()
		pcall(function()
			RunService:UnbindFromRenderStep(BIND)
		end)

		if folder then
			pcall(function()
				folder:Destroy()
			end)
		end

		folder, ringPart, preview = nil, nil, nil
		enemyPool = {}
		active = {}
	end

	ctx.Hitbox = Hitbox
	return Hitbox
end
