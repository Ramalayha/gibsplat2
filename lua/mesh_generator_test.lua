local function makemesh(mdl, pbone)
	local temp = ClientsideRagdoll(mdl)
	temp:SetupBones()

	local BONE2PBONE = {}
	local PBONE2BONE = {}

	for pbone = 0, temp:GetPhysicsObjectCount() - 1 do
		local bone = temp:TranslatePhysBoneToBone(pbone)
		PBONE2BONE[pbone] = bone		
	end

	for bone = 0, temp:GetBoneCount() - 1 do
		local pbone = temp:TranslateBoneToPhysBone(bone)
		BONE2PBONE[bone] = pbone
	end

	temp:Remove()

	local root_bone = PBONE2BONE[pbone]

	local meshes, bones = util.GetModelMeshes(mdl)

	for bone, info in pairs(bones) do
		info.matrix:Invert()
	end

	for bone, info in pairs(bones) do
		if bone == root_bone then continue end
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
			--local parent = bones[parent].parent
			info.matrix:Set(bones[parent].matrix)
			info.matrix:Translate(Vector(-2, 0, 0))
			info.matrix:Scale(vector_origin)			
		end
	end

	local new_meshes = {}

	for _, mesh in ipairs(meshes) do
		for _, vert in ipairs(mesh.verticies) do
			local strong = true
			local partial = false
			for _, bw in ipairs(vert.weights) do
				if BONE2PBONE[bw.bone] != pbone then
					strong = false
				else
					partial = true
				end
			end

			vert.strong = strong
			vert.partial = partial
			
			--vert.pos = bones[root_bone].matrix * vert.pos

			local pos = vert.pos * 1

			vert.pos:Set(vector_origin)

			for _, bw in ipairs(vert.weights) do
				if BONE2PBONE[bw.bone] == pbone then
					vert.pos:Add(pos * bw.weight)
				else
					local mat = bones[bw.bone].matrix
					if mat then
						vert.pos:Add(mat:GetTranslation() * bw.weight)
					else
						print(temp:GetBoneName(bw.bone))
					end
				end
			end
		end
		local new_tris = {}
		local tris = mesh.triangles
		for idx = 1, #tris - 2, 3 do
			local att = false
			local num_strong = 0
			for off = 0, 2 do
				local vert = tris[idx + off]
				if vert.partial then
					att = true
				end
				if vert.strong then
					num_strong = num_strong + 1
				end
			end

			--if att then
				for off = 0, 2 do
					local vert = tris[idx + off]
					table.insert(new_tris, vert)
				end
			--end
		end

		if #new_tris > 0 then
			local M = Mesh()
			M:BuildFromTriangles(new_tris)
			if IsValid(M) then
				table.insert(new_meshes, {
					mesh = M,
					mat = Material(mesh.material)
				})
			end
		end
	end

	return new_meshes
end

if MS then
	for _, m in pairs(MS) do
		if IsValid(m) then
			m.mesh:Destroy()
		end
	end
end

MS = makemesh("models/combine_soldier.mdl", 0)

local pos = there + Vector(0, 0, 0)

local mat = Matrix()
mat:Translate(pos)

hook.Add("PostDrawOpaqueRenderables", "h", function()
	cam.PushModelMatrix(mat)
	for _, M in pairs(MS) do
		render.SetMaterial(M.mat)
		M.mesh:Draw()
	end
	cam.PopModelMatrix()
end)