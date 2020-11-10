include("filesystem.lua")

util.GetBodygroupMask = util.GetBodygroupMask or function(ent)
	local mask = 0
	local offset = 1
	
	for index = 0, ent:GetNumBodyGroups() - 1 do
		local bg = ent:GetBodygroup(index)
		mask = mask + offset * bg
		offset = offset * ent:GetBodygroupCount(index)
	end

	return mask
end

local function sort(a, b)
	return a > b
end

function MESH2HASH(mesh, ent, phys_bone)
	local tbl = {mesh.material}
	for _, vert in ipairs(mesh.triangles) do
		for _, bw in ipairs(vert.weights) do
			if (ent:TranslateBoneToPhysBone(bw.bone) == phys_bone) then
				table.insert(tbl, tostring(vert.pos))
				break
			end
		end		
	end
	table.sort(tbl, sort)
	return util.CRC(table.concat(tbl))
end

function InsertMulti(out, ...)
	local tbl = {...}
	local val = tbl[#tbl]
	for i = 1, #tbl - 1 do
		local key = tbl[i]
		out[key] = out[key] or {}
		out = out[key]
	end
	table.insert(out, val)
end

function InsertMultiWithKey(out, ...)
	local tbl = {...}
	local key = tbl[#tbl-1]
	local val = tbl[#tbl]
	for i = 1, #tbl - 2 do
		local key = tbl[i]
		out[key] = out[key] or {}
		out = out[key]
	end
	out[key] = val
end

function SetMulti(out, ...)
	local tbl = {...}
	local val = tbl[#tbl]
	for i = 1, #tbl - 1 do
		local key = tbl[i]
		if (i == #tbl - 1 and !table.HasValue(out, val)) then
			out[key] = val
		else
			out[key] = out[key] or {}
			out = out[key]
		end		
	end
end

local MESH_CACHE = {}

local function GetModelMeshesCached(mdl, bg_mask)
	if (!MESH_CACHE[mdl] or !MESH_CACHE[mdl][bg_mask]) then
		SetMulti(MESH_CACHE, mdl, bg_mask, util.GetModelMeshes(mdl, 0, bg_mask) or {})
	end
	return MESH_CACHE[mdl][bg_mask]
end

local function IsConnected(mesh, ent, phys_bone)
	for _, vert in ipairs(mesh.verticies) do
		for _, bw in ipairs(vert.weights) do
			if (ent:TranslateBoneToPhysBone(bw.bone) == phys_bone) then
				return true
			end
		end
	end
end

local function GetPhysCount(ent)
	for phys_bone = 0, 23 do --MAX_RAGDOLL_PARTS = 23
		if (phys_bone != 0 and ent:TranslatePhysBoneToBone(phys_bone) == 0) then
			return phys_bone
		end
	end
	return -1
end

local MESH_HASH_LOOKUP = {}

local MDL_LOOKUP = {}

function GetSortedMeshHashTable(mdl)
	if MDL_LOOKUP[mdl] then
		return MDL_LOOKUP[mdl], MESH_HASH_LOOKUP
	end

	local ret = {}
	local temp = ClientsideRagdoll(mdl)
	temp:SetupBones()

	for phys_bone = 0, GetPhysCount(temp) - 1 do		
		for bg_num = 0, temp:GetNumBodyGroups() - 1 do
			--Loop backwards so we end up reset to 0
			for bg_val = temp:GetBodygroupCount(bg_num) - 1, 0, -1 do
				temp:SetBodygroup(bg_num, bg_val) 
				local bg_mask = util.GetBodygroupMask(temp)
				local meshes = GetModelMeshesCached(mdl, bg_mask)
				for _, mesh in pairs(meshes) do
					local hash = MESH2HASH(mesh, temp, phys_bone)
					if IsConnected(mesh, temp, phys_bone) then
						MESH_HASH_LOOKUP[hash] = MESH_HASH_LOOKUP[hash] or mesh
						InsertMulti(ret, phys_bone, bg_num, bg_val, hash)																
					end
					coroutine.yield()
				end
				coroutine.yield()
			end
			coroutine.yield()
		end
		coroutine.yield()
	end
	
	temp:Remove()

	MDL_LOOKUP[mdl] = ret

	return ret, MESH_HASH_LOOKUP
end