include("filesystem.lua")

util.GetBodygroupMask = util.GetBodygroupMask or function(ent)
	local mask = 0
	local offset = 1
	
	local num_bodygroups = ent:GetNumBodyGroups()

	if !num_bodygroups then return 0 end

	for index = 0, num_bodygroups - 1 do
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

local function SafeYield()
	if coroutine.running() then
		coroutine.yield()
	end
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

--[[local function GetPhysCount(ent)
	for phys_bone = 0, 23 do --MAX_RAGDOLL_PARTS = 23
		if (phys_bone != 0 and ent:TranslatePhysBoneToBone(phys_bone) == 0) then
			return phys_bone
		end
	end
	return -1
end]]

local MESH_HASH_LOOKUP = {}

local MDL_LOOKUP = {}

function GetSortedMeshHashTable(mdl)
	if MDL_LOOKUP[mdl] then
		return MDL_LOOKUP[mdl], MESH_HASH_LOOKUP
	end

	local ret = {}
	local temp = ClientsideRagdoll(mdl)
	temp:SetupBones()

	for phys_bone = 0, temp:GetPhysicsObjectCount() - 1 do		
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
					SafeYield()
				end
				SafeYield()
			end
			SafeYield()
		end
		SafeYield()
	end
	
	temp:Remove()

	MDL_LOOKUP[mdl] = ret

	return ret, MESH_HASH_LOOKUP
end

local SKIN_CACHE = {}

function GetSkinGroups(mdl)
	if SKIN_CACHE[mdl] then
		return SKIN_CACHE[mdl]
	end

	local F = file.Open(mdl, "rb", "GAME")

	if !F then return end

	F:Seek(204)

	local tex_count = F:ReadLong()
	local tex_offset = F:ReadLong()

	local texdir_count = F:ReadLong()
	local texdir_offset = F:ReadLong()

	local skinref_count = F:ReadLong()
	local skinrfamily_count = F:ReadLong()
	local skinref_offset = F:ReadLong()

	F:Seek(tex_offset)

	local textures = {}

	for i = 1, tex_count do
		local tell = F:Tell()
		F:Seek(tell + F:ReadLong())
		textures[i] = F:ReadStringZ():lower():gsub("\\", "/")
		F:Seek(tell+64)
	end

	F:Seek(texdir_offset)

	local texture_dirs = {}

	for i = 1, texdir_count do
		local tell = F:Tell()
		F:Seek(F:ReadLong())
		texture_dirs[i] = F:ReadStringZ():lower():gsub("\\", "/")
		F:Seek(tell)
	end

	/*print("textures")
	PrintTable(textures)
	print("dirs")
	PrintTable(texture_dirs)

	print(skinref_count, skinrfamily_count, skinref_offset)*/

	F:Seek(skinref_offset)

	local skin_families = {}

	for i = 1, skinrfamily_count do
		local fam = {}
		for j = 1, skinref_count do
			local idx = F:ReadShort() + 1
			local tex_from = textures[j]
			local tex_too = textures[idx]
			
			for _, dir in ipairs(texture_dirs) do
				local name = dir..tex_from
				if file.Exists("materials/"..name..".vmt", "GAME") then
					tex_from = name
				end
				local name = dir..tex_too
				if file.Exists("materials/"..name..".vmt", "GAME") then
					tex_too = name
				end
			end

			fam[tex_from] = Material(tex_too)
		end
		skin_families[i] = fam
	end

	/*print("skins")
	PrintTable(skin_families)*/

	F:Close()

	SKIN_CACHE[mdl] = skin_families

	return skin_families
end