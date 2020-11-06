AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

game.AddDecal("BloodSmall", {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
})

game.AddDecal("YellowBloodSmall", {
	"decals/alienflesh/shot1",
	"decals/alienflesh/shot2",
	"decals/alienflesh/shot3",
	"decals/alienflesh/shot4",
	"decals/alienflesh/shot5"
})

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

function ENT:OnTakeDamage(dmginfo)
	if !self.GS2_dummy then		
		dmginfo:SetDamageForce(dmginfo:GetDamageForce() / self:GetPhysicsObject():GetMass())
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