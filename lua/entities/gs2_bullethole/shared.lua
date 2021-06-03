ENT.Type = "anim"
ENT.Base = "base_anim"
 
game.AddDecal("Impact.Flesh2", {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
})
 
function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Body")
	self:NetworkVar("Int", 0, "TargetBone")
	self:NetworkVar("Vector", 0, "LPos")
	self:NetworkVar("Angle", 0, "LAng")
end