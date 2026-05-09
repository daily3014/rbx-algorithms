--[=[
	Data format: MessagePack
	
	Return type: table or buffer
	Example usage:
		local MyTable = {
			name = "Builderman",
			array = {1, 2, 3}
		}
		
		local Encoded: buffer = MessagePack.Encode(MyTable)
		local Decoded: {} = MessagePack.Decode(Encoded)
--]=]
--!strict
--!optimize 2
--!native

local MessagePack = {}

function MessagePack.Encode(Data: any): buffer
	return error("Not implemented")
end

function MessagePack.Decode(Data: buffer): any
	return error("Not implemented")
end

table.freeze(MessagePack)
return MessagePack