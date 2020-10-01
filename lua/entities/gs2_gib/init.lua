AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local ang_zero = Angle(0, 0, 0)

function ENT:Initialize()
	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	local phys = body:GetPhysicsObjectNum(phys_bone)

	self:SetPos(phys:GetPos())
	self:SetAngles(phys:GetAngles())

	local gib_index = self:GetGibIndex()

	self.GS2GibInfo = GetPhysGibMeshes(body:GetModel(), phys_bone)[gib_index]

	self:DrawShadow(false)

	self.GS2_dummy = true --default to this

	self.Created = CurTime()
end

function ENT:InitPhysics()
	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	local phys = body:GetPhysicsObjectNum(phys_bone)
	
	local phys_self = self:GetPhysicsObject()
	if IsValid(phys_self) then
		if IsValid(self:GetParent()) then
			self:PhysicsDestroy()
			self:SetNotSolid(true)
		else
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			self:EnableCustomCollisions(true)
			self:SetCustomCollisionCheck(true)
			phys_self:SetVelocity(phys:GetVelocity())
			phys_self:AddAngleVelocity(phys:GetAngleVelocity())
			phys_self:SetMaterial("watermelon")
			self.GS2_dummy = false
		end
	end
end

function ENT:OnTakeDamage(dmginfo)
	if !self.GS2_dummy then		
		dmginfo:SetDamageForce(dmginfo:GetDamageForce() / self:GetPhysicsObject():GetMass())
		self:TakePhysicsDamage(dmginfo)
	end
end

function ENT:PhysicsCollide(data, phys)
	if (CurTime() - self.Created < 1) then
		return
	end
	if (data.Speed > 1000) then
		local EF = EffectData()
		EF:SetOrigin(self:LocalToWorld(self:OBBCenter()))
		util.Effect("BloodImpact", EF)
		for _, child in ipairs(self:GetChildren()) do
			if child.GS2_dummy then
				EF:SetOrigin(child:LocalToWorld(child:OBBCenter()))
				util.Effect("BloodImpact", EF)
			end
		end
		self:Remove()
	end
end

local VERT_CACHE = {}
local CONVEX_CACHE = {}

function ENT:IsTouching(other)
	local mdl = other:GetModel()
	local verts = VERT_CACHE[mdl]
	if !verts then
		VERT_CACHE[mdl] = {}
		verts = VERT_CACHE[mdl]
		local phys = other:GetPhysicsObject()
		for _, convex in ipairs(phys:GetMeshConvexes()) do
			for _, vert in pairs(convex) do
				if !table.HasValue(verts, vert.pos) then
					table.insert(verts, vert.pos)
				end
			end
		end
	end

	local body = self:GetBody()
	local mdl = body:GetModel()
	local phys_bone = self:GetTargetBone()
	local gib_index = self:GetGibIndex()

	CONVEX_CACHE[mdl] = CONVEX_CACHE[mdl] or {}
	CONVEX_CACHE[mdl][phys_bone] = CONVEX_CACHE[mdl][phys_bone] or {}
	if !CONVEX_CACHE[mdl][phys_bone][gib_index] then
		self:PhysicsInitConvex(self.GS2GibInfo.triangles)
		local phys = self:GetPhysicsObject()
		CONVEX_CACHE[mdl][phys_bone][gib_index] = phys:GetMeshConvexes()[1]
		self:PhysicsDestroy()
	end
	
	local convex = CONVEX_CACHE[mdl][phys_bone][gib_index]

	for _, vert in ipairs(verts) do
		local wpos = other:LocalToWorld(vert)
		local lpos = self:WorldToLocal(wpos)
		local is_inside = true
		for vert_index = 1, #convex - 2, 3 do
			local p1 = convex[vert_index].pos
			local p2 = convex[vert_index + 1].pos
			local p3 = convex[vert_index + 2].pos

			local n = (p3 - p1):Cross(p2 - p1)
			n:Normalize()
			local d = n:Dot(p1)				
			if (n:Dot(lpos) > d) then
				is_inside = false
				break
			end
		end
		if is_inside then
			return true
		end
	end
end

--models/props_debris/concrete_spawnplug001a.mdl