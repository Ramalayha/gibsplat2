include("clipmesh.lua")

local NUM_PARTS = 30

function PhysGib(mdl, phys_bone)
	math.randomseed(util.CRC(mdl) + phys_bone)

	local temp
	if SERVER then
		temp = ents.Create("prop_ragdoll")
		temp:SetModel(mdl)
		temp:Spawn()
	else
		temp = ClientsideRagdoll(mdl)
	end
	
	local phys = temp:GetPhysicsObjectNum(phys_bone)

	local convexes = phys:GetMeshConvexes()

	temp:Remove()

	local points = {}

	for _, convex in pairs(convexes) do
		for _, vert in pairs(convex) do
			table.insert(points, vert.pos)
		end
	end

	temp = SERVER and ents.Create("prop_physics") or ents.CreateClientProp()

	temp:PhysicsInitConvex(points)

	local convex = temp:GetPhysicsObject():GetMeshConvexes()[1]

	temp:Remove()

	local min, max = phys:GetAABB()
	local size = max - min

	local points = {}

	local LEFT = NUM_PARTS

	while (LEFT > 0) do
		local point = Vector()
		point.x = math.Rand(min.x, max.x)
		point.y = math.Rand(min.y, max.y)
		point.z = math.Rand(min.z, max.z)

		local is_inside = true

		for vert_index = 1, #convex - 2, 3 do
			local v1 = convex[vert_index]
			local v2 = convex[vert_index + 1]
			local v3 = convex[vert_index + 2]

			local p1 = v1.pos
			local p2 = v2.pos
			local p3 = v3.pos

			local n = (p3 - p1):Cross(p2 - p1)
			n:Normalize()

			local d = n:Dot(p1) * 0.9

			if (n:Dot(point) > d) then
				is_inside = false
				break
			end
		end
		
		if is_inside then
			table.insert(points, point)
			LEFT = LEFT - 1
		end
	end

	local meshes = VoronoiSplit(convex, points)

	if CLIENT then
		for key, mesh in pairs(meshes) do
			local center = mesh.center
			for _, vert in ipairs(mesh.triangles) do
				vert.normal = (vert.pos - center):GetNormal()
				vert.u = vert.pos.x / size.x + vert.pos.z / size.z
				vert.v = vert.pos.y / size.y + vert.pos.z / size.z
			end
			local M = Mesh()
			M:BuildFromTriangles(mesh.triangles)
			mesh.mesh = M
		end
	end
	
	return meshes
end

local e = Entity(1):GetEyeTrace().Entity

if e:IsWorld() then print"no" return end

local temp = e:IsRagdoll() and ClientsideRagdoll(e:GetModel()) or ents.CreateClientProp(e:GetModel())

local M = PhysGib(temp:GetModel(), 10)

temp:Remove()

local mat = Material("models/flesh")

local matrix = Matrix()

hook.Add("PostDrawOpaqueRenderables","h",function()	
	for _, mesh in pairs(M) do	
		render.SetMaterial(mat)	
		matrix:Identity()
		matrix:Translate(mesh.center)

		cam.PushModelMatrix(matrix)
			mesh.mesh:Draw()
		
			for _, key in pairs(mesh.conns) do
				local p = M[key].center
				--convex[key].mesh:Draw()
				for _, key2 in pairs(M[key].conns) do
					--convex[key2].mesh:Draw()
				end
				render.DrawLine(p, mesh.center)
			end
		cam.PopModelMatrix()
	end
end)