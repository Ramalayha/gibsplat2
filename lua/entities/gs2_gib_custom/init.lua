AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self.Created = CurTime()
	if !self.GS2_merge then
		local mesh = self:GetMesh()
		if self.AdditionalMeshes then
			table.insert(self.AdditionalMeshes, mesh)
			self:PhysicsInitMultiConvex(self.AdditionalMeshes)
		else
			self:PhysicsInitConvex(mesh)
		end
		
		self:EnableCustomCollisions(true)
		self:SetCustomCollisionCheck(true)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		--self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		
		local self_phys = self:GetPhysicsObject()

		self_phys:SetMaterial("watermelon")
		self_phys:Wake()	
		self_phys:SetDragCoefficient(0.3)	
		self_phys:SetAngleDragCoefficient(0.3)
	end
end

function ENT:GetMesh()
	if self.PhysMesh then
		return self.PhysMesh
	end
	
	local phys = self:GetPhysicsObject()
	if !IsValid(phys) then
		self:PhysicsInit(SOLID_VPHYSICS)
		phys = self:GetPhysicsObject()
	end

	local memes = {}
	local mesh = phys:GetMeshConvexes()[1]
	for _, vert in pairs(mesh) do
		memes[vert.pos] = true
	end
	table.Empty(mesh)
	for vert in pairs(memes) do
		table.insert(mesh, vert)
	end
	self.PhysMesh = mesh
	return mesh
end

function ENT:DoMerge()
	if self.GS2_merge then
		self.GS2_dummy = true			
		self:SetParent(self.GS2_merge)
		self:PhysicsDestroy()
		return true
	end
end

function ENT:AddMerge(gib)
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