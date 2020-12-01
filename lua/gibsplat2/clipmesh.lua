local function SafeYield()
	if coroutine.running() then
		coroutine.yield()
	end
end

local function LinePlaneIntersect(pl, dl, n, d)
	local t = (d - n:Dot(pl)) / n:Dot(dl)

	return pl + dl * t
end

function ClipMesh(mesh, n, d)
	local new_tris = {}

	for i = 1, #mesh - 2, 3 do
		local v1 = mesh[i]
		local v2 = mesh[i + 1]
		local v3 = mesh[i + 2]

		local p1 = v1.pos
		local p2 = v2.pos
		local p3 = v3.pos

		local d1 = n:Dot(p1)
		local d2 = n:Dot(p2)
		local d3 = n:Dot(p3)

		local p1p2 = LinePlaneIntersect(p1, (p2 - p1):GetNormal(), n, d)
		local p1p3 = LinePlaneIntersect(p1, (p3 - p1):GetNormal(), n, d)
		local p2p3 = LinePlaneIntersect(p2, (p3 - p2):GetNormal(), n, d)


		if (d1 < d) then
			if (d2 < d) then
				if (d3 < d) then
					table.insert(new_tris, p1)
					table.insert(new_tris, p2)
					table.insert(new_tris, p3)
				else
					table.insert(new_tris, p2p3)
					table.insert(new_tris, p1p3)
					table.insert(new_tris, p1)

					table.insert(new_tris, p1)
					table.insert(new_tris, p2)
					table.insert(new_tris, p2p3)
				end
			else
				if (d3 < d) then
					table.insert(new_tris, p1)
					table.insert(new_tris, p1p2)
					table.insert(new_tris, p2p3)

					table.insert(new_tris, p2p3)
					table.insert(new_tris, p3)
					table.insert(new_tris, p1)
				else					
					table.insert(new_tris, p1)
					table.insert(new_tris, p1p2)
					table.insert(new_tris, p1p3)
				end
			end
		else
			if (d2 < d) then
				if (d3 < d) then
					table.insert(new_tris, p3)
					table.insert(new_tris, p1p3)
					table.insert(new_tris, p1p2)

					table.insert(new_tris, p1p2)
					table.insert(new_tris, p2)
					table.insert(new_tris, p3)
				else
					table.insert(new_tris, p2)
					table.insert(new_tris, p2p3)
					table.insert(new_tris, p1p2)
				end
			else
				if (d3 < d) then
					table.insert(new_tris, p3)
					table.insert(new_tris, p1p3)
					table.insert(new_tris, p2p3)
				else
					p1 = p1 - n * (d1 - d)
					p2 = p2 - n * (d2 - d)
					p3 = p3 - n * (d3 - d)

					--table.insert(new_tris, p1)
					--table.insert(new_tris, p2)
					--table.insert(new_tris, p3)
				end
			end
		end
	end

	local temp = SERVER and ents.Create("prop_physics") or ents.CreateClientProp()
	temp:PhysicsInitConvex(new_tris)

	local phys = temp:GetPhysicsObject()

	if IsValid(phys) then
		new_tris = phys:GetMeshConvexes()[1]
	else
		new_tris = nil
	end

	temp:Remove()

	return new_tris
end

function VoronoiSplit(mesh, points)
	local new_meshes = {}

	for key = 1, #points - 1 do
		local p1 = points[key]
		local tris = mesh
		for key2 = key + 1, #points do
			local p2 = points[key2]				
			local n = (p2 - p1)
			n:Normalize()
			local d = n:Dot((p1 + p2) / 2)
			tris = ClipMesh(tris, n, d)
			if (key2 % 3 == 0) then
				SafeYield()
			end
			if !tris then
				break
			end			
		end
		if tris then
			new_meshes[key] = tris
		end
	end

	local conns = {}

	for key, p1 in ipairs(points) do
		local tris = new_meshes[key]
		if tris then
			conns[key] = {}
			for key2, p2 in ipairs(points) do
				if (p1 != p2) then
					local n = (p2 - p1)
					n:Normalize()

					for vert_index = 1, #tris - 2, 3 do
						local v1 = tris[vert_index]
						local v2 = tris[vert_index + 1]
						local v3 = tris[vert_index + 2]

						local n2 = (v3.pos - v1.pos):Cross(v2.pos - v1.pos)
						n2:Normalize()

						if n:IsEqualTol(n2, 0.0001) then
							table.insert(conns[key], key2)
						end
					end
				end	
			end
		end
	end

	local temp = SERVER and ents.Create("prop_physics") or ents.CreateClientProp()

	for key, mesh in pairs(new_meshes) do
		for key2, vert in ipairs(mesh) do
			mesh[key2] = vert.pos
		end
		temp:PhysicsInitConvex(mesh)
		local phys = temp:GetPhysicsObject()
		local min, max 	= phys:GetAABB()
		new_meshes[key] = {
			triangles 	= phys:GetMeshConvexes()[1], 
			center 		= temp:OBBCenter(),
			min 		= min,
			max 		= max,
			conns 		= conns[key]
		}
	end

	temp:Remove()

	return new_meshes
end