local file_name = SERVER and "modellist_sv.txt" or "modellist_cl.txt"

if !file.Exists(file_name, "DATA") then
	file.Write(file_name,"")
end

local done = {}

for mdl in file.Read(file_name):gmatch("[^\n]+") do
	done[mdl:sub(1,-2)] = true
end

if F then F:Close() end

F = file.Open(file_name, "a", "DATA")

local function IsRagdoll(phy)
	if !file.Exists(phy, "GAME") then
		return false
	end

	local F = file.Open(phy, "rb", "GAME")
	F:Seek(8)
	local solid_count = F:ReadLong()
	F:Close()
	return (solid_count and solid_count > 1)
end

local n = 0

local models = {}

local function PreGenerate(path)
	local files, folders = file.Find(path, "GAME")
	path = path:sub(1,-2)
	for _, file_name in ipairs(files) do 
		local mdl = path..file_name
		if (n < 2000 and file_name:sub(-4) == ".mdl" and !done[mdl] and IsRagdoll(mdl:sub(1,-4).."phy")) then
			if util.IsValidRagdoll(mdl) then
				n = n+1
				models[n] = mdl					
			end
		end
	end
	for _, folder in ipairs(folders) do
		PreGenerate(path..folder.."/*")
	end
end

local list = {
	--"models/humans/*",
	--"models/zombie/*",
	"models/*",
	--"models/player/*",
}

print("Num models: "..table.Count(models))

local temp

local key = 1

function Process()
	if #models == 0 then
		for _, path in ipairs(list) do
			PreGenerate(path)
		end
	end
	local mdl = models[key]
	if !mdl then
		if SERVER then
			BroadcastLua("Process()")
		end
		F:Close()		
		return
	end
	game.CleanUpMap(true)
	if SERVER then
		temp = ents.Create("prop_dynamic")
		temp:SetModel(mdl)
		temp:Spawn() --loads the model			
	else
		temp = ClientsideRagdoll(mdl)		
		--gamemode.Call("NetworkEntityCreated",temp)
		GetBoneMeshes(temp, 0)
		for phys_bone = 0, temp:GetPhysicsObjectCount() - 1 do		
			GetPhysGibMeshes(mdl, phys_bone)				
		end
	end
	temp:Remove()
	print(key..": "..mdl)
	F:Write(mdl.."\n")
	F:Flush()
	key = key + 1
	timer.Simple(0.5, Process)
end

if CLIENT then
	hook.Add("HUDPaint", "h", function()
		if key > 1 and !models[key] then
			hook.Remove("HUDPaint", "h")
			return
		end

		surface.SetTextColor(255, 0, 0)
		surface.SetTextPos(ScrW()/2, ScrH()/2)
		surface.SetFont("Default")
		surface.DrawText("Current model: "..key.."/"..#models.." ("..(models[key] or "NULL")..")")
	end)
	--timer.Simple(1,Process)
else
	/*timer.Simple(1, function()
		for _, path in ipairs(list) do
			PreGenerate(path)
		end
		BroadcastLua("Process()")
	end)*/
	timer.Simple(1, Process)
end