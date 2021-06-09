AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local lifetime      = GetConVar("gs2_gib_lifetime")

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

	SafeRemoveEntityDelayed(self, lifetime:GetFloat() * math.random(0.9, 1.1))
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

function ENT:MakeDecal(mat, ent, pos, norm, rad)
	net.Start(self.NetMsg)
		net.WriteEntity(self)		
		net.WriteEntity(ent)
		net.WriteString(mat)
		net.WriteVector(pos)
		net.WriteNormal(norm)
		net.WriteFloat(rad)
	net.Broadcast()
end