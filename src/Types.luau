type Data = buffer | string

export type Checksums = {
	Adler32: (Message: Data) -> number,
	CRC32: (Message: Data) -> number
}

export type Encoding = {
	Base64: {
		Encode: (Input: Data) -> buffer,
		Decode: (Input: Data) -> buffer
	},

	Hexadecimal: {
		Encode: (Input: Data) -> string,
		Decode: (Input: Data) -> buffer
	},

	JSON: {
		Encode: (Value: any) -> string,
		Decode: (Input: Data) -> any
	}
}

export type Pathfinding = {

}

export type Groups = {
	Checksums: Checksums,
	Pathfinding: Pathfinding,
	Encoding: Encoding
}

return 0