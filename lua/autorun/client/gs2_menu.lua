local defaults =
{
    ["gs2_bloodpool_size"] = "10",
    ["gs2_old_effects"] = "1",
    ["gs2_new_effects"] = "1",
    --["gs2_particles_linger_chance"] = "0.1",
    --["gs2_max_particles"] = "10000",
    --["gs2_particles_lifetime"] = "60",
    ["gs2_mesh_iterations"] = "10",
    ["gs2_gib_cl"] = "1",
    --["gs2_less_limbs"] = "0",
    ["gs2_constraint_strength_multiplier"] = "250",
    ["gs2_max_constraint_strength"] = "15000",
    ["gs2_min_constraint_strength"] = "4000",
    ["gs2_gib_generate_all"] = "0",
    ["gs2_max_gibs"] = "128",
    ["gs2_gib_custom"] = "1",
    ["gs2_gib_merge_chance"] = "0.7",
    ["gs2_gib_factor"] = "0.3",
    ["gs2_gib_lifetime"] = "300",
    ["gs2_gib_expensive"] = "0",
    ["gs2_pull_limb"] = "1",
    ["gs2_gib_chance"] = "0.15",
    ["gs2_gib_sv"] = "1",
    ["gs2_default_ragdolls"] = "1",
    ["gs2_max_decals_transfer"] = "5",
    ["gs2_gib_chance_explosion_multiplier"] = "10"
}

concommand.Add("gs2_reset_cvars", function()
    for cvar, val in pairs(defaults) do
        local CV = GetConVar(cvar)
        if CV then
            RunConsoleCommand(cvar, CV:GetDefault())
        end
    end
end)

local function PopulateGS2Menu(pnl)
    pnl:CheckBox("Enabled", "gs2_enabled")
    pnl:ControlHelp("Enable or disable the addon.")

    pnl:CheckBox("Keep Corpses", "ai_serverragdolls")
    pnl:ControlHelp("This needs to be on to be able to gib NPCs.")

    if LocalPlayer():IsAdmin() then
        pnl:Button("Cleanup Gibs", "gs2_cleargibs_sv")
    else
        pnl:Button("Cleanup Gibs", "gs2_cleargibs")
    end
    
    pnl:Button("Reset Settings", "gs2_reset_cvars")

    pnl:CheckBox("Default Ragdolls", "gs2_default_ragdolls")
    pnl:ControlHelp("Controls if all ragdolls should be gibbable.")

    pnl:CheckBox("Player Ragdolls", "gs2_player_ragdolls")
    pnl:ControlHelp("Controls if player ragdolls should be gibbable.")

    pnl:CheckBox("Lua Effects", "gs2_old_effects")
    pnl:ControlHelp("Turn Lua based particle effects on or off.")

    pnl:CheckBox("Effects", "gs2_new_effects")
    pnl:ControlHelp("Turn particle effects on or off.")

    pnl:CheckBox("Expensive Gibs", "gs2_gib_expensive")
    pnl:ControlHelp("Controls if gibs should use a detailed physics mesh.")

    pnl:CheckBox("Custom Gibs", "gs2_gib_custom")
    pnl:ControlHelp("Controls wheter to use custom model gibs or not (ribs etc)")

    pnl:CheckBox("Serverside Gibs", "gs2_gib_sv")
    pnl:ControlHelp("Controls if gibs should be created server-side.")

    pnl:CheckBox("Clientside Gibs", "gs2_gib_cl")
    pnl:ControlHelp("Controls if gibs should be created client-side.")

    --this is broken :(
    --pnl:CheckBox("Less Limbs", "gs2_less_limbs")
    --pnl:ControlHelp("Limits the amount of pieces a ragdoll can be cut into.")

    pnl:CheckBox("Expensive Joints", "gs2_pull_limb")
    pnl:ControlHelp("Controls wheter joints can break from stress.")

    --int options

    pnl:NumSlider("Max Decal Transfer", "gs2_max_decals_transfer", 0, 15)
    pnl:ControlHelp("Maximum number of decals to transfer to a mesh part.")

    pnl:NumSlider("Gib Limit", "gs2_max_gibs", 0, 512)
    pnl:ControlHelp("Controls how many gibs can exist in the map.")

    --pnl:NumSlider("Particle Limit", "gs2_max_particles", 0, 500)
    --pnl:ControlHelp("Controls how many particles can exist in the map.")

    --float options
    pnl:NumSlider("Gib Chance", "gs2_gib_chance", 0, 1, 3)
    pnl:ControlHelp("The chance of a ragdoll gibbing from taking damage.")

    pnl:NumSlider("Explosion Chance", "gs2_gib_chance_explosion_multiplier", 0, 50, 3)
    pnl:ControlHelp("How much more likely the ragdoll is to gib from an explosion.")

    pnl:NumSlider("Gib Spawnrate", "gs2_gib_factor", 0, 1, 3)
    pnl:ControlHelp("Controls how many gibs to spawn.")

    pnl:NumSlider("Gib Merge Chance", "gs2_gib_merge_chance", 0, 1, 3)
    pnl:ControlHelp("The chance of smaller gibs sticking together.")

    pnl:NumSlider("Gib Lifetime", "gs2_gib_lifetime", 0, 1000)
    pnl:ControlHelp("Controls how long gibs stay before disappearing.")

    --pnl:NumSlider("Particle Lifetime", "gs2_particles_lifetime", 1, 500, 3)
    --pnl:ControlHelp("Controls how long a particle stays.")

    --pnl:NumSlider("Particle Linger Chance", "gs2_particles_linger_chance", 0, 1, 3)
    --pnl:ControlHelp("The chance of a particle sticking to a surface.")
end

-- Check if sandbox is active gamemode and add in the settings
if engine.ActiveGamemode() == "sandbox" then
    hook.Add("AddToolMenuCategories", "GibSplat2Category", function() 
        spawnmenu.AddToolCategory("Utilities", "GibSplat2", "GibSplat 2")
    end)

    hook.Add("PopulateToolMenu", "GibSplat2MenuSettings", function() 
        spawnmenu.AddToolMenuOption("Utilities", "GibSplat2", "GS2Settings", "Settings", "", "", function(pnl)
            pnl:ClearControls()
            pnl:Help("Here you can change the GibSplat 2 settings.")
            PopulateGS2Menu(pnl)
        end)
    end)
end