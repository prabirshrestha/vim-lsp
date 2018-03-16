--------------------------------------------------
--    LICENSE: MIT
--     Author: Cosson2017
--    Version: 0.1
-- CreateTime: 2018-03-19 14:10:29
-- LastUpdate: 2018-03-19 14:10:29
--       Desc: 
--------------------------------------------------

local module = {}

local function _readline(filename, line)
	if line < 1 then 
		return
	end

	file = io.open(filename, "r")
	for i = 1, line - 1, 1 do
		file:read()
	end
	local data = file:read()
	io.close(file)
	return data
end

local function _removePrefix(str, prefix)
	local slen = #str
	local plen = #prefix
	if slen <= plen then
		return str
	end

	return str:sub(plen + 1, slen)
end

function module.handle_loc_list(data, cwd)
	print(cwd)
	if #data == 0 then
		return
	end
	for k, it in pairs(data) do
		if it['filename'] ~= nil and it['lnum'] ~= nil then
			it['text'] = _readline(it['filename'], it['lnum'])
			it['filename'] = _removePrefix(it['filename'], cwd)
		end
	end
	return data
end

function module.test(data, cwd)
	print(data, cwd)
end

return module
