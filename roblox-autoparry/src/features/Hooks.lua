--[[
	features/Hooks.lua
	Animator.AnimationPlayed listeners.

	sweep() is safe to call repeatedly. It walks every container Entities
	resolves, not just one, because a game that keeps players in one folder and
	mobs in another would otherwise have half its attacks never hooked at all.

	The per-container DescendantAdded listeners are stored separately and
	replaced rather than appended, because sweep gets re-run on respawn and on
	every entity-source change; stacking them was quietly multiplying every
	animation event.
]]

return function(ctx)
	local Entities = ctx.Entities

	local Hooks = {
		connections = {},
		hooked = {},
		containerConnections = {},
	}

	---Hook a single animator.
	---@param animator Animator
	function Hooks.attach(animator)
		if Hooks.hooked[animator] then
			return
		end

		local entity = animator:FindFirstAncestorWhichIsA("Model")
		if not entity then
			return
		end

		Hooks.hooked[animator] = true

		local connection = animator.AnimationPlayed:Connect(function(track)
			local ok, err = pcall(ctx.Engine.onAnimation, entity, track)
			if not ok and ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
				warn("[AutoParry] " .. tostring(err))
			end
		end)

		table.insert(Hooks.connections, connection)

		table.insert(
			Hooks.connections,
			animator.AncestryChanged:Connect(function(_, parent)
				if not parent then
					Hooks.hooked[animator] = nil
					connection:Disconnect()
				end
			end)
		)
	end

	---Sweep every container and hook the animators in all of them.
	function Hooks.sweep()
		-- Replaced, never appended: sweep re-runs on respawn and on every entity
		-- source change, and stacking these was quietly multiplying every event.
		for _, connection in ipairs(Hooks.containerConnections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		Hooks.containerConnections = {}

		Entities.invalidate()
		local containers = Entities.containers()

		for _, container in ipairs(containers) do
			for _, descendant in ipairs(container:GetDescendants()) do
				if descendant:IsA("Animator") then
					Hooks.attach(descendant)
				end
			end

			table.insert(
				Hooks.containerConnections,
				container.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("Animator") then
						Hooks.attach(descendant)
					end
				end)
			)
		end

		return #containers
	end

	---Names of the containers currently being watched, for the UI.
	---@return string
	function Hooks.sources()
		local names = {}
		for _, container in ipairs(Entities.containers()) do
			table.insert(names, container.Name)
		end
		return #names > 0 and table.concat(names, ", ") or "none"
	end

	function Hooks.detach()
		for _, connection in ipairs(Hooks.connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		for _, connection in ipairs(Hooks.containerConnections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		Hooks.containerConnections = {}
		Hooks.connections = {}
		Hooks.hooked = {}
	end

	ctx.Hooks = Hooks
	return Hooks
end
