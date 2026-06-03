--!strict
local Utils = {}

function Utils.Symbol(Name: string): any
	local Proxy = newproxy(true)
	local Metatable = getmetatable(Proxy)

	Metatable.__metatable = "Locked"
	Metatable.__tostring = function()
		return Name
	end
	
	return Proxy
end

return Utils