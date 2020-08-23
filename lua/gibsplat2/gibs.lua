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
local max_gibs_per_bone = CreateConVar("gs2_max_gibs_per_bone", 10)
local max_gibs			= CreateConVar("gs2_max_gibs", 128)

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

function CreateGibs(ent, phys_bone)
	local mdl = ent:GetModel()

	local cached = GS2AreGibsCached[mdl]

	local chance = cached and gib_factor:GetFloat() or 1 --spawn all first time for caching

	if (chance <= 0) then
		return
	end

	local bone = ent:TranslatePhysBoneToBone(phys_bone)
	local bone_name = ent:GetBoneName(bone)

	local phys = ent:GetPhysicsObjectNum(phys_bone)
	local phys_mat = phys:GetMaterial()

	if (PHYS_MAT_CACHE[phys_mat] == NULL) then
		return
	elseif !PHYS_MAT_CACHE[phys_mat] then
		if file.Exists("materials/models/"..phys_mat..".vmt", "GAME") then
			PHYS_MAT_CACHE[phys_mat] = "models/"..phys_mat
		else
			PHYS_MAT_CACHE[phys_mat] = NULL
			return
		end
	end

	local body_type = GS2GetBodyType(mdl)

	local custom_gibs = gib_info[body_type] and gib_info[body_type][bone_name:lower()]

	local gibs = {}

	local gib_index = 0

	local limit = cached and max_gibs_per_bone:GetInt() or math.huge

	if custom_gibs then
		for gib_mdl, data in pairs(custom_gibs) do
			if (math.random() < chance) then
				local vec_offset = Vector(unpack(data.vec_offset:Split(" ")))
				local ang_offset = Angle(unpack(data.ang_offset:Split(" ")))

				local pos, ang = LocalToWorld(vec_offset, ang_offset, phys:GetPos(), phys:GetAngles())

				local gib = ents.Create("gs2_gib_custom")
				gib:SetModel(gib_mdl)
				gib:SetPos(pos)
				gib:SetAngles(ang)
				gib:Spawn()
				
				gibs[gib_index] = gib
			end
			gib_index = gib_index + 1
			if (gib_index >= limit) then
				break
			end
		end
	end

	GIB_CONN_DATA[mdl] = GIB_CONN_DATA[mdl] or {}

	if !GIB_CONN_DATA[mdl][phys_bone] then
		GenerateConnData(ent, phys_bone)
	end

	local mat = PHYS_MAT_CACHE[phys_mat]
	
	local phys_pos 		= phys:GetPos()
	local phys_ang 		= phys:GetAngles()
	local phys_vel 		= phys:GetVelocity()
	local phys_angvel 	= phys:GetAngleVelocity()
	local min, max 		= phys:GetAABB()
	local phys_size 	= max - min	

	local num_x = math.max(1, math.floor(phys_size.x / 4))
	local num_y = math.max(1, math.floor(phys_size.y / 4))
	local num_z = math.max(1, math.floor(phys_size.z / 4))

	for x = 0, num_x - 1 do
		for y = 0, num_y - 1 do
			for z = 0, num_z - 1 do
				if (math.random() <= chance) then
					local gib = ents.Create("gs2_gib")					
					gib:SetBody(ent)
					gib:SetTargetBone(phys_bone)
					gib:SetGibIndex(gib_index)
					gib:SetOffsetFactor(Vector(x / (num_x + 1), y / (num_y + 1), z / (num_z + 1)))									
					
					gibs[gib_index] = gib
					table.insert(G_GIBS, gib)					
				end
				gib_index = gib_index + 1
				if (gib_index >= limit) then
					break
				end
			end
			if (gib_index >= limit) then
				break
			end
		end
		if (gib_index >= limit) then
			break
		end
	end

	if !cached then
		for _, gib in pairs(gibs) do
			SafeRemoveEntity(gib)
		end
		return
	end

	--Connect
	local chance = gib_merge_chance:GetFloat()
	for gib_index1, gib1 in pairs(gibs) do
		if (gib1:GetClass() != "gs2_gib_custom") then
			local conns = GIB_CONN_DATA[mdl][phys_bone][gib_index1]
			if conns then			
				while true do
					local parent = gib1.GS2_merge
					if IsValid(parent) then
						gib1 = parent
					else
						break
					end
				end	
				for _, gib_index2 in pairs(conns) do
					local gib2 = gibs[gib_index2]				
					if (gib2 and math.random() < chance) then
						while true do
							local parent = gib2.GS2_merge
							if IsValid(parent) then
								gib2 = parent
							else
								break
							end
						end
						if (gib1 != gib2) then
							gib1:AddMerge(gib2)	
						end
					end	
				end
			end
		end
	end

	ent.GS2Gibs = ent.GS2Gibs or {}

	for _, gib in pairs(gibs) do
		gib:Spawn()	
		ent:DeleteOnRemove(gib)
		table.insert(ent.GS2Gibs, gib)		
	end

	for _, gib in pairs(gibs) do
		if !gib:DoMerge() then
			local gib_phys = gib:GetPhysicsObject()
			gib_phys:SetVelocity(phys:GetVelocity() + VectorRand(-0.1, 0.1) * phys:GetVelocity():Length())
			gib_phys:AddAngleVelocity(phys:GetAngleVelocity() + VectorRand(-0.1, 0.1) * phys:GetAngleVelocity():Length())
		end
	end

	for _, gib in pairs(gibs) do
		SafeRemoveEntityDelayed(gib, 20)
	end

	for i = 1, #G_GIBS - max_gibs:GetInt() do		
		SafeRemoveEntity(table.remove(G_GIBS, 1))
	end
end