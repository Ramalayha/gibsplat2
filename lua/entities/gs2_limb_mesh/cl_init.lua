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

local MAT_CACHE = {}

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

	if (self.Mesh and !self.look_for_material) then
		local skin = body:GetSkin()
		if (skin > 0) then
			local mat = body:GetMaterials()[skin + 1]
			if mat then
				MAT_CACHE[mat] = MAT_CACHE[mat] or Material(mat)
				self.Mesh.Material = MAT_CACHE[mat]
			end
		end
	end
end

function ENT:SetMesh(meshes)
	self.meshes = meshes
	if (meshes.body and meshes.flesh and meshes.flesh.Material:IsError()) then
		meshes.flesh.Material = meshes.body.Material
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
	elseif (self.Created and CurTime() - self.Created > 1) then
		self:Remove()
	end
end

local function null() end

local mat_def = Material("debug/wireframe")

local lhack_matrix = Matrix()

function ENT:Draw()
	if (self.meshes.body and !self.meshes.body.Mesh:IsValid()) then
		--try recreate it		
		self.meshes.body.Mesh = Mesh()
		self.meshes.body.Mesh:BuildFromTriangles(self.meshes.body.tris)
		if !self.meshes.body.Mesh:IsValid() then
			return
		end
	end
	if (self.meshes.flesh and !self.meshes.flesh.Mesh:IsValid()) then
		--try recreate it		
		self.meshes.flesh.Mesh = Mesh()
		self.meshes.flesh.Mesh:BuildFromTriangles(self.meshes.flesh.tris)
		if !self.meshes.flesh.Mesh:IsValid() then
			return
		end		
	end

	self:UpdateRenderPos()
	local matrix = self.Mesh and self.Mesh.Matrix
	local body = self.Body
	body.RenderOverride = null
	if body.GS2Dissolving then
		local start = body.GS2Dissolving[self.PhysBone]
		if start then
			local mod = 1 - math_min(1, CurTime() - start)
			render_SetColorModulation(mod, mod, mod)
		end
	end
	if self.meshes.flesh then
		self.is_flesh = true
		self.Mesh = self.meshes.flesh
		self.Mesh.Matrix = matrix
		self:DrawModel()
	end

	if !self.meshes.body then
		render_SetColorModulation(1, 1, 1)
		return
	end

	self.is_flesh = false
	self.Mesh = self.meshes.body
	
	if (!self.Mesh or !self.Mesh.Mesh) then return end

	local mat = self.Mesh.Material

	if mat:GetShader():find("^Eye") then
		mat:SetVector("$irisu", vector_origin) --fixes black eyes somehow!
	end

	self.Mesh.Matrix = matrix
	self:DrawModel()

	for key, decal in pairs(self.GS2Decals) do
		if !decal.Mesh then
			self.GS2Decals[key] = nil
		else
			self.Mesh = decal
			self.Mesh.Matrix = matrix
			self:DrawModel()
		end
	end

	render_SetColorModulation(1, 1, 1)
end

function ENT:UpdateRenderPos()
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
end

function ENT:GetRenderMesh()	
	return self.Mesh	
end

function ENT:AddDecal(mesh, mat, pos, norm, size)
	if (!mesh.Material or !mesh.Material:GetShader():find("Generic$")) then
		return
	end
	
	local mesh_decal, tris = GetDecalMesh(mesh, pos, norm, size, size)
	if mesh_decal then
		local decal = {
			Mesh = mesh_decal,
			Material = Material(mat)
		}
		table.insert(self.GS2Decals, decal)
		return decal
	end
end

function ENT:OnRemove()
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
end