include("shared.lua")

local SetColorModulation = render.SetColorModulation

local CurTime 	= CurTime
local min 		= math.min

local MAT_CACHE = {}

function ENT:Initialize()
	
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

function ENT:SetMesh(mesh)
	self.Mesh = mesh
	self.look_for_material = mesh.look_for_material
end

function ENT:Think()
	if IsValid(self.Body) then
		local mask = self.GS2ParentLimb:GetGibMask()

		if (bit.band(mask, bit.lshift(1, self.PhysBone)) != 0) then
			self:Remove()
			return
		end
		
		local min, max = self.Body:GetCollisionBounds()--self.Body:GetRenderBounds() render bounds can be 0 sometimes ?!?!
		min = self.Body:LocalToWorld(min)
		max = self.Body:LocalToWorld(max)
		self:SetRenderBoundsWS(min, max)

		local phys_mat = self.Body:GetNWString("GS2PhysMat")
		if !self.is_flesh and phys_mat and !self.FleshMat then				
			self.FleshMat = Material("models/"..phys_mat)					
		end
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
			local mod = 1 - min(1, CurTime() - start)
			SetColorModulation(mod, mod, mod)
		end
	end
	self:DrawModel()	
	if !self.is_flesh and self.FleshMat and !self.FleshMat:IsError() and body.GS2BulletHoles and body.GS2BulletHoles[self.PhysBone] then
		--The stencil stuff looks weird from some angles but what can you do ¯\_(ツ)_/¯
		render.SetStencilEnable(true)
		render.ClearStencil()

		render.SetStencilReferenceValue(0xFF)

		render.SetStencilFailOperation(STENCIL_KEEP)		
		render.SetStencilWriteMask(1)

		render.OverrideDepthEnable(true, false)
		render.OverrideColorWriteEnable(true, false)

		for _, hole in pairs(body.GS2BulletHoles[self.PhysBone]) do			
			local lpos = hole:GetLocalPos()
			local lang = hole:GetLocalAng()

			local pos, ang = LocalToWorld(lpos, lang, body:GetBonePosition(self.Bone))
			
			hole:SetRenderOrigin(pos)
			hole:SetRenderAngles(ang)
			
			render.SetStencilCompareFunction(STENCIL_ALWAYS)
			render.SetStencilPassOperation(STENCIL_KEEP)
			render.SetStencilZFailOperation(STENCIL_REPLACE)
			render.SetStencilWriteMask(1)

			render.CullMode(MATERIAL_CULLMODE_CW)
			hole:DrawModel()
			render.CullMode(MATERIAL_CULLMODE_CCW)

			render.SetStencilCompareFunction(STENCIL_EQUAL)
			render.SetStencilPassOperation(STENCIL_REPLACE)
			render.SetStencilZFailOperation(STENCIL_KEEP)

			render.SetStencilTestMask(1)
			render.SetStencilWriteMask(2)	
			
			hole:DrawModel()	
			
			hole:SetNoDraw(true)
		end
		
		render.OverrideDepthEnable(false)
		render.OverrideColorWriteEnable(false)

		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.SetStencilTestMask(2)

		render.MaterialOverride(self.FleshMat)

		self:DrawModel()

		render.MaterialOverride()

		render.SetStencilEnable(false)
	end

	SetColorModulation(1, 1, 1)
end

function ENT:GetRenderMesh()
	if self.Mesh and IsValid(self.Body) then
		if self.look_for_material then
			local phys_mat = self.Body:GetNWString("GS2PhysMat")
			if phys_mat then				
				if file.Exists("materials/models/"..phys_mat..".vmt", "GAME") then
					self.Mesh.Material = Material("models/"..phys_mat)		
				end
				self.look_for_material = nil
				self.is_flesh = true
			end
		end
		local matrix = self.Body:GetBoneMatrix(self.Bone)
		if matrix then
			local bone_pos = matrix:GetTranslation()
			self:SetRenderOrigin(bone_pos)
			
			--Ugly hack to get proper lighting on the mesh
			lhack_matrix:Identity()

			lhack_matrix:Translate(-bone_pos)

			self.Mesh.Matrix = lhack_matrix * self.Body:GetBoneMatrix(self.Bone)
			return self.Mesh
		end
	end
end