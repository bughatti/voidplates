----------------------------------------------------------------------
-- VoidPlates — Core: saved settings, colors, options panel.
--
-- Built for 12.x secret values: anything the game hides (enemy cast info,
-- health max, aura details, threat in instances) is only ever handed to
-- display calls (SetValue, SetText, SetTexture, *FromBoolean, duration
-- objects) and never compared or branched on in Lua.
----------------------------------------------------------------------
local ADDON, VP = ...
_G.VoidPlates = VP

VP.DEFAULTS = {
    width          = 175,
    height         = 18,
    castHeight     = 18,
    auraSize       = 26,
    nameSize       = 12,
    showHealthPercent = true,
    showMyDebuffs  = true,
    showCC         = true,
    showPurgeable  = true,
    unitTypeColors = true,
    threatColors   = true,
    importantGlow  = true,
    castFlash      = true,   -- pulse the whole plate while it casts something kickable
    targetArrows   = true,   -- arrows either side of your target's plate
    targetOutline  = false,  -- white/blue edge on target/focus (fading the rest is usually enough)
    nonTargetAlpha = 0.65,
    -- 2026-10-25 release set (the things Blizzard's own 12.x plates already do)
    showHealthNumber = false, -- health as a number, left side of the bar
    showLevel        = true,  -- level text, top-left (?? for bosses)
    showClassification = true, -- elite / rare / rare-elite icon
    showEnemyBuffs   = true,  -- any enemy buff Blizzard shows on plates, after your debuffs
    castTargetName   = true,  -- who the cast is aimed at, right side of the cast bar
    castAtYou        = true,  -- white frame round the cast bar when it's aimed at you
    smallMinions     = true,  -- pets, totems, guardians and minor mobs get a small plate
}

VP.COLOR = {
    hostile   = CreateColor(0.80, 0.18, 0.18),
    neutral   = CreateColor(0.90, 0.75, 0.15),
    friendly  = CreateColor(0.20, 0.72, 0.28),
    tapped    = CreateColor(0.50, 0.50, 0.50),
    caster    = CreateColor(0.55, 0.35, 0.90),
    miniboss  = CreateColor(0.55, 0.60, 1.00),
    boss      = CreateColor(0.25, 0.45, 1.00),
    threatBad = CreateColor(1.00, 0.45, 0.05),   -- tank lost it / you pulled it
    kick      = CreateColor(0.15, 0.95, 0.35),   -- bright: you can kick it
    noKick    = CreateColor(0.72, 0.72, 0.78),   -- light grey: can't kick (still readable)
    important = CreateColor(1.00, 0.20, 0.60),
    flash     = CreateColor(1.00, 0.90, 0.20),   -- kickable-cast flash around the plate
    flashLate = CreateColor(1.00, 0.15, 0.10),   -- same flash once the cast is past halfway
    target    = CreateColor(1.00, 1.00, 1.00),
    focus     = CreateColor(0.35, 0.75, 1.00),
    castAtYou = CreateColor(1.00, 1.00, 1.00),   -- frame round a cast aimed at you
    enemyBuff = CreateColor(0.45, 0.45, 0.52),   -- border of a plain enemy buff
}

VP.TEX  = "Interface\\Buttons\\WHITE8X8"
VP.BAR  = "Interface\\TargetingFrame\\UI-StatusBar"
VP.FONT = STANDARD_TEXT_FONT

function VP:Get(key)
    local v = VoidPlatesDB and VoidPlatesDB[key]
    if v == nil then return self.DEFAULTS[key] end
    return v
end

function VP:Set(key, value)
    VoidPlatesDB[key] = value
    if self.RefreshAll then self:RefreshAll(true) end
end

----------------------------------------------------------------------
-- Profiles: named snapshots of every setting (account-wide). The live
-- settings stay the top-level keys of VoidPlatesDB; a profile is a copy.
----------------------------------------------------------------------
function VP:Profiles()
    VoidPlatesDB.profiles = VoidPlatesDB.profiles or {}
    return VoidPlatesDB.profiles
end

function VP:SaveProfile(name)
    local p = {}
    for key in pairs(self.DEFAULTS) do
        if VoidPlatesDB[key] ~= nil then p[key] = VoidPlatesDB[key] end
    end
    self:Profiles()[name] = p
    print(("|cff00c7ffVoidPlates|r: saved profile \"%s\"."):format(name))
end

function VP:LoadProfile(name)
    local p = self:Profiles()[name]
    if not p then return end
    for key in pairs(self.DEFAULTS) do VoidPlatesDB[key] = p[key] end
    if self.RefreshAll then self:RefreshAll(true) end
    print(("|cff00c7ffVoidPlates|r: loaded profile \"%s\". Reopen the options to see its values."):format(name))
end

function VP:DeleteProfile(name)
    self:Profiles()[name] = nil
end

function VP:ResetDefaults()
    for key in pairs(self.DEFAULTS) do VoidPlatesDB[key] = nil end
    if self.RefreshAll then self:RefreshAll(true) end
    print("|cff00c7ffVoidPlates|r: every setting is back to its default. Saved profiles are kept.")
end

StaticPopupDialogs.VOIDPLATES_SAVEAS = {
    text = "Save your VoidPlates settings as a profile named:",
    button1 = SAVE, button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self)
        local eb = self.GetEditBox and self:GetEditBox() or self.editBox
        local name = eb and strtrim(eb:GetText() or "")
        if name and name ~= "" then VP:SaveProfile(name) end
    end,
    EditBoxOnEnterPressed = function(eb)
        local name = strtrim(eb:GetText() or "")
        if name ~= "" then VP:SaveProfile(name) end
        eb:GetParent():Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs.VOIDPLATES_RESET = {
    text = "Put every VoidPlates setting back to its default?\n\nSaved profiles are kept.",
    button1 = YES, button2 = NO,
    OnAccept = function() VP:ResetDefaults() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

----------------------------------------------------------------------
-- Blizzard's own plate controls that decide the CLICKABLE area and stacking
-- (addons can't size the click box per plate). Out of combat only.
----------------------------------------------------------------------
local STACK_CVAR, SIZE_CVAR = "nameplateStackingTypes", "nameplateSize"

function VP:GetStacking()
    local idx = Enum.NamePlateStackType and Enum.NamePlateStackType.Enemy
    if not (idx and C_CVar and C_CVar.GetCVarBitfield) then return true end
    local ok, v = pcall(C_CVar.GetCVarBitfield, STACK_CVAR, idx)
    return ok and v and true or false
end

function VP:SetStacking(on)
    if InCombatLockdown() then print("|cff00c7ffVoidPlates|r: change this out of combat.") return end
    local idx = Enum.NamePlateStackType and Enum.NamePlateStackType.Enemy
    if idx and C_CVar and C_CVar.SetCVarBitfield then pcall(C_CVar.SetCVarBitfield, STACK_CVAR, idx, on and true or false) end
end

function VP:GetClickSize()
    return tonumber(C_CVar and C_CVar.GetCVar(SIZE_CVAR)) or 2
end

function VP:SetClickSize(v)
    if InCombatLockdown() then print("|cff00c7ffVoidPlates|r: change this out of combat.") return end
    if C_CVar then pcall(C_CVar.SetCVar, SIZE_CVAR, tostring(math.floor(v + 0.5))) end
end

----------------------------------------------------------------------
-- Options panel: Esc -> Options -> AddOns -> VoidPlates.
----------------------------------------------------------------------
local function BuildOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("VoidPlates")
    local function Button(name, text, onClick, tip)
        if CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tip, true))
        end
    end

    local function Check(key, label, tip)
        local s = Settings.RegisterProxySetting(category, "VOIDPLATES_" .. key:upper(),
            Settings.VarType.Boolean, label, VP.DEFAULTS[key],
            function() return VP:Get(key) end, function(v) VP:Set(key, v) end)
        Settings.CreateCheckbox(category, s, tip)
    end
    local function Slider(key, label, min, max, step, tip, fmt)
        local s = Settings.RegisterProxySetting(category, "VOIDPLATES_" .. key:upper(),
            Settings.VarType.Number, label, VP.DEFAULTS[key],
            function() return VP:Get(key) end, function(v) VP:Set(key, v) end)
        local o = Settings.CreateSliderOptions(min, max, step)
        o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
        Settings.CreateSlider(category, s, o, tip)
    end

    Slider("width", "Plate width", 80, 220, 2, "Width of the health bar.")
    Slider("height", "Health bar height", 6, 24, 1, "Height of the health bar.")
    Slider("castHeight", "Cast bar height", 8, 28, 1, "Height of the cast bar under the plate.")
    Slider("nameSize", "Name text size", 7, 16, 1, "Font size of the unit name.")
    Slider("auraSize", "Aura icon size", 12, 32, 1, "Size of debuff, CC and purge icons.")
    Slider("nonTargetAlpha", "Non-target opacity", 0.2, 1, 0.05,
        "How faded plates are when they aren't your target (only while you have a target).",
        function(v) return string.format("%d%%", v * 100) end)
    Check("showHealthPercent", "Show health percent", "The mob's health as a percent on the right of the bar.")
    Check("showMyDebuffs", "Show your debuffs", "Your DoTs and debuffs on the enemy, with timers and stacks.")
    Check("showCC", "Show crowd control", "Stuns, fears, roots and other CC on the enemy.")
    Check("showPurgeable", "Show purgeable buffs and enrages", "Enemy buffs someone in your group can remove.")
    Check("unitTypeColors", "Color by mob type", "Casters purple, mini-bosses periwinkle, bosses blue (works before the pull).")
    Check("threatColors", "Color by threat", "Orange when a tank loses a mob, or when a non-tank pulls one.")
    Check("targetArrows", "Arrows on your target", "Arrows pointing in at your target's plate from both sides.")
    Check("targetOutline", "Outline target and focus", "White edge on your target's plate, blue on your focus. Off: your target stands out because the other plates fade.")
    Check("castFlash", "Flash kickable casts", "The whole plate pulses yellow and jumps to the front while the mob casts something you can interrupt.")
    Check("importantGlow", "Highlight important casts", "Pink edge on casts Blizzard marks as important (usually lethal if not kicked).")
    Check("castTargetName", "Show who a cast is aimed at", "The target's name, in its class color, on the right of the cast bar.")
    Check("castAtYou", "Highlight casts aimed at you", "A white frame round the cast bar while the spell is aimed at you.")
    Check("showHealthNumber", "Show health number", "The mob's health as a short number (1.2M) on the left of the bar.")
    Check("showLevel", "Show level", "The mob's level, top-left of the plate (?? for bosses), colored by difficulty.")
    Check("showClassification", "Show elite and rare icon", "Gold dragon for elites and bosses, silver for rare elites, a star for rares.")
    Check("showEnemyBuffs", "Show enemy buffs", "Any buff Blizzard shows on nameplates (shields, enrages, empowers), after your debuffs.")
    Check("smallMinions", "Small plates for minions and minor mobs", "Pets, totems, guardians and minor mobs get a smaller plate with only their name on target and CC shown. Casts still show.")

    -- Blizzard's own plate settings that set the clickable area and stacking
    do
        local s = Settings.RegisterProxySetting(category, "VOIDPLATES_STACKING", Settings.VarType.Boolean,
            "Stack enemy plates", true,
            function() return VP:GetStacking() end, function(v) VP:SetStacking(v) end)
        Settings.CreateCheckbox(category, s, "Plates move apart so they don't overlap (Blizzard's setting; change it out of combat).")
        local names = { "Small", "Medium", "Large", "Extra large", "Huge" }
        local z = Settings.RegisterProxySetting(category, "VOIDPLATES_CLICKSIZE", Settings.VarType.Number,
            "Clickable area", 2,
            function() return VP:GetClickSize() end, function(v) VP:SetClickSize(v) end)
        local o = Settings.CreateSliderOptions(1, 5, 1)
        o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return names[math.floor(v + 0.5)] or "" end)
        Settings.CreateSlider(category, z, o, "How big the area you click to target a mob is (Blizzard's nameplate size). Out of combat only.")
    end

    -- Profiles
    do
        local selected
        local s = Settings.RegisterProxySetting(category, "VOIDPLATES_PROFILE", Settings.VarType.String,
            "Profile", "",
            function() return selected or "" end, function(v) selected = v end)
        local function Options()
            local c = Settings.CreateControlTextContainer()
            local list = {}
            for n in pairs(VP:Profiles()) do list[#list + 1] = n end
            table.sort(list)
            if #list == 0 then c:Add("", "(no saved profiles yet)") end
            for _, n in ipairs(list) do c:Add(n, n) end
            return c:GetData()
        end
        Settings.CreateDropdown(category, s, Options, "Saved VoidPlates setups (all characters).")
        Button("Load this profile", "Load", function()
            if selected and selected ~= "" then VP:LoadProfile(selected) end
        end)
        Button("Save current settings as a profile", "Save as...", function() StaticPopup_Show("VOIDPLATES_SAVEAS") end)
        Button("Delete this profile", "Delete", function()
            if selected and selected ~= "" then VP:DeleteProfile(selected); selected = nil end
        end)
        Button("Reset everything to defaults", "Reset", function() StaticPopup_Show("VOIDPLATES_RESET") end,
            "Every VoidPlates setting back to its default. Saved profiles are kept.")
    end

    Settings.RegisterAddOnCategory(category)
    VP.optionsCategory = category

    -- VoidHub entry (no minimap button of its own)
    VoidHubLaunchers = VoidHubLaunchers or {}
    VoidHubLaunchers.VoidPlates = {
        icon = "Interface\\Icons\\Spell_Shadow_Shadowform",
        onClick = function() VP:OpenOptions() end,
    }
end

function VP:OpenOptions()
    if self.optionsCategory then Settings.OpenToCategory(self.optionsCategory:GetID()) end
end

SLASH_VOIDPLATES1 = "/vplates"
SlashCmdList.VOIDPLATES = function() VP:OpenOptions() end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    VoidPlatesDB = VoidPlatesDB or {}
    BuildOptions()
    if VP.Init then VP:Init() end
end)
