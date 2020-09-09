include("gibsplat2/gibs.lua")

ENT.Type = "anim"
ENT.Base = "base_anim"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "GibIndex")
	self:NetworkVar("Int", 1, "TargetBone")
	self:NetworkVar("Entity", 0, "Body")
end