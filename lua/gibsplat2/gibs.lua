include("clipmesh.lua")
include("filesystem.lua")

local MSG_GIBS = "GS2CreateGibs"

if SERVER then
	util.AddNetworkString(MSG_GIBS)
end

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

local ents_Create = SERVER and ents.Create or ents.CreateClientside
local ents_CreateClientProp = ents.CreateClientProp
local ents_GetAll = ents.GetAll

local ang_zero = Angle(0, 0, 0)

local NUM_PARTS = 10

local MDL_INDEX = {}

local PHYS_GIB_CACHE = {}

local GIB_VERSION = 3

local HOOK_NAME = "GibSplat2"

local THREADS = {}

local _ShouldGib = {}

local function ShouldGib(phys_mat)
	if (_ShouldGib[phys_mat] == nil) then
		_ShouldGib[phys_mat] = file.Exists("materials/models/gibsplat2/flesh/"..phys_mat..".vmt", "GAME")
	end
	return _ShouldGib[phys_mat]
end

local PERCENT = 0

local function SafeYield()
	if coroutine.running() then
		coroutine.yield()
	end
end

local function SafeResume(thread)
	if (coroutine.status(thread) != "dead") then
		return coroutine.resume(thread)
	end
end

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

	local temp
	if SERVER then
		temp = ents_Create("prop_ragdoll")
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

	if (!IsValid(phys) or !ShouldGib(phys:GetMaterial())) then
		temp:Remove()
		MDL_INDEX[mdl][phys_bone] = {}
		GS2LinkModelInfo(mdl, "gib_data", MDL_INDEX[mdl])
		return MDL_INDEX[mdl][phys_bone]
	end

	local min, max = phys:GetAABB()
	local size = max - min

	local convexes = phys:GetMeshConvexes()

	for _, convex in ipairs(convexes) do
		for _, vert in ipairs(convex) do
			table.insert(vertex_tbl, VEC2STR(vert.pos))
		end
	end
	
	local hash = TBL2HASH(vertex_tbl)

	local phys_count = temp:GetPhysicsObjectCount()

	temp:Remove()

	local mdl_info = GS2ReadModelData(mdl)

	if (mdl_info and mdl_info.gib_data) then
		for phys_bone, hash in pairs(mdl_info.gib_data) do
			if !PHYS_GIB_CACHE[hash] then				
				GS2ReadGibData(hash, PHYS_GIB_CACHE, size)
			end
			MDL_INDEX[mdl][phys_bone] = PHYS_GIB_CACHE[hash]
		end
		if MDL_INDEX[mdl][phys_bone] then
			THREADS[mdl] = nil
			GS2LinkModelInfo(mdl, "gib_data", MDL_INDEX[mdl])
			return MDL_INDEX[mdl][phys_bone]
		end
	end

	math_randomseed(util.CRC(mdl) + phys_bone)

	local points = {}

	for _, convex in pairs(convexes) do
		for _, vert in pairs(convex) do
			table_insert(points, vert.pos)
		end
	end

	temp = SERVER and ents_Create("prop_physics") or ents_CreateClientProp()

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
	--local size = max - min

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
				SafeYield()				
				GetPhysGibMeshes(mdl, phys_bone2, true)
			end
		end		
	end

	GS2WriteGibData(hash, PHYS_GIB_CACHE[hash])

	if (!norec and !mdl_info) then
		GS2LinkModelInfo(mdl, "gib_data", MDL_INDEX[mdl])
	end

	PERCENT = PERCENT + 1 / phys_count

	return meshes
end

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
		local is_bl
		for _, find in pairs(list) do
			if (find:sub(1, 1) == "!" and str:find(find:sub(2))) then
				is_bl = true
				break
			end
		end
		if !is_bl then
			for _, find in pairs(list) do
				if str:find(find) then
					MDLTYPE_CACHE[mdl] = body_type
					return body_type
				end
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

local gib_factor 		= GetConVar("gs2_gib_factor")
local gib_merge_chance 	= GetConVar("gs2_gib_merge_chance")
local gib_custom		= GetConVar("gs2_gib_custom")
local gib_expensive 	= GetConVar("gs2_gib_expensive")
local max_gibs			= GetConVar("gs2_max_gibs")

local generate_all		= GetConVar("gs2_gib_generate_all")

local sv_gibs			= GetConVar("gs2_gib_sv")
local cl_gibs 			= GetConVar("gs2_gib_cl")

local GIB_CONN_DATA = {}

local G_GIBS = {}

local text = file.Read("materials/gibsplat2/gibs.vmt", "GAME")

local gib_info = util.KeyValuesToTable(text or "")

for body_type, gib_data in pairs(gib_info) do
	for bone_name, data in pairs(gib_data) do
		for _, data in pairs(data) do
			if data.model then				
				if data.vec_offset then
					data.vec_offset = Vector(unpack(data.vec_offset:Split(" ")))
				end
				if data.ang_offset then
					data.ang_offset = Angle(unpack(data.ang_offset:Split(" ")))
				end
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

if CLIENT then
	net.Receive(MSG_GIBS, function()
		if !cl_gibs:GetBool() then return end
		local ent = net.ReadEntity()
		if IsValid(ent) then
			CreateGibs(ent, net.ReadInt(32), net.ReadVector(), net.ReadVector())
		end
	end)
end

--Prevent crazy origin messages
local world_max = Vector(16384, 16384, 16384)
local world_min = -world_max

function CreateGibs(ent, phys_bone, vel, ang_vel, blood_color)
	local factor = gib_factor:GetFloat()
	if (factor == 0) then
		return
	end

	blood_color = blood_color or 0

	local mdl = ent:GetModel()
	local meshes = GetPhysGibMeshes(mdl, phys_bone)

	local gibs = {}

	local body_type = GS2GetBodyType(mdl)

	local gib_data = gib_info[body_type]

	local custom_gibs

	if SERVER then
		local phys = ent:GetPhysicsObjectNum(phys_bone)
		vel = vel or phys:GetVelocity()
		ang_vel = ang_vel or phys:GetAngleVelocity()
		if !sv_gibs:GetBool() then
			local RF = RecipientFilter()
			RF:AddPVS(phys:GetPos())

			net.Start(MSG_GIBS)
				net.WriteEntity(ent)
				net.WriteInt(phys_bone, 32)
				net.WriteVector(vel)
				net.WriteVector(ang_vel)
			net.Send(RF)
			return
		end
	else
		vel = vel or Vector(0, 0, 0)
		ang_vel = ang_vel or Vector(0, 0, 0)
	end

	local bone = ent:TranslatePhysBoneToBone(phys_bone)
	local bone_name = ent:GetBoneName(bone):lower()

	local bone_pos, bone_ang = ent:GetBonePosition(bone)

	if !bone_pos:WithinAABox(world_min, world_max) then
		return --boogus bone position
	end

	if gib_data then		
		local custom_gib_data = gib_data[bone_name]

		custom_gibs = {}

		if (gib_custom:GetBool() and custom_gib_data) then
			for _, data in pairs(custom_gib_data) do
				if (math_random() < factor) then					
					local gib = ents_Create("gs2_gib_custom")
					gib:SetModel(data.model)

					gib.vec_offset = data.vec_offset or vector_origin
					gib.ang_offset = data.ang_offset or ang_zero

					local pos, ang = LocalToWorld(gib.vec_offset, gib.ang_offset, bone_pos, bone_ang)
					
					gib:SetPos(pos)
					gib:SetAngles(ang)
					gib:SetBColor(blood_color)
					gib:Spawn()
					
					local phys_gib = gib:GetPhysicsObject()

					if !IsValid(phys_gib) then
						gib:Remove()
						continue
					end

					phys_gib:SetVelocity(vel)
					phys_gib:AddAngleVelocity(ang_vel)

					--ent:DeleteOnRemove(gib)

					table_insert(custom_gibs, gib)
				end
			end
		end
	end

	for key, mesh in ipairs(meshes) do
		if (math_random() < factor) then
			local gib = ents_Create("gs2_gib")
			gib:SetBody(ent)
			gib:SetTargetBone(phys_bone)
			gib:SetGibIndex(key)
			gib:SetBColor(blood_color)
			if SERVER then
				gib:Spawn()
			else
				gib:Initialize()
			end

			--ent:DeleteOnRemove(gib)

			table_insert(gibs, gib)			
		end
	end

	--local chance = gib_merge_chance:GetFloat()
	local chance = CLIENT and 0 or gib_merge_chance:GetFloat() --causes floating gibs clientside and idk how to fix ¯\_(ツ)_/¯

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
				if (math_random() < chance and gib:IsTouching(custom_gib)) then												
					custom_gib:SetParent(gib)					
					break			
				end	
			end
			if !IsValid(custom_gib:GetParent()) then
				local phys = custom_gib:GetPhysicsObject()

				phys:SetVelocity(vel + vel * VectorRand())
				phys:AddAngleVelocity(ang_vel + ang_vel * VectorRand())
				table_insert(G_GIBS, custom_gib)
			end
			table.insert(ent.GS2Gibs, custom_gib)
		end		
	end

	for _, gib in ipairs(gibs) do
		if !IsValid(gib:GetParent()) then
			local convex = {}
			GetChildMeshRec(gib, convex, gib)
			
			if gib_expensive:GetBool() then
				gib:PhysicsInitConvex(convex)
			else
				local min = Vector(math.huge, math.huge, math.huge)
				local max = -min
				for _, vert in ipairs(convex) do
					min.x = math.min(min.x, vert.x)
					min.y = math.min(min.y, vert.y)
					min.z = math.min(min.z, vert.z)

					max.x = math.max(max.x, vert.x)
					max.y = math.max(max.y, vert.y)
					max.z = math.max(max.z, vert.z)
				end
				gib:PhysicsInitBox(min, max)
			end
			gib:InitPhysics()
			
			local phys = gib:GetPhysicsObject()

			phys:SetVelocity(vel + vel * VectorRand() + VectorRand() * 20)
			phys:AddAngleVelocity(ang_vel + ang_vel * VectorRand() + VectorRand() * 20)

			table_insert(G_GIBS, gib)
		end
		table_insert(ent.GS2Gibs, gib)
	end

	for i = 1, #G_GIBS - max_gibs:GetInt() do
		SafeRemoveEntity(table_remove(G_GIBS, 1))
	end

	if SERVER then
		for _, gib in pairs(ent.GS2Gibs) do
			if IsValid(gib) then
				ent:DeleteOnRemove(gib) --sometimes gib is not valid and i cba to figure out why
			end
		end
	end

	return gibs
end

local start

local enabled = GetConVar("gs2_enabled")

hook.Add("Think", "GS2Gibs", function()
	if !enabled:GetBool() then return end
	local mdl, thread = next(THREADS)
	if !mdl then
		return
	end
	if !start then
		start = SysTime()
		print("Started generating gibs for "..mdl)
	end
		
	local bool, err = SafeResume(thread)

	if (!bool and err) then
		print(mdl, err)
	elseif err then
		PERCENT = err
	end

	if (coroutine.status(thread) == "dead") then
		THREADS[mdl] = nil
		print("Generated gibs for "..mdl.." in "..math.Round(SysTime() - start, 3).." seconds ("..table.Count(THREADS).." models left)")
		start = nil
		PERCENT = 0
	end	
end)

local player_ragdolls = GetConVar("gs2_player_ragdolls")

if SERVER then
	hook.Add("OnEntityCreated", "GS2Gibs", function(ent)
		if !enabled:GetBool() then return end
		if (ent:IsPlayer() and !player_ragdolls:GetBool() and !engine.ActiveGamemode():find("ttt")) then return end
		timer.Simple(0.1, function()
			if !IsValid(ent) then return end
			local mdl = ent:GetModel()
			if (mdl and !MDL_INDEX[mdl] and !THREADS[mdl] and util.IsValidRagdoll(mdl)) then
				if GS2ReadModelData(mdl) then
					GetPhysGibMeshes(mdl, 0)
				else
					THREADS[mdl] = coroutine.create(function()			
						GetPhysGibMeshes(mdl, 0)
					end)					
				end
			end
		end)
	end)

	local function RemoveGibs(ply)
		if !ply:IsAdmin() then return end
		for _, gib in ipairs(ents_GetAll()) do			
			if gib:GetClass():find("^gs2_gib") then
				SafeRemoveEntity(gib)
			end
		end
		table.Empty(G_GIBS)
		ply:ConCommand("gs2_cleargibs") --clear clientside gibs too
	end

	concommand.Add("gs2_cleargibs_sv", RemoveGibs)
end
if CLIENT then
	local form = [[GS2: Building gibs for "%s" (%3.2f%% done), %i models remaining (PREPARE FOR FPS SPIKES)]]
	local form2 = [[GS2: Building gibs for "%s" (%3.2f%% done)]]

	hook.Add("HUDPaint", "GS2BuildGibsDisplay", function()
		if !enabled:GetBool() then return end
		local mdl = next(THREADS)
		if !mdl then return end

		local nmodels = table.Count(THREADS)

		local form = nmodels > 1 and form or form2

		local msg = form:format(mdl, 100 * PERCENT, nmodels - 1)

		surface.SetFont("DebugFixed")
		local w, h = surface.GetTextSize(msg)

		surface.SetTextColor(255, 0, 0)
		surface.SetTextPos(ScrW() * 0.99 - w, ScrH() / 2 - h * 2)
		surface.DrawText(msg)
	end)

	hook.Add("NetworkEntityCreated", "GS2Gibs", function(ent)
		if (!enabled:GetBool() or !IsValid(ent)) then return end
		if (ent:IsPlayer() and !player_ragdolls:GetBool() and !engine.ActiveGamemode():find("ttt")) then return end
		local mdl = ent:GetModel()
		if (mdl and !MDL_INDEX[mdl] and !THREADS[mdl] and util.IsValidRagdoll(mdl)) then
			THREADS[mdl] = coroutine.create(function()			
				GetPhysGibMeshes(mdl, 0)
			end)
			SafeResume(THREADS[mdl])
		end		
	end)

	local function RemoveGibs()
		for _, gib in ipairs(ents_GetAll()) do			
			if gib:GetClass():find("^gs2_gib") then
				if (gib:EntIndex() == -1) then
					SafeRemoveEntity(gib)
				end		
			end
		end
		table.Empty(G_GIBS)
	end

	hook.Add("PostCleanupMap", HOOK_NAME, RemoveGibs)
	concommand.Add("gs2_cleargibs", RemoveGibs)
end