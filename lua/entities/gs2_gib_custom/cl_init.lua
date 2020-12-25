include("shared.lua")

function ENT:Initialize()
	self.Created = CurTime()
	if (self:EntIndex() == -1) then
		self:PhysicsInit(SOLID_VPHYSICS)
		
		self:EnableCustomCollisions(true)
		self:SetCustomCollisionCheck(true)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		--self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		
		local self_phys = self:GetPhysicsObject()

		self_phys:SetMaterial("watermelon")
		self_phys:Wake()	
		self_phys:SetDragCoefficient(0.3)	
		self_phys:SetAngleDragCoefficient(0.3)

		self:StartMotionController()
	end
end

function ENT:Draw()
	self:DrawModel()
	if (self:EntIndex() == -1 and self.LastSim and self.LastSim + self.LifeTime:GetFloat() < CurTime()) then
		SafeRemoveEntityDelayed(self, 0)
	end
end