ENT.Type = "anim"
ENT.Base = "base_anim"

local gib_chance = CreateConVar("gs2_gib_chance", 0.3)

function ENT:Initialize()
	local ent = self.TargetEntity
	local phys_bone = self.TargetPhysBone

	local phys = ent:GetPhysicsObjectNum(phys_bone)

	self:PhysicsInitBox(phys:GetAABB())
	
	self:SetNotSolid(true)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetParent(ent) --Deletes us with ent

	self:DrawShadow(false)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:SetTarget(ent, phys_bone)
	self.TargetEntity = ent
	self.TargetPhysBone = phys_bone
end

function ENT:Think()
	local ent = self.TargetEntity
	local phys_bone = self.TargetPhysBone

	if ent:GS2IsGibbed(phys_bone) then
		return self:Remove()
	end

	local phys = ent:GetPhysicsObjectNum(phys_bone)

	self:SetPos(phys:GetPos())
	self:SetAngles(phys:GetAngles())
end

function ENT:OnTakeDamage(dmginfo)
	if (dmginfo:IsExplosionDamage() or dmginfo:IsDamageType(DMG_SONIC)) then
		local ent = self.TargetEntity
		local phys_bone = self.TargetPhysBone

		if math.random() < gib_chance:GetFloat() then
			ent:GS2Gib(phys_bone)
		else
			local phys = ent:GetPhysicsObjectNum(phys_bone)

			phys:ApplyForceOffset(dmginfo:GetDamageForce(), dmginfo:GetDamagePosition())
		end
	end
end