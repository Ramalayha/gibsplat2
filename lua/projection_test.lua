include("gibsplat2/decal_util.lua")

--local _mesh = util.GetModelMeshes("models/props_junk/cardboard_box001a.mdl")[1]
--local _mesh = util.GetModelMeshes("models/Combine_Helicopter/helicopter_bomb01.mdl")[1]
local _mesh = util.GetModelMeshes("models/kleiner.mdl")[4]

local M = Mesh()
M:BuildFromTriangles(_mesh.triangles)

local mat = Material("models/kleiner/walter_face")
local mat2 = Material("decals/flesh/blood1")
--local mat2 = Material("models/debug/debugwhite")

local proj_pos = Vector(0,-1,3.2) * 20
local proj_norm = Vector(0,1,0):GetNormal()
local proj_ang = proj_norm:Angle()

local size = 1

local M2 = GetDecalMesh(_mesh.triangles, proj_pos, proj_norm:Angle(), size, size)

size = size * 2

hook.Add("PostDrawOpaqueRenderables", "h", function()
	render.SetMaterial(mat)
	M:Draw()

	render.SetMaterial(mat2)

	mesh.Begin(MATERIAL_QUADS, 2)
	mesh.QuadEasy(proj_pos, proj_norm, size, size)
	mesh.QuadEasy(proj_pos, -proj_norm, size, size)
	mesh.End()
	
	M2:Draw()	
end)