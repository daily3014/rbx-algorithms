--[=[
	Data format: JSON
	
	Return type: table or string
	Example usage:
		local MyTable = {
			name = "Builderman",
			array = {1, 2, 3}
		}
		
		local Encoded: string = JSON.Encode(MyTable)
		local Decoded: {} = JSON.Decode(Encoded)
--]=]
--!strict
--!optimize 2
--!native

local JSON = {}

function JSON.Encode(Data: any): string
	return error("Not implemented")
end

function JSON.Decode(Data: string): any
	return error("Not implemented")
end

table.freeze(JSON)
return JSON