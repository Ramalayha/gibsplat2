include("shared.lua")

local dummy_mesh = Mesh()

local mat_default = Material("models/flesh")

<<<<<<< HEAD
local MATERIAL_CACHE = {}

=======
>>>>>>> 6576c1780fdf7503385bdb98f0fef873d98c6ca6
function ENT:Initialize()
	self.MeshData = {}
	self.MeshData.Mesh = dummy_mesh
	self.MeshData.Material = mat_default
end

function ENT:Think()
<<<<<<< HEAD
	local body = self:GetBody()
	if (self.MeshData.Mesh == dummy_mesh) then
		local gib_index = self:GetGibIndex()
		if (gib_index > 0) then			
			local phys_bone = self:GetTargetBone()	
			if IsValid(body) then
				self.MeshData.Mesh = GetPhysGibMeshes(body:GetModel(), phys_bone)[gib_index].mesh
			end
		end	
	end
	if (self.MeshData.Material == mat_default) then
		local phys_mat = body:GetNWString("GS2PhysMat", "")
		if (phys_mat != "") then
			MATERIAL_CACHE[phys_mat] = MATERIAL_CACHE[phys_mat] or Material("models/"..phys_mat)
			self.MeshData.Material = MATERIAL_CACHE[phys_mat]
		end
=======
	if (self.MeshData.Mesh == dummy_mesh) then
		local gib_index = self:GetGibIndex()
		if (gib_index > 0) then
			local body = self:GetBody()
			local phys_bone = self:GetTargetBone()	

			self.MeshData.Mesh = GetPhysGibMeshes(body:GetModel(), phys_bone)[gib_index].mesh
		end	
>>>>>>> 6576c1780fdf7503385bdb98f0fef873d98c6ca6
	end
end

function ENT:GetRenderMesh()
	return self.MeshData
end