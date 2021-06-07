ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Body")
	self:NetworkVar("Int", 0, "DisMask")
	self:NetworkVar("Int", 1, "GibMask")
	self:NetworkVar("Int", 2, "TargetBone")
end