include("clipmesh.lua")

local NUM_PARTS = 10

local PHYS_GIB_CACHE = {}

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
local custom_gibs		= CreateConVar("gs2_gib_custom", 1)
local max_gibs_per_bone = CreateConVar("gs2_max_gibs_per_bone", 10)
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

local PHYS_MAT_CACHE = {}

local function GetChildMeshRec(ent, output)
	output[#output + 1] = ent.GS2GibInfo.triangles
	for _, child in ipairs(ent:GetChildren()) do
		GetChildMeshRec(child, output)
	end
end

function CreateGibs(ent, phys_bone)
	local meshes = GetPhysGibMeshes(ent:GetModel(), phys_bone)

	local factor = gib_factor:GetFloat()

	local gibs = {}

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

	for _, gib in ipairs(gibs) do
		if !IsValid(gib:GetParent()) then
			local convexes = {}
			GetChildMeshRec(gib, convexes)
			
			gib:PhysicsInitMultiConvex(convexes)
			gib:InitPhysics()
		end
	end
end