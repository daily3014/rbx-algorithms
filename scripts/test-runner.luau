--!strict
local Testing = require("../tests/")

Testing.Describe("Checksums", function()
	require("../tests/CRC32")
	require("../tests/Adler32")
end)

Testing.Describe("Encoding", function()
	require("../tests/Base64")
end)

Testing.Complete()