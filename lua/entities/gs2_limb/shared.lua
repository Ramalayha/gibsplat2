ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_OPAQUE

game.AddDecal("BloodSimple", {
	"decals/blood1",
	"decals/blood2",
	"decals/blood3",
	"decals/blood4",
	"decals/blood5",
	"decals/blood6"
})

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Body")
	self:NetworkVar("Int", 0, "DisMask")
	self:NetworkVar("Int", 1, "GibMask")
	self:NetworkVar("Int", 2, "TargetBone")
end