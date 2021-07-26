include("shared.lua")

function ENT:Initialize()
	local ent = self.Target

	local phys1 = ent:GetPhysicsObjectNum(self.PhysBone1)
	local phys2 = ent:GetPhysicsObjectNum(self.PhysBone2)

	self.Offset = phys1:WorldToLocal(phys2:GetPos())

	self:StartMotionController()
	self:AddToMotionController(phys1)
	self:AddToMotionController(phys2)

	self:SetParent(ent)
end

function ENT:SetTarget(ent)
	self.Target = ent
end

function ENT:SetForceLimit(limit)
	self.ForceLimit = limit
end

function ENT:SetTorqueLimit(limit)
	self.TorqueLimit = limit
end

function ENT:SetPhysBones(phys_bonep, phys_bonec)
	self.PhysBone1 = phys_bonep
	self.PhysBone2 = phys_bonec
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:OnRemove()
	local ent = self.Target

	if !IsValid(ent) then return end

	ent:RemoveInternalConstraint(self.PhysBone2)
end

function ENT:PhysicsSimulate()
	local ent = self.Target

	if !IsValid(ent) then return end

	local phys1 = ent:GetPhysicsObjectNum(self.PhysBone1)
	local phys2 = ent:GetPhysicsObjectNum(self.PhysBone2)

	local vel1 = phys1:GetVelocityAtPoint(phys1:LocalToWorld(self.Offset))
	local vel2 = phys2:GetVelocity()
	
	if (vel1:DistToSqr(vel2) * phys2:GetMass() > self.ForceLimit^2) then
		self:Remove()
		return
	end

	local angvel1 = phys1:GetAngleVelocity()
	local angvel2 = phys2:GetAngleVelocity()

	if (angvel1:DistToSqr(angvel2) * phys2:GetMass() > self.TorqueLimit^2) then
		self:Remove()
		return
	end
end