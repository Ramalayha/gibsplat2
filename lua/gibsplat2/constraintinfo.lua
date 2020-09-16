local util_GetModelInfo = util.GetModelInfo
local util_KeyValuesToTable = util.KeyValuesToTable
local min = math.min
local max = math.max

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
			
			--Prevents constraints from freaking out
			part_info.xmin = min(part_info.xmin, -0.01)
			part_info.ymin = min(part_info.ymin, -0.01)
			part_info.zmin = min(part_info.zmin, -0.01)

			part_info.xmax = max(part_info.xmax, 0.01)
			part_info.ymax = max(part_info.ymax, 0.01)
			part_info.zmax = max(part_info.zmax, 0.01)

			table.insert(CONST_INFO, part_info)
		end
	end

	G_CONST_INFO[mdl] = CONST_INFO

	return CONST_INFO
end