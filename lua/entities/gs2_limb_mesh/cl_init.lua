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
		
		local min, max = self.Body:GetCollisionBounds()--self.Body:GetRenderBounds() render bounds can be 0 sometimes ?!?!
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
	local body = self.Body
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
		self:DrawModel()
	end

	if !self.meshes.body then
		render_SetColorModulation(1, 1, 1)
		return
	end

	self.is_flesh = false
	self.Mesh = self.meshes.body

	self:DrawModel()

	if (body.GS2BulletHoles and body.GS2BulletHoles[self.PhysBone]) then
		--The stencil stuff looks weird from some angles but what can you do ¯\_(ツ)_/¯
		render_SetStencilEnable(true)
		render_ClearStencil()

		render_SetStencilReferenceValue(0xFF)

		render_SetStencilFailOperation(STENCIL_KEEP)		
		render_SetStencilWriteMask(1)

		render_OverrideDepthEnable(true, false)
		render_OverrideColorWriteEnable(true, false)

		for _, hole in pairs(body.GS2BulletHoles[self.PhysBone]) do			
			local lpos = hole:GetLocalPos()
			local lang = hole:GetLocalAng()

			local pos, ang = LocalToWorld(lpos, lang, body:GetBonePosition(self.Bone))
			
			hole:SetRenderOrigin(pos)
			hole:SetRenderAngles(ang)
			
			render_SetStencilCompareFunction(STENCIL_ALWAYS)
			render_SetStencilPassOperation(STENCIL_KEEP)
			render_SetStencilZFailOperation(STENCIL_REPLACE)
			render_SetStencilWriteMask(1)

			render_CullMode(MATERIAL_CULLMODE_CW)
			hole:DrawModel()
			render_CullMode(MATERIAL_CULLMODE_CCW)

			render_SetStencilCompareFunction(STENCIL_EQUAL)
			render_SetStencilPassOperation(STENCIL_REPLACE)
			render_SetStencilZFailOperation(STENCIL_KEEP)

			render_SetStencilTestMask(1)
			render_SetStencilWriteMask(2)	
			
			hole:DrawModel()	
			
			hole:SetNoDraw(true)
		end
		
		render_OverrideDepthEnable(false)
		render_OverrideColorWriteEnable(false)

		render_SetStencilZFailOperation(STENCIL_KEEP)
		render_SetStencilTestMask(2)

		render_MaterialOverride(self.meshes.body.flesh_mat)

		self:DrawModel()

		render_MaterialOverride()

		render_SetStencilEnable(false)
	else
		self:DrawModel()
	end

	render_SetColorModulation(1, 1, 1)
end

function ENT:GetRenderMesh()
	if self.Mesh and IsValid(self.Body) then		
		local matrix = self.Body:GetBoneMatrix(self.Bone)
		if matrix then
			local bone_pos = matrix:GetTranslation()
			self:SetRenderOrigin(bone_pos)
			
			--Ugly hack to get proper lighting on the mesh
			lhack_matrix:Identity()

			lhack_matrix:Translate(-bone_pos)

			self.Mesh.Matrix = lhack_matrix * matrix
			return self.Mesh
		end
	end
end