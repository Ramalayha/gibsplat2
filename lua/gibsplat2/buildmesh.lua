local VERSION = 5

local MSG_REQ_POSE = "GS2ReqRagdollPose"

if SERVER then
util.AddNetworkString(MSG_REQ_POSE)

local ragdoll_ang = Angle(0, -90, 0) --idk why this is 

net.Receive(MSG_REQ_POSE, function(len, ply)
	local ent = net.ReadEntity()
	if !IsValid(ent) then
		return
	end
	local mdl = ent:GetModel()
	local temp = ents.Create("prop_ragdoll")
	temp:SetModel(mdl)
	temp:SetAngles(ragdoll_ang)

	local bone_count = temp:GetBoneCount()

	net.Start(MSG_REQ_POSE)		
	net.WriteEntity(ent)
	local bone_count = temp:GetBoneCount()
	net.WriteUInt(bone_count, 16)
	for bone = 0, bone_count - 1 do
		net.WriteMatrix(temp:GetBoneMatrix(bone) or Matrix())
	end
	net.Send(ply)
	
	temp:SetPos(ply:GetPos())

	temp:Remove()
end)
end

if CLIENT then

local BONE_CACHE = {}

local function WriteVector(F, vec)
	F:WriteFloat(vec.x)
	F:WriteFloat(vec.y)
	F:WriteFloat(vec.z)
end

local function WriteAngle(F, ang)
	F:WriteFloat(ang.p)
	F:WriteFloat(ang.y)
	F:WriteFloat(ang.r)
end

local function ReadVector(F)
	local x = F:ReadFloat()
	local y = F:ReadFloat()
	local z = F:ReadFloat()
	return Vector(x, y, z)
end

local function ReadAngle(F, ang)
	local p = F:ReadFloat()
	local y = F:ReadFloat()
	local t = F:ReadFloat()
	return Angle(p, y, r)
end

local function WriteBonePositions(mdl)
	local file_name = "gibsplat2/bone_cache/"..util.CRC(mdl)..".txt"

	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/bone_cache")

	file.Write(file_name, "") --creates file

	local F = file.Open(file_name, "wb", "DATA")

	if !F then
		return
	end

	F:WriteByte(VERSION)
	F:WriteShort(#mdl)
	F:Write(mdl)

	F:WriteShort(#BONE_CACHE[mdl] + 1)
	for bone = 0, #BONE_CACHE[mdl] do
		local matrix = BONE_CACHE[mdl][bone]
		WriteVector(F, matrix:GetTranslation())
		WriteAngle(F, matrix:GetAngles())
	end

	F:Close()
end

local cur_file = ""

local function LoadBonePositions()
	for _, file_name in pairs(file.Find("gibsplat2/bone_cache/*.txt", "DATA")) do
		local F = file.Open("gibsplat2/bone_cache/"..file_name, "rb", "DATA")

		cur_file = "gibsplat2/bone_cache/"..file_name

		if (F:ReadByte() != VERSION) then
			F:Close()
			continue
		end

		local mdl = F:Read(F:ReadShort())

		BONE_CACHE[mdl] = {}

		local num_entries = F:ReadShort()

		for entry_index = 0, num_entries - 1 do
			local matrix = Matrix()
			matrix:Translate(ReadVector(F))
			matrix:Rotate(ReadAngle(F))
			BONE_CACHE[mdl][entry_index] = matrix
		end
	end
end

local err, msg = pcall(LoadBonePositions)
if err then
	print("LoadBonePositions: '"..cur_file.."' is corrupt, deleting!")
	file.Delete(cur_file)
end

net.Receive(MSG_REQ_POSE, function()
	local ent = net.ReadEntity()
	if !IsValid(ent) then
		return
	end
	local mdl = ent:GetModel()
	BONE_CACHE[mdl] = {}
	for bone = 0, net.ReadUInt(16) - 1 do			
		BONE_CACHE[mdl][bone] = net.ReadMatrix()
	end
	
	WriteBonePositions(mdl)
	GetBoneMeshes(ent, 0)

	--Update all limbs
	for _, limb in ipairs(ents.FindByClass("gs2_limb")) do
		if (IsValid(limb) and limb.RenderInfo) then
			limb:UpdateRenderInfo()
		end
	end
end)

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

local MESH_CACHE = {}
local MATERIAL_CACHE = {}

local function WriteVector(F, vec)
	F:WriteFloat(vec.x)
	F:WriteFloat(vec.y)
	F:WriteFloat(vec.z)
end

local function ReadVector(F)
	local x = F:ReadFloat()
	local y = F:ReadFloat()
	local z = F:ReadFloat()
	return Vector(x, y, z)
end

local function WriteBoneMeshes(ent, bg_mask)
	local mdl = ent:GetModel()
	local file_name = "gibsplat2/mesh_cache/"..util.CRC(mdl..bg_mask)..".txt"

	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/mesh_cache")

	file.Write(file_name, "") --creates file

	local F = file.Open(file_name, "wb", "DATA")

	F:WriteByte(VERSION)
	F:WriteShort(#mdl)
	F:Write(mdl)
	F:WriteLong(bg_mask)

	F:WriteShort(#MESH_CACHE[mdl][bg_mask])
	for phys_bone, meshes in pairs(MESH_CACHE[mdl][bg_mask]) do
		F:WriteByte(phys_bone)
		F:WriteShort(#meshes)
		for _, mesh in pairs(meshes) do
			local mat = mesh.Material:GetName()
			F:WriteShort(#mat)
			F:Write(mat)
			F:WriteByte(mesh.look_for_material and 1 or 0)
			local VERTEX_BUFFER = {}
			local INDEX_BUFFER 	= {}
			for _, vert in ipairs(mesh.tris) do
				local index = table.KeyFromValue(VERTEX_BUFFER, vert)
				if !index then
					index = table.insert(VERTEX_BUFFER, vert)
				end
				table.insert(INDEX_BUFFER, index)
			end
			F:WriteLong(#VERTEX_BUFFER)
			for _, vert in ipairs(VERTEX_BUFFER) do
				WriteVector(F, vert.pos)
				WriteVector(F, vert.normal)
				F:WriteFloat(vert.u)
				F:WriteFloat(vert.v)
			end
			F:WriteLong(#INDEX_BUFFER)
			for _, index in ipairs(INDEX_BUFFER) do
				F:WriteLong(index)
			end
		end
	end

	F:Close()
end

local function LoadBoneMeshes()
	for _, file_name in pairs(file.Find("gibsplat2/mesh_cache/*.txt", "DATA")) do
		local F = file.Open("gibsplat2/mesh_cache/"..file_name, "rb", "DATA")

		cur_file = "gibsplat2/mesh_cache/"..file_name

		local version = F:ReadByte()
		
		if (version != VERSION) then
			F:Close()
			file.Delete("gibsplat2/mesh_cache/"..file_name)
			continue
		end

		local mdl 			= F:Read(F:ReadShort())
		local bg_mask 		= F:ReadLong()
		local num_entries 	= F:ReadShort()

		MESH_CACHE[mdl] = MESH_CACHE[mdl] or {}
		MESH_CACHE[mdl][bg_mask] = {}

		for entry_index = 1, num_entries do
			local phys_bone = F:ReadByte()
			local meshes = {}
			for mesh_index = 1, F:ReadShort() do
				local mat = F:Read(F:ReadShort())
				MATERIAL_CACHE[mat] = MATERIAL_CACHE[mat] or Material(mat)
				mat = MATERIAL_CACHE[mat]
				local lfm = F:ReadByte() == 1
				local VERTEX_BUFFER = {}
				for vert_index = 1, F:ReadLong() do
					local vert = {}
					vert.pos 	= ReadVector(F)
					vert.normal = ReadVector(F)
					vert.u 		= F:ReadFloat()
					vert.v 		= F:ReadFloat()
					table.insert(VERTEX_BUFFER, vert)
				end
				local tris = {}
				for index = 1, F:ReadLong() do
					table.insert(tris, VERTEX_BUFFER[F:ReadLong()])
				end
				local MESH = Mesh()
				MESH:BuildFromTriangles(tris)
				table.insert(meshes, {
					Mesh = MESH,
					Material = mat,
					look_for_material = lfm or nil,
					tris = tris
				})
			end
			MESH_CACHE[mdl][bg_mask][phys_bone] = meshes
		end

		F:Close()
	end
end

local err, msg = pcall(LoadBoneMeshes)
if err then
	print("LoadBoneMeshes: '"..cur_file.."' is corrupt, deleting!")
	file.Delete(cur_file)
end

function GetBoneMeshes(ent, phys_bone, norec)
	local mdl = ent:GetModel()

	MESH_CACHE[mdl] = MESH_CACHE[mdl] or {}

	local bg_mask = util.GetBodygroupMask(ent)

	MESH_CACHE[mdl][bg_mask] = MESH_CACHE[mdl][bg_mask] or {}

	if MESH_CACHE[mdl][bg_mask][phys_bone] then
		return MESH_CACHE[mdl][bg_mask][phys_bone]
	end

	local KVs = util.GetModelInfo(mdl).KeyValues

	local phys_mat = KVs and KVs:match('solid {.-"index" "'..phys_bone..'".-"surfaceprop" "([^"]-)"')

	if phys_mat and Material("models/gibsplat2/overlays/"..phys_mat):IsError() then
		phys_mat = nil
	end

	local temp = ClientsideModel(mdl)	
	temp:SetupBones()
	local bone = temp:TranslatePhysBoneToBone(phys_bone)

	if (!BONE_CACHE[mdl] or !BONE_CACHE[mdl][bone]) then		
		if (temp:LookupSequence("ragdoll") == 0) then		
			temp:Remove()
			net.Start(MSG_REQ_POSE)
			net.WriteEntity(ent)
			net.SendToServer()
			MESH_CACHE[mdl] = {}
			return MESH_CACHE[mdl]	
		else
			temp:Remove()
			temp = ClientsideModel(mdl) --Have to recreate to set default pose
			temp:ResetSequence(-2)
			temp:SetCycle(0)
			temp:SetPlaybackRate(0)
			
			for pose_param = 0, temp:GetNumPoseParameters() - 1 do
				if !temp:GetPoseParameterName(pose_param):find("^body_") then
					local min, max = temp:GetPoseParameterRange(pose_param)
					temp:SetPoseParameter(temp:GetPoseParameterName(pose_param), (min + max) / 2)
				end
			end

			temp:SetupBones()
			
			BONE_CACHE[mdl] = {}

			for bone = 0, temp:GetBoneCount() - 1 do		
				BONE_CACHE[mdl][bone] = temp:GetBoneMatrix(bone) or Matrix()
			end		
		end		
	end

	temp:SetupBones()

	local bone_matrix = BONE_CACHE[mdl][bone]
	local bone_pos, bone_ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()--temp:GetBonePosition(bone)
	
	local new_meshes = {}
	
	local MESHES = util.GetModelMeshes(mdl, 0, bg_mask)

	if !MESHES then
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

	--Add fleshy stump meshes
	for _, MESH in pairs(MESHES) do		
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

			local mat = MATERIAL_CACHE[MESH.material]

			if !mat then
				mat = Material(MESH.material)
				
				MATERIAL_CACHE[MESH.material] = mat				
			end

			table.insert(new_meshes, {
				Mesh = new_mesh,
				Material = mat,
				look_for_material = true,
				tris = new_tris
			})
		end	
	end

	temp:Remove()

	MESH_CACHE[mdl][bg_mask][phys_bone] = new_meshes

	if !norec then
		for pbone = 0, 23 do --23 = max ragdoll parts
			if (pbone != phys_bone) then
				if (pbone != 0 and ent:TranslatePhysBoneToBone(pbone) == 0) then
					break
				end
				GetBoneMeshes(ent, pbone, true)
			end
		end
		WriteBoneMeshes(ent, bg_mask) --write to file
	end

	return new_meshes
end
end