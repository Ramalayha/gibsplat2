game.AddParticles("particles/gs2_particles.pcf")

PrecacheParticleSystem("blood_body_explosion3_green")

--local p = CreateParticleSystem(Entity(0), "blood_body_explosion3_green", PATTACH_WORLDORIGIN, 0, Vector(0, 0, 100))

--p:SetControlPoint(2, Vector(10,10,10))

local sprites = {}

local function h(path)
	local files, folders = file.Find(path.."*","GAME")
	for k,v in pairs(files) do
		if v:find"blood" and v:find"vmt$" then
			table.insert(sprites, (Material(path:gsub("^materials/", "")..v:gsub(".vmt$", ""))))
		end
	end
	for k,v in pairs(folders) do
		h(path..v.."/")
	end
end

h("materials/effects/")

for k,v in pairs(sprites) do
	print(v:GetName())
end

local e = ParticleEmitter(vector_origin)

for i = 1, 20 do

local dir = VectorRand()
dir:Normalize()

local p = e:Add("particle/smokesprites_0005", dir * 20)

local size = math.Rand(5, 20)

p:SetLifeTime(0)
p:SetDieTime(0.6)

p:SetStartSize(size)
p:SetEndSize(size * 0.6)

p:SetStartAlpha(150)
p:SetEndAlpha(0)

p:SetColor(72 * math.Rand(0.5, 1.5), 0, 0)

p:SetRollDelta(0.2)

p:SetVelocity(dir * 10)
end