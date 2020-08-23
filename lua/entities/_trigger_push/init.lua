ENT.Type = "brush"
ENT.Base = "base_brush"

local PUSHED = {}

function ENT:Initialize()
	self:PhysicsInit(SOLID_BSP)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetTrigger(true)
	self:SetNotSolid(true)
end

function ENT:KeyValue(key, value)
	if (key == "pushdir") then
		self.PushDir = self:WorldToLocal(Vector(unpack(value:Split(" "))))
	elseif (key == "speed") then
		self.Speed = tonumber(value)
	end
end

function ENT:Think()
	self:NextThink(CurTime())
end

function ENT:Touch(other)
	local move_type = other:GetMoveType()

	if (!other:IsSolid() or move_type == MOVETYPE_PUSH or move_type == MOVETYPE_NONE) then
		return
	end

	if !self:PassesTriggerFilters(other) then
		return
	end

	if IsValid(other:GetMoveParent()) then
		return
	end

	local force = -self:LocalToWorld(self.PushDir * self.Speed)

	local phys = other:GetPhysicsObject()

	if (self:HasSpawnFlags(0x80)) then --SF_TRIG_PUSH_ONCE
		phys:SetAbsVelocity(force)

		if (force.z > 0) then
			other:SetGroundEntity(NULL)
		end
		self:Remove()
		return 
	end

	if (other:GetMoveType() == MOVETYPE_VPHYSICS) then
		if other:IsRagdoll() then
			local tr = self:GetTouchTrace()
			for phys_bone = 0, other:GetPhysicsObjectCount() - 1 do				
				local phys = other:GetPhysicsObjectNum(phys_bone)
				local lpos = phys:WorldToLocal(tr.HitPos)
				if lpos:WithinAABox(phys:GetAABB()) then
					phys:ApplyForceCenter(force * phys:GetMass() * FrameTime())					
				end
			end
		else
			phys:ApplyForceCenter(force * 100 * FrameTime())
		end		
	end
end