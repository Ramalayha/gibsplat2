include("clipmesh.lua")

local NUM_PARTS = 10

local PHYS_GIB_CACHE = {}

local GIB_VERSION = 2

local FILE = FindMetaTable("File")

function FILE:WriteVector(vec)
	self:WriteFloat(vec.x)
	self:WriteFloat(vec.y)
	self:WriteFloat(vec.z)
end

function FILE:ReadVector()
	return Vector(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
end

local function WriteGibCache(mdl, phys_bone, data)
	local prefix = SERVER and "gibsplat2/sv_gib_cache/" or "gibsplat2/cl_gib_cache/"
	
	local file_name = prefix..util.CRC(mdl)..phys_bone..".txt"

	file.CreateDir("gibsplat2")
	file.CreateDir(prefix)

	file.Write(file_name, "")

	local F = file.Open(file_name, "wb", "DATA")

	F:WriteByte(GIB_VERSION)
	F:WriteShort(#mdl)
	F:Write(mdl)
	F:WriteShort(phys_bone)

	F:WriteShort(#data)

	for _, entry in ipairs(data) do
		F:WriteVector(entry.center)
		F:WriteShort(#entry.conns)
		for _, conn in ipairs(entry.conns) do
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
				local index = table.KeyFromValue(VERTEX_BUFFER, vert)
				if !index then
					index = table.insert(VERTEX_BUFFER, vert)		
				end
				table.insert(INDEX_BUFFER, index)
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

	F:Close()
end

local function ReadGibFile(F, mdl)
	local phys_bone = F:ReadShort()

	PHYS_GIB_CACHE[mdl] = PHYS_GIB_CACHE[mdl] or {}

	local data = {}

	for i = 1, F:ReadShort() do
		local entry = {}
		entry.center = F:ReadVector()
		entry.conns = {}
		for j = 1, F:ReadShort() do
			entry.conns[j] = F:ReadShort()
		end
		entry.triangles = {}
		if SERVER then
			for j = 1, F:ReadLong() do
				entry.triangles[j] = F:ReadVector()
			end
		else
			local VERTEX_BUFFER = {}
			local min = Vector(math.huge, math.huge, math.huge)
			local max = -min
			for j = 1, F:ReadLong() do
				local pos = F:ReadVector()
				min.x = math.min(min.x, pos.x)
				min.y = math.min(min.y, pos.y)
				min.z = math.min(min.z, pos.z)

				max.x = math.max(max.x, pos.x)
				max.y = math.max(max.y, pos.y)
				max.z = math.max(max.z, pos.z)

				VERTEX_BUFFER[j] = {pos = pos}
			end

			local size = max - min

			for _, vert in ipairs(VERTEX_BUFFER) do
				vert.u = vert.pos.x / size.x + vert.pos.z / size.z
				vert.v = vert.pos.y / size.y + vert.pos.z / size.z
				vert.normal = (vert.pos - entry.center):GetNormal()
			end

			for j = 1, F:ReadLong() do
				entry.triangles[j] = VERTEX_BUFFER[F:ReadLong()]
			end
			entry.mesh = Mesh()
			entry.mesh:BuildFromTriangles(entry.triangles)
		end
		data[i] = entry
	end

	PHYS_GIB_CACHE[mdl][phys_bone] = data
end

local function ReadGibCache()
	local prefix = SERVER and "gibsplat2/sv_gib_cache/" or "gibsplat2/cl_gib_cache/"
	
	local files = file.Find(prefix.."*.txt", "DATA")

	for _, file_name in ipairs(files) do
		local F = file.Open(prefix..file_name, "rb", "DATA")
 		
 		if (F:ReadByte() != GIB_VERSION) then
			F:Close()
			file.Delete(prefix..file_name)		
			continue
		end

		local mdl = F:Read(F:ReadShort())

		local succ, err = pcall(ReadGibFile, F, mdl)
		F:Close()

		if !succ then
			print("Failed to load gib mesh for "..mdl.." ("..file_name..") Deleting!")
			file.Delete(prefix..file_name)
		end	
	end
end

ReadGibCache()

function GetPhysGibMeshes(mdl, phys_bone)
	if (PHYS_GIB_CACHE[mdl] and PHYS_GIB_CACHE[mdl][phys_bone]) then
		return PHYS_GIB_CACHE[mdl][phys_bone]
	end

	math.randomseed(util.CRC(mdl) + phys_bone)

	local temp
	if SERVER then
		temp = ents.Create("prop_ragdoll")
		temp:SetModel(mdl)
		temp:Spawn()
	else
		temp = ClientsideRagdoll(mdl)
	end
	
	local phys = temp:GetPhysicsObjectNum(phys_bone)

	if !IsValid(phys) then
		return
	end

	local convexes = phys:GetMeshConvexes()

	temp:Remove()

	local points = {}

	for _, convex in pairs(convexes) do
		for _, vert in pairs(convex) do
			table.insert(points, vert.pos)
		end
	end

	temp = SERVER and ents.Create("prop_physics") or ents.CreateClientProp()

	temp:PhysicsInitConvex(points)

	local convex = temp:GetPhysicsObject():GetMeshConvexes()[1]

	temp:Remove()

	local min, max = phys:GetAABB()
	local size = max - min

	local points = {}

	local LEFT = NUM_PARTS

	while (LEFT > 0) do
		local point = Vector()
		point.x = math.Rand(min.x, max.x)
		point.y = math.Rand(min.y, max.y)
		point.z = math.Rand(min.z, max.z)

		local is_inside = true

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

			if (n:Dot(point) > d) then
				is_inside = false
				break
			end
		end
		
		if is_inside then
			table.insert(points, point)
			LEFT = LEFT - 1
		end
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
			table.Empty(mesh.triangles)
			for vert in pairs(vertex_buffer) do
				table.insert(mesh.triangles, vert)
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

local text = file.Read("gibsplat2/skeletons.vmt", "GAME")

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

	local num_x = math.max(1, math.floor(phys_size.x / 4))
	local num_y = math.max(1, math.floor(phys_size.y / 4))
	local num_z = math.max(1, math.floor(phys_size.z / 4))

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

				table.insert(gibs, gib)
							
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
				table.insert(GIB_CONN_DATA[mdl][phys_bone][gib_index1], gib_index2)
			end
		end
	end

	for _, gib in pairs(gibs) do
		gib:Remove()
	end
end

local G_GIBS = {}

local text = file.Read("gibsplat2/gibs.vmt", "GAME")

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

local function GetChildMeshRec(ent, output)
	if ent.GS2GibInfo then
		table.Add(output, ent.GS2GibInfo.triangles)
	else		
		table.Add(output, ent.convex)
		ent:PhysicsDestroy()
		ent.GS2_dummy = true
	end
	for _, child in ipairs(ent:GetChildren()) do
		GetChildMeshRec(child, output)
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

	if gib_data then
		local bone = ent:TranslatePhysBoneToBone(phys_bone)
		local bone_name = ent:GetBoneName(bone):lower()

		local bone_pos, bone_ang = ent:GetBonePosition(bone)

		local custom_gib_data = gib_data[bone_name]

		custom_gibs = {}

		if (gib_custom:GetBool() and custom_gib_data) then
			for mdl, data in pairs(custom_gib_data) do
				if (math.random() < factor) then
					local gib = ents.Create("gs2_gib_custom")
					gib:SetModel(mdl)

					local pos = bone_pos
					local ang = bone_ang

					if data.vec_offset then
						pos = pos + data.vec_offset
						gib.vec_offset = data.vec_offset
					end

					if data.ang_offset then
						ang = ang + data.ang_offset
						gib.ang_offset = data.ang_offset
					end

					gib:SetPos(pos)
					gib:SetAngles(ang)
					gib:Spawn()

					if !data.convex then
						local points = {}
						local phys = gib:GetPhysicsObject()
						for _, convex in ipairs(phys:GetMeshConvexes()) do
							for _, vert in ipairs(convex) do
								points[vert.pos] = true
							end
						end
						data.convex = {}
						for point in ipairs(points) do
							if data.vec_offset then
								point:Add(data.vec_offset)
							end
							if data.ang_offset then
								point:Rotate(data.ang_offset)
							end
							table.insert(data.convex, point)
						end
					end

					gib.convex = data.convex

					ent:DeleteOnRemove(gib)

					table.insert(custom_gibs, gib)
				end
			end
		end
	end

	for key, mesh in ipairs(meshes) do
		if (math.random() < factor) then
			local gib = ents.Create("gs2_gib")
			gib:SetBody(ent)
			gib:SetTargetBone(phys_bone)
			gib:SetGibIndex(key)
			gib:Spawn()

			ent:DeleteOnRemove(gib)

			table.insert(gibs, gib)			
		end
	end

	local chance = gib_merge_chance:GetFloat()

	--Merge gibs into larger ones
	for _, gib in ipairs(gibs) do
		if !IsValid(gib:GetParent()) then		
			for _, gib2 in ipairs(gibs) do
				if (gib != gib2 and math.random() < chance and !IsValid(gib2:GetParent())) then
					for _, conn in ipairs(gib.GS2GibInfo.conns) do
						if (gib2:GetGibIndex() == conn) then
							gib2:SetNotSolid(true)	
							local parent = gib
							repeat
								local next_parent = parent:GetParent()
								if (next_parent == NULL) then
									break
								end
								parent = next_parent
							until (parent == NULL)
							gib2:SetParent(parent)	

							break
						end
					end
				end
			end
		end
	end

	if custom_gibs then
		for _, custom_gib in ipairs(custom_gibs) do
			for _, gib in ipairs(ents.FindInBox(custom_gib:WorldSpaceAABB())) do
				if (gib.GS2GibInfo and math.random() < chance) then
					custom_gib:SetParent(gib)
					break				
				end	
			end
			if !IsValid(custom_gib:GetParent()) then
				table.insert(G_GIBS, custom_gib)
			end
		end
	end

	for _, gib in ipairs(gibs) do
		if !IsValid(gib:GetParent()) then
			local convex = {}
			GetChildMeshRec(gib, convex)
			
			gib:PhysicsInitConvex(convex)
			gib:InitPhysics()

			table.insert(G_GIBS, gib)
		end
	end

	for i = 1, #G_GIBS - max_gibs:GetInt() do
		SafeRemoveEntity(table.remove(G_GIBS, 1))
	end
end