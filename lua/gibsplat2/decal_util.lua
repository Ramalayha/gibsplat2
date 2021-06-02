local MAT_CACHE = {}

function ApplyDecal(mat, ent, pos, norm, size)
	if !IsValid(ent) then
		return	
	end
	local size = size or 1
	local mat = util.DecalMaterial(mat)
	
	MAT_CACHE[mat] = MAT_CACHE[mat] or Material(mat)
	mat = MAT_CACHE[mat]

	util.DecalEx(mat, ent, pos, norm, color_white, 1, 1)
end

local function IsInBox(p, min, max)
	return (p.y >= min.y and p.y <= max.y and p.z >= min.z and p.z <= max.z)
end

local function Overlaps(p1, p2, p3, min, max)
	if (IsInBox(p1, min, max) or IsInBox(p2, min, max) or IsInBox(p3, min, max)) then
		return true
	end
	if (p1.y < min.y) then
		if (p2.y < min.y) then
			if (p3.y < min.y) then
				return false
			end
		end

		local b = p3.z
		local m = (p1.z - p3.z) / (p1.y - p3.y)
		
		local z = min.y * m + b
		
		if (z >= min.z and z <= max.z) then
			return true
		end

		local m = (p2.z - p3.z) / (p2.y - p3.y)
		local z2 = min.y * m + b

		if (z >= min.z and z <= max.z) then
			return true
		end		
	elseif (p1.y > max.y) then
		if (p2.y > max.y) then
			if (p3.y > max.y) then
				return false
			end
		end

		local b = p3.z
		local m = (p1.z - p3.z) / (p1.y - p3.y)
		
		local z = max.y * m + b
		
		if (z >= min.z and z <= max.z) then
			return true
		end

		local m = (p2.z - p3.z) / (p2.y - p3.y)
		local z2 = max.y * m + b

		if (z >= min.z and z <= max.z) then
			return true
		end		
	elseif (p1.z < min.z) then
		if (p2.z < min.z) then
			if (p3.z < min.z) then
				return false
			end
		end

		local b = p3.z
		local m = (p1.z - p3.z) / (p1.y - p3.y)
		
		local y = (min.z - b) / m
		
		if (y >= min.y and y <= max.y) then
			return true
		end

		local m = (p2.z - p3.z) / (p2.y - p3.y)
		local y = (min.z - b) / m
		
		if (y >= min.y and y <= max.y) then
			return true
		end	
	elseif (p1.z > max.z) then
		if (p2.z > max.z) then
			if (p3.z > max.z) then
				return false
			end
		end
		local b = p3.z
		local m = (p1.z - p3.z) / (p1.y - p3.y)
		
		local y = (max.z - b) / m
		
		if (y >= min.y and y <= max.y) then
			return true
		end

		local m = (p2.z - p3.z) / (p2.y - p3.y)
		local y = (max.z - b) / m
		
		if (y >= min.y and y <= max.y) then
			return true
		end	
	end
	return false
end

function GetDecalMesh(input, pos, ang, w, h)
	local tris_in = input
	local tris_out = {}

	local dir = ang:Forward()

	local min = Vector(0, -w, -h)
	local max = -min

	for vert_index = 1, #tris_in - 2, 3 do
		local v1 = tris_in[vert_index]
		local v2 = tris_in[vert_index + 1]
		local v3 = tris_in[vert_index + 2]

		local p1 = v1.pos
		local p2 = v2.pos
		local p3 = v3.pos

		local norm = (p2 - p1):Cross(p3 - p1)
		norm:Normalize()

		if (norm:Dot(dir) > 0) then
			local lp1 = WorldToLocal(p1, angle_zero, pos, ang)
			local lp2 = WorldToLocal(p2, angle_zero, pos, ang)
			local lp3 = WorldToLocal(p3, angle_zero, pos, ang)

			if Overlaps(lp1, lp2, lp3, min, max) then
				--lp1.x = 0
				--lp2.x = 0
				--lp3.x = 0

				p1 = LocalToWorld(lp1, angle_zero, pos, ang)
				p2 = LocalToWorld(lp2, angle_zero, pos, ang)
				p3 = LocalToWorld(lp3, angle_zero, pos, ang)

				v1 = table.Copy(v1)
				v2 = table.Copy(v2)
				v3 = table.Copy(v3)

				v1.pos = p1
				v2.pos = p2
				v3.pos = p3

				v1.u = (w + lp1.y) / w / 2
				v1.v = (h + lp1.z) / h / 2

				v2.u = (w + lp2.y) / w / 2
				v2.v = (h + lp2.z) / h / 2

				v3.u = (w + lp3.y) / w / 2
				v3.v = (h + lp3.z) / h / 2

				table.insert(tris_out, v1)
				table.insert(tris_out, v2)
				table.insert(tris_out, v3)
			end
		end
	end

	if (#tris_out != 0) then
		local M = Mesh()
		M:BuildFromTriangles(tris_out)
		return M, tris_out
	end
end