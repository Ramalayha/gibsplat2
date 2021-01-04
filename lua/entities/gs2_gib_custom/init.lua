AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local text = file.Read("materials/gibsplat2/gibs.vmt", "GAME")

local gib_info = util.KeyValuesToTable(text or "")

for _, data in pairs(gib_info) do
	for _, data in pairs(data) do
		for _, data in pairs(data) do
			util.PrecacheModel(data.model)
		end
	end
end

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

	self:StartMotionController()
end

function ENT:Think()
	if (self.LastSim and self.LastSim + self.LifeTime:GetFloat() < CurTime()) then
		self:Remove()
	end
end

function ENT:OnTakeDamage(dmginfo)
	local phys = self:GetPhysicsObject()
	if (!self.GS2_dummy and IsValid(phys)) then
		dmginfo:SetDamageForce(dmginfo:GetDamageForce() / phys:GetMass())
		self:TakePhysicsDamage(dmginfo)
	end
end

function ENT:OnRemove()
	local EF = EffectData()
	EF:SetOrigin(self:LocalToWorld(self:OBBCenter()))
	util.Effect("BloodImpact", EF)
end