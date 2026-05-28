--!strict
local Types = require("./Types")
type Encoding = Types.Encoding

local Map = {
	Base64 = "@self/Base64",
	JSON = "@self/JSON",
	MessagePack = "@self/MessagePack",
	Hexadecimal = "@self/Hexadecimal"
}

local Algorithms: Encoding = setmetatable({}, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} doesn't exist`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

return Algorithms