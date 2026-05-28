--!strict
local Types = require("./Types")
type Checksums = Types.Checksums

local Map = {
	CRC32 = "@self/CRC32",
	Adler32 = "@self/Adler32"
}

local Algorithms: Checksums = setmetatable({}, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} doesn't exist`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

return Algorithms