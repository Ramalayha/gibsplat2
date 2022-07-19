--include("mesh_util.lua")

local GIB_VERSION = 1
local MESH_VERSION = 2

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

function FILE:WriteString(str)
	self:WriteShort(#str)
	self:Write(str)
end

function FILE:ReadString()
	return self:Read(self:ReadShort())
end

function FILE:ReadStringZ()
	local str = {}
	while true do
		local c = self:Read(1)		
		if c == "\0" then
			break
		end
		table.insert(str, c)
	end
	return table.concat(str, "")
end

function GS2WriteGibData(mdl, data)
	mdl = mdl:lower()
	
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/mesh_data_new")

	local hash = util.CRC(mdl)

	file.CreateDir("gibsplat2/mesh_data_new/"..hash)

	local file_path = "gibsplat2/mesh_data_new/"..hash.."/gib_data"..(SERVER and "_sv" or "_cl")..".txt"

	file.Write(file_path, "")

	local F = file.Open(file_path, "wb", "DATA")

	if !F then
		return
	end

	F:WriteShort(GIB_VERSION)

	F:WriteShort(table.Count(data))

	for pbone, data in pairs(data) do
		F:WriteShort(pbone)
		F:WriteShort(table.Count(data))
		for _, mesh in pairs(data) do
			F:WriteVector(mesh.min) 
			F:WriteVector(mesh.max)
			F:WriteShort(table.Count(mesh.conns))
			for _, conn in pairs(mesh.conns) do
				F:WriteShort(conn)
			end

			F:WriteLong(table.Count(mesh.vertex_buffer))
			for _, vert in pairs(mesh.vertex_buffer) do
				F:WriteVector(vert)
			end
			F:WriteLong(table.Count(mesh.index_buffer))
			for _, idx in pairs(mesh.index_buffer) do
				F:WriteLong(idx)
			end
		end
	end
	
	F:Flush()
	F:Close()
end

local function Tesselate(mesh)
	local new_mesh = {}
	for vert_index = 1, #mesh - 2, 3 do
		local v1 = mesh[vert_index]
		local v2 = mesh[vert_index + 1]
		local v3 = mesh[vert_index + 2]
		
		v1.new = false
		v2.new = false
		v3.new = false

		/*v1.points = v1.points or {}
		v1.points[v2] = true
		v1.points[v3] = true

		v2.points = v2.points or {}
		v2.points[v1] = true
		v2.points[v3] = true

		v3.points = v3.points or {}
		v3.points[v1] = true
		v3.points[v2] = true*/

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

	for key, vert in ipairs(new_mesh) do		
		local exists = false
		
		for _, vert2 in ipairs(verts) do
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

	for _, vert in ipairs(verts) do
		if vert.new then
			vert.pos:Add(vert.extra.pos * 1 / 16)
			vert.pos:Add(vert.extra2.pos * 1 / 16)
		end
	end

	for _, vert in ipairs(verts) do
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
			--local points = vert.points
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

			--vert.pos = vert.pos * (1 - B * n) + p
			vert.pos:Mul(1 - B * n)
			vert.pos:Add(p)
		end
	end

	return new_mesh
end

local GIB_DATA_CACHE = {}

function GS2ReadGibData(mdl)
	mdl = mdl:lower()
	if GIB_DATA_CACHE[mdl] then
		return GIB_DATA_CACHE[mdl]
	end

	local hash = util.CRC(mdl)

	local file_path = "gibsplat2/mesh_data_new/"..hash.."/gib_data"..(SERVER and "_sv" or "_cl")

	local F = file.Open("materials/"..file_path..".vmt", "rb", "GAME") or file.Open(file_path..".txt", "rb", "DATA")

	if !F then
		return
	end

	F:Seek(0)

	local succ, err = pcall(function()
		local version = F:ReadShort()

		if (version != GIB_VERSION) then
			F:Close()
			print("GS2ReadGibData: File is wrong version ("..(version or "NULL")..") should be "..GIB_VERSION.."!",hash)
			file.Delete(file_path..".txt")
			return
		end

		local ret = {}

		for i = 1, F:ReadShort() do
			local pbone = F:ReadShort()
			local data = {}
			ret[pbone] = data
			for i = 1, F:ReadShort() do
				local min = F:ReadVector()
				local max = F:ReadVector()
				local center = (min + max) / 2

				local size = max - min

				local vertex_buffer = {}
				local index_buffer = {}
				local triangles = {}
				local conns = {}

				for j = 1, F:ReadShort() do
					conns[j] = F:ReadShort()
				end

				for j = 1, F:ReadLong() do				
					vertex_buffer[j] = {pos = F:ReadVector()}				
				end

				for j = 1, F:ReadLong() do
					local idx = F:ReadLong()
					index_buffer[j] = idx

					local vert = vertex_buffer[idx]
					
					triangles[j] = vert
				end

				--UGLY!!!
				for key, vert in pairs(vertex_buffer) do
					vertex_buffer[key] = vert.pos * 1
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
					--triangles = Tesselate(triangles)
					
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
		end

		return ret
	end)

	F:Close()

	if !succ then
		print("GS2ReadGibData: deleting corrupted file "..hash.." (Error: "..err..")")
		file.Delete(file_path..".txt")
	else
		GIB_DATA_CACHE[mdl] = err
		return err
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

	return VERTEX_BUFFER --return this to use for decals
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

	return tris, VERTEX_BUFFER
end

local MATERIAL_CACHE = {}

function GS2WriteMeshData(mdl, bg_mask, data)
	mdl = mdl:lower()
	
	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/mesh_data_new")

	local hash = util.CRC(mdl)

	--local hash_bg = util.CRC(bg_mask)
	local hash_bg = bg_mask

	local path_folder = "gibsplat2/mesh_data_new/"..hash
	file.CreateDir(path_folder)
	local path_file = path_folder.."/"..hash_bg..".txt"
	file.Write(path_file, "")
	local F = file.Open(path_file, "wb", "DATA")
	F:WriteShort(MESH_VERSION)

	F:WriteShort(table.Count(data))

	for phys_bone, entries in pairs(data) do
		F:WriteShort(phys_bone)
		F:WriteShort(#entries)
		for _, entry in ipairs(entries) do
			F:WriteString(entry.body and entry.body.Material:GetName() or "")
			local vtx_buffer = WriteTriangles(F, entry.body and entry.body.decal_tris or {})
			if entry.body then
				entry.body.vertexes = vtx_buffer
			end
			F:WriteString(entry.flesh and entry.flesh.Material:GetName() or "")
			local vtx_buffer = WriteTriangles(F, entry.flesh and entry.flesh.decal_tris or {})
			if entry.flesh then
				entry.flesh.vertexes = vtx_buffer
			end
		end		
	end

	F:Flush()
	F:Close()
end

local MDL_CACHE = {}

function GS2ReadMeshData(mdl, bg_mask, norec)
	if !bg_mask then return end

	if MDL_CACHE[mdl] and MDL_CACHE[mdl][bg_mask] then
		return MDL_CACHE[mdl][bg_mask]
	end

	local hash = util.CRC(mdl)

	--local hash_bg = util.CRC(bg_mask)
	local hash_bg = bg_mask

	local path_folder = "gibsplat2/mesh_data_new/"..hash
	local path_file = path_folder.."/"..hash_bg

	local _path = "materials/"..path_file..".vmt"

	local F

	if file.Exists(_path, "GAME") then
		F = file.Open(_path, "rb", "GAME")
	else
		F = file.Open(path_file..".txt", "rb", "DATA")
	end

	if !F then return end

	local version = F:ReadShort()

	if version != MESH_VERSION then	return end

	MDL_CACHE[mdl] = MDL_CACHE[mdl] or {}
	MDL_CACHE[mdl][bg_mask] = MDL_CACHE[mdl][bg_mask] or {}

	for i = 1, F:ReadShort() do
		local phys_bone = F:ReadShort()
		MDL_CACHE[mdl][bg_mask][phys_bone] = {}
		for j = 1, F:ReadShort() do
			local entry = {}
			local mat = F:ReadString()
			local tris, vtx_buffer = ReadTriangles(F)
			if #tris > 0 then
				local M = Mesh()
				M:BuildFromTriangles(tris)
				entry.body = {
					Mesh = M,
					Material = Material(mat),
					decal_tris = tris,
					mat_name = mat,
					vertexes = vtx_buffer
				}
			end
			local mat = F:ReadString()
			local tris, vtx_buffer = ReadTriangles(F)
			if #tris > 0 then
				local M = Mesh()
				M:BuildFromTriangles(tris)
				entry.flesh = {
					Mesh = M,
					Material = Material(mat),
					decal_tris = tris,
					is_flesh = true,
					vertexes = vtx_buffer
				}
			end
			table.insert(MDL_CACHE[mdl][bg_mask][phys_bone], entry)
		end
	end

	if !norec then
		local files = file.Find("materials/"..path_folder.."/*", "GAME")

		if files then
			if #files > 3 and #files <= 22 then
				print("GS2: Loading "..(#files - 2).." meshes for "..mdl)
				for _, name in pairs(files) do
					GS2ReadMeshData(mdl, tonumber(name:StripExtension()), true)
				end
			end
		else
			local files = file.Find(path_folder.."/*", "DATA")
			
			if files and #files > 3 and #files <= 22 then
				print("GS2: Loading "..(#files - 2).." meshes for "..mdl)
				for _, name in pairs(files) do
					GS2ReadMeshData(mdl, tonumber(name:StripExtension()), true)
				end
			end
		end

		if mdl:find("zombie") then
			--auto load headcrabs with zombies
			if mdl:find("poison") then
				print("GS: Loading poison headcrab")
				GS2ReadMeshData("models/headcrabblack.mdl", 0)
			elseif mdl:find("fast") then
				print("GS2: Loading fast headcrab")
				GS2ReadMeshData("models/headcrab.mdl", 0)
			elseif mdl:find("classic") or mdl:find("soldier") then
				print("GS2: Loading headcrab")
				GS2ReadMeshData("models/headcrabclassic.mdl", 0)
			end
		end
	end

	return MDL_CACHE[mdl][bg_mask]
end