AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

util.AddNetworkString(ENT.NetMsg)

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

	self:SetUseType(SIMPLE_USE)
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

function ENT:Use(ply)
	local hp = ply:Health()
	local max = ply:GetMaxHealth()
	if (hp < max) then
		local heal = #self:GetChildren() + 1
		ply:SetHealth(math.min(hp + heal, max))
		self:EmitSound("npc/barnacle/barnacle_crunch3.wav")
		self:Remove()
	end
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