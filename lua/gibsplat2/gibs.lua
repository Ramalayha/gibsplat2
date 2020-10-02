include("clipmesh.lua")

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

local PHYS_GIB_CACHE = {}

local GIB_VERSION = 3

local HOOK_NAME = "GibSplat2"

local FILE = FindMetaTable("File")

function FILE:WriteVector(vec)
	self:WriteFloat(vec.x)
	self:WriteFloat(vec.y)
	self:WriteFloat(vec.z)
end

function FILE:ReadVector()
	return Vector(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
end

local function WriteGibCache(mdl)
	if CLIENT then 
		game.CleanUpMap() --Prevents freezes
	end
	local gib_data = PHYS_GIB_CACHE[mdl]
	local prefix = SERVER and "gibsplat2/sv_gib_cache/" or "gibsplat2/cl_gib_cache/"
	
	local file_name = prefix..util.CRC(mdl)..".txt"

	file.CreateDir("gibsplat2")
	file.CreateDir(prefix)

	file.Write(file_name, "")

	local F = file.Open(file_name, "wb", "DATA")

	F:WriteByte(GIB_VERSION)
	F:WriteShort(#mdl)
	F:Write(mdl)
	
	F:WriteShort(table_Count(gib_data))
	for phys_bone, data in pairs(gib_data) do
		F:WriteShort(phys_bone)
		F:WriteShort(table_Count(data))
		for _, entry in pairs(data) do
			F:WriteVector(entry.center)
			F:WriteShort(table_Count(entry.conns))
			for _, conn in pairs(entry.conns) do
				F:WriteShort(conn)
			end
			if SERVER then
				F:WriteLong(#entry.triangles)
				for _, vert in ipairs(entry.triangles) do
					F:WriteVector(vert)
				end
			else
				local VERTEX_BUFFER = {}
				local INDEX_BUFFER = {}
				for _, vert in ipairs(entry.triangles) do
					local index = table_KeyFromValue(VERTEX_BUFFER, vert)
					if !index then
						index = table_insert(VERTEX_BUFFER, vert)		
					end
					table_insert(INDEX_BUFFER, index)
				end
				F:WriteLong(#VERTEX_BUFFER)
				for _, vert in ipairs(VERTEX_BUFFER) do
					F:WriteVector(vert.pos)
				end
				F:WriteLong(#INDEX_BUFFER)
				for _, index in ipairs(INDEX_BUFFER) do
					F:WriteLong(index)
				end
			end
		end
	end

	F:Close()
end

local function ReadGibFile(F)
	local VERSION = F:ReadByte()
	if (VERSION != GIB_VERSION) then
		F:Close()
		return false
	end

	local mdl = F:Read(F:ReadShort())
	
	PHYS_GIB_CACHE[mdl] = PHYS_GIB_CACHE[mdl] or {}

	local num_gibs = F:ReadShort()

	if num_gibs > 100 then
		print("ReadGibFile: too many gibs! "..mdl.." ("..num_gibs..")")
		F:Close()
		return
	end

	for i = 1, num_gibs do 
		local phys_bone = F:ReadShort()
		local data = {}
		local num_entries = F:ReadShort()
		if num_entries > 100 then
			print("ReadGibFile: too many entries! "..mdl.." ("..num_entries..")")
			F:Close()
			return
		end
		for j = 1, num_entries do
			local entry = {}
			entry.center = F:ReadVector()
			entry.conns = {}
			for k = 1, F:ReadShort() do
				entry.conns[k] = F:ReadShort()				
			end
			entry.triangles = {}
			if SERVER then
				local num_verts = F:ReadLong()
				if num_verts > 1000 then
					print("ReadGibFile: too many vertices! "..mdl.." ("..num_verts..")",F:Tell(),phys_bone,j)
					F:Close()
					return
				end
				for k = 1, num_verts do 
					entry.triangles[k] = F:ReadVector()
				end
			else
				local VERTEX_BUFFER = {}
				local min = Vector(math_huge, math_huge, math_huge)
				local max = -min
				local num_verts = F:ReadLong()
				if num_verts > 1000 then
					print("ReadGibFile: too many vertices! "..mdl.." ("..num_verts..")")
					F:Close()
					return
				end
				for k = 1, num_verts do
					local pos = F:ReadVector()
					min.x = math_min(min.x, pos.x)
					min.y = math_min(min.y, pos.y)
					min.z = math_min(min.z, pos.z)

					max.x = math_max(max.x, pos.x)
					max.y = math_max(max.y, pos.y)
					max.z = math_max(max.z, pos.z)

					VERTEX_BUFFER[k] = {pos = pos}
				end

				local size = max - min

				for _, vert in ipairs(VERTEX_BUFFER) do 
					vert.u = vert.pos.x / size.x + vert.pos.z / size.z
					vert.v = vert.pos.y / size.y + vert.pos.z / size.z
					vert.normal = (vert.pos - entry.center):GetNormal()
				end
 	
				for k = 1, F:ReadLong() do
					entry.triangles[k] = VERTEX_BUFFER[F:ReadLong()]
				end
				entry.mesh = Mesh()
				entry.mesh:BuildFromTriangles(entry.triangles)
			end
			data[j] = entry
		end
		PHYS_GIB_CACHE[mdl][phys_bone] = data
	end

	return true
end

function GetPhysGibMeshes(mdl, phys_bone)
	if (PHYS_GIB_CACHE[mdl] and PHYS_GIB_CACHE[mdl][phys_bone]) then
		return PHYS_GIB_CACHE[mdl][phys_bone]
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
		return
	end

	local phys = temp:GetPhysicsObjectNum(phys_bone)

	if !IsValid(phys) then
		temp:Remove()
		return
	end

	local convexes = phys:GetMeshConvexes()

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
		return
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
	else
		for _, mesh in pairs(meshes) do
			local vertex_buffer = {}
			for _, vert in pairs(mesh.triangles) do
				vertex_buffer[vert.pos] = true
			end
			table_Empty(mesh.triangles)
			for vert in pairs(vertex_buffer) do
				table_insert(mesh.triangles, vert)
			end
		end
	end
	
	PHYS_GIB_CACHE[mdl] = PHYS_GIB_CACHE[mdl] or {}
	PHYS_GIB_CACHE[mdl][phys_bone] = meshes

	WriteGibCache(mdl, phys_bone, meshes)

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

local function GenerateConnData(ent, phys_bone)
	local mdl = ent:GetModel()

	GIB_CONN_DATA[mdl][phys_bone] = {}

	local phys = ent:GetPhysicsObjectNum(phys_bone)

	local min, max 		= phys:GetAABB()
	local phys_size 	= max - min	

	local gib_index = 0

	local num_x = math_max(1, math_floor(phys_size.x / 4))
	local num_y = math_max(1, math_floor(phys_size.y / 4))
	local num_z = math_max(1, math_floor(phys_size.z / 4))

	local gibs = {}

	for x = 1, num_x do
		for y = 1, num_y do
			for z = 1, num_z do				
				local gib = ents.Create("gs2_gib")
				gib:SetBody(ent)
				gib:SetTargetBone(phys_bone)
				gib:SetGibIndex(gib_index)
				gib:SetOffsetFactor(Vector(x / (num_x + 1), y / (num_y + 1), z / (num_z + 1)))									
				gib:Spawn()

				table_insert(gibs, gib)
							
				gib_index = gib_index + 1
			end
		end
	end

	--Generate connections
	for _, gib1 in pairs(gibs) do
		if (gib1:GetClass() == "gs2_gib_custom") then
			continue
		end
		local gib_index1 = gib1:GetGibIndex()
		GIB_CONN_DATA[mdl][phys_bone][gib_index1] = {}
		local mesh1 = gib1:GetPhysicsObject():GetMeshConvexes()[1]
		for _, gib2 in pairs(gibs) do
			if (!custom_gibs:GetBool() and gib2:GetClass() == "gs2_gib_custom") then
				continue
			end
			local gib_index2 = gib2:GetGibIndex()
			local mesh2 = gib2:GetMesh()
			local is_conn = false
			for _, vert in pairs(mesh2) do
				local wpos = gib2:LocalToWorld(vert)
				local lpos = gib1:WorldToLocal(wpos)

				local is_inside = true
				for tri_index = 1, #mesh1 - 2, 3 do
					local p1 = mesh1[tri_index].pos
					local p2 = mesh1[tri_index + 1].pos
					local p3 = mesh1[tri_index + 2].pos

					local norm = (p3 - p1):Cross(p2 - p1)
					norm:Normalize()

					local dist = norm:Dot(p3) * 0.7

					if (norm:Dot(lpos) > dist) then
						is_inside = false
						break
					end
				end	
				if is_inside then
					is_conn = true
					break
				end			
			end

			if is_conn then
				table_insert(GIB_CONN_DATA[mdl][phys_bone][gib_index1], gib_index2)
			end
		end
	end

	for _, gib in pairs(gibs) do
		gib:Remove()
	end
end

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
		table_Add(output, ent.GS2GibInfo.triangles)
	else	
		if ent.convex then
			table_Add(output, ent.convex)
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
		end	
		
		ent:PhysicsDestroy()
		ent.GS2_dummy = true
	end
	for _, child in ipairs(ent:GetChildren()) do
		GetChildMeshRec(child, output, parent)
	end
end

function CreateGibs(ent, phys_bone)
	local mdl = ent:GetModel()
	local meshes = GetPhysGibMeshes(mdl, phys_bone)

	local factor = gib_factor:GetFloat()

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
	end

	for i = 1, #G_GIBS - max_gibs:GetInt() do
		SafeRemoveEntity(table_remove(G_GIBS, 1))
	end
end

local enabled = CreateConVar("gs2_enabled", 0, FCVAR_REPLICATED)

if CLIENT then
	hook.Add("NetworkEntityCreated", HOOK_NAME.."_LoadGibMeshes", function(ent)
		if !enabled:GetBool() then return end
		local mdl = ent:GetModel()
		if (mdl and !PHYS_GIB_CACHE[mdl] and util.IsValidRagdoll(mdl)) then
			local path = "gibsplat2/cl_gib_cache/"..util.CRC(mdl)
			local F = file.Open("materials/"..path..".vmt", "rb", "GAME") or file.Open(path..".txt", "rb", "DATA")
			if F then
				if !pcall(ReadGibFile, F) then
					print("ReadGibFile: corrupt file '"..path.."' deleting!")
					file.Delete(path)					
				end
				F:Close()			
			end
			PHYS_GIB_CACHE[mdl] = PHYS_GIB_CACHE[mdl] or {}
			for phys_bone = 0, 23 do
				if (phys_bone != 0 and ent:TranslatePhysBoneToBone(phys_bone) == 0) then
					break 
				end
				if !PHYS_GIB_CACHE[mdl][phys_bone] then
					GetPhysGibMeshes(mdl, phys_bone)					
				end	
			end			
		end		
	end)
end

if SERVER then
	hook.Add("OnEntityCreated", HOOK_NAME.."_LoadGibMeshes", function(ent)
		if !enabled:GetBool() then return end
		timer.Simple(0, function()
			if !IsValid(ent) then
				return
			end
			local mdl = ent:GetModel()
			if (mdl and !PHYS_GIB_CACHE[mdl] and util.IsValidRagdoll(mdl)) then
				local path = "gibsplat2/sv_gib_cache/"..util.CRC(mdl)
				local F = file.Open("materials/"..path..".vmt", "rb", "GAME") or file.Open(path..".txt", "rb", "DATA")
				if F then
					if !pcall(ReadGibFile, F) then
						print("ReadGibFile: corrupt file '"..path.."' deleting!")
						file.Delete(path)
						should_write = true
					end
					F:Close()
				end
				PHYS_GIB_CACHE[mdl] = PHYS_GIB_CACHE[mdl] or {}
				for phys_bone = 0, 23 do
					if (phys_bone != 0 and ent:TranslatePhysBoneToBone(phys_bone) == 0) then
						break 
					end
					if !PHYS_GIB_CACHE[mdl][phys_bone] then
						GetPhysGibMeshes(mdl, phys_bone)						
					end			
				end				
			end
		end)
	end)
end