include("clipmesh.lua")
include("filesystem.lua")

local SafeRemoveEntity = SafeRemoveEntity
local WorldToLocal = WorldToLocal
local ipairs = ipairs
local ClientsideRagdoll = ClientsideRagdoll
local pairs = pairs
local VoronoiSplit = VoronoiSplit
local LocalToWorld = LocalToWorld
local IsValid = IsValid

local math_max = math.max
local math_min = math.min
local math_randomseed = math.randomseed
local math_floor = math.floor
local math_random = math.random
local math_Rand = math.Rand

local table_Empty = table.Empty
local table_remove = table.remove
local table_Count = table.Count
local table_Add = table.Add
local table_insert = table.insert
local table_KeyFromValue = table.KeyFromValue

local ang_zero = Angle(0, 0, 0)

local NUM_PARTS = 10

local MDL_INDEX = {}

local PHYS_GIB_CACHE = {}

local GIB_VERSION = 3

local HOOK_NAME = "GibSplat2"

local THREADS = {}

function GetPhysGibMeshes(mdl, phys_bone, norec)
	if (MDL_INDEX[mdl] and MDL_INDEX[mdl][phys_bone]) then
		return MDL_INDEX[mdl][phys_bone]
	end

	if (THREADS[mdl] and coroutine.running() != THREADS[mdl]) then
		while (coroutine.status(THREADS[mdl]) != "dead") do 
			coroutine.resume(THREADS[mdl]) --force it to finish
		end
		THREADS[mdl] = nil
	end
	
	MDL_INDEX[mdl] = MDL_INDEX[mdl] or {}

	local mdl_info = GS2ReadModelData(mdl)

	if (mdl_info and mdl_info.gib_data) then
		for phys_bone, hash in pairs(mdl_info.gib_data) do
			if !PHYS_GIB_CACHE[hash] then				
				GS2ReadGibData(hash, PHYS_GIB_CACHE)
			end
			MDL_INDEX[mdl][phys_bone] = PHYS_GIB_CACHE[hash]
		end
		if MDL_INDEX[mdl][phys_bone] then
			THREADS[mdl] = nil
			return MDL_INDEX[mdl][phys_bone]
		end
	end

	math_randomseed(util.CRC(mdl) + phys_bone)

	local temp
	if SERVER then
		temp = ents.Create("prop_ragdoll")
		temp:SetModel(mdl)
		temp:Spawn()
	else
		temp = ClientsideRagdoll(mdl)
		temp:SetupBones()
	end
	
	if !IsValid(temp) then
		return {}
	end

	local vertex_tbl = {}

	local phys = temp:GetPhysicsObjectNum(phys_bone)

	if !IsValid(phys) then
		temp:Remove()
		return {}
	end

	local convexes = phys:GetMeshConvexes()

	for _, convex in ipairs(convexes) do
		for _, vert in ipairs(convex) do
			table.insert(vertex_tbl, VEC2STR(vert.pos))
		end
	end
	
	local hash = TBL2HASH(vertex_tbl)

	local phys_count = temp:GetPhysicsObjectCount()

	temp:Remove()

	local points = {}

	for _, convex in pairs(convexes) do
		for _, vert in pairs(convex) do
			table_insert(points, vert.pos)
		end
	end

	temp = SERVER and ents.Create("prop_physics") or ents.CreateClientProp()

	temp:PhysicsInitConvex(points)

	local phys = temp:GetPhysicsObject()

	if !IsValid(phys) then
		temp:Remove()
		return {}
	end

	local convex = phys:GetMeshConvexes()[1]

	temp:Remove()

	local min, max = phys:GetAABB()
	local center = (min + max) / 2
	local size = max - min

	local points = {}

	for i = 1, NUM_PARTS do
		local point = Vector()
		point.x = math_Rand(min.x, max.x)
		point.y = math_Rand(min.y, max.y)
		point.z = math_Rand(min.z, max.z)

		point = center + (point - center) * 0.9

		for vert_index = 1, #convex - 2, 3 do
			local v1 = convex[vert_index]
			local v2 = convex[vert_index + 1]
			local v3 = convex[vert_index + 2]

			local p1 = v1.pos
			local p2 = v2.pos
			local p3 = v3.pos

			local n = (p3 - p1):Cross(p2 - p1)
			n:Normalize()

			local d = n:Dot(p1) * 0.9

			local d2 = n:Dot(point)

			if (d2 > d) then
				point:Sub(n * (d2 - d))
			end
		end
		
		table_insert(points, point)		
	end

	local meshes = VoronoiSplit(convex, points)

	for key, mesh in pairs(meshes) do
		mesh.vertex_buffer = {}
		mesh.index_buffer = {}
		for _, vert in ipairs(mesh.triangles) do
			table.insert(mesh.index_buffer, table.KeyFromValue(mesh.vertex_buffer, vert.pos) or table.insert(mesh.vertex_buffer, vert.pos))
		end	
	end

	if CLIENT then
		for key, mesh in pairs(meshes) do
			local center = mesh.center
			for _, vert in ipairs(mesh.triangles) do
				vert.normal = (vert.pos - center):GetNormal()
				vert.u = vert.pos.x / size.x + vert.pos.z / size.z
				vert.v = vert.pos.y / size.y + vert.pos.z / size.z
			end
			local M = Mesh()
			M:BuildFromTriangles(mesh.triangles)
			mesh.mesh = M
		end
	end
	
	meshes.hash = hash

	PHYS_GIB_CACHE[hash] = meshes
			
	MDL_INDEX[mdl][phys_bone] = PHYS_GIB_CACHE[hash]

	if !norec then		
		for phys_bone2 = 0, phys_count - 1 do
			if (phys_bone2 != phys_bone) then
				if coroutine.running() then
					coroutine.yield()
				end				
				GetPhysGibMeshes(mdl, phys_bone2, true)
			end
		end		
	end

	GS2WriteGibData(hash, PHYS_GIB_CACHE[hash])

	if (!norec and !mdl_info) then
		GS2LinkModelInfo(mdl, "gib_data", MDL_INDEX[mdl])
	end

	return meshes
end

game.AddDecal("BloodSmall", {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
})

game.AddDecal("YellowBloodSmall", {
	"decals/alienflesh/shot1",
	"decals/alienflesh/shot2",
	"decals/alienflesh/shot3",
	"decals/alienflesh/shot4",
	"decals/alienflesh/shot5"
})

local text = file.Read("materials/gibsplat2/skeletons.vmt", "GAME")

local body_types = util.KeyValuesToTable(text or "").body_types or {}

local MDLTYPE_CACHE = {}

function GS2GetBodyType(mdl)
	if MDLTYPE_CACHE[mdl] then
		return MDLTYPE_CACHE[mdl]
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
				MDLTYPE_CACHE[mdl] = body_type
				return body_type
			end
		end
	end

	for model_include in str:gmatch("(models/.-%.mdl)") do
		if model_include != mdl then			
			local ret = GS2GetBodyType(model_include)
			if ret then
				MDLTYPE_CACHE[mdl] = ret
				return ret
			end
		end
	end

	return MDLTYPE_CACHE[mdl] or ""
end

local gib_factor 		= CreateConVar("gs2_gib_factor", 0.3)
local gib_merge_chance 	= CreateConVar("gs2_gib_merge_chance", 0.7)
local gib_custom		= CreateConVar("gs2_gib_custom", 1)
local max_gibs			= CreateConVar("gs2_max_gibs", 128)

local generate_all		= CreateConVar("gs2_gib_generate_all", 0)

local GIB_CONN_DATA = {}

local G_GIBS = {}

local text = file.Read("materials/gibsplat2/gibs.vmt", "GAME")

local gib_info = util.KeyValuesToTable(text or "")

for body_type, gib_data in pairs(gib_info) do
	for bone_name, data in pairs(gib_data) do
		for mdl, offset in pairs(data) do
			if offset.vec_offset then
				offset.vec_offset = Vector(unpack(offset.vec_offset:Split(" ")))
			end
			if offset.ang_offset then
				offset.ang_offset = Angle(unpack(offset.ang_offset:Split(" ")))
			end
		end
	end
end

local PHYS_MAT_CACHE = {}

local function GetChildMeshRec(ent, output, parent)
	if ent.GS2GibInfo then
		table_Add(output, ent.GS2GibInfo.vertex_buffer)
	else		
		local phys = ent:GetPhysicsObject()
		if phys then
			local pos = ent:GetPos()
			local ang = ent:GetAngles()
			local convexes = phys:GetMeshConvexes()
			for _, convex in pairs(convexes) do
				for key, vert in pairs(convex) do
					convex[key] = parent:WorldToLocal(ent:LocalToWorld(vert.pos))
				end
				table_Add(output, convex)
			end
			ent:PhysicsDestroy()
			ent:SetNotSolid(true)
		end
				
		ent:PhysicsDestroy()
		ent.GS2_dummy = true
	end
	for _, child in ipairs(ent:GetChildren()) do
		GetChildMeshRec(child, output, parent)
	end
end

function CreateGibs(ent, phys_bone)
	local factor = gib_factor:GetFloat()
	if (factor == 0) then
		return
	end

	local mdl = ent:GetModel()
	local meshes = GetPhysGibMeshes(mdl, phys_bone)

	local gibs = {}

	local body_type = GS2GetBodyType(mdl)

	local gib_data = gib_info[body_type]

	local custom_gibs

	local phys = ent:GetPhysicsObjectNum(phys_bone)

	if gib_data then
		local bone = ent:TranslatePhysBoneToBone(phys_bone)
		local bone_name = ent:GetBoneName(bone):lower()

		local bone_pos, bone_ang = ent:GetBonePosition(bone)

		local custom_gib_data = gib_data[bone_name]

		custom_gibs = {}

		if (gib_custom:GetBool() and custom_gib_data) then
			for mdl, data in pairs(custom_gib_data) do
				if (math_random() < factor) then
					local gib = ents.Create("gs2_gib_custom")
					gib:SetModel(mdl)

					gib.vec_offset = data.vec_offset or vector_origin
					gib.ang_offset = data.ang_offset or ang_zero

					local pos, ang = LocalToWorld(gib.vec_offset, gib.ang_offset, bone_pos, bone_ang)

					gib:SetPos(pos)
					gib:SetAngles(ang)
					gib:Spawn()

					local phys_gib = gib:GetPhysicsObject()

					--phys_gib:SetVelocity(phys:GetVelocity())
					--phys_gib:AddAngleVelocity(phys:GetAngleVelocity())

					ent:DeleteOnRemove(gib)

					table_insert(custom_gibs, gib)
				end
			end
		end
	end

	for key, mesh in ipairs(meshes) do
		if (math_random() < factor) then
			local gib = ents.Create("gs2_gib")
			gib:SetBody(ent)
			gib:SetTargetBone(phys_bone)
			gib:SetGibIndex(key)
			gib:Spawn()

			ent:DeleteOnRemove(gib)

			table_insert(gibs, gib)			
		end
	end

	local chance = gib_merge_chance:GetFloat()

	--Merge gibs into larger ones
	for _, gib in ipairs(gibs) do
		if !IsValid(gib:GetParent()) then		
			for _, gib2 in ipairs(gibs) do
				if (gib != gib2 and math_random() < chance and !IsValid(gib2:GetParent())) then
					for _, conn in ipairs(gib.GS2GibInfo.conns) do
						if (gib2:GetGibIndex() == conn) then
							gib2:SetNotSolid(true)							
							gib2:SetParent(gib)
							break
						end
					end
				end
			end
		end
	end

	ent.GS2Gibs = ent.GS2Gibs or {}

	if custom_gibs then
		for _, custom_gib in ipairs(custom_gibs) do
			for _, gib in ipairs(gibs) do				
				if (gib:IsTouching(custom_gib)) then												
					custom_gib:SetParent(gib)					
					break			
				end	
			end
			if !IsValid(custom_gib:GetParent()) then
				table_insert(G_GIBS, custom_gib)
			end
			table.insert(ent.GS2Gibs, custom_gib)
		end		
	end

	for _, gib in ipairs(gibs) do
		if !IsValid(gib:GetParent()) then
			local convex = {}
			GetChildMeshRec(gib, convex, gib)
			
			gib:PhysicsInitConvex(convex)
			gib:InitPhysics()
			
			table_insert(G_GIBS, gib)
		end
		table.insert(ent.GS2Gibs, gib)
	end

	for i = 1, #G_GIBS - max_gibs:GetInt() do
		SafeRemoveEntity(table_remove(G_GIBS, 1))
	end
end

local start

hook.Add("Think", "GS2Gibs", function()
	local mdl, thread = next(THREADS)
	if !mdl then
		return
	end
	if !start then
		start = SysTime()
	end
		
	local bool, err = coroutine.resume(thread)

	if !bool then
		print(mdl, err)
	end

	if (coroutine.status(thread) == "dead") then
		THREADS[mdl] = nil
		print("Generated gibs for "..mdl.." in "..math.Round(SysTime() - start, 3).." seconds ("..table.Count(THREADS).." models left)")
		start = nil							
	end			
end)

if SERVER then
	hook.Add("OnEntityCreated", "GS2Gibs", function(ent)
		timer.Simple(0.1, function()
			if !IsValid(ent) then return end
			local mdl = ent:GetModel()
			if (mdl and !MDL_INDEX[mdl] and !THREADS[mdl] and util.IsValidRagdoll(mdl)) then
				THREADS[mdl] = coroutine.create(function()			
					GetPhysGibMeshes(mdl, 0)
				end)
				coroutine.resume(THREADS[mdl])
			end
		end)
	end)
end
if CLIENT then
	hook.Add("NetworkEntityCreated", "GS2Gibs", function(ent)
		local mdl = ent:GetModel()
		if (mdl and !MDL_INDEX[mdl] and !THREADS[mdl] and util.IsValidRagdoll(mdl)) then
			THREADS[mdl] = coroutine.create(function()			
				GetPhysGibMeshes(mdl, 0)
			end)
			coroutine.resume(THREADS[mdl])
		end		
	end)
end