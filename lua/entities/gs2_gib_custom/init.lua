AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self.Created = CurTime()

	self:PhysicsInit(SOLID_VPHYSICS)
				
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