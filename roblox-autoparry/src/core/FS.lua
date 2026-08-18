--[[
	core/FS.lua
	Thin wrapper over the executor filesystem API.

	Every call is pcall'd and every failure is a return value, never a throw, so a
	missing executor function degrades the script instead of killing it. Check
	FS.available before promising the user their timings will persist.
]]

return function(ctx)
	local FS = {}

	local w, r, i, mf, isf, lf =
		rawget(getgenv(), "writefile") or writefile,
		rawget(getgenv(), "readfile") or readfile,
		rawget(getgenv(), "isfile") or isfile,
		rawget(getgenv(), "makefolder") or makefolder,
		rawget(getgenv(), "isfolder") or isfolder,
		rawget(getgenv(), "listfiles") or listfiles

	FS.available = (w and r and i and mf and isf and lf) ~= nil

	function FS.write(path, data)
		if not FS.available then
			return false
		end
		return pcall(w, path, data)
	end

	function FS.read(path)
		if not FS.available then
			return nil
		end
		local ok, data = pcall(r, path)
		return ok and data or nil
	end

	function FS.isFile(path)
		if not FS.available then
			return false
		end
		local ok, res = pcall(i, path)
		return ok and res or false
	end

	function FS.isFolder(path)
		if not FS.available then
			return false
		end
		local ok, res = pcall(isf, path)
		return ok and res or false
	end

	function FS.makeFolder(path)
		if not FS.available then
			return false
		end
		if FS.isFolder(path) then
			return true
		end
		return pcall(mf, path)
	end

	---Create a nested path one level at a time.
	---Plenty of executors will not create intermediate folders for you, so
	---writing to "AutoParry/timings/123" fails silently unless we walk it.
	---@param path string
	function FS.makeTree(path)
		local built = nil

		for segment in tostring(path):gmatch("[^/\\]+") do
			built = built and (built .. "/" .. segment) or segment
			FS.makeFolder(built)
		end

		return FS.isFolder(path)
	end

	function FS.list(path)
		if not FS.available or not FS.isFolder(path) then
			return {}
		end
		local ok, res = pcall(lf, path)
		return ok and res or {}
	end

	function FS.delete(path)
		local d = rawget(getgenv(), "delfile") or delfile
		if not d then
			return false
		end
		return pcall(d, path)
	end

	ctx.FS = FS
	return FS
end
