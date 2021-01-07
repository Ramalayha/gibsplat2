--include("shared.lua")

ENT.Type = "filter"
ENT.Base = "base_filter"

function ENT:Initialize()
	
end

function ENT:PassesFilter(caller, ent)
	if ent.__gs2custom then	
		ent.collides = ent.collides or CreatePhysCollidesFromModel(ent:GetModel())

		local pos = caller:GetPos()
		local min, max = caller:GetCollisionBounds()

		local touching = {}

		for phys_bone = 0, ent:GetPhysicsObjectCount() - 1 do
			local phys = ent:GetPhysicsObjectNum(phys_bone)
			if (IsValid(ent.collides[phys_bone + 1]) and ent.collides[phys_bone + 1]:TraceBox(phys:GetPos(), phys:GetAngles(), pos, pos, min, max)) then
				table.insert(touching, phys)
			end
		end
		
		if (#touching == 0) then
			return false
		end

		if (caller:GetClass() == "trigger_push") then
			local dir = caller:GetInternalVariable("m_vecPushDir")
			dir:Rotate(caller:GetAngles())
			local speed = caller:GetInternalVariable("speed")
			for _, touch_phys in ipairs(touching) do
				touch_phys:ApplyForceCenter(dir * speed * 100 * FrameTime())
			end
			return false
		end
	end
end