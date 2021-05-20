function Tesselate(mesh)
	for k, vert in pairs(mesh) do
		for k2, vert2 in pairs(mesh) do
			if (vert != vert2 and vert.pos:IsEqualTol(vert2.pos,0)) then
				mesh[k2] = vert
			end
		end
	end
	local new_mesh = {}
	for vert_index = 1, #mesh - 2, 3 do
		local v1 = mesh[vert_index]
		local v2 = mesh[vert_index + 1]
		local v3 = mesh[vert_index + 2]
		
		v1.new = false
		v2.new = false
		v3.new = false

		local v12 = {pos = (v1.pos + v2.pos) * 0.375, new = true, extra = v3}
		local v23 = {pos = (v2.pos + v3.pos) * 0.375, new = true, extra = v1}
		local v13 = {pos = (v1.pos + v3.pos) * 0.375, new = true, extra = v2}

		table.insert(new_mesh, v1)
		table.insert(new_mesh, v12)
		table.insert(new_mesh, v13)

		table.insert(new_mesh, v12)
		table.insert(new_mesh, v2)
		table.insert(new_mesh, v23)

		table.insert(new_mesh, v23)
		table.insert(new_mesh, v3)
		table.insert(new_mesh, v13)

		table.insert(new_mesh, v12)
		table.insert(new_mesh, v23)
		table.insert(new_mesh, v13)
	end

	local verts = {}

	for key, vert in pairs(new_mesh) do		
		local exists = false
		
		for _, vert2 in pairs(verts) do
			if (vert != vert2 and vert.pos:IsEqualTol(vert2.pos, 0)) then
				new_mesh[key] = vert2	
				vert2.extra2 = vert.extra			
				exists = true
				break
			end
		end
		
		if !exists then			
			table.insert(verts, vert)
		end
	end

	for _, vert in pairs(verts) do
		if vert.new then
			vert.pos:Add(vert.extra.pos * 1 / 16)
			vert.pos:Add(vert.extra2.pos * 1 / 16)
		end
	end

	for _, vert in pairs(verts) do
		if !vert.new then			
			local points = {}
			for vert_index = 1, #new_mesh - 2, 3 do
				for offset = 0, 2 do
					local v1 = new_mesh[vert_index + offset]
					if (v1 == vert) then
						local v2 = new_mesh[vert_index + (offset + 1) % 2]
						local v3 = new_mesh[vert_index + (offset + 2) % 2]
						points[v2] = true
						points[v3] = true
					end
				end
			end
			local n = table.Count(points)
						
			local B = 3 / (8 * n)
			
			local p = Vector(0, 0, 0)
			for p0 in pairs(points) do
				p:Add(p0.pos * B)				
			end

			local norm = p:GetNormal()

			for p0 in pairs(points) do
				p0.normal = norm			
			end

			vert.normal = norm

			vert.pos = vert.pos * (1 - B * n) + p
		end
		vert.u = vert.pos.x
		vert.v = vert.pos.y + vert.pos.z
	end

	return new_mesh
end

local tr = Entity(1):GetEyeTrace()

pos = pos or tr.HitPos + tr.HitNormal * 100

local temp = ents.CreateClientProp("models/props_junk/watermelon01_chunk01b.mdl")

local phys = temp:GetPhysicsObject()

local convex = phys:GetMeshConvexes()[1]

local mass_center = phys:GetMassCenter()

temp:Remove()

local verts = {}

for k,v in pairs(convex) do
	verts[v] = true
	v.norm = Vector(0, 0, 0)
	for k2, v2 in pairs(convex) do
		if v != v2 and v.pos:IsEqualTol(v2.pos, 0) then
			convex[k2] = v
		end
	end
end

for i = 1, 0 do
	convex = Tesselate(convex)
end

local M = Mesh()
M:BuildFromTriangles(convex)

local mat = Material("models/wireframe")
--local mat = Material("models/flesh")

local matrix = Matrix()
matrix:Translate(pos)
matrix:Scale(Vector(1, 1, 1) * 10)

hook.Add("PostDrawOpaqueRenderables", "h", function()
	cam.PushModelMatrix(matrix)
	render.SetMaterial(mat)
	M:Draw()
	cam.PopModelMatrix()
end)