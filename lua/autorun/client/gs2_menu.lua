local cvBool = 1
local cvFloat = 2
local cvInt = 3
local cvFunc = 4

local GS2CVarsMain = {
    ["gs2_enabled"] = {t = cvBool, name = "Enabled", desc = "Enable or disable the addon."},
    ["ai_serverragdolls"] = {t = cvBool, name = "Keep Corpses", desc = "This must be enabled for gibs to work."},
    ["gs2_cleargibs"] = {t = cvFunc, name = "Cleanup Gibs", desc = "Cleans up all clientside gibs."},
}
local GS2CVarsAdvanced = {
    ["gs2_default_ragdolls"] = {t = cvBool, name = "Default Ragdolls", desc = "Gibs for all or only default models."},
    ["gs2_player_ragdolls"] = {t = cvBool, name = "Player Ragdolls", desc = "Should player ragdolls be gibbable."},
    ["gs2_effects"] = {t = cvBool, name = "Effects", desc = "Enable or disable particle effects."},
    ["gs2_gib_chance"] = {t = cvFloat, name = "Gib Chance", desc = "Chances of gibs appearing from a ragdoll."},
    ["gs2_gib_sv"] = {t = cvBool, name = "Serverside Gibs", desc = "Sets gibs to be serverside and overrides clientside setting."},
    ["gs2_gib_cl"] = {t = cvBool, name = "Clientside Gibs", desc = "Sets gibs to be clientsided."},
    ["gs2_gib_factor"] = {t = cvFloat, name = "Gib Spawnrate", desc = "How many gibs should spawn"},
    ["gs2_gib_lifetime"] = {t = cvInt, name = "Gib Lifetime", desc = "How long do the gibs appear for.", min = 0, max = 1000},
    ["gs2_gib_merge_chance"] = {t = cvFloat, name = "Gib Merging", desc = "Controls the chance of small gibs sticking together"},
    ["gs2_less_limbs"] = {t = cvBool, name = "Limit Limbs", desc = "Limits the number of limbs that are gibbed."},
    ["gs2_max_gibs"] = {t = cvInt, name = "Gib Limit", desc = "How many gibs can be there at once.", min = 1, max = 100},
    ["gs2_max_particles"] = {t = cvInt, name = "Particle Limit", desc = "How many particles can exist at once.", min = 1, max = 500},
    ["gs2_particles_lifetime"] = {t = cvInt, name = "Particle Lifetime", desc = "How long does the particle effects last.", min = 1, max = 500},
    ["gs2_particles_linger_chance"] = {t = cvFloat, name = "Particle Lingerchance", desc = "Controls the chance of particles staying after hitting something.", min = 0, max = 1},
    ["gs2_pull_limb"] = {t = cvBool, name = "Expensive Joints", desc = "Uncheck to disable joints breaking from stress (improves performance)", min = 0, max = 1},
}

local function PopulateSBXToolMenu(pnl)

    local function addBoolOption(pnl, cv, name, desc)
        pnl:CheckBox(name, cv)
        pnl:ControlHelp(desc)
    end
    local function addFuncOption(pnl, cmd, name, desc)
        pnl:Button(name, cmd)
    end
    local function addIntOption(pnl, cv, name, desc, min, max)
        pnl:NumSlider(name, cv, min, max)
        pnl:ControlHelp(desc)
    end
    local function addFloatOption(pnl, cv, name, desc)
        pnl:NumSlider(name, cv, 0, 1, 3)
        pnl:ControlHelp(desc)
    end

    -- First add in the settings from GS2CVarsMain.
    for cv, dt in pairs(GS2CVarsMain) do
        if dt.t == cvBool then addBoolOption(pnl, cv, dt.name, dt.desc) end
        if dt.t == cvFunc then addFuncOption(pnl, cv, dt.name, dt.desc) end
    end

    -- Populate with other settings. The way the table is setup we got to loop over the table twice to maintain some order
    for cv, dt in pairs(GS2CVarsAdvanced) do
        if dt.t == cvBool then addBoolOption(pnl, cv, dt.name, dt.desc) end
    end
    for cv, dt in pairs(GS2CVarsAdvanced) do
        if dt.t == cvFloat then addFloatOption(pnl, cv, dt.name, dt.desc) end
        if dt.t == cvInt then addIntOption(pnl, cv, dt.name, dt.desc, dt.min, dt.max) end
    end

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
            PopulateSBXToolMenu(pnl)
        end)
    end)

end