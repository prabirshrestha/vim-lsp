--------------------------------------------------
--    LICENSE: MIT
--     Author: Cosson2017
--    Version: 0.1
-- CreateTime: 2018-03-19 14:10:29
-- LastUpdate: 2018-03-19 14:10:29
--       Desc: 
--------------------------------------------------

local module = {}

function module.readline(filename, line)
	if line < 1 then 
		return
	end

	file = io.open(filename, "r")
	for i = 1, line - 1, 1 do
		file:read()
	end
	return file:read()
end

return module
