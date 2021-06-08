if e:EntIndex() == -1 then e:Remove() end
e = ClientsideModel("models/combine_soldier.mdl")
e:SetNoDraw(true)

e = ents.FindByClass("prop_ragdoll")[1]

--mat = Material(util.DecalMaterial("Blood"))
mat = Material("models/debug/debugwhite")

local size = 0.1

util.DecalEx(mat, e, Vector(20, 20, 50), Vector(1, 1, 0), color_white, size, size)
util.DecalEx(mat, e, Vector(20, -20, 50), Vector(1, -1, 0), color_white, size, size)
util.DecalEx(mat, e, Vector(0, 0, 100), Vector(0, 0, 1), color_white, size, size)

SafeRemoveEntity(e2)
e2 = ClientsideModel("models/kleiner.mdl")
e2:SetNoDraw(true)
--e2:SetParent(e)
e2:AddEffects(EF_BONEMERGE)

SafeRemoveEntity(f)
f = ClientsideModel("models/infected/common_infected_w_torso_slash.mdl")
f:SetNoDraw(true)
f:AddEffects(EF_BONEMERGE)

local mat = Material("models/flesh")

hook.Add("PreDrawOpaqueRenderables", "h", function()
	local e = ents.FindByClass("prop_ragdoll")[1]
	if !IsValid(e) then
		return
	end 
	render.OverrideColorWriteEnable(true, false)
	e2:SetModel(e:GetModel())
	e2:SetParent(e)
	f:SetParent(e)
	f:SetupBones()

	e:SetNoDraw(true)
	e:SetupBones()
	
	e2:SetupBones()
	e2:DrawModel()

	render.SetStencilEnable(true)
	render.ClearStencil()

	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_INCR)
	render.SetStencilZFailOperation(STENCIL_KEEP)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilWriteMask(1)
	render.SetStencilReferenceValue(1)

	e:DrawModel()

	render.SetStencilPassOperation(STENCIL_DECR)
	
	e:DrawModel()
	render.OverrideColorWriteEnable(false)

	render.SetStencilCompareFunction(STENCIL_LESSEQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	render.SetStencilWriteMask(0)
	render.SetStencilTestMask(1)
	render.SetStencilReferenceValue(1)

	render.ClearBuffersObeyStencil(0, 0, 0, 0, true)

	render.MaterialOverride(mat)
	render.CullMode(MATERIAL_CULLMODE_CW)
	e2:DrawModel()
	render.CullMode(MATERIAL_CULLMODE_CCW)
	render.MaterialOverride()
	f:DrawModel()

	render.SetStencilCompareFunction(STENCIL_GREATER)
	e2:DrawModel()

	render.SetStencilEnable(false)
end)