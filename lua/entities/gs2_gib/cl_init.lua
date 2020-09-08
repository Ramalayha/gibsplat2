include("shared.lua")

local dummy_mesh = Mesh()

local mat_default = Material("models/flesh")

function ENT:Initialize()
	self.MeshData = {}
	self.MeshData.Mesh = dummy_mesh
	self.MeshData.Material = mat_default
end

function ENT:Think()
	if (self.MeshData.Mesh == dummy_mesh) then
		local gib_index = self:GetGibIndex()
		if (gib_index > 0) then
			local body = self:GetBody()
			local phys_bone = self:GetTargetBone()	

			self.MeshData.Mesh = GetPhysGibMeshes(body:GetModel(), phys_bone)[gib_index].mesh
		end	
	end
end

function ENT:GetRenderMesh()
	return self.MeshData
end