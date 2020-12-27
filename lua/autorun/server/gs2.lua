include("gibsplat2/sv_hooks.lua")
include("gibsplat2/constraintinfo.lua")
include("gibsplat2/gibs.lua")
include("gibsplat2/buildcustomragdoll.lua")
include("gibsplat2/buildmesh.lua")

resource.AddWorkshop("2336666211")

--[[AddCSLuaFile("gibsplat2/constraintinfo.lua")
AddCSLuaFile("gibsplat2/buildmesh.lua")
AddCSLuaFile("gibsplat2/gibs.lua")
AddCSLuaFile("gibsplat2/clipmesh.lua")
AddCSLuaFile("gibsplat2/filesystem.lua")
AddCSLuaFile("gibsplat2/mesh_util.lua")

local function AddFolder(path)
	local files, folders = file.Find(path, "GAME")
	for _, file_name in pairs(files) do		
		resource.AddSingleFile(path:sub(0, -2)..file_name)
	end
	for _, folder in pairs(folders) do
		AddFolder(path:sub(0, -2)..folder.."/*")
	end
end

AddFolder("models/gibsplat2/*")
AddFolder("materials/models/gibsplat2/*")
AddFolder("materials/decals/alienflesh/*")

resource.AddFile("materials/models/alienflesh.vmt")
resource.AddFile("materials/models/zombieflesh.vmt")
resource.AddFile("materials/models/antlion.vmt")
resource.AddSingleFile("materials/gibsplat2/skeletons.vmt")
resource.AddSingleFile("materials/gibsplat2/gibs.vmt")]]