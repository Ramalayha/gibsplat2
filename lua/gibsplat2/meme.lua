local path = "lua/entities/gs2_limb_mesh/cl_init.lua"

local str = file.Read(path, "GAME")

local ignore = {
	"util",
	"file",
	"include",
	"ClientsideModel",
	"net",
	"NextThink",
	"Material",
	"Matrix",
	"game",
	"CreateConVar",
	"unpack",
	"FindMetaTable",
	"hook",
	"KeyFromValue",
	"timer",
	"Mesh",
	"Angle",
	"Vector",
	"print",
	"pcall",
	"CreateClientProp",
	"Sound"
}

local tbl = {}

for w in str:gmatch("(%a+)%(") do
	if !table.HasValue(ignore, w) and _G[w] and !str:find("local "..w) and !str:find("function "..w) then
		tbl[w] = true
	end
end

for w in pairs(tbl) do
	print("local "..w.." = "..w)
end

table.Empty(tbl)

for lib, w in str:gmatch("(%a+)%.([^%(\n]+)%(") do
	if !table.HasValue(ignore, lib) and _G[lib] and _G[lib][w] then
		tbl[lib] = tbl[lib] or {}
		tbl[lib][w] = true		
	end
end

for lib, list in pairs(tbl) do
	print("")
	for w in pairs(list) do
		print("local "..lib.."_"..w.." = "..lib.."."..w)
	end	
end