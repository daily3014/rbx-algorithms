--[=[
	Data format: JSON (RFC 8259)

	Decode accepts a string or buffer and returns the decoded value.
	JSON null is represented by the Json.Null sentinel.
	Encode serializes a Lua value into a JSON string. Tables with no
	keys, or with the first key returned by next being a number, are
	encoded as arrays; otherwise as objects.

	Return types:
		Decode(Source: string | buffer): any
		Encode(Value: any): string

	Example usage:
		local Value = JSON.Decode('{"foo":[1,2,3]}')
		local Text = JSON.Encode({ Foo = { 1, 2, 3 } })
--]=]

--!strict
--!optimize 2
--!native

local Null: any = setmetatable({}, { __tostring = function() return "null" end })

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

local SWAR_QUOTE = 0x2222222222222222i
local SWAR_BACKSLASH = 0x5C5C5C5C5C5C5C5Ci
local SWAR_CONTROL = 0x2020202020202020i
local SWAR_LO = 0x0101010101010101i
local SWAR_HI = 0x8080808080808080i
local SWAR_ZERO = 0i

local HEX_DIGIT = buffer.create(256) do
	for Index = 0, 255 do
		buffer.writeu8(HEX_DIGIT, Index, 255)
	end
	for Index = 0, 9 do
		buffer.writeu8(HEX_DIGIT, 0x30 + Index, Index)
	end
	for Index = 0, 5 do
		buffer.writeu8(HEX_DIGIT, 0x41 + Index, 10 + Index)
		buffer.writeu8(HEX_DIGIT, 0x61 + Index, 10 + Index)
	end
end

local ESCAPE_STRINGS: { [number]: string } = {} do
	ESCAPE_STRINGS[0x22] = "\\\""
	ESCAPE_STRINGS[0x5C] = "\\\\"
	ESCAPE_STRINGS[0x08] = "\\b"
	ESCAPE_STRINGS[0x09] = "\\t"
	ESCAPE_STRINGS[0x0A] = "\\n"
	ESCAPE_STRINGS[0x0C] = "\\f"
	ESCAPE_STRINGS[0x0D] = "\\r"
	for Index = 0, 0x1F do
		if ESCAPE_STRINGS[Index] == nil then
			ESCAPE_STRINGS[Index] = string.format("\\u%04x", Index)
		end
	end
end

local Source: buffer = buffer.create(0)
local Position: number = 0
local Length: number = 0

local ParseValue: () -> any

local function ParseError(Message: string): never
	error(string.format("JSON parse error at offset %d: %s", Position, Message), 0)
end

local function SkipWhitespace()
	local Src = Source
	local Limit = Length
	local Table = IS_WHITESPACE
	while Position < Limit do
		if buffer.readu8(Table, buffer.readu8(Src, Position)) == 0 then
			return
		end
		Position += 1
	end
end

local function DecodeHex4(): number
	if Position + 4 > Length then
		ParseError("incomplete \\u escape")
	end
	local Src = Source
	local Hex = HEX_DIGIT
	local Digit0 = buffer.readu8(Hex, buffer.readu8(Src, Position))
	local Digit1 = buffer.readu8(Hex, buffer.readu8(Src, Position + 1))
	local Digit2 = buffer.readu8(Hex, buffer.readu8(Src, Position + 2))
	local Digit3 = buffer.readu8(Hex, buffer.readu8(Src, Position + 3))
	if bit32.bor(Digit0, Digit1, Digit2, Digit3) > 15 then
		ParseError("invalid hex digit in \\u escape")
	end
	Position += 4
	return Digit0 * 4096 + Digit1 * 256 + Digit2 * 16 + Digit3
end

local function WriteCodepointUtf8(Out: buffer, Offset: number, Codepoint: number): number
	if Codepoint < 0x80 then
		buffer.writeu8(Out, Offset, Codepoint)
		return 1
	elseif Codepoint < 0x800 then
		buffer.writeu8(Out, Offset, 0xC0 + bit32.rshift(Codepoint, 6))
		buffer.writeu8(Out, Offset + 1, 0x80 + bit32.band(Codepoint, 0x3F))
		return 2
	elseif Codepoint < 0x10000 then
		buffer.writeu8(Out, Offset, 0xE0 + bit32.rshift(Codepoint, 12))
		buffer.writeu8(Out, Offset + 1, 0x80 + bit32.band(bit32.rshift(Codepoint, 6), 0x3F))
		buffer.writeu8(Out, Offset + 2, 0x80 + bit32.band(Codepoint, 0x3F))
		return 3
	else
		buffer.writeu8(Out, Offset, 0xF0 + bit32.rshift(Codepoint, 18))
		buffer.writeu8(Out, Offset + 1, 0x80 + bit32.band(bit32.rshift(Codepoint, 12), 0x3F))
		buffer.writeu8(Out, Offset + 2, 0x80 + bit32.band(bit32.rshift(Codepoint, 6), 0x3F))
		buffer.writeu8(Out, Offset + 3, 0x80 + bit32.band(Codepoint, 0x3F))
		return 4
	end
end

local function ParseString(): string
	local Src = Source
	local Limit = Length
	local Cursor = Position + 1
	local Start = Cursor
	local ByteTable = IS_STRING_END

	while true do
		local V0 = buffer.readinteger(Src, Cursor)
		local V1 = buffer.readinteger(Src, Cursor + 8)
		local Q0 = integer.bxor(V0, SWAR_QUOTE)
		local Q1 = integer.bxor(V1, SWAR_QUOTE)
		local B0 = integer.bxor(V0, SWAR_BACKSLASH)
		local B1 = integer.bxor(V1, SWAR_BACKSLASH)
		local M = integer.bor(
			integer.band(integer.sub(Q0, SWAR_LO), integer.band(integer.bnot(Q0), SWAR_HI)),
			integer.band(integer.sub(Q1, SWAR_LO), integer.band(integer.bnot(Q1), SWAR_HI)),
			integer.band(integer.sub(B0, SWAR_LO), integer.band(integer.bnot(B0), SWAR_HI)),
			integer.band(integer.sub(B1, SWAR_LO), integer.band(integer.bnot(B1), SWAR_HI)),
			integer.band(integer.sub(V0, SWAR_CONTROL), integer.band(integer.bnot(V0), SWAR_HI)),
			integer.band(integer.sub(V1, SWAR_CONTROL), integer.band(integer.bnot(V1), SWAR_HI))
		)
		if M ~= SWAR_ZERO then
			break
		end
		Cursor += 16
	end
	
	while buffer.readu8(ByteTable, buffer.readu8(Src, Cursor)) == 0 do
		Cursor += 1
	end

	if Cursor >= Limit then
		Position = Cursor
		ParseError("unterminated string")
	end

	local Terminator = buffer.readu8(Src, Cursor)
	if Terminator == 0x22 then
		Position = Cursor + 1
		return buffer.readstring(Src, Start, Cursor - Start)
	elseif Terminator ~= 0x5C then
		Position = Cursor
		ParseError("invalid control character in string")
	end

	local InitialChunk = Cursor - Start
	local Capacity = InitialChunk * 2 + 16
	local Output = buffer.create(Capacity)
	local OutPos = InitialChunk
	if InitialChunk > 0 then
		buffer.copy(Output, 0, Src, Start, InitialChunk)
	end
	Position = Cursor

	while true do
		local Byte = buffer.readu8(Src, Position)
		if Byte == 0x22 then
			Position += 1
			return buffer.readstring(Output, 0, OutPos)
		elseif Byte == 0x5C then
			if Position + 1 >= Limit then
				ParseError("truncated escape")
			end
			local Escape = buffer.readu8(Src, Position + 1)
			Position += 2
			if OutPos + 4 > Capacity then
				while Capacity < OutPos + 4 do
					Capacity *= 2
				end
				local Grown = buffer.create(Capacity)
				buffer.copy(Grown, 0, Output, 0, OutPos)
				Output = Grown
			end
			if Escape == 0x22 then buffer.writeu8(Output, OutPos, 0x22); OutPos += 1
			elseif Escape == 0x5C then buffer.writeu8(Output, OutPos, 0x5C); OutPos += 1
			elseif Escape == 0x2F then buffer.writeu8(Output, OutPos, 0x2F); OutPos += 1
			elseif Escape == 0x62 then buffer.writeu8(Output, OutPos, 0x08); OutPos += 1
			elseif Escape == 0x66 then buffer.writeu8(Output, OutPos, 0x0C); OutPos += 1
			elseif Escape == 0x6E then buffer.writeu8(Output, OutPos, 0x0A); OutPos += 1
			elseif Escape == 0x72 then buffer.writeu8(Output, OutPos, 0x0D); OutPos += 1
			elseif Escape == 0x74 then buffer.writeu8(Output, OutPos, 0x09); OutPos += 1
			elseif Escape == 0x75 then
				local Codepoint = DecodeHex4()
				if Codepoint >= 0xD800 and Codepoint <= 0xDBFF then
					if Position + 1 >= Limit
						or buffer.readu8(Src, Position) ~= 0x5C
						or buffer.readu8(Src, Position + 1) ~= 0x75 then
						ParseError("expected low surrogate")
					end
					Position += 2
					local Low = DecodeHex4()
					if Low < 0xDC00 or Low > 0xDFFF then
						ParseError("invalid low surrogate")
					end
					Codepoint = 0x10000 + (Codepoint - 0xD800) * 0x400 + (Low - 0xDC00)
				elseif Codepoint >= 0xDC00 and Codepoint <= 0xDFFF then
					ParseError("unexpected low surrogate")
				end
				OutPos += WriteCodepointUtf8(Output, OutPos, Codepoint)
			else
				ParseError("invalid escape sequence")
			end
		elseif Byte < 0x20 then
			ParseError("invalid control character in string")
		else
			local ChunkStart = Position
			local C = Position
			while true do
				local V0 = buffer.readinteger(Src, C)
				local V1 = buffer.readinteger(Src, C + 8)
				local Q0 = integer.bxor(V0, SWAR_QUOTE)
				local Q1 = integer.bxor(V1, SWAR_QUOTE)
				local B0 = integer.bxor(V0, SWAR_BACKSLASH)
				local B1 = integer.bxor(V1, SWAR_BACKSLASH)
				local M = integer.bor(
					integer.band(integer.sub(Q0, SWAR_LO), integer.band(integer.bnot(Q0), SWAR_HI)),
					integer.band(integer.sub(Q1, SWAR_LO), integer.band(integer.bnot(Q1), SWAR_HI)),
					integer.band(integer.sub(B0, SWAR_LO), integer.band(integer.bnot(B0), SWAR_HI)),
					integer.band(integer.sub(B1, SWAR_LO), integer.band(integer.bnot(B1), SWAR_HI)),
					integer.band(integer.sub(V0, SWAR_CONTROL), integer.band(integer.bnot(V0), SWAR_HI)),
					integer.band(integer.sub(V1, SWAR_CONTROL), integer.band(integer.bnot(V1), SWAR_HI))
				)
				if M ~= SWAR_ZERO then
					break
				end
				C += 16
			end
			while buffer.readu8(ByteTable, buffer.readu8(Src, C)) == 0 do
				C += 1
			end
			if C >= Limit then
				Position = C
				ParseError("unterminated string")
			end
			Position = C
			local ChunkLen = C - ChunkStart
			if ChunkLen > 0 then
				if OutPos + ChunkLen > Capacity then
					while Capacity < OutPos + ChunkLen do
						Capacity *= 2
					end
					local Grown = buffer.create(Capacity)
					buffer.copy(Grown, 0, Output, 0, OutPos)
					Output = Grown
				end
				buffer.copy(Output, OutPos, Src, ChunkStart, ChunkLen)
				OutPos += ChunkLen
			end
		end
	end
end

local function ParseNumber(): number
	local Start = Position
	local Src = Source
	local Limit = Length
	local Sign = 1
	local Byte = buffer.readu8(Src, Position)
	if Byte == 0x2D then
		Sign = -1
		Position += 1
		if Position >= Limit then
			ParseError("expected digit after minus")
		end
		Byte = buffer.readu8(Src, Position)
	end

	local IntDigits = 0
	local IntValue = 0
	if Byte == 0x30 then
		Position += 1
		IntDigits = 1
	elseif Byte >= 0x31 and Byte <= 0x39 then
		IntValue = Byte - 0x30
		IntDigits = 1
		Position += 1
		while Position < Limit do
			local Digit = buffer.readu8(Src, Position)
			if Digit < 0x30 or Digit > 0x39 then break end
			IntValue = IntValue * 10 + (Digit - 0x30)
			IntDigits += 1
			Position += 1
		end
	else
		ParseError("invalid number")
	end

	local Next = if Position < Limit then buffer.readu8(Src, Position) else 0
	if Next ~= 0x2E and Next ~= 0x65 and Next ~= 0x45 then
		if IntDigits <= 15 then
			return Sign * IntValue
		end
		local Result = tonumber(buffer.readstring(Src, Start, Position - Start))
		if Result == nil then
			ParseError("invalid number")
		end
		return Result :: number
	end

	if Next == 0x2E then
		Position += 1
		local AfterDot = Position
		while Position < Limit do
			local Digit = buffer.readu8(Src, Position)
			if Digit < 0x30 or Digit > 0x39 then break end
			Position += 1
		end
		if Position == AfterDot then
			ParseError("expected digit after decimal point")
		end
		Next = if Position < Limit then buffer.readu8(Src, Position) else 0
	end

	if Next == 0x65 or Next == 0x45 then
		Position += 1
		if Position >= Limit then
			ParseError("expected digit in exponent")
		end
		local SignByte = buffer.readu8(Src, Position)
		if SignByte == 0x2B or SignByte == 0x2D then
			Position += 1
		end
		local AfterE = Position
		while Position < Limit do
			local Digit = buffer.readu8(Src, Position)
			if Digit < 0x30 or Digit > 0x39 then break end
			Position += 1
		end
		if Position == AfterE then
			ParseError("expected digit in exponent")
		end
	end

	local Result = tonumber(buffer.readstring(Src, Start, Position - Start))
	if Result == nil then
		ParseError("invalid number")
	end
	return Result :: number
end

local function ExpectLiteral(Word32: number, Length3: number, Description: string)
	if Position + 4 > Length then
		ParseError("unexpected end of input while parsing " .. Description)
	end
	local Read = buffer.readu32(Source, Position)
	if Length3 == 4 then
		if Read ~= Word32 then
			ParseError("invalid literal, expected " .. Description)
		end
		Position += 4
	else
		if Read ~= Word32 then
			ParseError("invalid literal, expected " .. Description)
		end
		if Position + 5 > Length or buffer.readu8(Source, Position + 4) ~= 0x65 then
			ParseError("invalid literal, expected " .. Description)
		end
		Position += 5
	end
end

local function ParseObject(): { [string]: any }
	Position += 1
	SkipWhitespace()
	local Result: { [string]: any } = {}
	if Position < Length and buffer.readu8(Source, Position) == 0x7D then
		Position += 1
		return Result
	end
	while true do
		SkipWhitespace()
		if Position >= Length or buffer.readu8(Source, Position) ~= 0x22 then
			ParseError("expected string key")
		end
		local Key = ParseString()
		SkipWhitespace()
		if Position >= Length or buffer.readu8(Source, Position) ~= 0x3A then
			ParseError("expected ':' after key")
		end
		Position += 1
		Result[Key] = ParseValue()
		SkipWhitespace()
		if Position >= Length then
			ParseError("unterminated object")
		end
		local Byte = buffer.readu8(Source, Position)
		if Byte == 0x2C then
			Position += 1
		elseif Byte == 0x7D then
			Position += 1
			return Result
		else
			ParseError("expected ',' or '}'")
		end
	end
end

local function ParseArray(): { any }
	Position += 1
	SkipWhitespace()
	local Result: { any } = {}
	if Position < Length and buffer.readu8(Source, Position) == 0x5D then
		Position += 1
		return Result
	end
	local Count = 0
	while true do
		Count += 1
		Result[Count] = ParseValue()
		SkipWhitespace()
		if Position >= Length then
			ParseError("unterminated array")
		end
		local Byte = buffer.readu8(Source, Position)
		if Byte == 0x2C then
			Position += 1
		elseif Byte == 0x5D then
			Position += 1
			return Result
		else
			ParseError("expected ',' or ']'")
		end
	end
end

function ParseValue(): any
	SkipWhitespace()
	if Position >= Length then
		ParseError("unexpected end of input")
	end
	local Byte = buffer.readu8(Source, Position)
	if Byte == 0x22 then
		return ParseString()
	elseif Byte == 0x7B then
		return ParseObject()
	elseif Byte == 0x5B then
		return ParseArray()
	elseif Byte == 0x74 then
		ExpectLiteral(0x65757274, 4, "true")
		return true
	elseif Byte == 0x66 then
		ExpectLiteral(0x736C6166, 5, "false")
		return false
	elseif Byte == 0x6E then
		ExpectLiteral(0x6C6C756E, 4, "null")
		return Null
	elseif Byte == 0x2D or (Byte >= 0x30 and Byte <= 0x39) then
		return ParseNumber()
	else
		ParseError("unexpected character")
	end
	return nil
end

local function Decode(Input: string | buffer): any
	if type(Input) == "string" then
		local Len = #Input
		Source = buffer.create(Len + 16)
		buffer.writestring(Source, 0, Input)
		Length = Len
	else
		local InBuf = Input :: buffer
		local Len = buffer.len(InBuf)
		Source = buffer.create(Len + 16)
		buffer.copy(Source, 0, InBuf, 0, Len)
		Length = Len
	end
	Position = 0
	local Result = ParseValue()
	SkipWhitespace()
	if Position < Length then
		ParseError("trailing data after JSON value")
	end
	return Result
end

local Output: buffer = buffer.create(256)
local OutPosition: number = 0
local OutCapacity: number = 256

local Scratch: buffer = buffer.create(4096)

local EncodeValue: (Value: any) -> ()

local function Grow(Needed: number)
	local Required = OutPosition + Needed
	if Required <= OutCapacity then
		return
	end
	local NewCapacity = OutCapacity * 2
	while NewCapacity < Required do
		NewCapacity *= 2
	end
	local Replacement = buffer.create(NewCapacity)
	buffer.copy(Replacement, 0, Output, 0, OutPosition)
	Output = Replacement
	OutCapacity = NewCapacity
end

local function EncodeString(Value: string)
	local Len = #Value
	local Required = OutPosition + Len + 2
	if Required > OutCapacity then
		Grow(Len + 2)
	end

	if Len > buffer.len(Scratch) then
		local NewCap = buffer.len(Scratch)
		while NewCap < Len do
			NewCap *= 2
		end
		Scratch = buffer.create(NewCap)
	end
	local Src = Scratch
	buffer.writestring(Src, 0, Value)

	local Out = Output
	local Pos = OutPosition
	buffer.writeu8(Out, Pos, 0x22)
	Pos += 1

	local EscTable = NEEDS_ESCAPE
	local Cursor = 0
	local UnrollStop = Len - 16

	while Cursor <= UnrollStop do
		local V0 = buffer.readinteger(Src, Cursor)
		local V1 = buffer.readinteger(Src, Cursor + 8)
		local Q0 = integer.bxor(V0, SWAR_QUOTE)
		local Q1 = integer.bxor(V1, SWAR_QUOTE)
		local B0 = integer.bxor(V0, SWAR_BACKSLASH)
		local B1 = integer.bxor(V1, SWAR_BACKSLASH)
		local M = integer.bor(
			integer.band(integer.sub(Q0, SWAR_LO), integer.band(integer.bnot(Q0), SWAR_HI)),
			integer.band(integer.sub(Q1, SWAR_LO), integer.band(integer.bnot(Q1), SWAR_HI)),
			integer.band(integer.sub(B0, SWAR_LO), integer.band(integer.bnot(B0), SWAR_HI)),
			integer.band(integer.sub(B1, SWAR_LO), integer.band(integer.bnot(B1), SWAR_HI)),
			integer.band(integer.sub(V0, SWAR_CONTROL), integer.band(integer.bnot(V0), SWAR_HI)),
			integer.band(integer.sub(V1, SWAR_CONTROL), integer.band(integer.bnot(V1), SWAR_HI))
		)
		if M ~= SWAR_ZERO then
			break
		end
		Cursor += 16
	end

	while Cursor < Len do
		if buffer.readu8(EscTable, buffer.readu8(Src, Cursor)) ~= 0 then
			break
		end
		Cursor += 1
	end

	if Cursor >= Len then
		buffer.copy(Out, Pos, Src, 0, Len)
		Pos += Len
		buffer.writeu8(Out, Pos, 0x22)
		OutPosition = Pos + 1
		return
	end

	if Cursor > 0 then
		buffer.copy(Out, Pos, Src, 0, Cursor)
		Pos += Cursor
	end
	local ChunkStart = Cursor

	while Cursor < Len do
		local Byte = buffer.readu8(Src, Cursor)
		if buffer.readu8(EscTable, Byte) ~= 0 then
			if Cursor > ChunkStart then
				local ChunkLen = Cursor - ChunkStart
				OutPosition = Pos
				if Pos + ChunkLen + 6 > OutCapacity then
					Grow(ChunkLen + 6)
					Out = Output
				end
				buffer.copy(Out, Pos, Src, ChunkStart, ChunkLen)
				Pos += ChunkLen
			end
			local EscapeStr = ESCAPE_STRINGS[Byte]
			local EscapeLen = #EscapeStr
			OutPosition = Pos
			if Pos + EscapeLen > OutCapacity then
				Grow(EscapeLen)
				Out = Output
			end
			buffer.writestring(Out, Pos, EscapeStr)
			Pos += EscapeLen
			Cursor += 1
			ChunkStart = Cursor

			local UnrollStop2 = Len - 16
			while Cursor <= UnrollStop2 do
				local V0 = buffer.readinteger(Src, Cursor)
				local V1 = buffer.readinteger(Src, Cursor + 8)
				local Q0 = integer.bxor(V0, SWAR_QUOTE)
				local Q1 = integer.bxor(V1, SWAR_QUOTE)
				local B0 = integer.bxor(V0, SWAR_BACKSLASH)
				local B1 = integer.bxor(V1, SWAR_BACKSLASH)
				local M = integer.bor(
					integer.band(integer.sub(Q0, SWAR_LO), integer.band(integer.bnot(Q0), SWAR_HI)),
					integer.band(integer.sub(Q1, SWAR_LO), integer.band(integer.bnot(Q1), SWAR_HI)),
					integer.band(integer.sub(B0, SWAR_LO), integer.band(integer.bnot(B0), SWAR_HI)),
					integer.band(integer.sub(B1, SWAR_LO), integer.band(integer.bnot(B1), SWAR_HI)),
					integer.band(integer.sub(V0, SWAR_CONTROL), integer.band(integer.bnot(V0), SWAR_HI)),
					integer.band(integer.sub(V1, SWAR_CONTROL), integer.band(integer.bnot(V1), SWAR_HI))
				)
				if M ~= SWAR_ZERO then
					break
				end
				Cursor += 16
			end
		else
			Cursor += 1
		end
	end

	if Cursor > ChunkStart then
		local ChunkLen = Cursor - ChunkStart
		OutPosition = Pos
		if Pos + ChunkLen + 1 > OutCapacity then
			Grow(ChunkLen + 1)
			Out = Output
		end
		buffer.copy(Out, Pos, Src, ChunkStart, ChunkLen)
		Pos += ChunkLen
	end

	OutPosition = Pos
	if Pos >= OutCapacity then
		Grow(1)
		Out = Output
	end
	buffer.writeu8(Out, Pos, 0x22)
	OutPosition = Pos + 1
end

local function EncodeArray(Value: { any })
	if OutPosition >= OutCapacity then Grow(1) end
	buffer.writeu8(Output, OutPosition, 0x5B)
	OutPosition += 1

	local Count = #Value
	for Index = 1, Count do
		if Index > 1 then
			if OutPosition >= OutCapacity then Grow(1) end
			buffer.writeu8(Output, OutPosition, 0x2C)
			OutPosition += 1
		end
		EncodeValue(Value[Index])
	end

	if OutPosition >= OutCapacity then Grow(1) end
	buffer.writeu8(Output, OutPosition, 0x5D)
	OutPosition += 1
end

local function EncodeObject(Value: { [any]: any })
	if OutPosition >= OutCapacity then Grow(1) end
	buffer.writeu8(Output, OutPosition, 0x7B)
	OutPosition += 1

	local First = true
	for Key, Field in pairs(Value) do
		if type(Key) ~= "string" then
			error("JSON object keys must be strings", 0)
		end
		if not First then
			if OutPosition >= OutCapacity then Grow(1) end
			buffer.writeu8(Output, OutPosition, 0x2C)
			OutPosition += 1
		end
		First = false
		EncodeString(Key :: string)
		if OutPosition >= OutCapacity then Grow(1) end
		buffer.writeu8(Output, OutPosition, 0x3A)
		OutPosition += 1
		EncodeValue(Field)
	end

	if OutPosition >= OutCapacity then Grow(1) end
	buffer.writeu8(Output, OutPosition, 0x7D)
	OutPosition += 1
end

function EncodeValue(Value: any)
	local Kind = type(Value)
	if Kind == "string" then
		EncodeString(Value)
	elseif Kind == "number" then
		if Value ~= Value or Value == math.huge or Value == -math.huge then
			error("JSON does not allow NaN or Infinity", 0)
		end
		local Str = tostring(Value)
		local L = #Str
		if OutPosition + L > OutCapacity then Grow(L) end
		buffer.writestring(Output, OutPosition, Str)
		OutPosition += L
	elseif Kind == "table" then
		if Value == Null then
			if OutPosition + 4 > OutCapacity then Grow(4) end
			buffer.writeu32(Output, OutPosition, 0x6C6C756E)
			OutPosition += 4
			return
		end
		local FirstKey = next(Value)
		if FirstKey == nil then
			if OutPosition + 2 > OutCapacity then Grow(2) end
			buffer.writeu16(Output, OutPosition, 0x5D5B)
			OutPosition += 2
		elseif type(FirstKey) == "number" then
			EncodeArray(Value)
		else
			EncodeObject(Value)
		end
	elseif Kind == "boolean" then
		if Value then
			if OutPosition + 4 > OutCapacity then Grow(4) end
			buffer.writeu32(Output, OutPosition, 0x65757274)
			OutPosition += 4
		else
			if OutPosition + 5 > OutCapacity then Grow(5) end
			buffer.writeu32(Output, OutPosition, 0x736C6166)
			buffer.writeu8(Output, OutPosition + 4, 0x65)
			OutPosition += 5
		end
	elseif Value == nil then
		if OutPosition + 4 > OutCapacity then Grow(4) end
		buffer.writeu32(Output, OutPosition, 0x6C6C756E)
		OutPosition += 4
	else
		error("cannot encode value of type " .. Kind, 0)
	end
end

local function Encode(Value: any): string
	OutPosition = 0
	EncodeValue(Value)
	return buffer.readstring(Output, 0, OutPosition)
end

return {
	Decode = Decode,
	Encode = Encode,
	Null = Null,
}
