include("shared.lua")
include("gibsplat2/gibs.lua")

local MAX_RAGDOLL_PARTS = 23

local SetColorModulation = render.SetColorModulation

local CurTime 	= CurTime
local min 		= math.min

local bor 		= bit.bor
local band 		= bit.band
local lshift 	= bit.lshift
local bnot 		= bit.bnot

local text = file.Read("data/gs2/skeletons.txt", "GAME")

local skeleton_parts = util.KeyValuesToTable(text or "").skeleton_parts or {}

local function GetOrCreateSkel(self, bone)
	local mdl = self:GetModel()
	
	local body_type = GS2GetBodyType(mdl)

	local parts = skeleton_parts[body_type]

	if !parts then		
		return NULL
	end

	local bone_name = self:GetBoneName(bone):lower()

	local bone_mdl = parts[bone_name]

	if !bone_mdl then		
		return NULL
	end

	local part = ClientsideModel(bone_mdl)
	part:SetSkin(2)
	part:SetupBones()
	part:SetNoDraw(true)
	
	return part
end

function ENT:Initialize()
	self.bone_trans = {}
	self.LastMask = 0
end

function ENT:Think()
	local body = self:GetBody()

	local dis_mask = body:GetNWInt("GS2DisMask", 0)
	local gib_mask = body:GetNWInt("GS2GibMask", 0)

	local mask = bor(dis_mask, gib_mask)

	if (self.LastMask != mask) then
		self.LastMask = mask
		for phys_bone = 0, MAX_RAGDOLL_PARTS do
			if band(mask, lshift(1, phys_bone)) != 0 then
				local bone = body:TranslatePhysBoneToBone(phys_bone)
				if (bone == 0 and phys_bone != 0) then
					break
				end
				local parent_bone = body:GetBoneParent(bone)
				local parent_phys_bone = body:TranslateBoneToPhysBone(parent_bone)
				parent_bone = body:TranslatePhysBoneToBone(parent_phys_bone)

				local part = self.bone_trans[bone] or GetOrCreateSkel(body, bone)
				self.bone_trans[bone] = part

				if IsValid(part) then
					local body_group = part:FindBodygroupByName(body:GetBoneName(parent_bone))
					if (body_group != -1) then
						part:SetBodygroup(body_group, 1)
					end
				end

				if (band(gib_mask, lshift(1, parent_phys_bone)) == 0) then
					local part = self.bone_trans[parent_bone] or GetOrCreateSkel(body, parent_bone)
					
					self.bone_trans[parent_bone] = part

					if IsValid(part) then
						local body_group = part:FindBodygroupByName(body:GetBoneName(bone))
						
						if (body_group != -1) then
							part:SetBodygroup(body_group, 1) 
						end
					end
				end
			end
		end
	end
end

function ENT:Draw()
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end

	local dis_mask = body:GetNWInt("GS2DisMask", 0)
	local gib_mask = body:GetNWInt("GS2GibMask", 0)

	for phys_bone = 0, MAX_RAGDOLL_PARTS do
		if band(dis_mask, lshift(1, phys_bone)) != 0 then
			local bone = body:TranslatePhysBoneToBone(phys_bone)
			if (bone == 0 and phys_bone != 0) then
				break
			end

			if body.GS2Dissolving then
				local start = body.GS2Dissolving[phys_bone]
				if start then
					local mod = 1 - min(1, CurTime() - start)
					SetColorModulation(mod, mod, mod)
				end
			end

			if band(gib_mask, lshift(1, phys_bone)) == 0 then
				local part = self.bone_trans[bone]
				if !part then
					part = GetOrCreateSkel(body, bone)
					self.bone_trans[bone] = part
				end

				if IsValid(part) then											
					local matrix = body:GetBoneMatrix(bone)	
					local pos, ang = matrix:GetTranslation(), matrix:GetAngles()			
					part:SetRenderOrigin(pos)
					part:SetRenderAngles(ang)	
					render.SetLightingOrigin(pos)				
					part:SetupBones()					
					part:DrawModel()					
				end
			end

			local parent_bone = body:GetBoneParent(bone)
			local parent_phys_bone = body:TranslateBoneToPhysBone(parent_bone)
			parent_bone = body:TranslatePhysBoneToBone(parent_phys_bone)

			if (band(gib_mask, lshift(1, parent_phys_bone)) == 0) then
				local part = self.bone_trans[parent_bone]
				if !part then
					part = GetOrCreateSkel(body, parent_bone)
					self.bone_trans[parent_bone] = part
				end

				if IsValid(part) then					
					local matrix = body:GetBoneMatrix(parent_bone)					
					local pos, ang = matrix:GetTranslation(), matrix:GetAngles()			
					part:SetRenderOrigin(pos)
					part:SetRenderAngles(ang)	
					render.SetLightingOrigin(pos)	
					part:SetupBones()
					part:DrawModel()					
				end
			end

			SetColorModulation(1, 1, 1)
		end
	end	
end