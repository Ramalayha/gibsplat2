include("shared.lua")
include("gibsplat2/gibs.lua")

local MAX_RAGDOLL_PARTS = 23

local LocalToWorld = LocalToWorld
local CurTime = CurTime
local IsValid = IsValid

local render_SetColorModulation = render.SetColorModulation
local render_SetLightingOrigin = render.SetLightingOrigin
local render_SetLightingOrigin = render.SetLightingOrigin
local render_SetColorModulation = render.SetColorModulation

local math_min 		= math.min

local bit_bor 		= bit.bor
local bit_band 		= bit.band
local bit_lshift 	= bit.lshift

local text = file.Read("materials/gibsplat2/skeletons.vmt", "GAME")

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

function ENT:OnRemove()
	for _, part in pairs(self.bone_trans) do
		SafeRemoveEntity(part)
	end
end

function ENT:Think()
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end

	local min, max = body:GetCollisionBounds()--self.Body:GetRenderBounds() render bounds can be 0 sometimes ?!?!
	min = body:LocalToWorld(min)
	max = body:LocalToWorld(max)
	self:SetRenderBoundsWS(min, max)
	
	local dis_mask = body:GetNWInt("GS2DisMask", 0)
	local gib_mask = body:GetNWInt("GS2GibMask", 0)

	local mask = bit_bor(dis_mask, gib_mask)

	if (self.LastMask != mask) then
		self.LastMask = mask
		for phys_bone = 0, MAX_RAGDOLL_PARTS do
			if (bit_band(mask, bit_lshift(1, phys_bone)) != 0) then
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

				if (bit_band(gib_mask, bit_lshift(1, parent_phys_bone)) == 0) then
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
		local bone = body:TranslatePhysBoneToBone(phys_bone)
		if (bone == 0 and phys_bone != 0) then
			break
		end
		if (bit_band(dis_mask, bit_lshift(1, phys_bone)) != 0) then
			if body.GS2Dissolving then
				local start = body.GS2Dissolving[phys_bone]
				if start then
					local time = CurTime() - start
					if (time > 1) then
						continue
					end
					local mod = 1 - math_min(1, time)
					render_SetColorModulation(mod, mod, mod)
				end
			end

			if (bit_band(gib_mask, bit_lshift(1, phys_bone)) == 0) then
				local part = self.bone_trans[bone]
				if !part then
					part = GetOrCreateSkel(body, bone)
					self.bone_trans[bone] = part
				end

				if IsValid(part) then											
					local matrix = body:GetBoneMatrix(bone)
					if matrix then
						local pos, ang = matrix:GetTranslation(), matrix:GetAngles()			
						part:SetRenderOrigin(pos)
						part:SetRenderAngles(ang)	
						render_SetLightingOrigin(pos)				
						--part:SetupBones()					
						part:DrawModel()
					end					
				end
			else
				SafeRemoveEntity(self.bone_trans[bone])
				self.bone_trans[bone] = nil
			end

			local parent_bone = body:GetBoneParent(bone)
			local parent_phys_bone = body:TranslateBoneToPhysBone(parent_bone)
			parent_bone = body:TranslatePhysBoneToBone(parent_phys_bone)

			if (bit_band(gib_mask, bit_lshift(1, parent_phys_bone)) == 0) then
				local part = self.bone_trans[parent_bone]
				if !part then
					part = GetOrCreateSkel(body, parent_bone)
					self.bone_trans[parent_bone] = part
				end

				if IsValid(part) then					
					local matrix = body:GetBoneMatrix(parent_bone)
					if matrix then					
						local pos, ang = matrix:GetTranslation(), matrix:GetAngles()			
						part:SetRenderOrigin(pos)
						part:SetRenderAngles(ang)	
						render_SetLightingOrigin(pos)	
						--part:SetupBones()
						part:DrawModel()
					end					
				end
			end

			render_SetColorModulation(1, 1, 1)
		end
	end	
end