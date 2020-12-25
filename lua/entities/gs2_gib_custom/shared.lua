ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.LifeTime = CreateConVar("gs2_gib_lifetime", 30) --after not moving for this amount of time the gib will fade away

game.AddDecal("BloodSmall", {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
})

local decals = {
	[BLOOD_COLOR_RED] = "BloodSmall",
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
						util.Decal(decal, data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
						util.Decal(decal, data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
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
				util.Decal(decal, data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
				util.Decal(decal, data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
			end
		end
	end
end