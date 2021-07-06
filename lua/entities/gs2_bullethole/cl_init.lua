include("shared.lua")
include("gibsplat2/decal_util.lua")

function ENT:Initialize()
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end
	local phys_bone = self:GetTargetBone()

	body.GS2BulletHoles = body.GS2BulletHoles or {}
	body.GS2BulletHoles[phys_bone] = body.GS2BulletHoles[phys_bone] or {}

	local bone = body:TranslatePhysBoneToBone(phys_bone)

	local bone_pos, bone_ang = body:GetBonePosition(bone)

	local pos = LocalToWorld(self:GetLPos(), angle_zero, bone_pos, bone_ang)

	local norm = -(bone_pos - pos):GetNormal()

	table.insert(body.GS2BulletHoles[phys_bone], self)
end

function ENT:ApplyDecal(target)
	local body = self:GetBody()
	if !IsValid(body) then
		return
	end
	local phys_bone = self:GetTargetBone()

	local bone = body:TranslatePhysBoneToBone(phys_bone)

	local bone_pos, bone_ang = body:GetBonePosition(bone)

	local pos = LocalToWorld(self:GetLPos(), angle_zero, bone_pos, bone_ang)

	local norm = pos - bone_pos
	norm:Normalize()

	local phys_mat = body:GetNWString("GS2PhysMat")

	if phys_mat then
		local mat = util.DecalMaterial("impact."..phys_mat)

		if mat then
			ApplyDecal(mat, target, pos, norm)

			if (target == body.GS2Limbs[self:GetTargetBone()] and target.GS2RenderMeshes) then
				local size = 1-- + math.log(Material(mat):GetTexture("$basetexture"):Width(), 2) - 6 --log2(64) = 6
				self.Decals = {}
				for _, rm in pairs(target.GS2RenderMeshes) do
					local mesh = rm:GetMesh()		
					if mesh.body then
						local decal = rm:AddDecal(mesh.body, mat, self:GetLPos(), self:GetLAng(), size)
						if decal then
							table.insert(self.Decals, decal)
						end
					elseif mesh.flesh then
						local decal = rm:AddDecal(mesh.flesh, mat, self:GetLPos(), self:GetLAng(), size)
						if decal then
							table.insert(self.Decals, decal)
						end
					end
				end
			end
		end
	end
end

function ENT:Think()
	if !self.DidDecals then
		self.DidDecals = true
		local body = self:GetBody()
		if !IsValid(body) then
			return
		end
		if body.GS2Limbs then
			for _, limb in pairs(body.GS2Limbs) do
				self:ApplyDecal(limb)
			end
		end
	end
end

function ENT:OnRemove()
	if self.Decals then
		for _, decal in pairs(self.Decals) do
			if IsValid(decal.Mesh) then
				decal.Mesh:Destroy()
			end
			decal.Mesh = nil
		end
	end
end