include("filesystem.lua")
include("mesh_util.lua")

local VERSION = 6

local BONE_CACHE = {}

local vec_zero = Vector(0,0,0)
local ang_zero = Angle(0,0,0)

local MDL_INDEX = {}

local MATERIAL_CACHE = {}

local THREADS = {}

local PERCENT = 0

local iterations = GetConVar("gs2_mesh_iterations")

local function SafeYield()
	if coroutine.running() then
		coroutine.yield()
	end
end

function GetBoneMeshes(ent, phys_bone, norec)
	PERCENT = 0

	local mdl = ent:GetModel()

	local bg_mask = util.GetBodygroupMask(ent)

	/*if !MDL_INDEX[mdl] then
		local data = GS2ReadModelData(mdl)
		if (data and data.mesh_data) then
			MDL_INDEX[mdl] = data.mesh_data
			THREADS[mdl] = nil
		end
	end*/

	if (!MDL_INDEX[mdl] and THREADS[mdl] and coroutine.running() != THREADS[mdl]) then
		while (coroutine.status(THREADS[mdl]) != "dead") do 
			coroutine.resume(THREADS[mdl]) --force it to finish
		end		
	end	

	if !MDL_INDEX[mdl] then	
		local temp = ClientsideRagdoll(mdl)
		temp:SetupBones()
		temp:SetNoDraw(true)
		
		local phys_count = temp:GetPhysicsObjectCount()

		local phys_mat = ""

		for phys_bone = 0, phys_count - 1 do
			local phys = temp:GetPhysicsObjectNum(phys_bone)
			if IsValid(phys) then
				phys_mat = phys:GetMaterial()
				break
			end
		end

		MATERIAL_CACHE[phys_mat] = MATERIAL_CACHE[phys_mat] or Material("models/gibsplat2/flesh/"..phys_mat)
		
		local PBONE2BONE = {}		
		local BONE2PBONE = {}
		local BONE_PARENT = {}

		for bone = 0, temp:GetBoneCount() - 1 do
			local pbone = temp:TranslateBoneToPhysBone(bone)
			PBONE2BONE[pbone] = bone
			BONE2PBONE[bone] = pbone
			BONE_PARENT[bone] = temp:GetBoneParent(bone)
		end

		temp:Remove()

		local _, matrixes = util.GetModelMeshes(mdl)

		local hash_tbl, mesh_lookup = GetSortedMeshHashTable(mdl)

		local new_meshes = {}

		for phys_bone = 0, phys_count - 1 do
			if !hash_tbl[phys_bone] then
				continue
			end 
			local bone = PBONE2BONE[phys_bone]
			local bone_matrix = matrixes[bone].matrix
			
			for bg_num, meshes in pairs(hash_tbl[phys_bone]) do
				for bg_val, data in pairs(meshes) do		
					for _, hash in pairs(data) do
						local mesh = GS2ReadMesh(hash)
						if mesh then							
							SetMulti(new_meshes, phys_bone, bg_num, bg_val, hash, mesh)
							continue
						end
						
						mesh = mesh_lookup[hash]

						if !MATERIAL_CACHE[mesh.material] then
							local mat = Material(mesh.material)
							if (phys_mat and file.Exists("models/gibsplat2/overlays/"..phys_mat..".vmt", "GAME")) then
								local mat_bloody = CreateMaterial(mesh.material.."_bloody", "VertexLitGeneric", {["$detail"] = mat_path})
								for key, value in pairs(mat:GetKeyValues()) do
									if (key == "$detail") then
										continue
									end
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
								MATERIAL_CACHE[mesh.material] = mat_bloody
							else
								MATERIAL_CACHE[mesh.material] = mat
							end
						end

						local verts = mesh.verticies
						
						for vert_index, vert in pairs(verts) do
							vert._pos = vert._pos or vert.pos
							vert.pos = bone_matrix * vert._pos
							
							vert.is_conn = nil
							vert.is_strong = nil
						end

						bone_matrix = bone_matrix:GetInverse()

						local new_tris = {}
						local new_verts = {}
						
						local TRIS = mesh.triangles			
						
						for tri_idx = 1, #TRIS-2, 3 do 
							local is_strong = true
							for offset = 0, 2 do
								local vert = TRIS[tri_idx + offset]
								for _, weight in pairs(vert.weights) do
									if BONE2PBONE[weight.bone] != phys_bone then
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
									if !new_verts[vert] then
										local new_vert = {
											pos = vert.pos * 1,
											normal = (vert.normal or vector_origin) * 1,
											tangent = (vert.tangent or vector_origin) * 1,
											binormal = (vert.binormal or vector_origin) * 1,
											u = vert.u,
											v = vert.v,
											userdata = vert.userdata,
											is_strong = true
										}
										new_verts[vert] = new_vert
									end
									table.insert(new_tris, new_verts[vert])	
								end
							end																							
						end

						if #new_tris != 0 then
							local new_mesh = Mesh()
							new_mesh:BuildFromTriangles(new_tris)

							local mat = MATERIAL_CACHE[mesh.material]
							
							SetMulti(new_meshes, phys_bone, bg_num, bg_val, hash, {body = {
								Mesh = new_mesh,
								Material = mat,
								tris = new_tris,
								mat_name = mesh.material								
							}})
						end	

						if mesh.material:find("eyeball") then --dont draw eyes as flesh
							continue
						end
						
						local mat = MATERIAL_CACHE[mesh.material]

						if (bit.band(mat:GetInt("$flags"), 0x200000) != 0) then --ignore translucent meshes
							continue
						end
					
						for vert_index, vert in pairs(verts) do
							if !vert.is_strong then								
								for _, weight in pairs(vert.weights) do
									if BONE2PBONE[weight.bone] == phys_bone then
										vert.is_conn = true										
									else
										local current_bone = weight.bone

										repeat
											if (BONE2PBONE[BONE_PARENT[current_bone]] == phys_bone) then
												break
											end
											current_bone = BONE_PARENT[current_bone]
										until (current_bone == -1)

										if (current_bone != -1) then
											local current_matrix = matrixes[current_bone].matrix
											
											local parent_bone = BONE_PARENT[current_bone]

											local parent_matrix = matrixes[parent_bone].matrix

											local lpos = current_matrix * bone_matrix:GetTranslation()

											local lpos2 = parent_matrix * bone_matrix:GetTranslation()

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
											local parent_bone = BONE_PARENT[weight.bone]

											if (BONE2PBONE[parent_bone] == phys_bone) then
												local weight_matrix = matrixes[weight.bone].matrix:GetInverse()
												
												local parent_matrix = matrixes[parent_bone].matrix
												
												local lpos = parent_matrix * weight_matrix:GetTranslation()

												parent_pos = parent_matrix:GetInverse() * (lpos * 0.7)

												vert_pos = vert_pos + bone_matrix * parent_pos
												weight_count = weight_count + 1
											end			
										end
									end
									if (weight_count > 0) then
										vert.pos = vert_pos / weight_count
									end
								end					
							end	
							if (vert_index % 500 == 0) then
								SafeYield()
							end 						
						end	
							
						new_tris = {}
						new_verts = {}				

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
										local vert = TRIS[tri_idx + offset]
										if !new_verts[vert] then
											local new_vert = {
												pos = vert.pos * 1,
												normal = (vert.normal or vector_origin) * 1,
												tangent = (vert.tangent or vector_origin) * 1,
												binormal = (vert.binormal or vector_origin) * 1,
												u = vert.u,
												v = vert.v,
												userdata = vert.userdata
											}
											new_verts[vert] = new_vert
										end
										table.insert(new_tris, new_verts[vert])					
									end				
								end
							end
							if (tri_idx % 500 == 0) then
								SafeYield()
							end 																					
						end

						if #new_tris != 0 then
							local new_mesh = Mesh()
							new_mesh:BuildFromTriangles(new_tris)

							local mat = MATERIAL_CACHE[phys_mat]

							if (!mat or mat:IsError()) then
								MATERIAL_CACHE[mesh.material] = MATERIAL_CACHE[mesh.material] or Material(mesh.material)
								mat = MATERIAL_CACHE[mesh.material]
							end
							
							InsertMultiWithKey(new_meshes, phys_bone, bg_num, bg_val, hash, "flesh", {
								Mesh = new_mesh,
								Material = mat,				
								tris = new_tris,
								is_flesh = true
							}) 
						end	
					end
				end
			end 
		end

		MDL_INDEX[mdl] = new_meshes

		GS2WriteMeshData(new_meshes) 
		GS2LinkModelInfo(mdl, "mesh_data", new_meshes)
	end

	if coroutine.running() then
		return --We're in generation phase
	end

	local ret = {}
	if MDL_INDEX[mdl][phys_bone] then
		for bg_num, data in pairs(MDL_INDEX[mdl][phys_bone]) do
			local bg_val = ent:GetBodygroup(bg_num)
			if data[bg_val] then
				for hash, mesh in pairs(data[bg_val]) do
					table.insert(ret, mesh)
				end
			end
		end
	end

	return ret
end

local start

local enabled = GetConVar("gs2_enabled")

hook.Add("HUDPaint", "GS2BuildMesh", function()
	if !enabled:GetBool() then return end
	local mdl, thread = next(THREADS)
	if !mdl then
		return
	end
	if !start then
		start = SysTime()
		PERCENT = 0
		print("Started generating meshes for "..mdl)
	end			
	
	if (coroutine.status(thread) == "dead") then
		THREADS[mdl] = nil
		local nmodels = table.Count(THREADS)
		local form = nmodels > 1 and [[Generated meshes for "%s" in %i:%02i.%02i (%i models left)]] or [[Generated meshes for "%s" in %i:%02i.%02i]]
		local ft = string.FormattedTime(math.Round(SysTime() - start, 3))
		local str = form:format(mdl, ft.m, ft.s, ft.ms, nmodels)
		print(str)
		start = nil	
	else		
		local iter = iterations:GetInt()
		if !system.HasFocus() then
			iter = iter * 10
		end
		for i = 1, iter do
			local bool, err = coroutine.resume(thread)
			if !bool then
				print(mdl, err)
				break
			elseif (coroutine.status(thread) == "dead") then
				break
			end	
		end
	end			
end)

local player_ragdolls = GetConVar("gs2_player_ragdolls")

hook.Add("NetworkEntityCreated", "GS2BuildMesh", function(ent)
	if !enabled:GetBool() then return end
	if (ent:IsPlayer() and !player_ragdolls:GetBool() and !engine.ActiveGamemode():find("ttt")) then return end
	local mdl = ent:GetModel()
	if (mdl and !MDL_INDEX[mdl] and !THREADS[mdl] and util.IsValidRagdoll(mdl)) then
		if GS2ReadModelData(mdl) then
			GetBoneMeshes(ent, 0)
		else
			THREADS[mdl] = coroutine.create(function()			
				GetBoneMeshes(ent, 0)
			end)
			coroutine.resume(THREADS[mdl])			
		end
	end
end)

net.Receive("GS2ForceModelPregen", function()
	local count = net.ReadUInt(16)
	for i = 1, count do
		local mdl = net.ReadString()
		if (mdl and !MDL_INDEX[mdl] and !THREADS[mdl] and util.IsValidRagdoll(mdl)) then
			if GS2ReadModelData(mdl) then
				local ent = ClientsideModel(mdl)		
				GetBoneMeshes(ent, 0)
				ent:Remove()
			else
				THREADS[mdl] = coroutine.create(function()	
					local ent = ClientsideModel(mdl)		
					GetBoneMeshes(ent, 0)
					ent:Remove()
				end)				
			end		
		end
		local temp = ClientsideModel(mdl)
		hook.GetTable()["NetworkEntityCreated"]["GS2Gibs"](temp) --ugly!
		temp:Remove()
	end
end)

local form = [[GS2: Building meshes for "%s" (%3.2f%% done), %i models remaining (PREPARE FOR FPS SPIKES)]]
local form2 = [[GS2: Building meshes for "%s" (%3.2f%% done)]]

hook.Add("HUDPaint", "GS2BuildMeshDisplay", function()
	if !enabled:GetBool() then return end
	local mdl = next(THREADS)
	if !mdl then return end

	local nmodels = table.Count(THREADS)

	local form = nmodels > 1 and form or form2

	local msg = form:format(mdl, 100 * PERCENT, nmodels - 1)

	surface.SetFont("DebugFixed")
	local w, h = surface.GetTextSize(msg)
	
	surface.SetTextColor(255, 0, 0)
	surface.SetTextPos(ScrW() * 0.99 - w, ScrH() / 2 - h / 2)
	surface.DrawText(msg)
end)