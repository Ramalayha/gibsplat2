--include("mesh_util.lua")

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
	if (SERVER and game.SinglePlayer()) then
		return
	end
	
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/gib_data")

	local file_path = "gibsplat2/gib_data/"..hash..".txt"

	file.Write(file_path, "")

	local F = file.Open(file_path, "wb", "DATA")

	if !F then
		return
	end

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

function GS2ReadGibData(hash, out, size)
	local file_path = "gibsplat2/gib_data/"..hash

	local F = file.Open("materials/"..file_path..".vmt", "rb", "GAME") or file.Open(file_path..".txt", "rb", "DATA")

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

local MESH_CACHE = {}

local function WriteTriangles(F, tris)
	local VERTEX_BUFFER = {}
	local INDEX_BUFFER = {}

	for key, vert in ipairs(tris) do
		INDEX_BUFFER[key] = table.KeyFromValue(VERTEX_BUFFER, vert) or table.insert(VERTEX_BUFFER, vert)
	end

	F:WriteLong(#VERTEX_BUFFER)
	for _, vert in ipairs(VERTEX_BUFFER) do
		F:WriteVector(vert.pos)
		F:WriteVector(vert.normal)
		F:WriteFloat(vert.u)
		F:WriteFloat(vert.v)
	end

	F:WriteLong(#INDEX_BUFFER)

	for _, idx in ipairs(INDEX_BUFFER) do
		F:WriteLong(idx)
	end
end

local function ReadTriangles(F)
	local tris = {}

	local VERTEX_BUFFER = {}
	
	for i = 1, F:ReadLong() do
		local vert = {}
		vert.pos = F:ReadVector()
		vert.normal = F:ReadVector()
		vert.u = F:ReadFloat()
		vert.v = F:ReadFloat()
		VERTEX_BUFFER[i] = vert
	end

	for i = 1, F:ReadLong() do
		tris[i] = VERTEX_BUFFER[F:ReadLong()]
	end

	return tris
end

local function GS2WriteMesh(hash, mesh)
	local file_path = "gibsplat2/mesh_data/"..hash..".txt"

	file.Write(file_path, "") --create file

	local F = file.Open(file_path, "wb", "DATA")
	
	if !F then
		return
	end

	F:WriteShort(MESH_VERSION)

	if !mesh.body then
		F:WriteShort(0)
	else
		local mat = mesh.body.mat_name --mesh.body.Material:GetName()

		F:WriteShort(#mat)
		F:Write(mat)

		WriteTriangles(F, mesh.body.tris)
	end

	if !mesh.flesh then
		F:WriteShort(0)
	else
		local mat = mesh.flesh.Material:GetName()

		F:WriteShort(#mat)
		F:Write(mat)

		WriteTriangles(F, mesh.flesh.tris)
	end

	F:Flush()
	F:Close()
end

local MATERIAL_CACHE = {}

function GS2ReadMesh(hash)
	if MESH_CACHE[hash] then
		return MESH_CACHE[hash]
	end

	local file_path = "gibsplat2/mesh_data/"..hash

	local F = file.Open("materials/"..file_path..".vmt", "rb", "GAME") or file.Open(file_path..".txt", "rb", "DATA")

	if !F then
		return
	end

	if (F:ReadShort() != MESH_VERSION) then
		file.Delete(file_path)
		return
	end

	local mesh = {}

	local len = F:ReadShort()

	if (len > 0) then
		mesh.body = {}

		local mat = F:Read(len)

		MATERIAL_CACHE[mat] = MATERIAL_CACHE[mat] or Material(mat)

		mesh.body.Material = MATERIAL_CACHE[mat]

		mesh.body.tris = ReadTriangles(F)

		mesh.body.Mesh = Mesh()
		mesh.body.Mesh:BuildFromTriangles(mesh.body.tris)
	end

	len = F:ReadShort()

	if (len > 0) then
		mesh.flesh = {is_flesh = true}

		local mat = F:Read(len)

		MATERIAL_CACHE[mat] = MATERIAL_CACHE[mat] or Material(mat)

		mesh.flesh.Material = MATERIAL_CACHE[mat]

		mesh.flesh.tris = ReadTriangles(F)

		mesh.flesh.Mesh = Mesh()
		mesh.flesh.Mesh:BuildFromTriangles(mesh.flesh.tris)
	end

	F:Close()

	MESH_CACHE[hash] = mesh

	return mesh
end

function GS2WriteMeshData(data)
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/mesh_data")

	for phys_bone, data in pairs(data) do	
		for bg_num, data in pairs(data) do			
			for bg_val, data in pairs(data) do				
				for hash, data in pairs(data) do
					if !GS2ReadMesh(hash) then
						GS2WriteMesh(hash, data)										
					end
				end
			end
		end
	end
end

local MAT_CACHE = {}

local MDL_INFO = {}

function GS2LinkModelInfo(mdl, name, data)
	MDL_INFO[mdl] = MDL_INFO[mdl] or {}
	if !MDL_INFO[mdl][name] then
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

		for phys_bone, data in pairs(mesh_data) do
			F:WriteShort(phys_bone)
			F:WriteShort(table.Count(data))
			for bg_num, data in pairs(data) do
				F:WriteShort(bg_num)
				F:WriteShort(table.Count(data))
				for bg_val, data in pairs(data) do
					F:WriteShort(bg_val)
					F:WriteShort(table.Count(data))
					for hash in pairs(data) do
						F:WriteShort(#hash)
						F:Write(hash)
					end
				end
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

	local file_path = "gibsplat2/model_data/"..hash

	local F = file.Open("materials/"..file_path..".vmt", "rb", "GAME") or file.Open(file_path..".txt", "rb", "DATA")

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
			local phys_bone = F:ReadShort()	
			for j = 1, F:ReadShort() do
				local bg_num = F:ReadShort()
				for k = 1, F:ReadShort() do
					local bg_val = F:ReadShort()
					for l = 1, F:ReadShort() do
						local hash = F:Read(F:ReadShort())
						InsertMulti(MDL_CACHE[mdl].mesh_data, phys_bone, bg_num, bg_val, GS2ReadMesh(hash))
					end
				end
			end
		end
	end

	F:Close()

	return MDL_CACHE[mdl]
end