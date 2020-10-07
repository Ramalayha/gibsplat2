include("filesystem.lua")

local VERSION = 6

local BONE_CACHE = {}

function util.GetBodygroupMask(ent)
	local mask = 0
	local offset = 1
	
	for index = 1, ent:GetNumBodyGroups() do
		local bg = ent:GetBodygroup(index)
		mask = mask + offset * bg
		offset = offset * ent:GetBodygroupCount(index)
	end

	return mask
end

local vec_zero = Vector(0,0,0)
local ang_zero = Angle(0,0,0)

local MDL_INDEX = {}

local MESH_CACHE = {}
local MATERIAL_CACHE = {}

function GetBoneMeshes(ent, phys_bone, norec)
	local mdl = ent:GetModel()

	local bg_mask = util.GetBodygroupMask(ent)

	MDL_INDEX[mdl] = MDL_INDEX[mdl] or {}
	MDL_INDEX[mdl][bg_mask] = MDL_INDEX[mdl][bg_mask] or {}

	if MDL_INDEX[mdl][bg_mask][phys_bone] then
		return MDL_INDEX[mdl][bg_mask][phys_bone]
	end

	local mdl_info = GS2ReadModelData(mdl)

	if (mdl_info and mdl_info.mesh_data) then
		for bg_mask, data in pairs(mdl_info.mesh_data) do
			MDL_INDEX[mdl][bg_mask] = MDL_INDEX[mdl][bg_mask] or {}
			for phys_bone, hash in pairs(data) do
				MDL_INDEX[mdl][bg_mask][phys_bone] = MESH_CACHE[hash]
			end
		end
		if MDL_INDEX[mdl][bg_mask][phys_bone] then
			return MDL_INDEX[mdl][bg_mask][phys_bone]
		end
	end

	--Generate for all bones of model
	if !norec then
		for pbone = 0, 23 do --23 = max ragdoll parts
			if (pbone != phys_bone) then
				if (pbone != 0 and ent:TranslatePhysBoneToBone(pbone) == 0) then
					break
				end
				GetBoneMeshes(ent, pbone, true)
			end
		end
		GS2LinkModelInfo(mdl, "mesh_data", MDL_INDEX[mdl])	
	end

	local KVs = util.GetModelInfo(mdl).KeyValues

	local phys_mat = KVs and KVs:match('solid {.-"index" "'..phys_bone..'".-"surfaceprop" "([^"]-)"')

	if phys_mat and Material("models/gibsplat2/overlays/"..phys_mat):IsError() then
		phys_mat = nil
	end

	local temp = ClientsideModel(mdl)
	temp:SetupBones()
	local bone = temp:TranslatePhysBoneToBone(phys_bone)

	if !BONE_CACHE[mdl] then
		BONE_CACHE[mdl] = {}
		local poser = ents.CreateClientProp(mdl)
		poser:ResetSequence(-2)
		poser:SetCycle(0)

		for pose_param = 0, poser:GetNumPoseParameters() - 1 do
			local name = poser:GetPoseParameterName(pose_param)
			local min, max = poser:GetPoseParameterRange(pose_param)
			if !name:find("^body_") then
				poser:SetPoseParameter(name, (min + max) / 2)
			end
		end

		poser:SetupBones()

		for bone = 0, poser:GetBoneCount() - 1 do
			BONE_CACHE[mdl][bone] = poser:GetBoneMatrix(bone)
		end

		poser:Remove()
	end

	local bone_matrix = BONE_CACHE[mdl][bone]
	local bone_pos, bone_ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()--temp:GetBonePosition(bone)
	
	local new_meshes = {}
	
	local MESHES = util.GetModelMeshes(mdl, 0, bg_mask)

	if !MESHES then
		temp:Remove()
		return {}
	end
	
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

			local mat = MATERIAL_CACHE[MESH.material]

			if !mat then
				mat = Material(MESH.material)
				if phys_mat then
					local mat_bloody = CreateMaterial(MESH.material.."_bloody", "VertexLitGeneric", {
						["$detail"] = "models/gibsplat2/overlays/"..phys_mat						
					})		
					for key, value in pairs(mat:GetKeyValues()) do
						if (type(value) == "string") then
							mat_bloody:SetString(key, value)
						elseif (type(value) == "number") then
							mat_bloody:SetFloat(key, value)
						elseif (type(value) == "Vector") then
							mat_bloody:SetVector(key, value)
						elseif (type(value) == "ITexture") then
							mat_bloody:SetTexture(key, value)
						elseif (type(value) == "VMatrix") then
							mat_bloody:SetMatrix(key, value)							
						end
					end
					mat = mat_bloody
				end
				MATERIAL_CACHE[MESH.material] = mat				
			end

			table.insert(new_meshes, {
				Mesh = new_mesh,
				Material = mat,
				tris = new_tris				
			})
		end	
	end

	local mesh_tbl = {}

	for _, mesh in ipairs(new_meshes) do
		for _, vert in ipairs(mesh.tris) do
			table.insert(mesh_tbl, VEC2STR(vert.pos))
		end
	end

	local hash = TBL2HASH(mesh_tbl)

	if !MESH_CACHE[hash] then
		GS2ReadMeshData(hash, MESH_CACHE) --try read from file
	end

	if MESH_CACHE[hash] then
		temp:Remove()
		MDL_INDEX[mdl][bg_mask][phys_bone] = MESH_CACHE[hash]
		return MESH_CACHE[hash]
	end

	--Add fleshy stump meshes
	for _, MESH in pairs(MESHES) do
		if MESH.material:find("eyeball") then --dont draw eyes as flesh
			continue
		end
		MATERIAL_CACHE[MESH.material] = MATERIAL_CACHE[MESH.material] or Material(MESH.material)
		local mat = MATERIAL_CACHE[MESH.material]

		if (bit.band(mat:GetInt("$flags"), 0x200000) != 0) then --ignore translucent meshes
			continue
		end
	
		for _, vert in pairs(MESH.verticies) do
			if !vert.is_strong then								
				for _, weight in pairs(vert.weights) do
					if temp:TranslateBoneToPhysBone(weight.bone) == phys_bone then
						vert.is_conn = true										
					else
						local current_bone = weight.bone

						repeat
							if (temp:TranslateBoneToPhysBone(temp:GetBoneParent(current_bone)) == phys_bone) then
								break
							end
							current_bone = temp:GetBoneParent(current_bone)
						until (current_bone == -1)

						if (current_bone != -1) then
							local current_matrix = BONE_CACHE[mdl][current_bone]

							local current_pos = current_matrix:GetTranslation()
							local current_ang = current_matrix:GetAngles()

							local parent_bone = temp:GetBoneParent(current_bone)

							local parent_matrix = BONE_CACHE[mdl][parent_bone]

							local parent_pos = parent_matrix:GetTranslation()
							local parent_ang = parent_matrix:GetAngles()

							local lpos = WorldToLocal(current_pos, current_ang, bone_pos, bone_ang)

							local lpos2 = WorldToLocal(parent_pos, parent_ang, bone_pos, bone_ang)

							vert.pos = vert.pos + (lpos - vert.pos) * weight.weight * 0.7
							vert.pos = vert.pos + (lpos2 - vert.pos) * weight.weight * 0.3
						else
							vert.pos = vert.pos * (1 - weight.weight)
						end
					end
				end

				if !vert.is_conn then														
					vert.pos = vec_zero
					local vert_pos = Vector(0,0,0)
					local weight_count = 0
					for _, weight in pairs(vert.weights) do
						if (weight.bone != bone) then
							local parent_bone = temp:GetBoneParent(weight.bone)

							if (temp:TranslateBoneToPhysBone(parent_bone) == phys_bone) then
								local weight_matrix = BONE_CACHE[mdl][weight.bone]
								local weight_pos = weight_matrix:GetTranslation()
								local weight_ang = weight_matrix:GetAngles()

								local parent_matrix = BONE_CACHE[mdl][parent_bone]
								local parent_pos = parent_matrix:GetTranslation()
								local parent_ang = parent_matrix:GetAngles()

								local lpos = WorldToLocal(weight_pos, weight_ang, parent_pos, parent_ang)

								parent_pos = LocalToWorld(lpos * 0.7, ang_zero, parent_pos, parent_ang)

								vert_pos = vert_pos + WorldToLocal(parent_pos, ang_zero, bone_pos, bone_ang)
								weight_count = weight_count + 1
							end			
						end
					end
					if (weight_count > 0) then
						vert.pos = vert_pos / weight_count
					end
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
					if vert.is_conn then
						conn_count = conn_count + 1					
					end	
				end			
			end
			if conn_count > 0 and strong_count < 3 then
				local vert1 = TRIS[tri_idx]
				local vert2 = TRIS[tri_idx + 1]
				local vert3 = TRIS[tri_idx + 2]
				
				if (!vert1.pos:IsEqualTol(vert2.pos, 0) and
					!vert1.pos:IsEqualTol(vert3.pos, 0) and
					!vert2.pos:IsEqualTol(vert3.pos, 0)) then
					for offset = 0, 2 do
						table.insert(new_tris, TRIS[tri_idx + offset])					
					end				
				end
			end
		end

		if #new_tris != 0 then
			local new_mesh = Mesh()
			new_mesh:BuildFromTriangles(new_tris)

			table.insert(new_meshes, {
				Mesh = new_mesh,
				Material = mat,
				look_for_material = true,
				tris = new_tris
			})
		end	
	end

	temp:Remove()

	GS2WriteMeshData(hash, new_meshes)

	new_meshes.hash = hash

	MESH_CACHE[hash] = new_meshes
	MDL_INDEX[mdl][bg_mask][phys_bone] = new_meshes

	GS2LinkModelInfo(mdl, "mesh_data", MDL_INDEX[mdl])

	return new_meshes
end