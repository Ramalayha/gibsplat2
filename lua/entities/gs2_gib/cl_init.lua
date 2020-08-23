include("shared.lua")

local MAT_CACHE = {}

local mat_default = Material("models/flesh")

MAT_CACHE["models/flesh"] = mat_default

local dummy_mesh = Mesh()

function ENT:Initialize()
	self.MeshData = {}
	self.MeshData.Mesh = dummy_mesh
	self.MeshData.Material = mat_default
end

function ENT:Think()
	if (self.MeshData.Mesh == dummy_mesh) then
		local mesh, min, max = self:GetMesh()
		if mesh then
			self:SetRenderBounds(min, max)
			self.MeshData.Mesh = mesh
		end
	end
	local body = self:GetBody()
	if !IsValid(body) then		
		return
	end
	local phys_mat = body:GetNWString("GS2PhysMat")

	if phys_mat then
		if (MAT_CACHE[phys_mat] == NULL) then
			return
		elseif !MAT_CACHE[phys_mat] then
			if file.Exists("materials/models/"..phys_mat..".vmt", "GAME") then
				MAT_CACHE[phys_mat] = Material("models/"..phys_mat)
				self.MeshData.Material = MAT_CACHE[phys_mat]
			else
				MAT_CACHE[phys_mat] = NULL	
			end
		else
			self.MeshData.Material = MAT_CACHE[phys_mat]
		end		
	end
end

function ENT:GetRenderMesh()
	return self.MeshData
end