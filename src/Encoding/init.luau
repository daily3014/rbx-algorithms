--!strict
local Types = require("./Types")
type Encoding = Types.Encoding

local Map: {[any]: string} = table.freeze({
	Base64 = "@self/Base64",
	JSON = "@self/JSON",
	MessagePack = "@self/MessagePack",
	Hexadecimal = "@self/Hexadecimal"
}) :: any

local Algorithms: Encoding = setmetatable({ _Map = Map }, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} doesn't exist`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

return Algorithms