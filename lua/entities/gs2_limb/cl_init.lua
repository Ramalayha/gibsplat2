include("shared.lua")

include("gibsplat2/constraintinfo.lua")
include("gibsplat2/buildmesh.lua")
include("gibsplat2/decal_util.lua")

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

local vec_zero = Vector(0, 0, 0)
local vec_offset = Vector(1, 0, 0)
local matrix_zero = Matrix()
matrix_zero:Scale(vec_zero)

local dummy = ClientsideModel("models/error.mdl")
dummy:SetNoDraw(true)

local max_decals = CreateClientConVar("gs2_max_decals_transfer", 5, true)

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

net.Receive("GS2ApplyDecal", function()
	local body = net.ReadEntity()
	if !IsValid(body) then return end
	local mat = net.ReadString()
	local pos = net.ReadVector()
	local norm = net.ReadNormal()
	
	for key, limb in pairs(body.GS2Limbs) do
		if IsValid(limb) then
			limb:ApplyDecal(util.DecalMaterial(mat.."Simple"), pos, norm, 1, 3)
		else
			body.GS2Limbs[key] = nil
		end
	end
end)

local function BuildBones(self, num_bones)
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end
	body:SetupBones()

	local self_phys_bone = self:GetTargetBone()
		
	local self_bone = self:TranslatePhysBoneToBone(self_phys_bone)
	local self_matrix = body:GetBoneMatrix(self_bone)
	if !self_matrix then
		return
	end

	if self.SkinPass then
		self_matrix:Translate(vec_offset)
		self_matrix:Scale(vec_zero)
		for bone = 0, num_bones - 1 do
			if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
				local info = self.GS2BoneList[bone]
				
				if !info then
					self:SetBoneMatrix(bone, self_matrix)
				elseif (info.parent != bone) then
					local matrix = body:GetBoneMatrix(info.parent)
					matrix:Translate(vec_offset)
					matrix:Scale(vec_zero)
					self:SetBoneMatrix(bone, matrix)
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

	self:SetupBones()

	self:DrawShadow(false)
	self:DestroyShadow()

	local phys_bone = self:GetTargetBone()

	self.mat_restore = {}

	if (phys_bone != 0) then
		for key, mat in pairs(self:GetMaterials()) do
			local mat_bloody = "!"..mat.."_bloody"
			if !Material(mat_bloody):IsError() then
				self.mat_restore[key - 1] = mat_bloody
			end
		end
	end

	self:UpdateRenderInfo()
end

function ENT:OnRemove()
	if self.GS2RenderMeshes then
		for _, mesh in ipairs(self.GS2RenderMeshes) do
			SafeRemoveEntity(mesh)
		end
	end
end

local alpha_tags = 
{
	"$additive",
	"$alpha",
	"$translucent"
}

function ENT:Think()
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
				if file.Exists("materials/models/gibsplat2/flesh/"..phys_mat..".vmt", "GAME") then
					self.flesh_mat = "models/gibsplat2/flesh/"..phys_mat
					self.flesh_mat_replace = {}
					for key, mat_name in pairs(self:GetMaterials()) do
						local text = file.Read("materials/"..mat_name..".vmt", "GAME")
						if text then
							text = text:lower()
							local has_alpha
							for _, tag in pairs(alpha_tags) do
								if text:find(tag) then
									has_alpha = true
									break
								end
							end
							if !has_alpha then
								table.insert(self.flesh_mat_replace, key - 1)
							end
						end
					end
				else
					self.flesh_mat = NULL
				end
			end
		end

		for _, bg in pairs(body:GetBodyGroups()) do
			self:SetBodygroup(bg.id, body:GetBodygroup(bg.id))
		end
		
		local min, max = body:GetRenderBounds()
		min = body:LocalToWorld(min)
		max = body:LocalToWorld(max)
		self:SetRenderBoundsWS(min, max)

		local pos = body:GetBonePosition(body:TranslatePhysBoneToBone(self_phys_bone or 0))
		if pos then
			self:SetPos(pos)
			self:SetRenderOrigin(pos)
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
	self:DestroyShadow()
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
		local bone = body:TranslatePhysBoneToBone(self_phys_bone)
		local bone_pos, bone_ang = body:GetBonePosition(bone)
		local meshes = GetBoneMeshes(body, self_phys_bone)
		if (table.Count(meshes) > 0) then
			self.GS2RenderMeshes = {}
			for key, mesh in pairs(meshes) do				
				local M = ents.CreateClientside("gs2_limb_mesh")
				M:SetBody(body, self_phys_bone)	
				M:SetMesh(mesh)	
				M:Spawn()

				M.GS2ParentLimb = self
				self.GS2RenderMeshes[key] = M

				if (mesh.body) then	
					if (body.GS2BulletHoles and body.GS2BulletHoles[self_phys_bone]) then
						local count = 0
						for key, bh in pairs(body.GS2BulletHoles[self_phys_bone]) do
							if IsValid(bh) then						
								M:AddDecal(mesh.body, util.DecalMaterial("BloodSimple"), bh:GetLPos(), bh:GetLAng(), 1)
								count = count + 1
								if (count >= max_decals:GetInt()) then
									break
								end
							else
								body.GS2BulletHoles[self_phys_bone][key] = nil
							end
						end
					end
					M:AddDecal(mesh.body, util.DecalMaterial("BloodSimple"), vector_origin, Angle(0, 0, math.Rand(-180, 180)), 3, -0.1)					
				end
			end
		end	
		if self.BBID then
			self:RemoveCallback("BuildBonePositions", self.BBID)
			self.BBID = nil			
		end
		--self:SetNoDraw(true)
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
				for _, id in pairs(self.flesh_mat_replace) do
					self:SetSubMaterial(id, self.flesh_mat)
				end
				self:DrawModel()
				for _, id in pairs(self.flesh_mat_replace) do
					self:SetSubMaterial(id, self.mat_restore[id]) --if self.mat_restore[id] == nil then it will restore to default
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

		if !self.HasDecals then
			self.HasDecals = true
			if body.GS2BulletHoles then
				if self.GS2RenderMeshes then
					local count = 0
					for phys_bone, holes in pairs(body.GS2BulletHoles) do
						for _, hole in pairs(holes) do
							if IsValid(hole) then
								hole:ApplyDecal(self)
								count = count + 1
								if (count >= max_decals:GetInt()) then
									break
								end
							end
						end
					end	
				else
					for phys_bone, holes in pairs(body.GS2BulletHoles) do
						for _, hole in pairs(holes) do
							if IsValid(hole) then
								hole:ApplyDecal(self)								
							end
						end
					end
				end	
			end
			local phys_bone = self:GetTargetBone()
			if (phys_bone != 0) then
				local bone = body:TranslatePhysBoneToBone(phys_bone)
				
				local bone_parent = body:GetBoneParent(bone)

				if bone_parent then
					local bone_pos, bone_ang = body:GetBonePosition(bone)

					local offset = vector_origin--bone_ang:Up() * 5

					local bone_dir = bone_pos - body:GetBonePosition(bone_parent)
					bone_dir:Normalize()
					--debugoverlay.Axis(bone_pos, bone_dir:Angle(), 5, 10, true)
					for _, limb in pairs(body.GS2Limbs) do
						if !IsValid(limb) then
							continue
						end
						local limb_phys_bone = limb:GetTargetBone()
						local limb_bone = body:TranslatePhysBoneToBone(limb_phys_bone)

						--if (limb == self or body:TranslateBoneToPhysBone(body:GetBoneParent(bone)) == limb_phys_bone) then
						if (limb == self) then
							limb:ApplyDecal(util.DecalMaterial("BloodSimple"), bone_pos - bone_dir * 2 - offset, -bone_dir - offset, 5)
							--limb:ApplyDecal(util.DecalMaterial("BloodSimple"), bone_pos - bone_dir * 2 + offset, -bone_dir + offset, 5)
						else
							local parent = body:GetBoneParent(bone)
							repeat
								if (parent == limb_bone) then
									break
								end
								parent = body:GetBoneParent(parent)
							until (parent == -1)
							if (parent != -1) then
								limb:ApplyDecal(util.DecalMaterial("BloodSimple"), bone_pos + bone_dir * 2 + offset, bone_dir + offset, 5)
								--limb:ApplyDecal(util.DecalMaterial("BloodSimple"), bone_pos + bone_dir * 2 - offset, bone_dir - offset, 5)						
							end
						end					
					end
				end
			end
		end
	end
end

function ENT:ApplyDecal(mat, pos, norm, size, mesh_size)
	ApplyDecal(mat, self, pos, norm, size)
	self.GS2Decals = self.GS2Decals or {}

	local body = self:GetBody()

	local phys_bone = self:GetTargetBone()
	local bone = body:TranslatePhysBoneToBone(phys_bone)

	local lpos, lang = WorldToLocal(pos, norm:Angle(), body:GetBonePosition(bone))

	table.insert(self.GS2Decals, {
		LPos = lpos,
		LAng = lang,
		Material = mat,
		Size = size
	})

	if self.GS2RenderMeshes then
		for _, M in pairs(self.GS2RenderMeshes) do
			if M.meshes.body then
				M:AddDecal(M.meshes.body, mat, lpos, lang, mesh_size or size)
			end	
			if M.meshes.flesh then
				M:AddDecal(M.meshes.flesh, mat, lpos, lang, mesh_size or size)
			end	
		end
	end
end

local vec_inf = Vector()/0

local HOOK_NAME = "GibSplat2"

--Removes ropes from models that have them
hook.Add("OnEntityCreated", HOOK_NAME, function(ent)
	if ent:IsRagdoll() or ent:GetClass() == "gs2_limb" then
		local old_all = ents.GetAll()
		timer.Simple(0.1, function()
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
		timer.Simple(1, function()
			if IsValid(ent) then
				ent:UpdateRenderInfo()
			end
		end)
	end
end)