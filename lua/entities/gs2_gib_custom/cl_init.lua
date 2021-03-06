include("shared.lua")

local lifetime      = GetConVar("gs2_gib_lifetime")

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

		if !IsValid(self_phys) then
			self:Remove()
			return
		end

		self_phys:SetMaterial("watermelon")
		self_phys:Wake()	
		self_phys:SetDragCoefficient(0.3)	
		self_phys:SetAngleDragCoefficient(0.3)

		self:StartMotionController()

		SafeRemoveEntityDelayed(self, lifetime:GetFloat() * math.random(0.9, 1.1))
	end
end

function ENT:Draw()
	self:DrawModel()
end

function ENT:MakeDecal(mat, ent, pos, norm, rad)
	local size = rad / 10

	ApplyDecal(util.DecalMaterial(mat), ent, pos, -norm, size)
end