ENT.Type = "anim"
ENT.Base = "base_anim"
 
function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Body")
end