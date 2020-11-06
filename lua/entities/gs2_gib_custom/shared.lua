ENT.Type = "anim"
ENT.Base = "base_anim"

function ENT:PhysicsCollide(data, phys)
	if (data.Speed > 100) then
		util.Decal("BloodSmall", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
		util.Decal("BloodSmall", data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
	end
	
	if CLIENT then return end

	if ((phys:GetEnergy() == 0 and data.HitEntity:GetMoveType() == MOVETYPE_PUSH) or (data.Speed > 1000 and CurTime() - self.Created < 1)) then --0 energy = jammed in something
		self:Remove()
	end
end