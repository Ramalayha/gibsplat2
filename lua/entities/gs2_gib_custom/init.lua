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
	if (data.Speed > 100) then
		util.Decal("BloodSmall", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
		util.Decal("BloodSmall", data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
	end
	
	if ((phys:GetEnergy() == 0 and data.HitEntity:GetMoveType() == MOVETYPE_PUSH) or (data.Speed > 1000 and CurTime() - self.Created < 1)) then --0 energy = jammed in something
		self:Remove()
	end
end

function ENT:OnRemove()
	local EF = EffectData()
	EF:SetOrigin(self:LocalToWorld(self:OBBCenter()))
	util.Effect("BloodImpact", EF)
end