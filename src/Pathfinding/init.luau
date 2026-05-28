--!strict
local Types = require("./Types")
type Pathfinding = Types.Pathfinding

local Map = {
	AStar = "@self/AStar",
}

local Algorithms: Pathfinding = setmetatable({}, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} doesn't exist`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

return Algorithms