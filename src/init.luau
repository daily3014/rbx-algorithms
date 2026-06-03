--!strict
local Types = require("@self/Types")
export type Algorithms = Types.Groups

local Map: {[any]: string} = table.freeze({
	Checksums = "@self/Checksums",
	Pathfinding = "@self/Pathfinding",
	Encoding = "@self/Encoding",
}) :: any

local Groups: Algorithms = setmetatable({ _Map = Map }, {
	__index = function(self, Key)
		if not Map[Key] then
			error(`{Key} is an invalid group`, 2)
		end

		self[Key] = require(Map[Key])
	end
}) :: any

function Groups.Preload(Modules: {string})
	local function IsSubGroup(Value: any): boolean
		return type(Value) == "table" and rawget(Value, "_Map") ~= nil
	end

	local function PreloadAll(SubGroup: any, Path: string)
		local MapValue = rawget(SubGroup, "_Map") :: {[any]: string}
		for Name in MapValue do
			local Item = SubGroup[Name]
			if IsSubGroup(Item) then
				PreloadAll(Item, `{Path}/{Name}`)
			end
		end
	end

	local function PreloadPath(Path: string)
		local Parts: {string} = {}
		for Part in string.gmatch(Path, "[^/]+") do
			table.insert(Parts, Part)
		end

		if #Parts < 2 then
			error(`{Path} is not a valid preload path`, 2)
		end

		local Current: any = Groups
		local CurrentPath = ""

		for Index, Part in Parts do
			if Index == 1 then
				Current = Current[Part]
				CurrentPath = Part
				continue
			end

			if Part == "*" then
				if Index ~= #Parts then
					error(`Wildcard must be last in preload path {Path}`, 2)
				end

				if not IsSubGroup(Current) then
					error(`{CurrentPath} does not contain submodules`, 2)
				end

				PreloadAll(Current, CurrentPath)
				return
			end

			if not IsSubGroup(Current) then
				error(`{CurrentPath} is not a subgroup`, 2)
			end

			local NextValue = Current[Part]
			CurrentPath ..= `/{Part}`

			if Index == #Parts then
				if IsSubGroup(NextValue) then
					error(`{CurrentPath} points to a subgroup; specify an algorithm or use *`, 2)
				end
				return
			end

			if not IsSubGroup(NextValue) then
				error(`{CurrentPath} is an algorithm; expected a subgroup`, 2)
			end

			Current = NextValue
		end
	end

	for _, Path in Modules do
		PreloadPath(Path)
	end
end

return Groups