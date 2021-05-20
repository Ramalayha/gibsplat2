--include("mesh_util.lua")

local GIB_VERSION = 1
local MESH_VERSION = 1
local MDL_VERSION = 2

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
		F:WriteShort(table.Count(mesh.conns))
		for _, conn in pairs(mesh.conns) do
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

local function Tesselate(mesh)
	for k, vert in pairs(mesh) do
		for k2, vert2 in pairs(mesh) do
			if (vert != vert2 and vert.pos:IsEqualTol(vert2.pos,0)) then
				mesh[k2] = vert
			end
		end
	end
	local new_mesh = {}
	for vert_index = 1, #mesh - 2, 3 do
		local v1 = mesh[vert_index]
		local v2 = mesh[vert_index + 1]
		local v3 = mesh[vert_index + 2]
		
		v1.new = false
		v2.new = false
		v3.new = false

		local v12 = {pos = (v1.pos + v2.pos) * 0.375, new = true, extra = v3}
		local v23 = {pos = (v2.pos + v3.pos) * 0.375, new = true, extra = v1}
		local v13 = {pos = (v1.pos + v3.pos) * 0.375, new = true, extra = v2}

		table.insert(new_mesh, v1)
		table.insert(new_mesh, v12)
		table.insert(new_mesh, v13)

		table.insert(new_mesh, v12)
		table.insert(new_mesh, v2)
		table.insert(new_mesh, v23)

		table.insert(new_mesh, v23)
		table.insert(new_mesh, v3)
		table.insert(new_mesh, v13)

		table.insert(new_mesh, v12)
		table.insert(new_mesh, v23)
		table.insert(new_mesh, v13)
	end

	local verts = {}

	for key, vert in pairs(new_mesh) do		
		local exists = false
		
		for _, vert2 in pairs(verts) do
			if (vert != vert2 and vert.pos:IsEqualTol(vert2.pos, 0)) then
				new_mesh[key] = vert2	
				vert2.extra2 = vert.extra			
				exists = true
				break
			end
		end
		
		if !exists then			
			table.insert(verts, vert)
		end
	end

	for _, vert in pairs(verts) do
		if vert.new then
			vert.pos:Add(vert.extra.pos * 1 / 16)
			vert.pos:Add(vert.extra2.pos * 1 / 16)
		end
	end

	for _, vert in pairs(verts) do
		if !vert.new then			
			local points = {}
			for vert_index = 1, #new_mesh - 2, 3 do
				for offset = 0, 2 do
					local v1 = new_mesh[vert_index + offset]
					if (v1 == vert) then
						local v2 = new_mesh[vert_index + (offset + 1) % 2]
						local v3 = new_mesh[vert_index + (offset + 2) % 2]
						points[v2] = true
						points[v3] = true
					end
				end
			end
			local n = table.Count(points)
						
			local B = 3 / (8 * n)
			
			local p = Vector(0, 0, 0)
			for p0 in pairs(points) do
				p:Add(p0.pos * B)				
			end

			local norm = p:GetNormal()

			for p0 in pairs(points) do
				p0.normal = norm			
			end

			vert.normal = norm

			vert.pos = vert.pos * (1 - B * n) + p
		end
		vert.u = vert.pos.x
		vert.v = vert.pos.y + vert.pos.z
	end

	return new_mesh
end

function GS2ReadGibData(hash, out, size)
	local file_path = "gibsplat2/gib_data/"..hash

	local F = file.Open("materials/"..file_path..".vmt", "rb", "GAME") or file.Open(file_path..".txt", "rb", "DATA")

	if !F then
		return
	end

	local succ, err = pcall(function()
		local version = F:ReadShort()

		if (version != GIB_VERSION) then
			F:Close()
			print("GS2ReadGibData: File is wrong version ("..(version or "NULL")..") should be "..GIB_VERSION.."!",hash)
			file.Delete(file_path..".txt")
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
				if CLIENT then
					vertex_buffer[j] = {pos = F:ReadVector()}
				else
					vertex_buffer[j] = F:ReadVector()
				end
			end

			for j = 1, F:ReadLong() do
				local idx = F:ReadLong()
				index_buffer[j] = idx

				local vert = CLIENT and vertex_buffer[idx] or {pos = vertex_buffer[idx]}
				
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
						
				triangles = Tesselate(triangles)
			
				for _, vert in pairs(triangles) do
					if !vert.modded then
						vert.modded = true
						vert.normal = (vert.pos - center):GetNormal()
						vert.u = vert.pos.x / size.x + vert.pos.z / size.z
						vert.v = vert.pos.y / size.y + vert.pos.z / size.z
					end
				end
				local M = Mesh()
				M:BuildFromTriangles(triangles)
				entry.mesh = M
			end

			data[i] = entry
		end

		out[hash] = data
	end)

	F:Close()
	
	if !succ then
		print("GS2ReadGibData: deleting corrupted file "..hash.." (Error: "..err..")")
		file.Delete(file_path..".txt")
	end
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

	local succ, ret = pcall(function()
		if (F:ReadShort() != MESH_VERSION) then
			F:Close()
			print("GS2ReadMesh: File is wrong version ("..version..") should be "..GIB_VERSION.."!", hash)
			file.Delete(file_path..".txt")
			return
		end

		local mesh = {}

		local len = F:ReadShort()

		if (len > 0) then
			mesh.body = {}

			local mat = F:Read(len)

			MATERIAL_CACHE[mat] = MATERIAL_CACHE[mat] or Material(mat)

			mesh.body.Material = MATERIAL_CACHE[mat.."_bloody"] or MATERIAL_CACHE[mat]

			mesh.body.tris = ReadTriangles(F)

			mesh.body.Mesh = Mesh()
			mesh.body.Mesh:BuildFromTriangles(mesh.body.tris)
		end

		len = F:ReadShort()

		if (len and len > 0) then
			mesh.flesh = {is_flesh = true}

			local mat = F:Read(len)

			local phys_mat = mat:match("/(.-)$")

			--backwards compatability
			if !mat:find("gibsplat2") then
				mat = "models/gibsplat2/flesh/"..phys_mat
			end

			MATERIAL_CACHE[mat] = MATERIAL_CACHE[mat] or Material(mat)

			mesh.flesh.Material = MATERIAL_CACHE[mat]

			mesh.flesh.tris = ReadTriangles(F)

			mesh.flesh.Mesh = Mesh()
			mesh.flesh.Mesh:BuildFromTriangles(mesh.flesh.tris)

			local mat_path = "models/gibsplat2/overlays/"..phys_mat

			if (mesh.body and phys_mat and file.Exists("materials/"..mat_path..".vmt", "GAME")) then
				mat = mesh.body.Material
				local mat_name = mat:GetName().."_bloody"
				if !MATERIAL_CACHE[mat_name] then
					local mat_bloody = CreateMaterial(mat_name, "VertexLitGeneric", {["$detail"] = mat_path})
					for key, value in pairs(mat:GetKeyValues()) do
						if (key == "$detail") then
							continue
						end
						if (type(value) == "string") then
							mat_bloody:SetString(key, value)
						elseif (type(value) == "number") then
							mat_bloody:SetFloat(key, value)
						elseif (type(value) == "Vector") then
							mat_bloody:SetVector(key, value)
						elseif (type(value) == "ITexture") then
							mat_bloody:SetTexture(key, value)
						elseif (type(value) == "VMatrix") then
							mat_bloody:SetMatrix(key, value)							
						end
					end	
					MATERIAL_CACHE[mat_name] = mat_bloody
					mesh.body.Material = mat_bloody
				end
			end			
		end

		MESH_CACHE[hash] = mesh

		return mesh
	end)

	F:Close()

	if !succ then 
		print("GS2ReadMesh: deleting corrupted file "..hash.." (Error: "..ret..")")
		file.Delete(file_path..".txt")
	else
		return ret
	end
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

	local F = file.Open(mdl, "rb", "GAME")
	F:Seek(8)
	local checksum = F:Read(4)
	F:Close()

	local hash = util.CRC(mdl..checksum)

	local file_path = "gibsplat2/model_data/"..hash..".txt"

	local F = file.Open(file_path, "wb", "DATA")
	F:Seek(0)

	F:WriteShort(MDL_VERSION)

	local gib_data = MDL_INFO[mdl].gib_data
	local mesh_data = MDL_INFO[mdl].mesh_data

	F:WriteShort(table.Count(gib_data))

	for phys_bone, data in pairs(gib_data) do
		F:WriteShort(phys_bone)
		if data.hash then
			F:WriteShort(#data.hash)
			F:Write(data.hash)
		else
			F:WriteShort(0)
		end
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
					if (data == 0) then
						F:WriteShort(0)
					else
						F:WriteShort(table.Count(data))
						for hash in pairs(data) do
							hash = tostring(hash)
							F:WriteShort(#hash)
							F:Write(hash)
						end
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
 
	local F = file.Open(mdl, "rb", "GAME")
	F:Seek(8)
	local checksum = F:Read(4)
	F:Close()

	local hash = util.CRC(mdl..checksum)

	local file_path = "gibsplat2/model_data/"..hash

	local F = file.Open("materials/"..file_path..".vmt", "rb", "GAME") or file.Open(file_path..".txt", "rb", "DATA")

	if !F then
		return
	end

	F:Seek(0)

	local version = F:ReadShort()

	if (version != MDL_VERSION) then
		F:Close()
		print("GS2ReadModelData: File is wrong version ("..(version or "NULL")..") should be "..MDL_VERSION.."!",hash)
		file.Delete(file_path..".txt")
		return
	end

	MDL_CACHE[mdl] = {
		gib_data = {}
	}
	
	local succ, err = pcall(function()
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
	end)

	F:Close()

	if !succ then
		print("GS2ReadModelData: deleting corrupted file "..hash.." (Error: "..err..")")
		file.Delete(file_path..".txt")
		return
	end

	return MDL_CACHE[mdl]
end