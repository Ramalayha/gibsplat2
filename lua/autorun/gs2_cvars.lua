CreateConVar("gs2_enabled", 1, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_player_ragdolls", 0, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_default_ragdolls", 1, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_gib_sv", 1, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_gib_chance", 0.15, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_pull_limb", 1, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_gib_chance", 0.15, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
CreateConVar("gs2_gib_expensive", 0, FCVAR_ARCHIVE)
CreateConVar("gs2_gib_lifetime", 300) --after not moving for this amount of time the gib will fade away

if SERVER then
	CreateConVar("gs2_gib_factor", 0.3, FCVAR_ARCHIVE)
	CreateConVar("gs2_gib_merge_chance", 0.7, FCVAR_ARCHIVE)
	CreateConVar("gs2_gib_custom", 1, FCVAR_ARCHIVE)
	CreateConVar("gs2_gib_expensive", 1, FCVAR_ARCHIVE)
	CreateConVar("gs2_max_gibs", 32, FCVAR_ARCHIVE)
	CreateConVar("gs2_gib_generate_all", 0, FCVAR_ARCHIVE)
	CreateConVar("gs2_min_constraint_strength", 4000, FCVAR_ARCHIVE)
	CreateConVar("gs2_max_constraint_strength", 15000, FCVAR_ARCHIVE)
	CreateConVar("gs2_constraint_strength_multiplier", 250, FCVAR_ARCHIVE)
	CreateConVar("gs2_less_limbs", 0, FCVAR_ARCHIVE)
end

if CLIENT then
	CreateClientConVar("gs2_gib_cl", 1, true)
	CreateClientConVar("gs2_mesh_iterations", 10, true, false, "How many times per frame the mesh generation code should run (higher = quicker generation, lower = smaller fps spikes)")
end