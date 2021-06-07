ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.LifeTime = GetConVar("gs2_gib_lifetime")

ENT.NetMsg = "GS2MakeDecal"

local decals = {
	[BLOOD_COLOR_RED] = "Blood",
	[BLOOD_COLOR_YELLOW] = "YellowBlood",
	[BLOOD_COLOR_GREEN] = "YellowBlood",
	[BLOOD_COLOR_ANTLION] = "YellowBlood",
	[BLOOD_COLOR_ANTLION_WORKER] = "YellowBlood"
}

function ENT:SetBColor(color)
	self.GS2BloodColor = color
end

function ENT:PhysicsSimulate()
	self.LastSim = CurTime()
end

function ENT:PhysicsCollide(data, phys_self)
	local speed = data.Speed
	if (self.Created and speed > 1000 and CurTime() - self.Created > 1) then
		self:Remove()
		return
	end
	if SERVER then
		if (!data.HitEntity:IsWorld() and !data.HitEntity:IsRagdoll() and (phys_self:GetEnergy() == 0 or phys_self:GetEnergy() > 10000)) then --0 energy = jammed in something
			if (math.random() > 0.6 or phys_self:GetPos():Distance(data.HitPos) > self:BoundingRadius() * 0.7) then
				self:Remove()
			else	
				local color = self.GS2BloodColor
				if color then
					local decal = decals[color]
					if decal then
						self:MakeDecal(decal, data.HitEntity, data.HitPos, data.HitNormal, self:BoundingRadius())						
					end
				end
				local phys = data.HitObject
				local lpos, lang = WorldToLocal(phys_self:GetPos(), phys_self:GetAngles(), phys:GetPos(), phys:GetAngles())
				timer.Simple(0, function()
					if (IsValid(self) and IsValid(phys)) then			
						self:SetNotSolid(true)
						self:PhysicsDestroy()
						local pos, ang = LocalToWorld(lpos, lang, phys:GetPos(), phys:GetAngles())
						self:SetPos(pos)
						self:SetAngles(ang)
						self:SetParent(data.HitEntity)									
					end
				end)			
			end
		end
	end

	if (data.DeltaTime < 0.05) then
		return
	end
	
	if (speed > 100) then
		local color = self.GS2BloodColor
		if color then
			local decal = decals[color]
			if decal then
				self:MakeDecal(decal, data.HitEntity, data.HitPos, data.HitNormal, self:BoundingRadius())						
			end
		end
	end
end