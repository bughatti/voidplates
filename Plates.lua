----------------------------------------------------------------------
-- VoidPlates — the plates.
--
-- One VoidPlates frame per visible nameplate, parented to Blizzard's plate
-- (so clicking/targeting and stacking stay Blizzard's), with Blizzard's own
-- art hidden underneath.
--
-- SECRET VALUES: enemy cast info, health max, aura details, raid marks and
-- (in instances) threat are secret. They go straight into display calls:
--   StatusBar:SetMinMaxValues/SetValue, FontString:SetText, Texture:SetTexture,
--   *FromBoolean, SetTimerDuration, Cooldown:SetCooldownFromDurationObject.
-- They are NEVER compared, branched on, used as table keys, or used in math.
----------------------------------------------------------------------
local _, VP = ...
local C = VP.COLOR

local plates = {}      -- unit token -> our frame
local pool = {}        -- released frames
local hooked = {}      -- Blizzard UnitFrame -> true once we've hooked its Show
local suppressed = {}  -- Blizzard UnitFrame -> true while we own that plate

local MAX_AURAS = 8

local function sec(v) return issecretvalue and issecretvalue(v) end
-- A boolean we may branch on: false when the game hid it.
local function yes(v) return not sec(v) and v and true or false end

----------------------------------------------------------------------
-- Frame construction
----------------------------------------------------------------------
local function Border(parent, r, g, b, a, size)
    local t = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                         { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetColorTexture(r, g, b, a)
        e:SetPoint(p[1], parent, p[1], 0, 0)
        e:SetPoint(p[2], parent, p[2], 0, 0)
        if i <= 2 then e:SetHeight(size) else e:SetWidth(size) end
        t[i] = e
    end
    function t:SetShown(show) for _, e in ipairs(self) do e:SetShown(show) end end
    function t:SetColor(color) for _, e in ipairs(self) do e:SetColorTexture(color:GetRGBA()) end end
    return t
end

local function CreateAuraIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetDrawEdge(false)
    b.cd:SetReverse(true)
    b.cd:SetHideCountdownNumbers(false)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(VP.FONT, 10, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 2, -1)
    b:Hide()
    return b
end

local function CreatePlate()
    local f = CreateFrame("Frame", nil, UIParent)
    f:EnableMouse(false)

    local hp = CreateFrame("StatusBar", nil, f)
    hp:SetPoint("CENTER")
    hp:SetStatusBarTexture(VP.BAR)
    hp.bg = hp:CreateTexture(nil, "BACKGROUND")
    hp.bg:SetAllPoints()
    hp.bg:SetColorTexture(0.06, 0.06, 0.08, 0.9)
    hp.edge = Border(hp, 0, 0, 0, 1, 1)
    f.hp, f.hpTex = hp, hp:GetStatusBarTexture()

    f.sel = Border(hp, 1, 1, 1, 1, 2)   -- target / focus highlight
    f.sel:SetShown(false)

    f.name = hp:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("BOTTOM", hp, "TOP", 0, 2)
    f.name:SetWordWrap(false)

    -- Health percent, right side of the bar. The number is secret in
    -- instances; it only ever reaches SetText (via RoundToNearestString).
    -- The "%" sign is its own string so we never concatenate a secret.
    -- A font must be set before SetText, or the whole plate build errors out.
    f.pctSign = hp:CreateFontString(nil, "OVERLAY")
    f.pctSign:SetFont(VP.FONT, 10, "OUTLINE")
    f.pctSign:SetPoint("RIGHT", hp, "RIGHT", -3, 0)
    f.pctSign:SetText("%")
    f.pct = hp:CreateFontString(nil, "OVERLAY")
    f.pct:SetFont(VP.FONT, 10, "OUTLINE")
    f.pct:SetPoint("RIGHT", f.pctSign, "LEFT", 0, 0)
    -- Health as a short number (1.2M), left side. Secret in instances: it only
    -- reaches SetText via AbbreviateNumbers, which takes secrets.
    f.hpNum = hp:CreateFontString(nil, "OVERLAY")
    f.hpNum:SetFont(VP.FONT, 10, "OUTLINE")
    f.hpNum:SetPoint("LEFT", hp, "LEFT", 3, 0)

    -- Elite / rare icon and level, top-left above the bar (the name stays centered).
    -- placed beside the name in UpdateClassification
    f.class = hp:CreateTexture(nil, "OVERLAY")
    f.class:SetSize(14, 14)
    f.class:Hide()
    f.level = hp:CreateFontString(nil, "OVERLAY")
    f.level:SetFont(VP.FONT, 10, "OUTLINE")

    f.mark = hp:CreateTexture(nil, "OVERLAY")
    f.mark:SetSize(18, 18)
    f.mark:SetPoint("BOTTOMRIGHT", hp, "TOPRIGHT", 0, 2)   -- top-right: arrows/cast icon own the sides
    f.mark:Hide()

    -- Target arrows pointing in at the bar from both sides.
    f.arrowL = hp:CreateTexture(nil, "OVERLAY")
    f.arrowL:SetAtlas("NPE_ArrowRight")
    f.arrowR = hp:CreateTexture(nil, "OVERLAY")
    f.arrowR:SetAtlas("NPE_ArrowLeft")
    f.arrowL:Hide(); f.arrowR:Hide()

    -- Cast bar under the health bar.
    local cb = CreateFrame("StatusBar", nil, f)
    cb:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -2)
    cb:SetStatusBarTexture(VP.BAR)
    cb.bg = cb:CreateTexture(nil, "BACKGROUND")
    cb.bg:SetAllPoints()
    cb.bg:SetColorTexture(0, 0, 0, 0.9)
    cb.edge = Border(cb, 0, 0, 0, 1, 1)
    cb.important = Border(cb, C.important.r, C.important.g, C.important.b, 1, 2)
    cb.icon = cb:CreateTexture(nil, "ARTWORK")
    -- Big spell icon to the left, spanning the health and cast bars.
    cb.icon:SetPoint("TOPRIGHT", hp, "TOPLEFT", -2, 0)
    cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Who the cast is aimed at, right side; the spell name takes the rest.
    cb.target = cb:CreateFontString(nil, "OVERLAY")
    cb.target:SetPoint("RIGHT", -3, 0)
    cb.target:SetJustifyH("RIGHT")
    cb.target:SetWordWrap(false)
    cb.text = cb:CreateFontString(nil, "OVERLAY")
    cb.text:SetPoint("LEFT", 3, 0)
    cb.text:SetPoint("RIGHT", cb.target, "LEFT", -4, 0)
    cb.text:SetJustifyH("LEFT")
    cb.text:SetWordWrap(false)
    -- A frame round the cast bar while the spell is aimed at you. Its alpha comes
    -- from the (secret) PlayerIsSpellTarget flag via SetAlphaFromBoolean.
    local you = CreateFrame("Frame", nil, cb)
    you:SetPoint("TOPLEFT", -3, 3)
    you:SetPoint("BOTTOMRIGHT", 3, -3)
    you.edge = Border(you, C.castAtYou.r, C.castAtYou.g, C.castAtYou.b, 1, 2)
    you:Hide()
    cb.you = you
    cb:Hide()
    f.cast, f.castTex = cb, cb:GetStatusBarTexture()

    -- Kick flash: a thick pulsing frame around health + cast bar while the mob
    -- casts something kickable. The holder's alpha comes from the (secret)
    -- notInterruptible flag via SetAlphaFromBoolean, so uninterruptible casts
    -- stay quiet; the inner frame does the pulsing.
    local holder = CreateFrame("Frame", nil, f)
    -- Top edge goes ABOVE the name, so the frame doesn't cut through it
    -- (seen 2026-10-25: the 3px edge ran through the mob's name). ApplyLayout
    -- sets the gap from the name size.
    holder:SetPoint("TOPLEFT", hp, "TOPLEFT", -5, 22)
    holder:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 5, -5)
    f.flashHolder = holder
    local pulse = CreateFrame("Frame", nil, holder)
    pulse:SetAllPoints()
    pulse.edge = Border(pulse, C.flash.r, C.flash.g, C.flash.b, 1, 3)
    local glow = pulse:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetColorTexture(C.flash.r, C.flash.g, C.flash.b, 0.18)
    local ag = pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.15); a:SetDuration(0.3)
    holder:Hide()
    f.flash, f.flashAnim, f.flashEdge, f.flashGlow = holder, ag, pulse.edge, glow

    f.auras = {}
    for i = 1, MAX_AURAS do f.auras[i] = CreateAuraIcon(f) end
    return f
end

-- Left target arrow: right next to the bar, mirroring the right one; it steps out
-- past the cast icon only while a cast shows (the player, 2026-10-25).
local function PlaceLeftArrow(f)
    local gap = 3
    if f.cast:IsShown() then gap = gap + (f.castIconW or 0) + 2 end
    if f.arrowGap == gap then return end
    f.arrowGap = gap
    f.arrowL:ClearAllPoints()
    f.arrowL:SetPoint("RIGHT", f.hp, "LEFT", -gap, 0)
end

local function ApplyLayout(f)
    f.PlaceLeftArrow = PlaceLeftArrow
    f.arrowGap = nil   -- sizes may have changed: re-place
    local w, h, ch = VP:Get("width"), VP:Get("height"), VP:Get("castHeight")
    if f.minor then   -- minions / minor mobs: a smaller plate (the cast bar stays readable)
        w, h = math.floor(w * 0.6), math.max(6, math.floor(h * 0.6))
    end
    local as = VP:Get("auraSize")
    f:SetSize(w, h + ch + 40)
    f.hp:SetSize(w, h)
    f.name:SetFont(VP.FONT, VP:Get("nameSize"), "OUTLINE")
    local ps = math.max(8, math.min(VP:Get("nameSize"), h - 4))
    f.pct:SetFont(VP.FONT, ps, "OUTLINE")
    f.pctSign:SetFont(VP.FONT, ps, "OUTLINE")
    f.hpNum:SetFont(VP.FONT, ps, "OUTLINE")
    -- minor plates carry no health text, like Blizzard's simplified plates
    local showPct = VP:Get("showHealthPercent") and not f.minor
    f.pct:SetShown(showPct); f.pctSign:SetShown(showPct)
    f.hpNum:SetShown(VP:Get("showHealthNumber") and not f.minor)
    local ls = math.max(8, VP:Get("nameSize") - 2)
    f.level:SetFont(VP.FONT, ls, "OUTLINE")
    f.class:SetSize(ls + 4, ls + 4)
    f.name:SetWidth(w + 20)
    f.cast:SetSize(w, ch)
    f.cast.icon:SetSize(h + ch + 2, h + ch + 2)
    local cfs = math.max(9, math.min(15, ch - 4))
    f.cast.text:SetFont(VP.FONT, cfs, "OUTLINE")
    f.cast.target:SetFont(VP.FONT, cfs, "OUTLINE")
    f.cast.target:SetWidth(math.floor(w * 0.42))
    -- kick flash: clear the name row (name text height + its 2px gap + 3px air)
    f.flashHolder:ClearAllPoints()
    f.flashHolder:SetPoint("TOPLEFT", f.hp, "TOPLEFT", -5, VP:Get("nameSize") + 7)
    f.flashHolder:SetPoint("BOTTOMRIGHT", f.cast, "BOTTOMRIGHT", 5, -5)
    local a = h + 10
    f.arrowL:SetSize(a, a)
    f.arrowR:SetSize(a, a)
    f.arrowR:ClearAllPoints()
    f.arrowR:SetPoint("LEFT", f.hp, "RIGHT", 3, 0)
    f.castIconW = h + ch + 2   -- PlaceLeftArrow steps out by this while a cast shows
    f.PlaceLeftArrow(f)
    for i, a in ipairs(f.auras) do
        a:SetSize(as, as)
        a:ClearAllPoints()
        if i == 1 then
            a:SetPoint("BOTTOMLEFT", f.hp, "TOPLEFT", 0, VP:Get("nameSize") + 5)
        else
            a:SetPoint("LEFT", f.auras[i - 1], "RIGHT", 2, 0)
        end
        if a.cd.SetCountdownFont then a.cd:SetCountdownFont("GameFontHighlightSmallOutline") end
    end
end

----------------------------------------------------------------------
-- Updates
----------------------------------------------------------------------
local function IsTarget(f)
    return f.plate ~= nil and f.plate == C_NamePlate.GetNamePlateForUnit("target")
end

local function UpdateName(f)
    f.name:SetText(UnitName(f.unit))
    -- box hugs the text (capped at the plate width), so the level / elite icon
    -- anchored to its left edge sit right next to the name. A secret name
    -- (instances) can't be measured: keep the full-width box then.
    local okW, tw = pcall(f.name.GetUnboundedStringWidth, f.name)
    if okW and tw and not sec(tw) then
        -- generous slack: Blizzard scales non-target plates down, and text drawn at
        -- that scale came out a few px wider than measured, so a tight box cut the
        -- name off ("Stasis Channe...", recorded 2026-10-25)
        f.name:SetWidth(math.min(tw * 1.1 + 8, f.hp:GetWidth() + 20))
    end
    -- minor plates: name only while it's your target (Blizzard does the same)
    f.name:SetShown(not f.minor or IsTarget(f))
end

-- Elite / rare icon (Blizzard's own atlases) and level, colored by difficulty.
local CLASS_ATLAS = {
    elite = "nameplates-icon-elite-gold", worldboss = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-elite-silver", rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}
local function UpdateClassification(f)
    local unit = f.unit
    local atlas
    if VP:Get("showClassification") and not f.minor and not yes(UnitIsPlayer(unit)) then
        local cls = UnitClassification(unit)
        if not sec(cls) then atlas = CLASS_ATLAS[cls] end
    end
    if atlas then f.class:SetAtlas(atlas); f.class:Show() else f.class:Hide() end

    local text = ""
    if VP:Get("showLevel") and not f.minor then
        local lvl = UnitLevel(unit)
        if not sec(lvl) and lvl then
            if lvl < 0 then
                text = "??"
                f.level:SetTextColor(1, 0.1, 0.1)
            else
                text = tostring(lvl)
                local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl)
                if c then f.level:SetTextColor(c.r, c.g, c.b) else f.level:SetTextColor(1, 1, 1) end
            end
        end
    end
    f.level:SetText(text)
    -- Level sits just left of the NAME (which is centered), and the elite icon left of
    -- the level -- a long name pushes them out instead of running into them (seen
    -- 2026-10-25: "86Manaforge Netherdrifter").
    f.level:ClearAllPoints()
    f.level:SetPoint("RIGHT", f.name, "LEFT", -3, 0)
    f.class:ClearAllPoints()
    if text ~= "" then
        f.class:SetPoint("RIGHT", f.level, "LEFT", -1, 0)
    else
        f.class:SetPoint("RIGHT", f.name, "LEFT", -2, 0)
    end
end

local function UpdateHealth(f)
    f.hp:SetMinMaxValues(0, UnitHealthMax(f.unit))
    f.hp:SetValue(UnitHealth(f.unit))
    if VP:Get("showHealthNumber") and not f.minor and AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, UnitHealth(f.unit))
        f.hpNum:SetText(ok and s or "")
    end
    if VP:Get("showHealthPercent") and UnitHealthPercent and C_StringUtil and C_StringUtil.RoundToNearestString then
        local curve = CurveConstants and CurveConstants.ScaleTo100
        local okP, p = pcall(UnitHealthPercent, f.unit, true, curve)
        local okS, s = false, nil
        if okP then okS, s = pcall(C_StringUtil.RoundToNearestString, p) end
        if okS then f.pct:SetText(s) else f.pct:SetText("") end
        f.pctSign:SetShown(okS and not f.minor)
    end
end

local function IsTankRole()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local spec = getSpec and getSpec()
    return spec and GetSpecializationRole(spec) == "TANK"
end

-- Base color: reaction / class / mob type. Plain (non-secret) reads only;
-- anything that turns out secret just falls back to the reaction color.
local function BaseColor(unit)
    if yes(UnitIsTapDenied(unit)) then return C.tapped end
    local isPlayer = yes(UnitIsPlayer(unit))
    if isPlayer then
        local _, class = UnitClass(unit)
        if not sec(class) and class and yes(UnitCanAttack("player", unit)) then
            local cc = RAID_CLASS_COLORS[class]
            if cc then return cc end
        end
    end
    local reaction = UnitReaction(unit, "player")
    if sec(reaction) or not reaction then return C.hostile end
    if reaction >= 5 then return C.friendly end
    if reaction == 4 then return C.neutral end

    if VP:Get("unitTypeColors") and not isPlayer then
        local cls, lvl, me = UnitClassification(unit), UnitLevel(unit), UnitLevel("player")
        if not sec(cls) and not sec(lvl) then
            if cls == "worldboss" or lvl == -1 or lvl >= me + 2 then return C.boss end
            local lt = UnitIsLieutenant and yes(UnitIsLieutenant(unit))
            if lvl == me + 1 or lt then return C.miniboss end
        end
        local pt = UnitPowerType(unit)
        if not sec(pt) and pt == Enum.PowerType.Mana then return C.caster end
    end
    return C.hostile
end

local function UpdateColor(f)
    local unit = f.unit
    local base = BaseColor(unit)
    f.hpTex:SetVertexColor(base.r, base.g, base.b)

    if not VP:Get("threatColors") or not yes(UnitCanAttack("player", unit)) then return end
    local isTanking = UnitDetailedThreatSituation("player", unit)
    if not sec(isTanking) and isTanking == nil then return end   -- not on its threat table
    if IsTankRole() then
        -- Tank: fine while you hold it, orange when someone else has it.
        f.hpTex:SetVertexColorFromBoolean(isTanking, base, C.threatBad)
    elseif IsInGroup() then
        -- Everyone else: orange when YOU have it.
        f.hpTex:SetVertexColorFromBoolean(isTanking, C.threatBad, base)
    end
end

local function UpdateSelection(f)
    local plate = f.plate
    local isTarget = IsTarget(f)
    if f.minor then f.name:SetShown(isTarget) end
    local isFocus = plate and plate == C_NamePlate.GetNamePlateForUnit("focus")
    if not VP:Get("targetOutline") then
        f.sel:SetShown(false)
    elseif isTarget then
        f.sel:SetColor(C.target); f.sel:SetShown(true)
    elseif isFocus then
        f.sel:SetColor(C.focus); f.sel:SetShown(true)
    else
        f.sel:SetShown(false)
    end
    local arrows = isTarget and VP:Get("targetArrows") and true or false
    f.arrowL:SetShown(arrows); f.arrowR:SetShown(arrows)
    local fade = UnitExists("target") and not isTarget
    f:SetAlpha(fade and VP:Get("nonTargetAlpha") or 1)
end

local function UpdateRaidMark(f)
    local idx = GetRaidTargetIndex(f.unit)
    if not sec(idx) and idx == nil then f.mark:Hide(); return end
    -- The index can be secret: it goes straight to SetSpriteSheetCell on the marker
    -- sheet (takes secrets, the way Blizzard's own plates do it). Building a texture
    -- path from it ("..._" .. idx) would concatenate a secret -- release review 2026-10-26.
    f.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local ok = pcall(f.mark.SetSpriteSheetCell, f.mark, idx, 4, 4)
    f.mark:SetShown(ok)
end

-- Flash colour over the cast: yellow for the first half, red from halfway (the
-- player, 2026-10-25). A cast's progress is secret, so the engine picks the colour:
-- Duration:EvaluateElapsedPercent on a Step colour curve, and the result only ever
-- goes into a colour setter. Whether "percent" runs 0-1 or 0-100 isn't documented,
-- so it's measured once on a duration we make ourselves (not secret).
local flashCurve   -- nil = not built yet, false = unavailable
local function FlashCurve()
    if flashCurve == nil then
        flashCurve = false
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and C_DurationUtil and C_DurationUtil.CreateDuration then
            local ok, scale = pcall(function()
                local d = C_DurationUtil.CreateDuration()
                d:SetTimeFromStart(GetTime() - 5, 10)        -- exactly half elapsed
                return d:GetElapsedPercent() > 1.5 and 100 or 1
            end)
            if ok then
                local c = C_CurveUtil.CreateColorCurve()
                c:SetType(Enum.LuaCurveType.Step)
                c:AddPoint(0, C.flash)
                c:AddPoint(0.5 * scale, C.flashLate)
                flashCurve = c
            end
        end
    end
    return flashCurve or nil
end

local function ColorFlash(f)
    local curve, dur = FlashCurve(), f.castDur
    local col
    if curve and dur then
        local ok, res = pcall(dur.EvaluateElapsedPercent, dur, curve)
        if ok then col = res end
    end
    col = col or C.flash
    pcall(f.flashEdge.SetColor, f.flashEdge, col)
    pcall(function()
        local r, g, b = col:GetRGB()
        f.flashGlow:SetColorTexture(r, g, b, 0.18)
    end)
end

-- Casting plates jump above the rest of the stack and (if kickable) flash.
local function StopFlash(f)
    f.flashAnim:Stop()
    f.flash:Hide()
    f.castDur = nil
    if f.plate then f:SetFrameStrata(f.plate:GetFrameStrata()) end
end

local function StartFlash(f, notInt)
    f:SetFrameStrata("HIGH")
    if not VP:Get("castFlash") then f.flash:Hide(); return end
    if notInt == nil then
        f.flash:SetAlpha(1)
    else
        f.flash:SetAlphaFromBoolean(notInt, 0, 1)   -- engine resolves the secret
    end
    ColorFlash(f)
    if not f.flash.vpTick then   -- re-colour while it shows (OnUpdate only runs when shown)
        f.flash.vpTick = 0
        f.flash:SetScript("OnUpdate", function(self, elapsed)
            self.vpTick = self.vpTick + elapsed
            if self.vpTick < 0.1 then return end
            self.vpTick = 0
            ColorFlash(f)
        end)
    end
    f.flash:Show()
    if not f.flashAnim:IsPlaying() then f.flashAnim:Play() end
end

-- Cast bar: same proven pattern as VoidRaidTools' kick bar.
local function UpdateCast(f)
    local unit, cb = f.unit, f.cast
    local name, _, tex, _, _, _, _, notInt, spellID = UnitCastingInfo(unit)
    local dur, channel = nil, false
    if name ~= nil then
        dur = UnitCastingDuration and UnitCastingDuration(unit)
    else
        local _, cTex, cNotInt, cSpell
        name, _, cTex, _, _, _, cNotInt, cSpell = UnitChannelInfo(unit)
        if name == nil then cb:Hide(); StopFlash(f); PlaceLeftArrow(f); return end
        tex, notInt, spellID, channel = cTex, cNotInt, cSpell, true
        dur = UnitChannelDuration and UnitChannelDuration(unit)
    end

    cb.text:SetText(name)
    cb.icon:SetTexture(tex)
    if notInt == nil then
        f.castTex:SetVertexColor(C.kick:GetRGB())
    else
        f.castTex:SetVertexColorFromBoolean(notInt, C.noKick, C.kick)
    end

    local showImp = false
    if VP:Get("importantGlow") and spellID ~= nil and C_Spell.IsSpellImportant then
        local ok, imp = pcall(C_Spell.IsSpellImportant, spellID)
        if ok and imp ~= nil then
            for _, e in ipairs(cb.important) do e:SetAlphaFromBoolean(imp, 1, 0) end
            showImp = true
        end
    end
    cb.important:SetShown(showImp)

    -- Who it's aimed at: Blizzard's "should display" flag is plain; the name and
    -- class are secret and only reach SetText / SetTextColor.
    local showTarget = false
    if VP:Get("castTargetName") and UnitShouldDisplaySpellTargetName then
        local okS, should = pcall(UnitShouldDisplaySpellTargetName, unit)
        if okS and yes(should) then
            local okN = pcall(cb.target.SetText, cb.target, UnitSpellTargetName(unit))
            showTarget = okN
            local okC, col = pcall(C_ClassColor.GetClassColor, UnitSpellTargetClass(unit))
            if not (okC and col and pcall(function() cb.target:SetTextColor(col:GetRGB()) end)) then
                cb.target:SetTextColor(1, 1, 1)
            end
        end
    end
    if not showTarget then cb.target:SetText("") end
    -- the spell name takes the full width when there's no target to show
    cb.text:ClearAllPoints()
    cb.text:SetPoint("LEFT", 3, 0)
    if showTarget then
        cb.text:SetPoint("RIGHT", cb.target, "LEFT", -4, 0)
    else
        cb.text:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
    end

    -- Aimed at you: secret yes/no -> the frame's alpha (engine resolves it).
    local you = false
    if VP:Get("castAtYou") and PlayerIsSpellTarget then
        local okY, me = pcall(PlayerIsSpellTarget, unit)
        if okY and me ~= nil then
            you = pcall(cb.you.SetAlphaFromBoolean, cb.you, me, 1, 0)
        end
    end
    cb.you:SetShown(you)

    local ok = false
    if dur and cb.SetTimerDuration then
        ok = pcall(cb.SetTimerDuration, cb, dur, Enum.StatusBarInterpolation.Immediate,
            channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    end
    if not ok then cb:SetMinMaxValues(0, 1); cb:SetValue(1) end
    cb:Show()
    PlaceLeftArrow(f)
    f.castDur = dur
    StartFlash(f, notInt)
end

-- Auras: Blizzard's own filters pick them server-side, so we never have to
-- read (secret) aura fields to decide what to show.
-- Order = priority when the row is full: CC, purgeable, your debuffs, then any other
-- enemy buff Blizzard shows on plates (same filter as Blizzard's own plates).
-- Minor plates show CC only.
local AURA_GROUPS = {
    -- INCLUDE_NAME_PLATE_ONLY everywhere: without it, auras flagged nameplate-only are
    -- filtered OUT. Enemy buffs use IMPORTANT (what Blizzard's plates show on enemies),
    -- so ordinary buffs don't take the slots. (Release review 2026-10-26.)
    { key = "showCC",         filter = "HARMFUL|CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY",         max = 2, border = { 1, 0.55, 0.1 }, minor = true },
    { key = "showPurgeable",  filter = "HELPFUL|RAID_PLAYER_DISPELLABLE|INCLUDE_NAME_PLATE_ONLY", max = 2, border = { 0.25, 0.6, 1 } },
    { key = "showMyDebuffs",  filter = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",               max = 6, border = { 0, 0, 0 } },
    { key = "showEnemyBuffs", filter = "HELPFUL|IMPORTANT|INCLUDE_NAME_PLATE_ONLY",            max = 3,
      border = { C.enemyBuff.r, C.enemyBuff.g, C.enemyBuff.b } },
}

local function UpdateAuras(f)
    local unit, n = f.unit, 0
    if yes(UnitCanAttack("player", unit)) then
        local seen = {}
        for _, g in ipairs(AURA_GROUPS) do
            if VP:Get(g.key) and n < MAX_AURAS and (g.minor or not f.minor) then
                -- ask for extra: some may already be shown by an earlier group;
                -- g.max counts only the NEW ones this group adds
                local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, g.filter, g.max + MAX_AURAS)
                local added = 0
                if ok and list then
                    for _, aura in ipairs(list) do
                        if n >= MAX_AURAS or added >= g.max then break end
                        local id = aura.auraInstanceID
                        local plainID = not sec(id) and id ~= nil
                        if not (plainID and seen[id]) then
                            if plainID then seen[id] = true end
                            n = n + 1
                            added = added + 1
                            local b = f.auras[n]
                            b.icon:SetTexture(aura.icon)
                            b.bg:SetColorTexture(g.border[1], g.border[2], g.border[3], 1)
                            if plainID then
                                local okD, d = pcall(C_UnitAuras.GetAuraDuration, unit, id)
                                if okD and d then b.cd:SetCooldownFromDurationObject(d, true) else b.cd:Clear() end
                                local okC, c = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2)
                                if okC then b.count:SetText(c) else b.count:SetText("") end
                            else
                                b.cd:Clear(); b.count:SetText("")
                            end
                            b:Show()
                        end
                    end
                end
            end
        end
    end
    for i = n + 1, MAX_AURAS do f.auras[i]:Hide() end
end

local function FullUpdate(f)
    UpdateName(f); UpdateHealth(f); UpdateColor(f); UpdateSelection(f)
    UpdateRaidMark(f); UpdateCast(f); UpdateAuras(f); UpdateClassification(f)
end

-- Pets, totems, guardians (UnitIsMinion) and minor mobs (classification "minus"),
-- the same two groups Blizzard draws smaller.
local function IsMinor(unit)
    if not VP:Get("smallMinions") then return false end
    if UnitIsMinion and yes(UnitIsMinion(unit)) then return true end
    local cls = UnitClassification(unit)
    return not sec(cls) and cls == "minus"
end

----------------------------------------------------------------------
-- Attach / detach
----------------------------------------------------------------------
local function SuppressBlizzard(uf)
    if not uf then return end
    if not hooked[uf] then
        hooksecurefunc(uf, "Show", function(self) if suppressed[self] then self:Hide() end end)
        hooked[uf] = true
    end
    suppressed[uf] = true
    uf:Hide()
end

local function ReleaseBlizzard(uf)
    -- Hand it back: Blizzard pools these, and the next plate it lands on may be one
    -- we don't restyle (personal bar, widget-only plates). Shown again only while it
    -- still belongs to a unit; a pooled frame is Blizzard's to show.
    if uf and suppressed[uf] then
        suppressed[uf] = nil
        if uf.unit then uf:Show() end
    end
end

-- Track the exact Blizzard frame hidden for a plate: Blizzard may clear
-- plate.UnitFrame before our removal handler runs (release review 2026-10-26),
-- and a frame left marked as suppressed would hide whatever plate reuses it.
local function TakeBlizzard(f, uf)
    if f.blizzUF and f.blizzUF ~= uf then ReleaseBlizzard(f.blizzUF) end
    f.blizzUF = uf
    SuppressBlizzard(uf)
end

local function OnAdded(unit)
    if yes(UnitIsUnit(unit, "player")) then return end   -- personal resource bar stays Blizzard's
    if UnitNameplateShowsWidgetsOnly and yes(UnitNameplateShowsWidgetsOnly(unit)) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end                    -- forbidden (e.g. friendly in instances)

    local f = table.remove(pool) or CreatePlate()
    f.unit, f.plate = unit, plate
    f.minor = IsMinor(unit)
    f:SetParent(plate)
    f:ClearAllPoints()
    f:SetPoint("CENTER", plate, "CENTER", 0, 0)
    ApplyLayout(f)
    plates[unit] = f
    TakeBlizzard(f, plate.UnitFrame)
    FullUpdate(f)
    f:Show()
end

local function OnRemoved(unit)
    local f = plates[unit]
    if not f then return end
    plates[unit] = nil
    ReleaseBlizzard(f.blizzUF)
    f.blizzUF = nil
    f:Hide()
    f.cast:Hide()
    StopFlash(f)
    f:SetParent(UIParent)
    f.unit, f.plate = nil, nil
    pool[#pool + 1] = f
end

function VP:RefreshAll(relayout)
    for _, f in pairs(plates) do
        if relayout then
            f.minor = IsMinor(f.unit)   -- the "small minions" option may have changed
            ApplyLayout(f)
        end
        FullUpdate(f)
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local UNIT_HANDLERS = {
    UNIT_HEALTH                  = UpdateHealth,
    UNIT_MAXHEALTH               = UpdateHealth,
    UNIT_NAME_UPDATE             = UpdateName,
    UNIT_LEVEL                   = UpdateClassification,
    UNIT_CLASSIFICATION_CHANGED  = function(f)
        -- a mob can become (or stop being) a minor mob: re-size the plate
        local minor = IsMinor(f.unit)
        if minor ~= f.minor then
            f.minor = minor
            ApplyLayout(f)
            FullUpdate(f)
        else
            UpdateClassification(f)
        end
    end,
    -- a pull fires UNIT_AURA many times per plate per frame: rebuild once, next frame
    UNIT_AURA                    = function(f)
        if f.auraQueued then return end
        f.auraQueued = true
        C_Timer.After(0, function()
            f.auraQueued = nil
            if f.unit then UpdateAuras(f) end
        end)
    end,
    -- faction can flip (mind control): color AND which auras apply
    UNIT_FACTION                 = function(f) UpdateColor(f); UpdateAuras(f) end,
    UNIT_FLAGS                   = UpdateColor,
    UNIT_THREAT_LIST_UPDATE      = UpdateColor,
    UNIT_THREAT_SITUATION_UPDATE = UpdateColor,
    UNIT_SPELLCAST_START             = UpdateCast,
    UNIT_SPELLCAST_CHANNEL_START     = UpdateCast,
    UNIT_SPELLCAST_CHANNEL_UPDATE    = UpdateCast,
    UNIT_SPELLCAST_DELAYED           = UpdateCast,
    UNIT_SPELLCAST_INTERRUPTIBLE     = UpdateCast,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = UpdateCast,
    UNIT_SPELLCAST_STOP              = UpdateCast,
    UNIT_SPELLCAST_CHANNEL_STOP      = UpdateCast,
    UNIT_SPELLCAST_FAILED            = UpdateCast,
    UNIT_SPELLCAST_INTERRUPTED       = UpdateCast,
    UNIT_SPELLCAST_SUCCEEDED         = UpdateCast,
}

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        OnAdded(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnRemoved(unit)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        for _, f in pairs(plates) do UpdateSelection(f) end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, f in pairs(plates) do UpdateRaidMark(f) end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ROLES_ASSIGNED"
        or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        for _, f in pairs(plates) do UpdateColor(f) end
    else
        local f = unit and plates[unit]
        if f then UNIT_HANDLERS[event](f) end
    end
end)

function VP:Init()
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "RAID_TARGET_UPDATE",
        "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE",
        "PLAYER_REGEN_ENABLED" }) do
        ev:RegisterEvent(e)
    end
    for e in pairs(UNIT_HANDLERS) do ev:RegisterEvent(e) end
    -- Blizzard may hand a plate a fresh UnitFrame after our ADDED handler ran;
    -- re-hide whatever it attached.
    if NamePlateDriverFrame and NamePlateDriverFrame.OnNamePlateAdded then
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
            local f = unit and plates[unit]
            if f and f.plate then TakeBlizzard(f, f.plate.UnitFrame) end
        end)
    end
    -- Plates already on screen at load (e.g. after /reload).
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.GetUnit and plate:GetUnit()
        if unit then OnAdded(unit) end
    end
end
