ENT.Type = "anim"
ENT.Base = "base_anim"
 
function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Body")
	self:NetworkVar("Int", 0, "TargetBone")
	self:NetworkVar("Vector", 0, "LPos")
	self:NetworkVar("Angle", 0, "LAng")
end