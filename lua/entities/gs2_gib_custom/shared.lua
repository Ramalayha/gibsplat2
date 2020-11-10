ENT.Type = "anim"
ENT.Base = "base_anim"

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

function ENT:PhysicsCollide(data, phys)
	if (data.Speed > 100) then
		local color = self.GS2BloodColor
		if color then
			local decal = decals[color]
			if decal then
				util.Decal(decal, data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
				util.Decal(decal, data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
			end
		end
	end
	
	if CLIENT then return end

	if ((phys:GetEnergy() == 0 and data.HitEntity:GetMoveType() == MOVETYPE_PUSH) or (data.Speed > 1000 and CurTime() - self.Created < 1)) then --0 energy = jammed in something
		self:Remove()
	end
end