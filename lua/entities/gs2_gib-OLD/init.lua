AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self.Created = CurTime()
	self:DrawShadow(false)
	self:SetBodyModel(self:GetBody():GetModel())
	if !self.GS2_merge then
		local mesh, min, max = self:GetMesh()
		if self.AdditionalMeshes then
			table.insert(self.AdditionalMeshes, mesh)
			self:PhysicsInitMultiConvex(self.AdditionalMeshes)
		else
			self:PhysicsInitConvex(mesh)
		end
		
		local self_phys = self:GetPhysicsObject()

		local self_min, self_max = self_phys:GetAABB()

		if (self_min:DistToSqr(self_max) > min:DistToSqr(max)) then
			self:Remove()
			return
		end

		--self:PhysicsInit(SOLID_VPHYSICS)
		self:EnableCustomCollisions(true)
		self:SetCustomCollisionCheck(true)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		--self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		
		self_phys:SetMaterial("watermelon")
		self_phys:Wake()	
		self_phys:SetDragCoefficient(0.3)	
		self_phys:SetAngleDragCoefficient(0.3)
	end
end

function ENT:DoMerge()
	if self.GS2_merge then
		self.GS2_dummy = true			
		self:SetParent(self.GS2_merge)
		return true
	end
end

function ENT:AddMerge(gib)
	if (gib:GetClass() == "gs2_gib_custom") then
		gib.GS2_merge = self
		return
	end
	self.AdditionalMeshes = self.AdditionalMeshes or {}
	if gib.AdditionalMeshes then
		for _, mesh in pairs(gib.AdditionalMeshes) do
			local new_mesh = {}
			for index, vert in pairs(mesh) do
				local wpos = gib:LocalToWorld(vert)
				local lpos = self:WorldToLocal(wpos)
				new_mesh[index] = vert
			end
			table.insert(self.AdditionalMeshes, new_mesh)
		end
	end
	local mesh = gib:GetMesh()
	local new_mesh = {}
	for index, vert in pairs(mesh) do
		local wpos = gib:LocalToWorld(vert)
		local lpos = self:WorldToLocal(wpos)
		new_mesh[index] = vert
	end
	table.insert(self.AdditionalMeshes, new_mesh)
	gib.GS2_merge = self
	
	local lpos, lang = WorldToLocal(gib:GetPos(), gib:GetAngles(), self:GetPos(), self:GetAngles())

	gib.GS2_lpos = lpos
	gib.GS2_lang = lang
end

function ENT:Think()
	local body = self:GetBody()
	if (!IsValid(body) and !self.__mat) then
		self:Remove()
		return
	end
	self.__mat = self:GetBody():GetNWString("GS2PhysMat")
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
		EF:SetOrigin(self:GetPos())
		util.Effect("BloodImpact", EF)
		self:Remove()
	end
end

--models/props_debris/concrete_spawnplug001a.mdl