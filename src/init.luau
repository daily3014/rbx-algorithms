--!strict
local Types = require("@self/Types")
export type Groups = Types.Groups

local Map = {
	Checksums = "@self/Checksums",
	Pathfinding = "@self/Pathfinding",
	Encoding = "@self/Encoding",
}

-- lazy loading; could become a problem in the future if luau adds inlining between modules
local Groups: Groups = setmetatable({}, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} is an invalid group`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

return Groups