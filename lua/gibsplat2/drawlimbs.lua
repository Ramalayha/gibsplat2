include("constraintinfo.lua")
include("buildmesh.lua")
include("gibs.lua")

local GetModelConstraintInfo = GetModelConstraintInfo
local GetBoneSkinMesh = GetBoneSkinMesh
local band = bit.band
local lshift = bit.lshift
local render_MaterialOverride = render.MaterialOverride
local render_SetMaterial = render.SetMaterial
local cam_PushModelMatrix = cam.PushModelMatrix
local cam_PopModelMatrix = cam.PopModelMatrix

local MAX_PARTS = 23 --24-1

local matrix_inf = Matrix()
matrix_inf:Translate(Vector()/0)

local vec_zero = Vector(0,0,0)

local function IsLonelyBone(self, phys_bone, mask)
	self.GS2IsLonelyBone = self.GS2IsLonelyBone or {}
	if self.GS2IsLonelyBone[phys_bone] then
		return true
	end

	for _, part_info in pairs(GetModelConstraintInfo(self:GetModel())) do
		if part_info.parent == phys_bone and band(mask, lshift(1, part_info.child)) == 0 then
			return false
		end
	end

	return true
end

local mat_flesh = Material("models/flesh")

local function DrawBody(self)
	local mask_old = self.__GS2DismemberMaskOld or 0
	local mask = self:GetGS2DisMask() or 0--self:GetNWInt("GS2DismemberMask", 0)
	local num_bones = self:GetBoneCount()-1
	
	local gibmask = self:GetGS2GibMask() or 0--self:GetNWInt("GS2GibMask", 0)
	if band(gibmask, 1) == 0 then
		--Draw main body flesh
		self:SetupBones()
		self:SetRenderOrigin(self:GetPos())
		for bone = 0, num_bones do
			if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
				local parent_bone = bone--self:GetBoneParent(bone)
				repeat
					local phys_bone = self:TranslateBoneToPhysBone(parent_bone)
					if band(mask, lshift(1, phys_bone)) != 0 then
						break
					end
					parent_bone = self:GetBoneParent(parent_bone)
				until (parent_bone == -1)
				if parent_bone != -1 then
					parent_bone = self:GetBoneParent(parent_bone)
					local matrix = self:GetBoneMatrix(parent_bone)
					matrix:Scale(vec_zero)
					self:SetBoneMatrix(bone, matrix)
				end
			end
		end
		render_MaterialOverride(mat_flesh)
		--self:DrawModel()
		render_MaterialOverride()

		--Draw main body skin
		self:SetupBones()		
		for bone = 0, num_bones do
			if self:BoneHasFlag(bone, BONE_USED_BY_ANYTHING) then
				local phys_bone = self:TranslateBoneToPhysBone(bone)
				if band(mask, lshift(1, phys_bone)) != 0 then
					self:SetBoneMatrix(bone, matrix_inf)					
				end
			end
		end
		self:DrawModel()		
	end

	self._GS2Limbs = self._GS2Limbs or {}	
	--Draw severed limbs
	for phys_bone = 1, MAX_PARTS do
		local phys_bone_mask = lshift(1, phys_bone)
		if band(mask, phys_bone_mask) != 0 then
			self._GS2Limbs = self._GS2Limbs or {}			
			local bone = self:TranslatePhysBoneToBone(phys_bone)
			if band(mask_old, phys_bone_mask) == 0 then --this bone just got dismembered, create blood effect
				local limb = ClientsideModel(self:GetModel())			
				limb:SetNoDraw(true)
				limb:SetLOD(0)
				for _, data in pairs(self:GetBodyGroups()) do
					limb:SetBodyGroup(data.id, data.num)
				end		
				self._GS2Limbs[phys_bone] = limb

				local parent_bone = self:GetBoneParent(bone)
				local temp = ClientsideModel(self:GetModel())
				temp:SetupBones()
				temp:ResetSequence(temp:LookupSequence("ragdoll"))
				local pos, ang = temp:GetBonePosition(bone)
				local parent_pos, parent_ang = temp:GetBonePosition(parent_bone)
				if !pos or !parent_pos then
					continue
				end
				local trace = {}
				trace.start = pos + ang:Forward() * 10
				trace.endpos = pos - ang:Forward() * 10
				local tr = util.TraceLine(trace)
				util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
				local pos2, ang2 = WorldToLocal(pos, ang, parent_pos, parent_ang)
				local parent_pos2, parent_ang2 = WorldToLocal(parent_pos, parent_ang, pos, ang)
				temp:Remove()
				local EF = EffectData()				
				EF:SetMagnitude(1)				
				EF:SetColor(0)
				EF:SetFlags(3)	
				EF:SetScale(6)			
				local start_time = CurTime()
				timer.Create("bloodspray"..self:EntIndex()..phys_bone, 0.1, 20, function()
					if IsValid(self) then
						local pos, ang = LocalToWorld(pos2, ang2, self:GetBonePosition(parent_bone))
						EF:SetOrigin(pos)
						EF:SetNormal(ang:Forward())						
						util.Effect("bloodspray", EF)

						trace.start = pos
						trace.endpos = pos + ang:Forward() * 100
						trace.endpos.z = trace.endpos.z - (CurTime() - start_time) * 100
						local tr = util.TraceLine(trace)
						util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)

						local pos, ang = LocalToWorld(parent_pos2, parent_ang2, self:GetBonePosition(bone))
						EF:SetOrigin(pos)
						EF:SetNormal(ang:Forward())						
						util.Effect("bloodspray", EF)

						trace.start = pos
						trace.endpos = pos + ang2:Forward() * 100
						trace.endpos.z = trace.endpos.z - (CurTime() - start_time) * 100
						local tr = util.TraceLine(trace)
						util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
					end
				end)
			end
			local limb = self._GS2Limbs[phys_bone]
			limb:SetParent(self)
			limb:AddEffects(EF_BONEMERGE)
			if !IsLonelyBone(self, phys_bone, mask) then
				--Draw flesh	
				self:SetupBones()
				limb:SetupBones()								
				local matrix = self:GetBoneMatrix(bone)
				limb:SetRenderOrigin(matrix:GetTranslation())
				matrix:Scale(vec_zero)

				for bone2 = 0, num_bones do
					if self:BoneHasFlag(bone2, BONE_USED_BY_ANYTHING) then
						local parent_bone = bone2
						local phys_bone2
						repeat
							phys_bone2 = self:TranslateBoneToPhysBone(parent_bone)
							if phys_bone2 == phys_bone or band(mask, lshift(1, phys_bone2)) != 0 then
								break
							end
							parent_bone = self:GetBoneParent(parent_bone)
						until parent_bone == -1
						if parent_bone == -1 then
							limb:SetBoneMatrix(bone2, matrix)
						elseif phys_bone2 != phys_bone then						
							local matrix = limb:GetBoneMatrix(self:GetBoneParent(bone2))
							matrix:Scale(vec_zero)
							limb:SetBoneMatrix(bone2, matrix)						
						end
					end
				end
				render_MaterialOverride(mat_flesh)
				--limb:DrawModel()
				render_MaterialOverride()

				--Draw skin		
				limb:SetupBones()		
				local bone = self:TranslatePhysBoneToBone(phys_bone)
				for bone2 = 0, num_bones do
					if self:BoneHasFlag(bone2, BONE_USED_BY_ANYTHING) then
						local phys_bone2 = self:TranslateBoneToPhysBone(bone2)
						if phys_bone2 != phys_bone then
							if band(mask, lshift(1, phys_bone2)) != 0 then
								limb:SetBoneMatrix(bone2, matrix_inf)
							else
								local parent_bone = bone2
								repeat
									if parent_bone == bone then
										break
									end
									parent_bone = self:GetBoneParent(parent_bone)
								until parent_bone == -1

								if parent_bone == -1 then
									limb:SetBoneMatrix(bone2, matrix_inf)
								end
							end
						end
					end
				end
				limb:SnatchModelInstance(self) --renders decals
				--limb:DrawModel()
				self:SnatchModelInstance(limb)
			else				
				if band(gibmask, lshift(1, phys_bone)) == 0 then
					--do mesh shit
					self:SetupBones() print("nooooo")
					--local meshes = GetBoneMeshes(self, phys_bone)				
					cam_PushModelMatrix(self:GetBoneMatrix(bone))
						--for _, mesh in pairs(meshes) do
							--render_SetMaterial(mesh.material)
							--mesh.mesh:Draw()					
						--end
					cam_PopModelMatrix()
				end
			end
		end
	end

	self.__GS2DismemberMaskOld = mask
end

hook.Add("PreDrawOpaqueRenderables","h",function()--timer.Create("_h_ragdoll", 0.1, 0, function()
	for _, v in pairs(ents.FindByClass("prop_ragdoll")) do
		if v.GetGS2GibMask and (v:GetGS2DisMask() or 0) != 0 then--v:GetNWInt("GS2DismemberMask", 0) != 0 then
			v:SetLOD(0)
			//v.RenderOverride = DrawBody
		end
	end
end)