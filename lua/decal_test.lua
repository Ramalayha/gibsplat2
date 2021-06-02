_decals = _decals or {}

local dec = util.DecalMaterial("Blood")

_decals[dec] = _decals[dec] or Material(dec)

dec = _decals[dec]

SafeRemoveEntity(e)
e = ClientsideModel("models/Gibs/HGIBS.mdl")
e:SetColor(Color(255, 255, 255, 50))
for k,v in pairs(ents.FindByClass("gs2_limb_mesh")) do
	--v.Mesh = v.meshes.body
	local p = v:GetPos() + Vector(0,0,7)
	e:SetPos(p)
	e:SetupBones()
	e:SetNoDraw(true)
	util.DecalEx(dec, v, p, Vector(0,0,1), color_white, 1, 1)
end