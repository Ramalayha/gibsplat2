local util_GetModelInfo = util.GetModelInfo
local util_KeyValuesToTable = util.KeyValuesToTable

local G_CONST_INFO = {}

function GetModelConstraintInfo(mdl)
	if G_CONST_INFO[mdl] then
		return G_CONST_INFO[mdl]
	end

	local CONST_INFO = {}

	local KV = util.GetModelInfo(mdl).KeyValues

	if KV then
		for str_part in KV:gmatch[[("?ragdollconstraint"?%s-{.-})]] do
			local part_info = util_KeyValuesToTable(str_part)
			
			table.insert(CONST_INFO, part_info)
		end
	end

	G_CONST_INFO[mdl] = CONST_INFO

	return CONST_INFO
end