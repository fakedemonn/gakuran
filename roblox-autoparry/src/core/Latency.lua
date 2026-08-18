--[[
	core/Latency.lua
	Network timing.

	Stats "Data Ping" is a ROUND TRIP measurement, not one-way. Getting this
	backwards is the single most common way an auto parry ends up firing at
	double the intended offset, so the two functions are named to make the
	distinction impossible to miss at the call site.
]]

return function(ctx)
	local Latency = {}

	---Round trip time in seconds.
	function Latency.rtt()
		local network = ctx.Stats:FindFirstChild("Network")
		local item = network and network:FindFirstChild("ServerStatsItem")
		local ping = item and item:FindFirstChild("Data Ping")
		if not ping then
			return 0
		end
		local ok, value = pcall(function()
			return ping:GetValue()
		end)
		return ok and (value / 1000) or 0
	end

	---One-way delay in seconds.
	function Latency.half()
		return math.max(Latency.rtt() / 2, 0)
	end

	ctx.Latency = Latency
	return Latency
end
