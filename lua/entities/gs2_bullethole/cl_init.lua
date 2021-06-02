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

	for _, limb in pairs(body.GS2Limbs) do
		self:ApplyDecal(limb)
	end

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

	ApplyDecal("Blood", target, pos, norm)

	if (target == body.GS2Limbs[self:GetTargetBone()] and target.GS2RenderMeshes) then
		self.Decals = {}
		for _, rm in pairs(target.GS2RenderMeshes) do
			local mesh = rm:GetMesh()
			local mat = "decals/flesh/blood1"
			if mesh.body then
				local decal = rm:AddDecal(mesh.body.tris, mat, self:GetLPos(), self:GetLAng(), 1)
				if decal then
					table.insert(self.Decals, decal)
				end
			elseif mesh.flesh then
				local decal = rm:AddDecal(mesh.flesh.tris, mat, self:GetLPos(), self:GetLAng(), 1)
				if decal then
					table.insert(self.Decals, decal)
				end
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