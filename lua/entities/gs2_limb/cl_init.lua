include("shared.lua")

include("gibsplat2/constraintinfo.lua")
include("gibsplat2/buildmesh.lua")

local STUMP_DEPTH_FACTOR = 0.7

local pairs = pairs

local math_min 		= math.min

local bit_lshift 	= bit.lshift
local bit_band 		= bit.band
local bit_bor 		= bit.bor

local render_SetColorModulation = render.SetColorModulation
local render_MaterialOverride = render.MaterialOverride
local render_MaterialOverride = render.MaterialOverride
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
local render_SetStencilCompareFunction = render.SetStencilCompareFunction
local render_SetStencilZFailOperation = render.SetStencilZFailOperation
local render_SetStencilTestMask = render.SetStencilTestMask
local render_SetStencilEnable = render.SetStencilEnable
local render_SetColorModulation = render.SetColorModulation

local table_Empty = table.Empty
local table_HasValue = table.HasValue

local vec_zero = Vector(0,0,0)
local matrix_inf = Matrix()
matrix_inf:Translate(Vector(math.huge))

local dummy = ClientsideModel("models/error.mdl")
dummy:SetNoDraw(true)

net.Receive("GS2Dissolve", function()
	local ent = net.ReadEntity()
	if !IsValid(ent) then
		return
	end
	
	local start = net.ReadFloat()
	local mask = net.ReadUInt(32)

	ent.GS2Dissolving = ent.GS2Dissolving or {}

	for phys_bone = 0, 23 do
		if (bit_band(mask, bit_lshift(1, phys_bone)) != 0) then
			ent.GS2Dissolving[phys_bone] = start
		end
	end
end)

local function BuildBones(self, num_bones)
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end
	body:SetupBones()
	if self.SkinPass then
		for bone = 0, num_bones - 1 do
			if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
				local info = self.GS2BoneList[bone]
				
				if (!info or info.parent != bone) then
					self:SetBoneMatrix(bone, matrix_inf)
				else
					local matrix = body:GetBoneMatrix(bone)
					if matrix then
						self:SetBoneMatrix(bone, matrix)
					end
				end				
			end
		end	
		return
	end

	local self_phys_bone = self:GetTargetBone()
		
	local self_bone = self:TranslatePhysBoneToBone(self_phys_bone)
	local self_matrix = body:GetBoneMatrix(self_bone)
	if !self_matrix then
		return
	end
	self_matrix:Scale(vec_zero)
	
	for bone = 0, num_bones - 1 do
		if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
			local info = self.GS2BoneList[bone]
			local matrix
			if info then
				if (info.parent == bone) then
					matrix = body:GetBoneMatrix(info.parent)					
				else
					matrix = body:GetBoneMatrix(info.parent) * info.matrix
					matrix:Scale(vec_zero)
				end				
			end
			
			self:SetBoneMatrix(bone, matrix or self_matrix)
		end
	end	
end

function ENT:Initialize()
	self:SetLOD(0)
	
	self.GS2BoneList = {}

	self.BBID = self:AddCallback("BuildBonePositions", BuildBones)
end

function ENT:OnRemove()
	if self.GS2RenderMeshes then
		for _, mesh in ipairs(self.GS2RenderMeshes) do
			SafeRemoveEntity(mesh)
		end
	end
end

function ENT:Think()
	if self.DoUpdate then
		self.DoUpdate = nil
		self:UpdateRenderInfo()
	end
	local body = self:GetBody()
	local dis_mask = self:GetDisMask()
	local gib_mask = self:GetGibMask()

	local self_phys_bone = self:GetTargetBone()
	
	if IsValid(body) then
		if !self.flesh_mat then
			body.GS2Limbs = body.GS2Limbs or {}
			body.GS2Limbs[self_phys_bone] = self
			
			self:SetParent(body)
			if (self:GetModel() != body:GetModel()) then
				self:SetModel(body:GetModel())				
			end
			local phys_mat = body:GetNWString("GS2PhysMat", "")
			if phys_mat != "" then
				if file.Exists("materials/models/"..phys_mat..".vmt", "GAME") then
					self.flesh_mat = Material("models/"..phys_mat)
				else
					self.flesh_mat = NULL
				end
			end
		end

		for _, bg in pairs(body:GetBodyGroups()) do
			self:SetBodygroup(bg.id, body:GetBodygroup(bg.id))
		end
		
		local min, max = body:GetCollisionBounds()--self.Body:GetRenderBounds() render bounds can be 0 sometimes ?!?!
		min = body:LocalToWorld(min)
		max = body:LocalToWorld(max)
		self:SetRenderBoundsWS(min, max)

		local pos = body:GetBonePosition(body:TranslatePhysBoneToBone(self_phys_bone or 0))
		if pos then
			--self:SetPos(pos)
			--self:SetRenderOrigin(pos)
			self:SetupBones()
		end

		if (!self.BBID and body.GS2Dissolving and body.GS2Dissolving[self_phys_bone]) then
			self.BBID = self:AddCallback("BuildBonePositions", BuildBones)
			table_Empty(self.GS2BoneList)		
			self:UpdateChildBonesRec(self:TranslatePhysBoneToBone(self_phys_bone), bit_bor(dis_mask, gib_mask))	
		end
	end
	
	if self._LastDisMask != dis_mask or self._LastGibMask != gib_mask then
		self._LastDisMask = dis_mask
		self._LastGibMask = gib_mask
		self:UpdateRenderInfo()
	end	
end

local dummy_tbl = {}

function ENT:UpdateChildBonesRec(bone, mask, bone_override)
	local body = self:GetBody()
	
	if !IsValid(body) then return end
	
	dummy:SetModel(self:GetModel())
	dummy:SetupBones()

	if bone_override then
		local parent_bone = bone
		repeat
			if (self:GetBoneParent(parent_bone) == bone_override) then
				break
			end
			parent_bone = self:GetBoneParent(parent_bone)
		until (parent_bone == -1)

		if (parent_bone != -1) then
			local bone_matrix = dummy:GetBoneMatrix(parent_bone)

			local bone_pos, bone_ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()

			local bone_override_matrix = dummy:GetBoneMatrix(bone_override)

			local bone_override_pos, bone_override_ang = bone_override_matrix:GetTranslation(), bone_override_matrix:GetAngles()

			bone_pos, bone_ang = WorldToLocal(bone_pos, bone_ang, bone_override_pos, bone_override_ang)

			local matrix = Matrix()
			matrix:Translate(bone_pos * STUMP_DEPTH_FACTOR)

			self.GS2BoneList[bone] = {
				parent = bone_override,
				matrix = matrix
			}
		end
	else
		self.GS2BoneList[bone] = {
			parent = bone			
		}
	end
	for _, child_bone in ipairs(self:GetChildBones(bone) or dummy_tbl) do
		if bone_override then
			self:UpdateChildBonesRec(child_bone, mask, bone_override)
		else
			local phys_bone = body:TranslateBoneToPhysBone(child_bone)
			if phys_bone != self:GetTargetBone() and bit_band(mask, bit_lshift(1, phys_bone)) != 0 then
				self:UpdateChildBonesRec(child_bone, mask, bone)				
			else
				self:UpdateChildBonesRec(child_bone, mask)
			end
		end
	end
end

function ENT:UpdateRenderInfo()
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end
	local dis_mask = self:GetDisMask()
	local gib_mask = self:GetGibMask()

	local self_phys_bone = self:GetTargetBone() or 0
	local self_mask = bit_lshift(1, self_phys_bone)
	
	if (bit_band(self_mask, gib_mask) != 0) then
		if self.GS2RenderMeshes then
			for _, mesh in ipairs(self.GS2RenderMeshes) do
				SafeRemoveEntity(mesh)
			end	
			self.GS2RenderMeshes = nil
		end		
		return
	end

	if self.GS2RenderMeshes then return end --Already at mesh stage, nothing can change from here

	--Checks if any other parts of the ragdoll are attached to us
	local is_lonely = true
	for _, part_info in ipairs(GetModelConstraintInfo(self:GetModel())) do
		if part_info.parent == self_phys_bone and bit_band(dis_mask, bit_lshift(1, part_info.child)) == 0 then
			is_lonely = false
			break			
		end
	end
		
	if is_lonely then
		--If no other parts are attached generate a mesh to optimize
		local meshes = GetBoneMeshes(body, self_phys_bone)
		if (table.Count(meshes) > 0) then
			self.GS2RenderMeshes = {}
			for key, mesh in pairs(meshes) do				
				local M = ents.CreateClientside("gs2_limb_mesh")
				M:SetMesh(mesh)
				M:SetBody(body, self_phys_bone)				
				M:Spawn()

				M.GS2ParentLimb = self
				self.GS2RenderMeshes[key] = M
			end
		end	
		if self.BBID then
			self:RemoveCallback("BuildBonePositions", self.BBID)
			self.BBID = nil			
		end
		self:SetNoDraw(true)
	else		
		body:SetupBones()
		--Update bone info
		table_Empty(self.GS2BoneList)		
		self:UpdateChildBonesRec(self:TranslatePhysBoneToBone(self_phys_bone), bit_bor(dis_mask, gib_mask))	
	end
end

local function null() end

function ENT:Draw()
	local body = self:GetBody()
	if IsValid(body) then
		body.RenderOverride = null --Hide actual ragdoll
		if !self.GS2RenderMeshes and self.GS2BoneList then
			self:SetupBones()						
			if body.GS2Dissolving then
				local start = body.GS2Dissolving[self:GetTargetBone()]
				if start then
					local mod = 1 - math_min(1, CurTime() - start)
					render_SetColorModulation(mod, mod, mod)
				end
			end

			--Draw flesh
			if !self.flesh_mat or self.flesh_mat == NULL then --Only 1 draw call with no overlay if theres no flesh texture
				self:DrawModel()	
			else
				render_MaterialOverride(self.flesh_mat)
				self:DrawModel()	
				render_MaterialOverride()

				--Draw bulletholes into stencil buffer
				if body.GS2BulletHoles then
					local self_bone = body:TranslatePhysBoneToBone(self:GetTargetBone())
					render_SetStencilEnable(true)
					render_ClearStencil()

					render_SetStencilReferenceValue(0xFF)

					render_SetStencilFailOperation(STENCIL_KEEP)		
					render_SetStencilWriteMask(1)

					render_OverrideDepthEnable(true, false)
					render_OverrideColorWriteEnable(true, false)

					for phys_bone, bullet_holes in pairs(body.GS2BulletHoles) do
						local bone = body:TranslatePhysBoneToBone(phys_bone)
						local parent = bone
						repeat
							if (parent == self_bone) then
								break
							end
							parent = self:GetBoneParent(parent)
						until (parent == -1)
						
						if (parent != -1) then
							local bone_pos, bone_ang = body:GetBonePosition(bone)
							for key, hole in pairs(bullet_holes) do
								if !IsValid(hole) then
									bullet_holes[key] = nil
									continue
								end			
								
								local pos, ang = LocalToWorld(hole:GetLPos(), hole:GetLAng(), bone_pos, bone_ang)

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
						end
					end
					
					render_OverrideDepthEnable(false)
					render_OverrideColorWriteEnable(false)

					render_SetStencilCompareFunction(STENCIL_NOTEQUAL)
					render_SetStencilZFailOperation(STENCIL_KEEP)
					render_SetStencilTestMask(2)
				end				

				--Draw skin
				self.SkinPass = true
				self:SetupBones()
				self:DrawModel()
				self.SkinPass = false
					
				render_SetStencilEnable(false)
			end

			render_SetColorModulation(1, 1, 1)
		end
	end
end

local vec_inf = Vector()/0

local HOOK_NAME = "GibSplat2"

--Removes ropes from models that have them
hook.Add("OnEntityCreated", HOOK_NAME, function(ent)
	if ent:IsRagdoll() or ent:GetClass() == "gs2_limb" then
		local old_all = ents.GetAll()
		timer.Simple(0.015, function()
			local all = ents.GetAll()
			for _, e in ipairs(all) do
				if (e:EntIndex() == -1 and e:GetClass() == "class C_RopeKeyframe" and !table_HasValue(old_all, e)) then
					e:SetRenderBounds(vec_inf, vec_inf) --Disabled rendering					
				end
			end
		end)
	end
end)

hook.Add("NotifyShouldTransmit", HOOK_NAME, function(ent, should)
	if (should and ent.UpdateRenderInfo) then
		ent.GS2RenderMeshes = nil
		ent.BBID = ent:AddCallback("BuildBonePositions", BuildBones)
		ent.DoUpdate = true
	end
end)