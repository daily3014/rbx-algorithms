--!strict
local Types = require("./Types")
type Pathfinding = Types.Pathfinding

local Map: {[any]: string} = table.freeze({
	AStar = "@self/AStar",
}) :: any

local Algorithms: Pathfinding = setmetatable({ _Map = Map }, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} doesn't exist`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

return Algorithms