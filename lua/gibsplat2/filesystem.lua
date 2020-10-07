--[[
gib files for each physobj
mesh files for different mesh shapes
1 file per model pointing to gib and mesh files also holding the ragdoll pose
]]

local GIB_VERSION = 1
local MESH_VERSION = 1
local MDL_VERSION = 1

function VEC2STR(vec)
	return math.Round(vec.x, 3)..math.Round(vec.y, 3)..math.Round(vec.z, 3)
end

local function sort(a, b)
	return a > b
end

function TBL2HASH(tbl)
	table.sort(tbl, sort)
	return util.CRC(table.concat(tbl))
end

local FILE = FindMetaTable("File")

function FILE:WriteVector(vec)
	self:WriteFloat(vec.x)
	self:WriteFloat(vec.y)
	self:WriteFloat(vec.z)
end

function FILE:ReadVector()
	return Vector(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
end

function GS2WriteGibData(hash, data)
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/gib_data")

	local file_path = "gibsplat2/gib_data/"..hash..".txt"

	file.Write(file_path, "")

	local F = file.Open(file_path, "wb", "DATA")

	F:WriteShort(GIB_VERSION)

	F:WriteShort(#data)

	for _, mesh in ipairs(data) do
		F:WriteVector(mesh.min) 
		F:WriteVector(mesh.max)
		F:WriteShort(#mesh.conns)
		for _, conn in ipairs(mesh.conns) do
			F:WriteShort(conn)
		end

		F:WriteLong(#mesh.vertex_buffer)
		for _, vert in ipairs(mesh.vertex_buffer) do
			F:WriteVector(vert)
		end
		F:WriteLong(#mesh.index_buffer)
		for _, idx in ipairs(mesh.index_buffer) do
			F:WriteLong(idx)
		end
	end
	
	F:Flush()
	F:Close()
end

function GS2ReadGibData(hash, out)
	local file_path = "gibsplat2/gib_data/"..hash..".txt"

	local F = file.Open(file_path, "rb", "DATA")

	if !F then
		return
	end

	local version = F:ReadShort()

	if (version != GIB_VERSION) then
		F:Close()
		print("GS2ReadGibData: File is wrong version ("..version..") should be "..GIB_VERSION.."!",hash)
		file.Delete(file_path)
		return
	end

	local data = {hash = hash}

	for i = 1, F:ReadShort() do
		local min = F:ReadVector()
		local max = F:ReadVector()
		local size = max - min
		local center = (min + max) / 2

		local vertex_buffer = {}
		local index_buffer = {}
		local triangles = {}
		local conns = {}

		for j = 1, F:ReadShort() do
			conns[j] = F:ReadShort()
		end

		for j = 1, F:ReadLong() do
			vertex_buffer[j] = F:ReadVector()
		end

		for j = 1, F:ReadLong() do
			local idx = F:ReadLong()
			index_buffer[j] = idx

			local vert = {pos = vertex_buffer[idx]}
			vert.normal = (vert.pos - center):GetNormal()
			vert.u = vert.pos.x / size.x + vert.pos.z / size.z
			vert.v = vert.pos.y / size.y + vert.pos.z / size.z

			triangles[j] = vert
		end
				
		local entry = {
			vertex_buffer 	= vertex_buffer,
			index_buffer 	= index_buffer,
			triangles 		= triangles,
			conns 			= conns,
			min 			= min,
			max 			= max,
			center 			= center
		}

		if CLIENT then 
			local M = Mesh()
			M:BuildFromTriangles(triangles)
			entry.mesh = M
		end

		data[i] = entry
	end

	out[hash] = data

	F:Close()
end

function GS2WriteMeshData(hash, data)
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/mesh_data")

	local file_path = "gibsplat2/mesh_data/"..hash..".txt"

	local F = file.Open(file_path, "wb", "DATA")

	F:WriteShort(MESH_VERSION)

	F:WriteShort(#data)

	for _, mesh in ipairs(data) do
		local mat = mesh.Material:GetName()
		F:WriteShort(#mat)
		F:Write(mat)

		local vertex_buffer = {}
		local index_buffer = {}

		for key, vert in ipairs(mesh.tris) do
			index_buffer[key] = table.KeyFromValue(vertex_buffer, vert) or table.insert(vertex_buffer, vert)
		end

		F:WriteLong(#vertex_buffer)
		for _, vert in ipairs(vertex_buffer) do
			F:WriteVector(vert.pos)
			F:WriteVector(vert.normal)
			F:WriteFloat(vert.u)
			F:WriteFloat(vert.v)
		end

		F:WriteLong(#index_buffer)
		for _, idx in ipairs(index_buffer) do
			F:WriteLong(idx)
		end
	end

	F:Flush()
	F:Close()
end

local MAT_CACHE = {}

function GS2ReadMeshData(hash, out)
	local file_path = "gibsplat2/mesh_data/"..hash..".txt"

	local F = file.Open(file_path, "rb", "DATA")

	if !F then
		return
	end

	local version = F:ReadShort()

	if (version != GIB_VERSION) then
		F:Close()
		print("GS2ReadMeshData: File is wrong version ("..version..") should be "..MESH_VERSION.."!",hash)
		file.Delete(file_path)
		return
	end

	local data = {hash = hash}

	for i = 1, F:ReadShort() do
		local mat = F:Read(F:ReadShort())

		local vertex_buffer = {}
		local index_buffer = {}
		local triangles = {}

		for j = 1, F:ReadLong() do
			local vert = {}
			vert.pos = F:ReadVector()
			vert.normal = F:ReadVector()
			vert.u = F:ReadFloat()
			vert.v = F:ReadFloat()
			vertex_buffer[j] = vert
		end

		for j = 1, F:ReadLong() do
			local idx = F:ReadLong()
			index_buffer[j] = idx

			triangles[j] = vertex_buffer[idx]
		end

		MAT_CACHE[mat] = MAT_CACHE[mat] or Material(mat)

		data[i] = {
			Material = MAT_CACHE[mat],
			tris = triangles
		}

		local M = Mesh()
		M:BuildFromTriangles(triangles)
		data[i].Mesh = M
	end

	out[hash] = data

	F:Close()
end

local MDL_INFO = {}

function GS2LinkModelInfo(mdl, name, data)
	MDL_INFO[mdl] = MDL_INFO[mdl] or {}
	if !MDL_INFO[name] then
		MDL_INFO[mdl][name] = data

		if (table.Count(MDL_INFO[mdl]) == 2) then
			GS2WriteModelData(mdl)
		end
	end
end

function GS2WriteModelData(mdl)
	if (SERVER and game.SinglePlayer()) then
		return
	end

	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/model_data")

	local hash = util.CRC(mdl)

	local file_path = "gibsplat2/model_data/"..hash..".txt"

	local F = file.Open(file_path, "wb", "DATA")

	F:WriteShort(MDL_VERSION)

	local gib_data = MDL_INFO[mdl].gib_data
	local mesh_data = MDL_INFO[mdl].mesh_data

	F:WriteShort(table.Count(gib_data))

	for phys_bone, data in pairs(gib_data) do
		F:WriteShort(phys_bone)
		F:WriteShort(#data.hash)
		F:Write(data.hash)
	end

	if CLIENT then
		F:WriteShort(table.Count(mesh_data))

		for bg_mask, data in pairs(mesh_data) do
			F:WriteLong(bg_mask)
			F:WriteShort(table.Count(data))
			for phys_bone, data2 in pairs(data) do
				F:WriteShort(phys_bone)
				F:WriteShort(#data2.hash)
				F:Write(data2.hash)
			end
		end
	end

	F:Flush()
	F:Close()
end

local MDL_CACHE = {}

function GS2ReadModelData(mdl)
	if MDL_CACHE[mdl] then
		return MDL_CACHE[mdl]
	end
 
	local hash = util.CRC(mdl)

	local file_path = "gibsplat2/model_data/"..hash..".txt"

	local F = file.Open(file_path, "rb", "DATA")

	if !F then
		return
	end

	local version = F:ReadShort()

	if (version != MDL_VERSION) then
		F:Close()
		print("GS2ReadModelData: File is wrong version ("..version..") should be "..MDL_VERSION.."!",hash)
		file.Delete(file_path)
		return
	end

	MDL_CACHE[mdl] = {
		gib_data = {}
	}
	
	for i = 1, F:ReadShort() do
		local phys_bone = F:ReadShort()
		local hash = F:Read(F:ReadShort())
		MDL_CACHE[mdl].gib_data[phys_bone] = hash
	end

	if CLIENT then
		MDL_CACHE[mdl].mesh_data = {}

		for i = 1, F:ReadShort() do
			local bg_mask = F:ReadLong()
			MDL_CACHE[mdl].mesh_data[bg_mask] = {}
			for j = 1, F:ReadShort() do
				local phys_bone = F:ReadShort()
				local hash = F:Read(F:ReadShort())
				MDL_CACHE[mdl].mesh_data[bg_mask][phys_bone] = hash
			end
		end
	end

	F:Close()

	return MDL_CACHE[mdl]
end