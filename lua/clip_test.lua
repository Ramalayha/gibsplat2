include("clipmesh.lua")

local mdl = "models/props_c17/oildrum001.mdl"

local e = ents.CreateClientProp(mdl)
e:Spawn()
e:PhysicsInit(SOLID_VPHYSICS)

local center = e:OBBCenter()

local size = e:OBBMaxs() - e:OBBMins()

local phys = e:GetPhysicsObject()

local convex = phys:GetMeshConvexes()[1]

e:Remove()

local points = {}

for i = 1, 25 do
	table.insert(points, center + AngleRand():Forward() * size * math.random())
end

local meshes = VoronoiSplit(convex, points)

local n = AngleRand():Forward()
local p = Vector(0,0,30)

local n2 = AngleRand():Forward()

--local meshes = {ClipMesh(ClipMesh(convex, n, n:Dot(p) + math.random(1, 10)), n2, n2:Dot(p) + math.random(1,10))}

for key, mesh in ipairs(meshes) do
	for _, vert in pairs(mesh[1]) do
		vert.normal = (vert.pos - center):GetNormal()
		vert.u = vert.pos.x / size.x + vert.pos.z / size.z
		vert.v = vert.pos.y / size.y + vert.pos.z / size.z
	end
	local m = Mesh()
	m:BuildFromTriangles(mesh[1])
	meshes[key] = {m,(mesh[2] - center):GetNormal()}
end

local m = file.Find("materials/*.vmt", "GAME")
local mats = {}
for key in pairs(m) do
	mats[key] = Material("models/flesh")
	--mats[key] = Material(m[math.random(1,#m)]:sub(1, -5))
end

local matrix = Matrix()

hook.Add("PostDrawOpaqueRenderables","h",function()
	for key, mesh in pairs(meshes) do
		render.SetMaterial(mats[key])

		matrix:Identity()
		matrix:Translate(mesh[2] * 10)

		cam.PushModelMatrix(matrix)
			mesh[1]:Draw()
		cam.PopModelMatrix()
	end
end)