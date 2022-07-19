include("filesystem.lua")
include("mesh_util.lua")

local VERSION = 6

local BONE_CACHE = {}

local MDL_INDEX = {}

local MATERIAL_CACHE = {}

function GetBoneMeshes(ent, phys_bone)
	local mdl = ent:GetModel()

	local bg_mask = util.GetBodygroupMask(ent)

	if !MDL_INDEX[mdl] then
		MDL_INDEX[mdl] = {}
		GetSkinGroups(mdl) --preload skingroups
	end

	if !MDL_INDEX[mdl][bg_mask] then
		MDL_INDEX[mdl][bg_mask] = GS2ReadMeshData(mdl, bg_mask)
	end

	if !MDL_INDEX[mdl][bg_mask] then
		local temp = ClientsideRagdoll(mdl)
		temp:SetupBones()

		local phys_count = temp:GetPhysicsObjectCount()

		local phys_mat = temp:GetPhysicsObject():GetMaterial()

		local BONE2PBONE = {}
		local PBONE2BONE = {}
		for bone = 0, temp:GetBoneCount() - 1 do			
			local pbone = temp:TranslateBoneToPhysBone(bone)
			BONE2PBONE[bone] = pbone
				
		end

		for pbone = 0, phys_count - 1 do
			local bone = temp:TranslatePhysBoneToBone(pbone)
			PBONE2BONE[pbone] = bone
		end

		temp:Remove()

		MATERIAL_CACHE[phys_mat] = MATERIAL_CACHE[phys_mat] or Material("models/gibsplat2/flesh/"..phys_mat)
		
		local flesh_mat = MATERIAL_CACHE[phys_mat]

		local new_meshes = {}

		for pbone = 0, phys_count - 1 do
			local meshes, bones = util.GetModelMeshes(mdl, 0, bg_mask)

			local root_bone = PBONE2BONE[pbone]

			for bone, info in pairs(bones) do
				info.matrix:Invert()
			end

			for bone, info in pairs(bones) do
				if BONE2PBONE[bone] == pbone then
					continue
				end
				local parent = bone
				repeat
					if BONE2PBONE[bones[parent].parent] == pbone then
						break
					end
					parent = bones[parent].parent
				until (parent == -1)
				
				if parent == -1 then
					info.matrix:Set(bones[root_bone].matrix)
				else					
					local matrix = bones[parent].matrix
					local parent = bones[parent].parent
					local matrix2 = bones[parent].matrix

					local center = matrix:GetTranslation() * 0.7 + matrix2:GetTranslation() * 0.3

					info.matrix:Identity()
					info.matrix:Translate(center)
					info.matrix:Scale(vector_origin)			
				end
			end

			local root_matrix = bones[root_bone].matrix:GetInverse()

			local new_entries = {}

			for _, mesh in ipairs(meshes) do
				for _, vert in ipairs(mesh.verticies) do
					local pos = vert.pos * 1
					vert.pos:Set(vector_origin)
					vert.strong_conn = true
					for _, bw in ipairs(vert.weights) do
						if BONE2PBONE[bw.bone] != pbone then
							vert.strong_conn = false
							local matrix = bones[bw.bone].matrix
							vert.pos:Add(matrix:GetTranslation() * bw.weight)
						else
							vert.pos:Add(pos * bw.weight)
							vert.conn = true
						end						
					end

					vert.pos = root_matrix * vert.pos				
				end

				local tris = mesh.triangles
				local skin_tris = {}
				local flesh_tris = {}

				for idx = 1, #tris - 2, 3 do
					local conn = false
					local strong_count = 0
					for off = 0, 2 do
						local vert = tris[idx + off]
						if vert.conn then
							conn = true
						end
						if vert.strong_conn then
							strong_count = strong_count + 1
						end
					end

					if conn then
						if strong_count == 3 then
							for off = 0, 2 do
								local vert = tris[idx + off]
								table.insert(skin_tris, vert)
							end
						else
							for off = 0, 2 do
								local vert = tris[idx + off]
								table.insert(flesh_tris, vert)
							end
						end
					end
				end

				local mesh_skin = Mesh()
				mesh_skin:BuildFromTriangles(skin_tris)			
				local mesh_flesh = Mesh()
				mesh_flesh:BuildFromTriangles(flesh_tris)

				local entry = {}
				entry.body = {
					Mesh = mesh_skin,
					Material = Material(mesh.material),
					decal_tris = skin_tris,
					mat_name = mesh.material
				}
				entry.flesh = {
					Mesh = mesh_flesh,
					Material = flesh_mat,
					is_flesh = true,
					decal_tris = flesh_tris
				}
				
				table.insert(new_entries, entry)
			end

			new_meshes[pbone] = new_entries
		end

		MDL_INDEX[mdl][bg_mask] = new_meshes
		
		GS2WriteMeshData(mdl, bg_mask, new_meshes)
	end

	if !phys_bone then return end --pregen

	return MDL_INDEX[mdl][bg_mask][phys_bone]
end

local enabled = GetConVar("gs2_enabled")

local player_ragdolls = GetConVar("gs2_player_ragdolls")

hook.Add("NetworkEntityCreated", "GS2BuildMesh", function(ent)
	if !enabled:GetBool() then return end
	if (ent:IsPlayer() and !player_ragdolls:GetBool() and !engine.ActiveGamemode():find("ttt")) then return end
	local mdl = ent:GetModel()
	if (mdl and !MDL_INDEX[mdl] and util.IsValidRagdoll(mdl)) then
		GetBoneMeshes(ent, 0)
	end
end)

local keep_corpses = GetConVar("ai_serverragdolls")

hook.Add("OnEntityCreated", "GS2DeleteFakeRagdolls", function(ent)
	if !enabled:GetBool() or !keep_corpses:GetBool() then return end

	if !ent:IsNPC() or !ent:GetClass():find("headcrab") then return end

	local zombie = ent:GetOwner()

	if IsValid(zombie) then
		timer.Simple(0.015, function()
			for _, ragdoll in pairs(ents.FindByClass("class C_ClientRagdoll")) do
				if ragdoll:GetModel():find("zombie") then
					ragdoll:Remove()
				end
			end
		end)
	end
end)

net.Receive("GS2ForceModelPregen", function()
	local count = net.ReadUInt(16)
	for i = 1, count do
		local mdl = net.ReadString()
		local ent = ClientsideModel(mdl)		
		GetBoneMeshes(ent, 0)
		ent:Remove()
		
		local temp = ClientsideModel(mdl)
		hook.GetTable()["NetworkEntityCreated"]["GS2Gibs"](temp) --ugly!
		temp:Remove()
	end
end)