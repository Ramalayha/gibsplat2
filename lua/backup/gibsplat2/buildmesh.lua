local vec_zero = Vector(0,0,0)
local ang_zero = Angle(0,0,0)

local mat_flesh = Material("models/flesh")

local CACHE = {}

function GetBoneMeshes(mdl, phys_bone)
	CACHE[mdl] = CACHE[mdl] or {}

	if CACHE[mdl][phys_bone] then
		return CACHE[mdl][phys_bone]
	end

	local temp = ClientsideModel(mdl)
	temp:SetAngles(Angle(0,-90,0)) --dunno why its turned -90 but i dont question it
	temp:SetupBones()
	temp:ResetSequence(temp:LookupSequence("ragdoll"))
	temp:SetCycle(0)
	temp:SetupBones()

	local bone = temp:TranslatePhysBoneToBone(phys_bone)
	local bone_pos, bone_ang = temp:GetBonePosition(bone)
	
	local new_meshes = {}

	local MESHES = util.GetModelMeshes(mdl)
	
	for _, MESH in pairs(MESHES) do
		for _, vert in pairs(MESH.verticies) do
			vert.pos = WorldToLocal(vert.pos, ang_zero, bone_pos, bone_ang)
		end
		local new_tris = {}
		local TRIS = MESH.triangles
		for tri_idx = 1, #TRIS-2, 3 do
			local is_strong = true
			for offset = 0, 2 do
				local vert = TRIS[tri_idx + offset]
				for _, weight in pairs(vert.weights) do
					if temp:TranslateBoneToPhysBone(weight.bone) != phys_bone then
						is_strong = false
						break
					end
				end
				if !is_strong then
					break
				end
			end
			if is_strong then
				for offset = 0, 2 do
					local vert = TRIS[tri_idx + offset]
					vert.is_strong = true
					table.insert(new_tris, vert)
				end
			end
		end

		if #new_tris != 0 then
			local new_mesh = Mesh()
			new_mesh:BuildFromTriangles(new_tris)

			table.insert(new_meshes, {
				mesh = new_mesh,
				material = Material(MESH.material)
			})
		end	
	end

	--Add fleshy stump meshes
	for _, MESH in pairs(MESHES) do
		for _, vert in pairs(MESH.verticies) do
			if !vert.is_strong then
				local is_conn = false
				for _, weight in pairs(vert.weights) do
					if temp:TranslateBoneToPhysBone(weight.bone) == phys_bone then
						is_conn = true
					else
						vert.pos = vert.pos * (1-weight.weight)
					end
				end
				if !is_conn then									
					vert.pos = vec_zero					
				end
			end
		end		
		local new_tris = {}
		local TRIS = MESH.triangles
		for tri_idx = 1, #TRIS-2, 3 do
			local strong_count = 0
			local conn_count = 0
			for offset = 0, 2 do
				local vert = TRIS[tri_idx + offset]
				if vert.is_strong then
					conn_count = conn_count + 1
					strong_count = strong_count + 1
				else
					for _, weight in pairs(vert.weights) do
						if temp:TranslateBoneToPhysBone(weight.bone) == phys_bone then
							conn_count = conn_count + 1
							break										
						end
					end	
				end			
			end
			if conn_count > 1 and strong_count < 3 then
				for offset = 0, 2 do
					table.insert(new_tris, TRIS[tri_idx + offset])
				end
			end
		end

		if #new_tris != 0 then
			local new_mesh = Mesh()
			new_mesh:BuildFromTriangles(new_tris)

			table.insert(new_meshes, {
				mesh = new_mesh,
				material = mat_flesh
			})
		end	
	end

	temp:Remove()

	CACHE[mdl][phys_bone] = new_meshes

	return new_meshes
end