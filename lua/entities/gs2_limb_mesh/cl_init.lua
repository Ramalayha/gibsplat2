include("shared.lua")

local CurTime = CurTime
local pairs = pairs
local SafeRemoveEntity = SafeRemoveEntity
local IsValid = IsValid
local LocalToWorld = LocalToWorld

local bit_band = bit.band
local bit_lshift = bit.lshift

local render_SetColorModulation = render.SetColorModulation
local render_SetStencilEnable = render.SetStencilEnable
local render_ClearStencil = render.ClearStencil
local render_SetStencilReferenceValue = render.SetStencilReferenceValue
local render_SetStencilFailOperation = render.SetStencilFailOperation
local render_SetStencilWriteMask = render.SetStencilWriteMask
local render_OverrideDepthEnable = render.OverrideDepthEnable
local render_OverrideColorWriteEnable = render.OverrideColorWriteEnable
local render_SetStencilCompareFunction = render.SetStencilCompareFunction
local render_SetStencilPassOperation = render.SetStencilPassOperation
local render_SetStencilZFailOperation = render.SetStencilZFailOperation
local render_SetStencilWriteMask = render.SetStencilWriteMask
local render_CullMode = render.CullMode
local render_CullMode = render.CullMode
local render_SetStencilCompareFunction = render.SetStencilCompareFunction
local render_SetStencilPassOperation = render.SetStencilPassOperation
local render_SetStencilZFailOperation = render.SetStencilZFailOperation
local render_SetStencilTestMask = render.SetStencilTestMask
local render_SetStencilWriteMask = render.SetStencilWriteMask
local render_OverrideDepthEnable = render.OverrideDepthEnable
local render_OverrideColorWriteEnable = render.OverrideColorWriteEnable
local render_SetStencilZFailOperation = render.SetStencilZFailOperation
local render_SetStencilTestMask = render.SetStencilTestMask
local render_MaterialOverride = render.MaterialOverride
local render_MaterialOverride = render.MaterialOverride
local render_SetStencilEnable = render.SetStencilEnable
local render_SetColorModulation = render.SetColorModulation

local math_min 		= math.min

local GetBodygroupMask = util.GetBodygroupMask

local MAT_CACHE = {}

AccessorFunc(ENT, "player_color", "PlayerColor")

function ENT:Initialize()
	self.Created = CurTime()
	self:DrawShadow(false)
	self:DestroyShadow()

	self.GS2Decals = {}
end

function ENT:SetBody(body, phys_bone)
	self.Body = body
	self.PhysBone = phys_bone
	self.Bone = body:TranslatePhysBoneToBone(phys_bone)

	if phys_bone == 0 and body:GetBonePosition(self.Bone) != body:GetPos() then
		self.IsDerpy = true --sometimes zombies get weird if they release their headcrab on death
	else
		self:FollowBone(self.Body, self.Bone)
		self:SetLocalPos(vector_origin)
		self:SetLocalAngles(angle_zero)
	end
	
	/*if (self.Mesh and !self.look_for_material) then
		local skin = body:GetSkin()
		if (skin > 0) then
			local mat = body:GetMaterials()[skin + 1]
			if mat then
				MAT_CACHE[mat] = MAT_CACHE[mat] or Material(mat)
				self.Mesh.Material = MAT_CACHE[mat]
			end
		end
	end*/

	self.SkinGroups = GetSkinGroups(body:GetModel())
	self.BGMask = GetBodygroupMask(body)
end

function ENT:SetMesh(meshes)local t = SysTime()
	if !meshes then print"uh oh" return end
	self.meshes = meshes
	for _, meshes in ipairs(meshes) do
		if (meshes.body and meshes.flesh and meshes.flesh.Material:IsError()) then
			meshes.flesh.Material = meshes.body.Material
		end
	end
end

function ENT:GetMesh()
	return self.meshes
end

function ENT:Think()
	if IsValid(self.Body) then	
		if !IsValid(self.GS2ParentLimb) then
			SafeRemoveEntity(self)
			return
		end
		local mask = self.GS2ParentLimb:GetGibMask()

		if (bit_band(mask, bit_lshift(1, self.PhysBone)) != 0) then
			self:Remove()
			return
		end
		
		local min, max = self.Body:GetRenderBounds()
		min = self.Body:LocalToWorld(min)
		max = self.Body:LocalToWorld(max)
		self:SetRenderBoundsWS(min, max)

		local skin = self.Body:GetSkin()

		if self.Skin != skin then
			local skin_group = self.SkinGroups[skin + 1]

			if skin_group and self.meshes then
				self.Skin = skin
				for _, meshes in ipairs(self.meshes) do		
					if meshes.body then						
						local replace = skin_group[meshes.body.mat_name]
						if replace then
							meshes.body.Material = replace
						end						
					end
				end
			end
		end

		local mask = GetBodygroupMask(self.Body)

		if self.BGMask != mask then
			self.BGMask = mask
			self:SetMesh(GetBoneMeshes(self.Body, self.PhysBone))
		end
	elseif (self.Created and CurTime() - self.Created > 1) then
		self:Remove()
	end
end

local function null() end

local mat_def = Material("debug/wireframe")

local lhack_matrix = Matrix()

local wireframe_decals = GetConVar("r_modelwireframedecal")

local mat_wf = Material("models/wireframe")

function ENT:Draw()
	self:AddEFlags(2048) --EFL_DIRTY_ABSTRANSFORM this gets unset when phys 0 of the ragdoll goes to sleep for whatever reason ¯\_(ツ)_/¯

	if self.IsDerpy then
		local pos, ang = self.Body:GetBonePosition(0)
		self:SetPos(pos)
		self:SetAngles(ang)
	elseif self.Bone == 0 then
		--bone 0 doesnt update angles properly
		self.AngleMatrix = self.Body:GetBoneMatrix(0)
		self.AngleMatrix:SetTranslation(vector_origin)		
	end

	local body = self.Body
	body.RenderOverride = null

	for _, meshes in ipairs(self.meshes) do
		if (meshes.body and !meshes.body.Mesh:IsValid()) then
			--try recreate it		
			meshes.body.Mesh = Mesh()
			meshes.body.Mesh:BuildFromTriangles(meshes.body.tris)
			if !meshes.body.Mesh:IsValid() then
				continue
			end
		end
		if (meshes.flesh and !meshes.flesh.Mesh:IsValid()) then
			--try recreate it		
			meshes.flesh.Mesh = Mesh()
			meshes.flesh.Mesh:BuildFromTriangles(meshes.flesh.tris)
			if !meshes.flesh.Mesh:IsValid() then
				continue
			end		
		end

		--self:UpdateRenderPos()
		--local matrix = self.Mesh and self.Mesh.Matrix
		
		if body.GS2Dissolving then
			local start = body.GS2Dissolving[self.PhysBone]
			if start then
				local mod = 1 - math_min(1, CurTime() - start)
				render_SetColorModulation(mod, mod, mod)
			end
		end
		if meshes.flesh then		
			self.is_flesh = true
			self.Mesh = meshes.flesh		
			self.Mesh.Matrix = self.AngleMatrix
			self:DrawModel()
		end

		if !meshes.body then
			render_SetColorModulation(1, 1, 1)
			continue
		end

		self.is_flesh = false
		self.Mesh = meshes.body
		self.Mesh.Matrix = self.AngleMatrix
		
		if (!self.Mesh or !self.Mesh.Mesh) then return end

		local mat = self.Mesh.Material

		if mat:GetShader():find("^Eye") then
			mat:SetVector("$irisu", vector_origin) --fixes black eyes somehow!
		end

		--self.Mesh.Matrix = matrix
		self:DrawModel()

		if wireframe_decals:GetBool() then
			render_MaterialOverride(mat_wf)
			render_SetColorModulation(0.3, 1, 1)
		end

		for key, decal in pairs(self.GS2Decals) do
			if !decal.Mesh then
				self.GS2Decals[key] = nil
			else
				self.Mesh = decal
				self.Mesh.Matrix = self.AngleMatrix

				self:DrawModel()
			end
		end

		render_MaterialOverride()

		render_SetColorModulation(1, 1, 1)
	end
end

/*function ENT:UpdateRenderPos()
	if self.Mesh and IsValid(self.Body) then
		self.Body:SetupBones()	
		local matrix = self.Body:GetBoneMatrix(self.Bone)
		if matrix then
			local bone_pos = matrix:GetTranslation()
			self:SetRenderOrigin(bone_pos)
			
			--Ugly hack to get proper lighting on the mesh
			lhack_matrix:Identity()

			lhack_matrix:Translate(-bone_pos)

			self.Mesh.Matrix = lhack_matrix * matrix			
		end		
	end
end*/

function ENT:GetRenderMesh()	
	return self.Mesh	
end

function ENT:AddDecal(mat, pos, norm, size)
	if !mat then return end
	mat = Material(mat)
	for _, mesh in ipairs(self.meshes) do				
		local mmat = mat:GetString("$modelmaterial")
		if mmat then
			mat = Material(mmat)
		end

		local scale = mat:GetFloat("$decalscale")

	--mat = Material("models/wireframe")
		if mesh.body then
			local mesh_decal, tris = GetDecalMesh(mesh.body, pos, norm, size, size, scale)
			if IsValid(mesh_decal) then		
				local decal = {
					Mesh = mesh_decal,
					Material = mat
				}
				
				table.insert(self.GS2Decals, decal)				
			end
		end
		if mesh.flesh then
			local mesh_decal, tris = GetDecalMesh(mesh.flesh, pos, norm, size, size, scale)
			if IsValid(mesh_decal) then		
				local decal = {
					Mesh = mesh_decal,
					Material = mat
				}
				
				table.insert(self.GS2Decals, decal)				
			end
		end
	end
end

/*function ENT:OnRemove()
	for _, mesh in pairs(self.meshes) do
		if IsValid(mesh.Mesh) then
			mesh.Mesh:Destroy()
		end
	end
	for _, decal in pairs(self.GS2Decals) do
		if IsValid(decal.Mesh) then
			decal.Mesh:Destroy()
		end
	end
end*/