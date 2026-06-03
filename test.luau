local IS_STRING_END = buffer.create(256) do
	for Index = 0, 0x1F do
		buffer.writeu8(IS_STRING_END, Index, 1)
	end
	buffer.writeu8(IS_STRING_END, 0x22, 1)
	buffer.writeu8(IS_STRING_END, 0x5C, 1)
end

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
			print(M)
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

print(FindStringEnd("Hello world\\aaaaaaaaaaaaaa"))