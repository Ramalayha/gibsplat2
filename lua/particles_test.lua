game.AddParticles("particles/gs2_particles.pcf")

PrecacheParticleSystem("blood_fluid_BI")
PrecacheParticleSystem("blood_fluid_02")

local p = CreateParticleSystem(Entity(0), "blood_fluid_02", PATTACH_WORLDORIGIN)

p:SetControlPoint(2, Vector(10,10,10))