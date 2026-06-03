--[=[
	Data format: JSON (RFC 8259)

	Decode accepts a string or buffer and returns the decoded value.
	JSON null is represented by the JSON.Null sentinel.
	Encode serializes a Lua value into a JSON string. Tables with no
	keys, or with the first key returned by next being a number, are
	encoded as arrays; otherwise as objects.

	Return types:
		Decode(Input: string | buffer): any
		Encode(Value: any): string

	Example usage:
		local Value = JSON.Decode('{"foo":[1,2,3]}')
		local Text = JSON.Encode({ Foo = { 1, 2, 3 } })
--]=]

--!strict
--!optimize 2
--!native

local SCALING_FACTOR = 1.5
local BUFFER_START_SIZE = 1024

local IS_WHITESPACE = buffer.create(256) do
	buffer.writeu8(IS_WHITESPACE, 0x20, 1)
	buffer.writeu8(IS_WHITESPACE, 0x09, 1)
	buffer.writeu8(IS_WHITESPACE, 0x0A, 1)
	buffer.writeu8(IS_WHITESPACE, 0x0D, 1)
end

local IS_STRING_END = buffer.create(256) do
	for Index = 0, 0x1F do
		buffer.writeu8(IS_STRING_END, Index, 1)
	end
	buffer.writeu8(IS_STRING_END, 0x22, 1)
	buffer.writeu8(IS_STRING_END, 0x5C, 1)
end

local NEEDS_ESCAPE = buffer.create(256) do
	for Index = 0, 0x1F do
		buffer.writeu8(NEEDS_ESCAPE, Index, 1)
	end
	buffer.writeu8(NEEDS_ESCAPE, 0x22, 1)
	buffer.writeu8(NEEDS_ESCAPE, 0x5C, 1)
end

local Utils = require("../Utils")
local JSON = { Null = Utils.Symbol("JSON.Null") }

type JSONStruct = {
	Input: any,

	Output: buffer,
	Length: number,
}

local function ParseError(Parser: JSONStruct, Message: string): never
	error(`JSON parse error at offset {Parser.Length}: {Message}`, 0)
end

local function EstimateSize(Value: any): number
	if type(Value) == "buffer" then
		return buffer.len(Value)
	elseif type(Value) == "string" then
		return string.len(Value)
	elseif type(Value) == "number" then
		return 8
	end

	return BUFFER_START_SIZE
end

local function CreateParser(Input: any): JSONStruct
	return {
		Input = Input,
		Output = buffer.create(EstimateSize(Input)),
		Length = 0
	}
end

local function ReservePointer(Parser: JSONStruct, Size: number): number
	local Pointer = Parser.Length
	Parser.Length += Size

	local OldSize = buffer.len(Parser.Output)
	if Pointer + Size >= OldSize then
		local NewSize = OldSize * SCALING_FACTOR

		while Pointer + Size >= NewSize do
			-- if we land on the exact size, just add one
			if Pointer + Size == NewSize then
				NewSize += 1
				break	
			end

			NewSize *= SCALING_FACTOR
		end

		local NewBuffer = buffer.create(NewSize)
		buffer.copy(Parser.Output, 0, NewBuffer, 0, OldSize)
		Parser.Output = NewBuffer
	end

	return Pointer
end

local function WriteUInt32(Parser: JSONStruct, Value: number)
	local Pointer = ReservePointer(Parser, 4)
	buffer.writeu32(Parser.Output, Pointer, Value)
end

local function WriteString(Parser: JSONStruct, Value: string)
	local Pointer = ReservePointer(Parser, string.len(Value))
	buffer.writestring(Parser.Output, Pointer, Value)
end

local function WriteRaw(Parser: JSONStruct, Value: buffer)
	local Pointer = ReservePointer(Parser, buffer.len(Value))
	buffer.copy(Parser.Output, Pointer, Value)
end

-- Encoding
local function FindStringEnd(Value: string): number
	local Length = string.len(Value)
	local Raw = buffer.create(Length + 16)
	buffer.writestring(Raw, 0, Value)

	local Pointer = 0

	while true do
		local V0 = buffer.readinteger(Raw, Pointer)
		local V1 = buffer.readinteger(Raw, Pointer + 8)

		local Q0, Q1, B0, B1 =
			integer.bxor(V0, 0x2222222222222222i),
			integer.bxor(V1, 0x2222222222222222i),
			integer.bxor(V0, 0x5C5C5C5C5C5C5C5Ci),
			integer.bxor(V1, 0x5C5C5C5C5C5C5C5Ci)

		local M = integer.bor(
			integer.band(integer.sub(Q0, 0x0101010101010101i), integer.band(integer.bnot(Q0), 0x8080808080808080i)),
			integer.band(integer.sub(Q1, 0x0101010101010101i), integer.band(integer.bnot(Q1), 0x8080808080808080i)),
			integer.band(integer.sub(B0, 0x0101010101010101i), integer.band(integer.bnot(B0), 0x8080808080808080i)),
			integer.band(integer.sub(B1, 0x0101010101010101i), integer.band(integer.bnot(B1), 0x8080808080808080i)),
			integer.band(integer.sub(V0, 0x2020202020202020i), integer.band(integer.bnot(V0), 0x8080808080808080i)),
			integer.band(integer.sub(V1, 0x2020202020202020i), integer.band(integer.bnot(V1), 0x8080808080808080i))
		)

		if M ~= 0i then
			break
		end
		
		Pointer += 16
	end

	local IsStringEnd = IS_STRING_END
	while buffer.readu8(IsStringEnd, buffer.readu8(Raw, Pointer)) == 0 do
		Pointer += 1
	end

	return Pointer
end

local function DecodeJSON(Parser: JSONStruct): any
	return nil
end

local function EncodeJSON(Parser: JSONStruct): string
	return ""
end

function JSON.Decode(Input: string | buffer): any
	if type(Input) ~= "string" and type(Input) ~= "buffer" then
		error(`Input must be a string or buffer, got {typeof(Input)}`, 2)
	end

	local Parser = CreateParser(Input)
	return DecodeJSON(Parser)
end

function JSON.Encode(Value: any): string
	local Parser = CreateParser(Value)
	return EncodeJSON(Parser)
end

table.freeze(JSON)
return JSON
