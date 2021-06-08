include("shared.lua")

local gib_chance = GetConVar("gs2_gib_chance")
local multiplier = GetConVar("gs2_gib_chance_explosion_multiplier")

function ENT:Initialize()
	local ent = self.TargetEntity
	local phys_bone = self.TargetPhysBone

	local phys = ent:GetPhysicsObjectNum(phys_bone)
	self.TargetPhys = phys

	self:PhysicsInitBox(phys:GetAABB())

	self:SetNotSolid(true)
	self:SetMoveType(MOVETYPE_NONE)	
	self:SetCustomCollisionCheck(true)
	
	self:DrawShadow(false)

	self:Think() --update position
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

	if (!IsValid(ent) or ent:GS2IsGibbed(phys_bone)) then
		return self:Remove()
	end

	local phys = ent:GetPhysicsObjectNum(phys_bone)
	if phys:GetPos():Length() > 100000 then 
		print("UH OH",phys:GetPos())
	else
		self:SetPos(phys:GetPos())
		self:SetAngles(phys:GetAngles())
	end
end

function ENT:OnTakeDamage(dmginfo)
	if (dmginfo:IsExplosionDamage() or dmginfo:IsDamageType(DMG_SONIC)) then
		local infl = dmginfo:GetInflictor()		
		
		local dmgpos = dmginfo:GetDamagePosition()

		local mod = gib_chance:GetFloat()

		local radius = infl:GetInternalVariable("m_DmgRadius")

		if (infl:GetClass() == "rpg_missile") then
			radius = 100 --hard coded
		end

		if (radius and radius != 0) then			
			mod = math.max(0, 1 - dmgpos:Distance(self:GetPos()) / radius) ^ 2			
		end

		local ent = self.TargetEntity
		local phys_bone = self.TargetPhysBone
		
		local phys = ent:GetPhysicsObjectNum(phys_bone)

		local dmgforce = dmginfo:GetDamageForce()
		dmgforce:Div(ent:GetPhysicsObjectCount())

		phys:ApplyForceOffset(dmgforce, dmgpos)
		
		if (math.random() < 0.3) then
			local ent = self.TargetEntity

			local tr = {
				start = dmgpos,
				endpos = phys:GetPos()
			}

			tr = util.TraceLine(tr)

			if tr.Hit then
				net.Start("GS2ApplyDecal")
					net.WriteEntity(ent)
					net.WriteString(phys:GetMaterial())
					net.WriteVector(tr.HitPos)
					net.WriteVector(-tr.HitNormal)
				net.Broadcast()
			end
		end

		local chance = 1 - (1 - gib_chance:GetFloat()) / (multiplier:GetFloat() * mod)

		if (math.random() < chance) then
			ent:GS2Gib(phys_bone, false, true)
		end
	end
end

local function ShouldCollide(ent1, ent2)
	if (ent1:GetClass() == "gs2_limb_relay") then
		return ent2:GetClass():find("^trigger_")
	end
end