AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

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
<<<<<<< HEAD

	self.Created = CurTime()
=======
>>>>>>> 6576c1780fdf7503385bdb98f0fef873d98c6ca6
end

function ENT:InitPhysics()
	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	local phys = body:GetPhysicsObjectNum(phys_bone)
<<<<<<< HEAD
=======

	--self:PhysicsInitConvex(self.GS2GibInfo.triangles)
>>>>>>> 6576c1780fdf7503385bdb98f0fef873d98c6ca6
	
	local phys_self = self:GetPhysicsObject()
	if IsValid(phys_self) then	
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
<<<<<<< HEAD
		self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
=======
>>>>>>> 6576c1780fdf7503385bdb98f0fef873d98c6ca6
		self:EnableCustomCollisions(true)
		phys_self:SetVelocity(phys:GetVelocity())
		phys_self:AddAngleVelocity(phys:GetAngleVelocity())
		self.GS2_dummy = false
<<<<<<< HEAD
=======
	end

	for _, child in ipairs(self:GetChildren()) do
		--child:InitPhysics()
>>>>>>> 6576c1780fdf7503385bdb98f0fef873d98c6ca6
	end
end

function ENT:OnTakeDamage(dmginfo)
	if !self.GS2_dummy then		
		dmginfo:SetDamageForce(dmginfo:GetDamageForce() / self:GetPhysicsObject():GetMass())
		self:TakePhysicsDamage(dmginfo)
	end
end

function ENT:PhysicsCollide(data, phys)
	if (data.Speed > 1000) then
		local EF = EffectData()
		EF:SetOrigin(self:GetPos())
		util.Effect("BloodImpact", EF)
		self:Remove()
	end
end

--models/props_debris/concrete_spawnplug001a.mdl