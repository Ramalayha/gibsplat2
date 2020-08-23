local body_types = util.KeyValuesToTable(file.Read("data/gs2/skeletons.txt", "GAME")).body_types

local CACHE = {}

function GetModelGender(mdl)
	if CACHE[mdl] then
		return CACHE[mdl]
	end

	mdl = mdl:lower()

	local str = file.Read(mdl, "GAME")
	if !str then
		return
	end

	str = str:lower()

	for body_type, list in pairs(body_types) do
		for _, find in pairs(list) do
			if str:find(find) then
				CACHE[mdl] = body_type
				return body_type
			end
		end
	end

	for model_include in str:gmatch("(models/.-%.mdl)") do
		if model_include != mdl then			
			local ret = GetModelGender(model_include)
			if ret then
				CACHE[mdl] = ret
				return ret
			end
		end
	end

	if CACHE[mdl] then
		return CACHE[mdl]
	end
end

--print(GetModelGender("models/breen.mdl"))