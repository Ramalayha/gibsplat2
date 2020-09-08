ENT.Type = "anim"
ENT.Base = "base_anim"

local VERSION = 1

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Body")
	self:NetworkVar("Int", 0, "TargetBone")
	self:NetworkVar("Int", 1, "GibIndex")
	self:NetworkVar("Vector", 0, "OffsetFactor")
	self:NetworkVar("String", 0, "BodyModel")
end

local ang_zero = Angle(0, 0, 0)

local CACHE = {}

local function WriteVector(F, vec)
	F:WriteFloat(vec.x)
	F:WriteFloat(vec.y)
	F:WriteFloat(vec.z)
end

local function ReadVector(F)
	local x = F:ReadFloat()
	local y = F:ReadFloat()
	local z = F:ReadFloat()
	return Vector(x, y, z)
end

GS2AreGibsCached = {}

local function WriteTriangles(mdl, phys_bone, gib_index, tris, min, max) if CLIENT then return end
	local file_name = "gibsplat2/gib_mesh_cache/"..util.CRC(gib_index..mdl..phys_bone)..".txt"
print(mdl,phys_bone,gib_index)
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/gib_mesh_cache")

	file.Write(file_name, "") --creates file

	local F = file.Open(file_name, "wb", "DATA")
	if !F then
		return
	end

	F:WriteByte(VERSION)
	F:WriteShort(#mdl)
	F:Write(mdl)
	F:WriteByte(phys_bone)
	F:WriteShort(gib_index)
	WriteVector(F, min)
	WriteVector(F, max)
	F:WriteLong(#tris)
	for _, vert in pairs(tris) do
		WriteVector(F, vert.pos)
	end

	F:Close()

	GS2AreGibsCached[mdl] = true
end

local function LoadTriangles()
	for _, file_name in pairs(file.Find("gibsplat2/gib_mesh_cache/*.txt", "DATA")) do
		local F = file.Open("gibsplat2/gib_mesh_cache/"..file_name, "rb", "DATA")
		if !F then
			continue
		end
		if (F:ReadByte() != VERSION) then
			F:Close()
			continue
		end

		local mdl = F:Read(F:ReadShort())
		
		local phys_bone = F:ReadByte()
		
		local gib_index = F:ReadShort()

		local min = ReadVector(F)
		local max = ReadVector(F)

		local num_verts = F:ReadLong()

		CACHE[mdl] = CACHE[mdl] or {}
		CACHE[mdl][phys_bone] = CACHE[mdl][phys_bone] or {}

		local verts = {}
		if SERVER then
			for vert_index = 1, num_verts do
				verts[vert_index] = ReadVector(F)
			end
			CACHE[mdl][phys_bone][gib_index] = {verts, min, max}
		else
			for vert_index = 1, num_verts do
				local vert = {}
				vert.pos = ReadVector(F)
				vert.u = vert.pos.x / max.x
				vert.v = vert.pos.y / max.y
				vert.normal = vert.pos:GetNormal()
				verts[vert_index] = vert
			end
			local M = Mesh()
			M:BuildFromTriangles(verts)
			CACHE[mdl][phys_bone][gib_index] = {M, min, max}
		end

		F:Close()

		GS2AreGibsCached[mdl] = true
	end
end

LoadTriangles()

function ENT:GetMesh()
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end
	local phys_bone = self:GetTargetBone()
	local gib_index = self:GetGibIndex()
	local phys = IsValid(body) and body:GetPhysicsObjectNum(phys_bone)

	local mdl = body:GetModel()

	if (mdl == "") then
		return
	end

	CACHE[mdl] = CACHE[mdl] or {}
	CACHE[mdl][phys_bone] = CACHE[mdl][phys_bone] or {}

	local offset_factor = self:GetOffsetFactor()

	if CACHE[mdl][phys_bone][gib_index] then
		if SERVER then
			local phys = body:GetPhysicsObjectNum(self:GetTargetBone())
			
			local min, max = phys:GetAABB()

			local pos, ang = LocalToWorld(min + (max - min) * offset_factor, ang_zero, phys:GetPos(), phys:GetAngles())

			self:SetPos(pos)
			self:SetAngles(ang)
		end
		return unpack(CACHE[mdl][phys_bone][gib_index])
	end
	
	local min, max, convexes

	if CLIENT then
		local temp = ClientsideRagdoll(mdl)
		temp:SetupBones()
		phys = temp:GetPhysicsObjectNum(phys_bone)
		min, max = phys:GetAABB()
		convexes = phys:GetMeshConvexes()
		temp:Remove()
	else
		min, max = phys:GetAABB()
		convexes = phys:GetMeshConvexes()
	end

	math.randomseed(util.CRC(mdl) + (phys_bone + 1) * (gib_index + 1))

	local tris = convexes[math.random(1, #convexes)]

	local verts = {}
	
	local offset = min + (max - min) * offset_factor * math.Rand(0.8, 1.2)

	for vert_index = 1, math.random(5, 15) do
		local pos = offset * 1 --Creates new vector object

		for index = 1, #tris - 2, 3 do
			local p1 = tris[index].pos
			local p2 = tris[index+1].pos
			local p3 = tris[index+2].pos

			local norm = (p3 - p1):Cross(p2 - p1)
			norm:Normalize()

			local dist = norm:Dot(p3)

			local d = norm:Dot(pos)

			if (d > dist) then
				pos:Sub(norm * (d - dist))						
			end
		end

		local randx = math.Rand(min.x, max.x)
		local randy = math.Rand(min.y, max.y)
		local randz = math.Rand(min.z, max.z)
		
		local rand = Vector(randx, randy, randz) * 0.6

		pos:Add(rand)

		for index = 1, #tris - 2, 3 do
			local p1 = tris[index].pos
			local p2 = tris[index+1].pos
			local p3 = tris[index+2].pos

			local norm = (p3 - p1):Cross(p2 - p1)
			norm:Normalize()

			local dist = norm:Dot(p3)

			local d = norm:Dot(pos)

			if (d > dist) then
				pos:Sub(norm * (d - dist))					
			end
		end

		pos:Sub(offset)

		table.insert(verts, pos)
	end

	local temp
	if SERVER then
		temp = ents.Create("prop_physics")
		temp:SetModel("models/weapons/w_shotgun.mdl")
		temp:Spawn()
	else
		temp = ents.CreateClientProp("models/weapons/w_shotgun.mdl")		
	end
	temp:PhysicsInitConvex(verts)

	local phys_temp = temp:GetPhysicsObject()
	
	tris = phys_temp:GetMeshConvexes()[1]
	temp:Remove()

	WriteTriangles(mdl, phys_bone, gib_index, tris, min, max)

	if CLIENT then
		for _, vert in pairs(tris) do			
			vert.u = vert.pos.x / max.x
			vert.v = vert.pos.y / max.y
			vert.normal = vert.pos:GetNormal()
		end

		local M = Mesh()
		M:BuildFromTriangles(tris)
		tris = M
	else
		local meme = {}
		for index, vert in pairs(tris) do
			meme[vert.pos] = true
		end
		table.Empty(tris)
		for p in pairs(meme) do
			table.insert(tris, p)
		end		
	end
	
	CACHE[mdl][phys_bone][gib_index] = {tris, min, max}

	if SERVER then
		local phys = body:GetPhysicsObjectNum(self:GetTargetBone())
		
		local min, max = phys:GetAABB()

		local pos, ang = LocalToWorld(min + (max - min) * offset_factor, ang_zero, phys:GetPos(), phys:GetAngles())

		self:SetPos(pos)
		self:SetAngles(ang)
	end

	return tris, min, max
end

concommand.Add("gibtest", function(ply, cmd, args)
	local tr = ply:GetEyeTrace()
	if IsValid(tr.Entity) and tr.Entity:IsRagdoll() and !tr.Entity:GS2IsGibbed(tr.PhysicsBone) then
		tr.Entity:GS2Gib(tr.PhysicsBone)
	end
end)