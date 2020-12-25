local ent = ents.FindByClass("prop_ragdoll")[1]

local mdl = ent:GetModel()

local temp = ClientsideRagdoll(mdl)
local phys = temp:GetPhysicsObjectNum(10)

local convexes = phys:GetMeshConvexes()
temp:Remove()

local meshes = {}

for _, convex in pairs(convexes) do
	local center = Vector(0,0,0)
	local count = 0
	for _, vert in pairs(convex) do
		if !vert.checked then
			vert.checked = true
			center:Add(vert.pos)
			count = count + 1
		end
	end
	center:Div(count)
	for _, vert in pairs(convex) do
		if vert.checked then
			vert.checked = nil
			--vert.pos = center + (vert.pos - center) * 0.85
		end
	end
	local m = Mesh()
	m:BuildFromTriangles(convex)
	table.insert(meshes, m)	
end
PrintTable(meshes)
local bone = ent:LookupBone("ValveBiped.Bip01_Head1")

local mat = Material("models/flesh")

local matrix = ent:GetBoneMatrix(bone)

hook.Add("PostDrawOpaqueRenderables","h",function()
	if !IsValid(ent) then return end
	render.SetMaterial(mat)
	
	cam.PushModelMatrix(matrix)
		for _, mesh in pairs(meshes) do		
			mesh:Draw()		
		end
	cam.PopModelMatrix()
end)