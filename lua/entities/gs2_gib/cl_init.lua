include("shared.lua")

local IsValid = IsValid

local dummy_mesh = Mesh()

local mat_default = Material("models/flesh")

local MATERIAL_CACHE = {}

function ENT:Initialize()
	self.MeshData = {}
	self.MeshData.Mesh = dummy_mesh
	self.MeshData.Material = mat_default

	local body = self:GetBody()
	if !IsValid(body) then		
		return
	end
	
	local phys_bone = self:GetTargetBone()

	local bone = body:TranslatePhysBoneToBone(phys_bone)

	local pos, ang = body:GetBonePosition(bone)

	self:SetPos(pos)
	self:SetAngles(ang)

	local gib_index = self:GetGibIndex()

	self.GS2GibInfo = GetPhysGibMeshes(body:GetModel(), phys_bone)[gib_index]

	self:SetModel("models/error.mdl")

	self:AddCallback("PhysicsCollide", self.PhysicsCollide)

	self:Think() --Forces think once for clientside only gibs
end

function ENT:Think()
	local body = self:GetBody()
	if (self.MeshData.Mesh == dummy_mesh) then
		local gib_index = self:GetGibIndex()
		if (gib_index > 0) then			
			local phys_bone = self:GetTargetBone()	
			if IsValid(body) then
				local meshes = GetPhysGibMeshes(body:GetModel(), phys_bone)
				if (meshes and meshes[gib_index]) then
					self.MeshData.Mesh = meshes[gib_index].mesh or dummy_mesh
				end
			end
		end	
	end
	if (self.MeshData.Material == mat_default) then
		local phys_mat = body:GetNWString("GS2PhysMat", "")
		if (phys_mat != "") then
			MATERIAL_CACHE[phys_mat] = MATERIAL_CACHE[phys_mat] or Material("models/"..phys_mat)
			self.MeshData.Material = MATERIAL_CACHE[phys_mat]
		end
	end
end

function ENT:Draw()
	self:DrawModel()
end

function ENT:GetRenderMesh()
	return self.MeshData
end