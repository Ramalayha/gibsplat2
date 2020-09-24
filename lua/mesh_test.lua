local mdl = "models/hunter.mdl"

SafeRemoveEntity(e)

e = ClientsideModel(mdl)

e:ResetSequence(-2)
e:SetCycle(0)
e:SetPlaybackRate(0)

e:SetupBones()
for i=0,e:GetBoneCount()-1 do
	--print(e:GetBoneName(i), e:GetBonePosition(i))
end

for pose_param = 0, e:GetNumPoseParameters() - 1 do
	print(e:GetPoseParameterName(pose_param))
end

local a = Angle(0,0,0)
a:RotateAroundAxis(e:GetUp(), -90)
--local p,a = e:GetBonePosition(0)
--a:RotateAroundAxis(a:Right(), 180)
--a:RotateAroundAxis(a:Forward(), -90)
print(a)
--e:SetPos(-p)
--e:SetAngles(a)
e:SetupBones()

local meshes = util.GetModelMeshes(mdl)

local M = {}

for k,v in pairs(meshes) do
	local m = Mesh()
	m:BuildFromTriangles(v.triangles)
	table.insert(M, {Material(v.material),m})
end

hook.Add("PostDrawOpaqueRenderables","h",function()
	for k,v in pairs(M) do
		render.SetMaterial(v[1])
		v[2]:Draw()
	end
end)