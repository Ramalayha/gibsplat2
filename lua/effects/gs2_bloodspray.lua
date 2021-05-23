--[[
	Code borrowed from source sdk with slight modifications
]]

local decal_lifetime 	= CreateClientConVar("gs2_particles_lifetime", 60, true)
local max_particles 	= CreateClientConVar("gs2_max_particles", 128, true)
local do_effects 		= CreateClientConVar("gs2_effects", 1, true)
local linger_chance 	= CreateClientConVar("gs2_particles_linger_chance", 0.1, true)

local SIZE = 2

local bit_band = bit.band
local bit_lshift = bit.lshift

local blood_colors = {
	[BLOOD_COLOR_RED] = Vector(72, 0, 0),
	[BLOOD_COLOR_YELLOW] = Vector(195, 195, 0),
	[BLOOD_COLOR_GREEN] = Vector(195, 195, 0)
}

local blood = {
	[BLOOD_COLOR_RED] = {
		"decals/flesh2/blood1",
		"decals/flesh2/blood2",
		"decals/flesh2/blood3",
		"decals/flesh2/blood4",
		"decals/flesh2/blood5"
	},
	[BLOOD_COLOR_YELLOW] = {
		"decals/alienflesh/blood1",
		"decals/alienflesh/blood2",
		"decals/alienflesh/blood3",
		"decals/alienflesh/blood4",
		"decals/alienflesh/blood5"
	},
	[BLOOD_COLOR_GREEN] = {
		"decals/alienflesh/blood1",
		"decals/alienflesh/blood2",
		"decals/alienflesh/blood3",
		"decals/alienflesh/blood4",
		"decals/alienflesh/blood5"
	}
}

function EFFECT:Init(data)
	if !do_effects:GetBool() then return end
	
	self.LocalPos = data:GetOrigin()
	self.LocalAng = data:GetAngles()

	self.Body = data:GetEntity()
	self.Color = data:GetColor()
	self.Bone = data:GetHitBox()
	self.Created = CurTime()
	self.DieTime = math.Clamp(data:GetScale(), 0, 10)
	self.Blood = data:GetColor()
	self.BloodColor = blood_colors[self.Blood] or Vector(255, 255, 255)

	if !IsValid(self.Body) then
		self:Remove()
		return
	end

	self.PhysBone = self.Body:TranslateBoneToPhysBone(self.Bone)

	self.mask = bit_lshift(1, self.PhysBone)

	local matrix = self.Body:GetBoneMatrix(self.Bone)
	
	if !matrix then
		return
	end

	local bone_pos = matrix:GetTranslation()
	local bone_ang = matrix:GetAngles()

	--self:SetRenderBounds(Vector(-1, -1, -1), Vector(1, 1, 1))
	self:SetPos(bone_pos)

	self:SetParent(self.Body)
	self:SetParentPhysNum(self.Body:TranslateBoneToPhysBone(self.Bone))

	self.Emitter = ParticleEmitter(bone_pos, false)
	self.Emitter3D = ParticleEmitter(bone_pos, true)

	self.last_sim = CurTime()

	self.Particles = {}

	for hbg = 0, self.Body:GetHitBoxGroupCount() - 1 do
		for hb = 0, self.Body:GetHitBoxCount(hbg) - 1 do
			if (self.Body:GetHitBoxBone(hb, hbg) == self.Bone) then
				local min, max = self.Body:GetHitBoxBounds(hb, hbg)
				min.x = 0
				max.x = 0
				self.Radius = min:Distance(max) * 0.2
				return
			end
		end
	end
	self.Radius = 0
end

local trace = {
	mask = MASK_SOLID_BRUSHONLY
}

local PARTICLES = {}

timer.Create("gs2_gcparticles", 3, 0, function()
	while PARTICLES[1] do
		if (!PARTICLES[1].Created or PARTICLES[1].Created + PARTICLES[1]:GetDieTime() < CurTime()) then
			table.remove(PARTICLES, 1)
		else
			break
		end
	end
end)

local function OnCollide(self, pos, norm)
	if (#PARTICLES >= max_particles:GetInt()) then return end
	
	trace.start = pos + norm
	trace.endpos = pos - norm

	local tr = util.TraceLine(trace)

	if (!tr.Hit or tr.HitNoDraw or tr.HitSky or (IsValid(tr.Entity) and !tr.Entity:IsWorld())) then
		return
	end

	local blood_materials = blood[self.Blood]

	if (blood_materials and IsValid(self.Emitter) and math.random() < linger_chance:GetFloat()) then
		local mat = blood_materials[math.random(1, #blood_materials)]
		
		local particle = self.Emitter:Add(mat, pos)

		local ang = norm:Angle()
		ang:RotateAroundAxis(norm, math.Rand(0, 360))

		particle:SetAngles(ang)

		local size = math.Rand(0.5, 1)
		particle:SetStartSize(SIZE * size)
		particle:SetEndSize(SIZE * size)

		particle:SetStartAlpha(255)
		particle:SetEndAlpha(255)
		--particle:SetRoll(math.random(0, 360))
		
		particle:SetLifeTime(0)
		particle:SetDieTime(decal_lifetime:GetFloat())

		local color = render.GetLightColor(pos + norm)
		
		--color:Mul(blood_color * math.random(0.95, 1))

		--particle:SetColor(color.x, color.y, color.z)

		particle.Created = CurTime()

		table.insert(PARTICLES, particle)
	end

	self:SetCollide(false)
	self:SetDieTime(0)
end

function EFFECT:Think()
	if !do_effects:GetBool() then return false end
	--line 162 is not an error dammit!
	local cur_time = CurTime()

	if !IsValid(self.Emitter) then
		if self.Emitter3D then
			self.Emitter3D:Finish()
		end
		return false
	end
	if (!IsValid(self.Body) or
	 	cur_time - self.Created > self.DieTime or
	 	!self.Body.GS2Limbs or bit_band(self.mask, self.Body:GetNWInt("GS2GibMask")) != 0) then

		local Emitter = self.Emitter
		local Emitter3D = self.Emitter3D

		timer.Simple(10 ,function() --give some time for particles to hit the ground
		 	Emitter:Finish()	
		 	if Emitter3D then
		 		Emitter3D:Finish()
		 	end
		end)
		return false
	end

	local matrix = self.Body:GetBoneMatrix(self.Bone)

	local bone_pos, bone_ang = LocalToWorld(self.LocalPos, self.LocalAng, matrix:GetTranslation(), matrix:GetAngles())

	self.last_bone_pos = self._last_bone_pos or bone_pos

	local bone_vel = bone_pos - self.last_bone_pos
	bone_vel:Div(cur_time - self.last_sim)
	self.last_sim = cur_time

	local bone_dir = -bone_ang:Forward()

	local right = bone_dir:Cross(Vector(0, 0, 1))
	local up = right:Cross(bone_dir)

	for i = 1, 4 do --14
		local pos = bone_pos
		 + right * math.Rand(-0.5, 0.5)
		 + up * math.Rand(0.5, 0.5)

		local dir = bone_dir + VectorRand(-0.3, 0.3)

		local vel = dir * math.Rand(4, 40) * 10 * (0.7 + 0.3 * math.sin((cur_time - self.Created) * 3)) * (self.Created + self.DieTime - cur_time) / self.DieTime
		
		--vel = vel * (0.5 + math.sin(self.Created - cur_time) * 0.5)

		local particle = self.Emitter:Add("effects/blood_drop", pos + Angle(0, math.Rand(0, 360), 0):Forward() * self.Radius)

		table.insert(self.Particles, particle)

		particle:SetGravity(Vector(0, 0, -600))
		particle:SetVelocity(bone_vel + vel)
		particle:SetStartSize(SIZE * math.Rand(0.2, 0.3) * 5)
		particle:SetStartLength(math.Rand(1.25, 2.75) * 5)
		particle:SetLifeTime(0)
		particle:SetDieTime(math.Rand(0.5, 1))

		local color = render.GetLightColor(pos)
		
		color = color * self.BloodColor

		particle:SetColor(color.x, color.y, color.z)

		particle:SetCollide(true)

		particle.Blood = self.Blood
		particle.Emitter = self.Emitter3D
		particle:SetCollideCallback(OnCollide)
	end

	for i = 1, 8 do --24
		local pos = bone_pos
		 + right * math.Rand(-0.5, 0.5)
		 + up * math.Rand(0.5, 0.5)

		local dir = bone_dir + VectorRand(-1, 1)
		--dir.z = dir.z + math.Rand(0, 1)

		local vel = dir * math.Rand(2, 25) * 5 * (self.Created + self.DieTime - cur_time) / self.DieTime
		
		--vel = vel * (1 + math.sin((self.Created - cur_time) * 10))

		local particle = self.Emitter:Add("effects/blood_drop", pos)

		table.insert(self.Particles, particle)

		particle:SetGravity(Vector(0, 0, -600))
		particle:SetVelocity(bone_vel + vel)
		particle:SetStartSize(SIZE * math.Rand(0.025, 0.05))
		particle:SetStartLength(math.Rand(2.5, 3.75))
		particle:SetLifeTime(0)
		particle:SetDieTime(math.Rand(5, 10))

		local color = render.GetLightColor(pos)
		
		color = color * self.BloodColor

		particle:SetColor(color.x, color.y, color.z)

		particle:SetCollide(true)

		particle.Blood = self.Blood
		particle.Emitter = self.Emitter3D
		particle:SetCollideCallback(OnCollide)
	end

	for i = 1, 10 do --6
		local pos = bone_pos + bone_dir
		 + right * math.Rand(-1, 1)
		 + up * math.Rand(-1, 1)

		local vel = bone_dir * math.Rand(10, 20) + VectorRand(-0.5, 0.5)

		local particle = self.Emitter:Add("effects/blood_puff", pos + Angle(math.Rand(0, 360), 0, 0):Forward() * self.Radius)

		particle:SetGravity(Vector(0, 0, -600))
		particle:SetVelocity(bone_vel + vel)

		local size = math.Rand(1, 1.5)
		particle:SetStartSize(SIZE * size)	
		particle:SetEndSize(SIZE * size * 4)

		particle:SetStartAlpha(math.random(150, 200))
		particle:SetEndAlpha(0)
		particle:SetRoll(math.random(0, 360))
		particle:SetRollDelta(0)

		particle:SetLifeTime(0)
		particle:SetDieTime(math.Rand(0.01, 0.03))

		local color = render.GetLightColor(pos)

		color = color * self.BloodColor

		particle:SetColor(color.x, color.y, color.z)

		particle:SetCollide(true)

		particle.Blood = self.Blood
		particle.Emitter = self.Emitter3D
		particle:SetCollideCallback(OnCollide)
	end

 	return true
end

local mat = Material("models/flesh")

function EFFECT:Render()
	
end

hook.Add("PostCleanupMap", "GS2ClearParticles", function()
	for key, particle in pairs(PARTICLES) do
		if particle then
			particle:SetDieTime(0)
		end
		PARTICLES[key] = nil
	end
end)