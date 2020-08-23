--[[
	Code borrowed from source sdk with slight modifications
]]

local Clamp 	= math.Clamp
local random 	= math.random
local Rand 		= math.Rand
local Vector 	= Vector

local mat_spark = Material("effects/spark")

function EFFECT:Init(data)
	self.Body 	= data:GetEntity()
	self.HitBox = data:GetHitBox()
	
	self.Created = CurTime()
	
	self.Emitter = ParticleEmitter(vector_origin, false)
end

function EFFECT:Think()
	
end

function EFFECT:Render()
	if !IsValid(self.Body) then
		self:Remove()
		return
	end

	local min, max = self.Body:GetHitBoxBounds(self.HitBox, 0)

	local vec_skew

	local fade_perc = 1

	local x_dir
	local y_dir

	local x_scale = x_dir * 0.75
	local y_scale = y_dir * 0.75

	local num_particles = Clamp(3 * fade_perc, 0, 3)

	for i = 1, 2 do
		if (random(0, 2) != 0) then
			continue
		end

		local offset = x_dir * Rand(-x_scale * 0.5, x_scale * 0.5) +
			y_dir * Rand(-y_scale * 0.5, y_scale * 0.5)

		offset:Add(vec_skew)

		local particle = self.Emitter:Add(mat_spark, offset)

		particle:SetVelocity(Vector(Rand(-4, 4), Rand(-4, 4), Rand(16, 64)))

		if (num_particles == 0) then
			particle:SetStartSize(2)
			particle:SetDieTime(Rand(0.8, 1))
			particle:SetRollDelta(Rand(-4, 4))
		else
			particle:SetStartSize(Rand(4, 6))
			particle:SetDieTime(Rand(0.4, 0.5))
			particle:SetRollDelta(Rand(-8, 8))
		end

		particle:SetLifeTime(0)
		particle:SetRoll(random(0, 360))

		particle:SetStartAlpha(255)

		particle:SetEndSize(0)
		particle:SetEndAlpha(0)
	end
end