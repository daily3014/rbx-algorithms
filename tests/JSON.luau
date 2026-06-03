--!strict
local Bridge = require("./Bridge")
local IsCLI = Bridge.IsCLI
local Testing = require("./")

type TestVector = {
	Description: string,
	Input: any,

	Expected: any,
	FilteredInput: any?,
}

type ErrorTestVector = {
	Description: string,
	Input: any,

	Message: string,
}


type Groups = {
	Errors: {ErrorTestVector},
	[string]: {TestVector},
}

--local Algorithm = if IsCLI then require("../src/Encoding/JSON") else require("../Encoding/JSON")
local Algorithm = require("../src/Encoding/JSON/old")

local function ValueMatches(Left: any, Right: any): boolean
	if type(Left) == "table" and type(Right) == "table" then
		if getmetatable(Right) ~= nil and getmetatable(Right) ~= getmetatable(Left) then
			return false
		end

		for Key, Value in Right do
			local LeftValue = Left[Key]

			if not LeftValue then
				return false
			end

			if type(Value) ~= type(LeftValue) then
				return false
			end

			if type(Value) == "table" and not ValueMatches(LeftValue, Value) then
				return false
			end

			if Value ~= LeftValue then
				return false
			end
		end

		return true
	end

	return Left == Right
end

local TestVectors: Groups = {
	Arrays = {
		{
			Description = "Arrays are encoded as JSON arrays",
			Input = {1, 2, 3},
			Expected = "[1,2,3]",
		},

		{
			Description = "Arrays can contain multiple types",
			Input = {1, "Hello World", Algorithm.Null},
			Expected = '[1,"Hello World",null]',
		},

		{
			Description = "Arrays ignore string keys",
			Input = {1, 2, 3, Foo = "Bar"},
			Expected = "[1,2,3]",
			FilteredInput = {1, 2, 3},
		},

		{
			Description = "Arrays ignore float keys",
			Input = {[1] = 1, [1.234] = 1.234},
			Expected = "[1]",
			FilteredInput = {[1] = 1},
		},

		{
			Description = "Arrays stop after first gap",
			Input = {[1] = 1, [3] = 3}, 
			Expected = "[1]",
			FilteredInput = {[1] = 1},
		}
	},

	Objects = {
		-- Ordering is finicky.

		{
			Description = "Objects are encoded as JSON objects",
			Input = {Foo = 1, Bar = 2, Baz = 3},
			Expected = '{"Baz":3,"Bar":2,"Foo":1}',
		},

		{
			Description = "Objects can contain multiple types",
			Input = {Foo = 1, Bar = "Hello World", Baz = Algorithm.Null},
			Expected = '{"Baz":null,"Bar":"Hello World","Foo":1}',
		},

		{
			Description = "Arrays are prioritized",
			Input = {Test = 1, Key = 2, Member = 3, "Hello World"},
			Expected = '["Hello World"]',
			FilteredInput = {"Hello World"},
		},

		{
			Description = "Negative indices are treated as keys",
			Input = {[-1] = 1},
			Expected = '{"-1":1}',
		},
	},

	Types = {
		{
			Description = "Empty tables are treated as objects",
			Input = {},
			Expected = "[]",
		},

		{
			Description = "Strings are wrapped in double quotes",
			Input = "Hello World",
			Expected = '"Hello World"',
		},

		{
			Description = "Numbers are encoded as-is",
			Input = 12345,
			Expected = "12345",
		},

		{
			Description = "Booleans (true) are encoded as-is",
			Input = true,
			Expected = "true",
		},

		{
			Description = "Booleans (false) are encoded as-is",
			Input = false,
			Expected = "false",
		},

		{
			Description = "Null sentinel value works",
			Input = Algorithm.Null,
			Expected = "null",
		},

		{
			Description = "Nil is interpreted as null",
			Input = nil,
			Expected = "null",
			FilteredInput = Algorithm.Null,
		}
	},

	Numbers = {
		{
			Description = "Special numbers aren't encoded (inf)",
			Input = math.huge,
			Expected = false,
		},

		{
			Description = "Special numbers aren't encoded (NaN)",
			Input = math.nan,
			Expected = false,
		},
	},

	Errors = {
		{
			Description = "Number with trailing dot",
			Input = "123.",
			Message = "expected digit after decimal point"
		},

		{
			Description = "Number with multiple dots",
			Input = "123.2.",
			Message = "trailing data after JSON value"
		},

		{
			Description = "Number with unfinished exponent",
			Input = "123e",
			Message = "expected digit in exponent"
		},

		{
			Description = "Number with unfinished negative exponent",
			Input = "123e-",
			Message = "expected digit in exponent"
		},

		{
			Description = "Number with unfinished positive exponent",
			Input = "123e+",
			Message = "expected digit in exponent"
		},

		{
			Description = "Number with trailing dot after exponent",
			Input = "123e1.",
			Message = "trailing data after JSON value"
		},

		{
			Description = "Number with trailing dot after negative exponent",
			Input = "123e-1.",
			Message = "trailing data after JSON value"
		},

		{
			Description = "Number with trailing dot after positive exponent",
			Input = "123e+1.",
			Message = "trailing data after JSON value"
		},

		{
			Description = "Number with double minus",
			Input = "--123",
			Message = "invalid number"
		},

		{
			Description = "Number with plus sign",
			Input = "+123",
			Message = "unexpected character"
		},

		{
			Description = "Unfinished string",
			Input = '"Hello',
			Message = "unterminated string"
		},

		{
			Description = "Escaping closing quote",
			Input = '"Hello\\"',
			Message = "invalid control character in string"
		},

		{
			Description = "Literals",
			Input = 'hello',
			Message = "unexpected character"
		},
	}
}

local function DoTest(Test: TestVector)
	Testing.Test(Test.Description, function()
		local Success, Result = pcall(Algorithm.Encode, Test.Input)
		if type(Test.Expected) == "boolean" then
			return Testing.Expect(Success).ToBe(Test.Expected)
		end

		Testing.Expect(Result).ToBe(Test.Expected)

		local DecodeSuccess, DecodeResult = pcall(Algorithm.Decode, Result)
		Testing.Expect(DecodeSuccess).ToBeTruthy()

		local ExpectedValue = if Test.FilteredInput ~= nil
			then Test.FilteredInput
			else Test.Input
			
		Testing.Expect(ValueMatches(DecodeResult, ExpectedValue)).ToBeTruthy()
	end)
end

local function DoErrorTest(Test: ErrorTestVector)
	Testing.Test(Test.Description, function()
		local DecodeSuccess, DecodeResult = pcall(Algorithm.Decode, Test.Input)

		Testing.Expect(DecodeSuccess).ToBeFalsy()
		Testing.Expect(DecodeResult).ToContain(Test.Message)
	end)
end

local function TestGroup(Name: string, Group: {TestVector})
	Testing.Describe(Name, function()
		for _, Test in Group do
			if Name == "Errors" then
				DoErrorTest(Test :: ErrorTestVector)
				continue
			end

			DoTest(Test)
		end
	end)
end

Testing.Describe("JSON", function()
	for Name, Group in TestVectors do
		TestGroup(Name, Group)
	end
end)

return 0