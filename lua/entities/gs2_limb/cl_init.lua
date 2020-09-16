include("shared.lua")

include("gibsplat2/constraintinfo.lua")
include("gibsplat2/buildmesh.lua")

local STUMP_DEPTH_FACTOR = 0.7

local GetModelConstraintInfo 	= GetModelConstraintInfo
local GetBoneMeshes				= GetBoneMeshes

local CurTime 	= CurTime
local min 		= math.min

local lshift 	= bit.lshift
local band 		= bit.band
local bor 		= bit.bor

local MaterialOverride 		= render.MaterialOverride
local SetColorModulation 	= render.SetColorModulation

local vec_zero = Vector(0,0,0)
local matrix_inf = Matrix()
matrix_inf:Translate(Vector(math.huge))

net.Receive("GS2Dissolve", function()
	local ent = net.ReadEntity()
	local start = net.ReadFloat()
	local mask = net.ReadUInt(32)

	ent.GS2Dissolving = ent.GS2Dissolving or {}

	for phys_bone = 0, 23 do
		if (band(mask, lshift(1, phys_bone)) != 0) then
			ent.GS2Dissolving[phys_bone] = start
		end
	end
end)

function ENT:Initialize()
	self:SetLOD(0)
	self:DrawShadow(false)
	self:DestroyShadow()

	self._LastDisMask = 0
	self._LastGibMask = 0
	self.Created = CurTime()

	self.GS2BoneList = {}
end

function ENT:OnRemove()
	if self.GS2RenderMeshes then
		for _, mesh in pairs(self.GS2RenderMeshes) do
			SafeRemoveEntity(mesh)
		end
	end
end

function ENT:Think()
	local body = self:GetBody()
	if IsValid(body) then
		body.GS2Limbs = body.GS2Limbs or {}
		body.GS2Limbs[self:GetTargetBone()] = self
		
		self:SetParent(body)
		if (self:GetModel() != body:GetModel()) then
			self:SetModel(body:GetModel())
			for _, bg in pairs(body:GetBodyGroups()) do
				self:SetBodygroup(bg.id, body:GetBodygroup(bg.id))
			end
		end
		if !self.flesh_mat then
			local phys_mat = body:GetNWString("GS2PhysMat", "")
			if phys_mat != "" then
				if file.Exists("materials/models/"..phys_mat..".vmt", "GAME") then
					self.flesh_mat = Material("models/"..phys_mat)
				else
					self.flesh_mat = NULL
				end
			end
		end
		local min, max = body:GetCollisionBounds()--self.Body:GetRenderBounds() render bounds can be 0 sometimes ?!?!
		min = body:LocalToWorld(min)
		max = body:LocalToWorld(max)
		self:SetRenderBoundsWS(min, max)
	end
	
	local dis_mask = self:GetDisMask()
	local gib_mask = self:GetGibMask()
	if self._LastDisMask != dis_mask or self._LastGibMask != gib_mask then
		self._LastDisMask = dis_mask
		self._LastGibMask = gib_mask
		self:UpdateRenderInfo()
	end
	local body = self:GetBody()
	if IsValid(body) then		
		local pos = body:GetBonePosition(body:TranslatePhysBoneToBone(self:GetTargetBone() or 0))
		if pos then
			self:SetPos(pos)
			self:SetRenderOrigin(pos)
			self:SetupBones()
		end
	end
end

local dummy_tbl = {}

function ENT:UpdateChildBonesRec(bone, mask, bone_override)
	local body = self:GetBody()
	
	if !IsValid(body) then return end
	
	if bone_override then
		local parent_bone = bone
		repeat
			if (self:GetBoneParent(parent_bone) == bone_override) then
				break
			end
			parent_bone = self:GetBoneParent(parent_bone)
		until (parent_bone == -1)

		if (parent_bone != -1) then
			local bone_matrix = self:GetBoneMatrix(parent_bone)

			local bone_pos, bone_ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()

			local bone_override_matrix = self:GetBoneMatrix(bone_override)

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
	for _, child_bone in pairs(self:GetChildBones(bone) or dummy_tbl) do
		if bone_override then
			self:UpdateChildBonesRec(child_bone, mask, bone_override)
		else
			local phys_bone = body:TranslateBoneToPhysBone(child_bone)
			if phys_bone != self:GetTargetBone() and band(mask, lshift(1, phys_bone)) != 0 then
				self:UpdateChildBonesRec(child_bone, mask, bone)				
			else
				self:UpdateChildBonesRec(child_bone, mask)
			end
		end
	end
end

function ENT:UpdateRenderInfo()
	local dis_mask = self:GetDisMask()
	local gib_mask = self:GetGibMask()

	local self_phys_bone = self:GetTargetBone() or 0
	local self_mask = lshift(1, self_phys_bone)
	
	if band(self_mask, gib_mask) != 0 then
		if self.GS2RenderMeshes then
			for _, mesh in pairs(self.GS2RenderMeshes) do
				SafeRemoveEntity(mesh)
			end	
			self.GS2RenderMeshes = nil
		end		
		return
	end

	if self.GS2RenderMeshes then return end --Already at mesh stage, nothing can change from here

	--Checks if any other parts of the ragdoll are attached to us
	local is_lonely = true
	for _, part_info in pairs(GetModelConstraintInfo(self:GetModel())) do
		if part_info.parent == self_phys_bone and band(dis_mask, lshift(1, part_info.child)) == 0 then
			is_lonely = false
			break			
		end
	end
	
	local body = self:GetBody()
	
	if is_lonely then
		self.GS2RenderMeshes = {}
		
		if IsValid(body) then
			--If no other parts are attached generate a mesh to optimize
			local meshes = GetBoneMeshes(body, self_phys_bone)
			for key, mesh in pairs(meshes) do
				local M = ents.CreateClientside("gs2_limb_mesh")
				M:SetMesh(mesh)
				M:SetBody(body, self_phys_bone)				
				M:Spawn()

				M.GS2ParentLimb = self
				self.GS2RenderMeshes[key] = M
			end		
		end 
	else
		self:SetupBones()
		body:SetupBones()
		--Otherwise update bone info
		table.Empty(self.GS2BoneList)		
		self:UpdateChildBonesRec(self:TranslatePhysBoneToBone(self_phys_bone), bor(dis_mask, gib_mask))	
	end
end

local function null() end

function ENT:Draw()
	local body = self:GetBody()
	if IsValid(body) then
		body.RenderOverride = null --Hide actual ragdoll
		if !self.GS2RenderMeshes and self.GS2BoneList then
			--Scale bones and draw			
			local self_phys_bone = self:GetTargetBone()
			if body.GS2Dissolving then
				local start = body.GS2Dissolving[self_phys_bone]
				if start then
					local mod = 1 - min(1, CurTime() - start)
					SetColorModulation(mod, mod, mod)
				end
			end		
									
			--self:SnatchModelInstance(body) --Transfers decals

			--Draw flesh
			body:SetupBones()
			self:SetupBones()
			
			local self_bone = self:TranslatePhysBoneToBone(self_phys_bone)
			local self_matrix = body:GetBoneMatrix(self_bone)
			if !self_matrix then
				return
			end
			self_matrix:Scale(vec_zero)
			
			for bone = 0, self:GetBoneCount()-1 do
				if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
					local info = self.GS2BoneList[bone]
					local matrix
					if info then
						if (info.parent == bone) then
							matrix = body:GetBoneMatrix(bone)
						else
							matrix = body:GetBoneMatrix(info.parent) * info.matrix
							matrix:Scale(vec_zero)
						end						
					else
						matrix = self_matrix					
					end
					self:SetBoneMatrix(bone, matrix)
				end
			end	

			if !self.flesh_mat or self.flesh_mat == NULL then --Only 1 draw call with no overlay if theres no flesh texture
				self:DrawModel()	
			else
				MaterialOverride(self.flesh_mat)
				self:DrawModel()	
				MaterialOverride()

				--Draw skin
				self:SetupBones()
				for bone = 0, self:GetBoneCount()-1 do
					if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
						local info = self.GS2BoneList[bone]
						
						if (info and info.parent == bone) then
							self:SetBoneMatrix(bone, body:GetBoneMatrix(bone))
						else
							self:SetBoneMatrix(bone, matrix_inf)				
						end
					end
				end			
				self:DrawModel()
			end

			SetColorModulation(1, 1, 1)
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
			for _, e in pairs(all) do
				if (e:EntIndex() == -1 and e:GetClass() == "class C_RopeKeyframe" and !table.HasValue(old_all, e)) then
					e:SetRenderBounds(vec_inf, vec_inf) --Disabled rendering					
				end
			end
		end)
	end
end)

hook.Add("NotifyShouldTransmit", HOOK_NAME, function(ent, should)
	if (should and ent.UpdateRenderInfo) then
		ent.GS2RenderMeshes = nil
		ent:UpdateRenderInfo()
	end
end)