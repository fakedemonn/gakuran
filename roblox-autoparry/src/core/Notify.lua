--[[
	core/Notify.lua
	One notification entry point.

	Deliberately safe to call before the UI exists: modules further down load
	before ui/Library.lua, and a notification during boot should be a no-op
	rather than an error.
]]

return function(ctx)
	local function notify(text, duration)
		local Library = ctx.Library
		if Library and Library.Notify then
			Library:Notify(text, duration or 2)
		end
	end

	ctx.notify = notify
	return notify
end
