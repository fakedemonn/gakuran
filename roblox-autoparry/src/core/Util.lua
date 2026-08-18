--[[
	core/Util.lua
	Small pure helpers. No state, no dependencies.
]]

return function(ctx)
	local Util = {}

	---Round a number to n decimal places.
	function Util.round(n, places)
		local mult = 10 ^ (places or 0)
		return math.floor(n * mult + 0.5) / mult
	end

	---Strip an AnimationId down to its numeric part for display.
	function Util.shortId(animationId)
		return (tostring(animationId):gsub("rbxassetid://", ""):gsub("http://www.roblox.com/asset/%?id=", ""))
	end

	---Safe distance between two models.
	function Util.distance(a, b)
		local ra = a and a:FindFirstChild("HumanoidRootPart")
		local rb = b and b:FindFirstChild("HumanoidRootPart")
		if not ra or not rb then
			return nil
		end
		return (ra.Position - rb.Position).Magnitude
	end

	---Dot product of A's look vector against the direction to B. 1 = facing directly.
	function Util.facing(a, b)
		local ra = a and a:FindFirstChild("HumanoidRootPart")
		local rb = b and b:FindFirstChild("HumanoidRootPart")
		if not ra or not rb then
			return nil
		end
		local dir = (rb.Position - ra.Position)
		if dir.Magnitude < 0.001 then
			return 1
		end
		return ra.CFrame.LookVector:Dot(dir.Unit)
	end

	---Is this model alive?
	function Util.alive(model)
		local hum = model and model:FindFirstChildWhichIsA("Humanoid")
		return hum ~= nil and hum.Health > 0
	end

	---The part everything else measures from.
	---One place to look so the engine, the preview and the effect logger cannot
	---disagree about what "the rig's position" means.
	---@param model Model?
	---@return BasePart?
	function Util.root(model)
		if not model or not model.Parent then
			return nil
		end
		return model.PrimaryPart
			or model:FindFirstChild("HumanoidRootPart")
			or model:FindFirstChildWhichIsA("BasePart")
	end

	---World Y of the rig's feet.
	---Taken from the bounding box rather than HipHeight + root size, because R6,
	---R15 and custom NPC rigs all disagree about those two and none of them
	---disagree about where the lowest part is.
	---@param model Model
	---@return number?
	function Util.groundY(model)
		if not model then
			return nil
		end
		local ok, cf, size = pcall(function()
			local a, b = model:GetBoundingBox()
			return a, b
		end)
		if not ok or not cf then
			return nil
		end
		return cf.Position.Y - (size.Y / 2)
	end

	ctx.Util = Util
	return Util
end
