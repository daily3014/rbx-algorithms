--!strict
local Testing = require("../tests/")

Testing.Describe("Checksums", function()
	require("../tests/CRC32")
	require("../tests/Adler32")
end)

Testing.Describe("Encoding", function()
	require("../tests/Base64")
	require("../tests/JSON")
end)

Testing.Complete()