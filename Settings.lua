-- Broker_MidnightEvents - Settings
-- WoW Settings panel registration and saved-variables defaults.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

-- Default visibility flags. enabledSections mirrors the tooltip's top-level
-- section list one-for-one. showWorldBosses gates the World Boss row inside
-- the "weekly" section (kept as a separate flag so disabling it doesn't hide
-- the whole section).
local defaults = {
    enabledSections = {
        now       = true,
        upcoming  = true,
        delves    = true,
        weekly    = true,
        voidforge = true,
        alts      = true,
    },
    showWorldBosses = true,
    broker = {
        showProgress = true,   -- "Weeklies N/M" / "All done" left-side chunk
        showEvent    = true,   -- "Stormarion 12m next" / "Abundance now!" tag
    },
}

-- Returns the epoch (seconds) of the most recent weekly reset, or nil if the
-- API isn't available yet (early addon-load, or rare timing windows).
local function CurrentWeeklyResetEpoch()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local s = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if s and s > 0 then
            return time() + s - 7 * 86400
        end
    end
    return nil
end

local function RefreshUI()
    if ns.UpdateBrokerText     then ns.UpdateBrokerText()     end
    if ns.RebuildTooltipIfOpen then ns.RebuildTooltipIfOpen() end
end

local sf = CreateFrame("Frame")
sf:RegisterEvent("ADDON_LOADED")
sf:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    Broker_MidnightEventsDB = Broker_MidnightEventsDB or {}
    local db = Broker_MidnightEventsDB
    db.minimapIcon = db.minimapIcon or { hide = false }  -- managed by LibDBIcon
    db.chars       = db.chars       or {}

    -- Phase 2 migration: per-event toggles and "hide distant" are gone now
    -- that the Events surface is C_EventScheduler-driven (Blizzard's own
    -- panel handles filtering). Drop the orphaned SV keys on first load.
    db.events      = nil
    db.hideDistant = nil

    -- Phase 6 migration: consolidate section visibility under enabledSections.
    -- The legacy showAltSummary flag becomes enabledSections.alts; new flags
    -- (now, upcoming, weekly) default to true on first load.
    db.enabledSections = db.enabledSections or {}
    if db.showAltSummary ~= nil then
        if db.enabledSections.alts == nil then
            db.enabledSections.alts = db.showAltSummary
        end
        db.showAltSummary = nil
    end
    for k, v in pairs(defaults.enabledSections) do
        if db.enabledSections[k] == nil then db.enabledSections[k] = v end
    end

    if db.showWorldBosses == nil then db.showWorldBosses = defaults.showWorldBosses end

    db.broker = db.broker or {}
    for k, v in pairs(defaults.broker) do
        if db.broker[k] == nil then db.broker[k] = v end
    end

    ns.db = db

    -- Per-character bootstrap. Key is "Realm/Name" so connected realms with
    -- duplicate character names stay distinct.
    local charKey  = (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
    db.chars[charKey] = db.chars[charKey] or {}
    local char = db.chars[charKey]
    char.lastLogin       = time()
    char.weeklyReset     = char.weeklyReset or 0
    char.worldBoss       = char.worldBoss   or { done = false }
    char.weeklies        = char.weeklies    or {}
    char.worldBossesDone = nil  -- legacy, replaced by worldBoss table
    -- Myth-crest delve counter. `validSince` stays nil until this char
    -- witnesses a real weekly-reset boundary (set in the reset hook
    -- below), so a mid-week install greys the row instead of showing a
    -- partial count. See the reset block + Core's CURRENCY hook.
    char.crestDelve      = char.crestDelve  or { count = 0 }

    -- Class is stable per char (race+faction changes leave it intact); record
    -- it once at login so the Alts detail panel can color names without
    -- needing to call UnitClass on every render. fileName is the unlocalized
    -- key into RAID_CLASS_COLORS.
    local _, classFile = UnitClass("player")
    if classFile then char.class = classFile end
    char.level = UnitLevel("player") or char.level or 0

    -- Phase 10: bountiful delve completion cache (daily-reset cycle).
    -- bountifulSeen is the snapshot of bountifuls observed today; entries
    -- missing from the live list are rendered as completed.
    char.bountifulSeen       = char.bountifulSeen       or {}
    char.bountifulResetEpoch = char.bountifulResetEpoch or 0

    -- The earlier eventScheduledToday cache turned out unnecessary — the
    -- claimed-today heuristic in Core.lua reads source + isTimed + current
    -- scheduler view directly, no session memory required. Clean up if
    -- present from a prior install.
    char.eventScheduledToday      = nil
    char.eventScheduledResetEpoch = nil

    -- Migration: the previous Liadrin-only pick tracker (char.liadrinChoice)
    -- was generalized into char.picks[<weeklyKey>] when the Bonus Event
    -- Weekly row landed. Lift any legacy value into the new shape.
    if char.liadrinChoice and (not char.picks or not char.picks.liadrin) then
        char.picks = char.picks or {}
        char.picks.liadrin = char.liadrinChoice
    end
    char.liadrinChoice = nil

    ns.char = char

    -- Phase 8: Alts detail panel geometry. Lazily applied when the panel
    -- first opens; persisted on drag-stop. bgAlpha controls the panel's
    -- background-texture opacity (0.6 by default — slightly transparent so
    -- the world behind stays partly visible, like a tooltip).
    db.altsPanel = db.altsPanel or {
        point = "CENTER", x = 0, y = 0,
    }
    if db.altsPanel.bgAlpha == nil then db.altsPanel.bgAlpha = 0.6 end
    if db.altsPanel.showHidden == nil then db.altsPanel.showHidden = false end
    db.hiddenChars = db.hiddenChars or {}

    -- Note: we considered pre-warming the achievement catalog with
    -- LoadAddOn("Blizzard_AchievementUI") at init so the delve-story
    -- annotations could render definite colors for never-engaged delves.
    -- Empirically (2026-05-23) loading the UI module is NOT sufficient —
    -- WoW genuinely lazy-loads per-achievement criteria only when the
    -- player engages with the content (runs that delve, scrolls to the
    -- achievement in the UI, etc.). For our case, that means the grey
    -- "unknown" fallback color persists for delves the character has
    -- never run — accepted as the honest signal rather than guessing
    -- wrong with a "not done" gold colour.

    -- Weekly reset detection: if the most recent reset is newer than the one
    -- this character's data covers, wipe weekly state. Voidforge entries
    -- scoped "weekly" (e.g. Voidcores 0/N) reset their value to 0; their
    -- max stays as the last-observed cap until the next Decimus visit
    -- refreshes it. Scope-"lifetime" entries (Nilhammer) persist.
    local currentReset = CurrentWeeklyResetEpoch()
    if currentReset and char.weeklyReset < currentReset then
        -- Capture the prior reset epoch BEFORE overwriting it: 0 means a
        -- fresh / mid-week install (we never saw last week), a non-zero
        -- value means we were already running and are now witnessing a
        -- genuine reset boundary.
        local priorReset = char.weeklyReset
        char.worldBoss   = { done = false }
        char.weeklies    = {}
        char.weeklyReset = currentReset
        -- Picks cache must reset too: pool quest completion flags don't
        -- reliably clear on weekly reset (Artherio's account showed all
        -- 9 Liadrin pool members flagged simultaneously), so the
        -- in-log-or-cached-flagged detection would otherwise carry last
        -- week's pick into the new cycle indefinitely. Clearing here
        -- starts each new week from a clean slate; the next time the
        -- player accepts a Liadrin / Bonus Event / Void Assault quest
        -- the pass-1 active-log scan refills it.
        char.picks       = {}
        if char.voidforge and ns.charProgress then
            for _, entry in ipairs(ns.charProgress) do
                if entry.scope == "weekly" and char.voidforge[entry.key] then
                    char.voidforge[entry.key].value = 0
                end
            end
        end
        -- Prey Hunts board: visible-tier bar resets to full each weekly
        -- cycle. Restore value to max so the post-reset display reflects
        -- a fresh week immediately, before the player next visits the
        -- Eversong board.
        if char.preyHunts and char.preyHunts.max then
            char.preyHunts.value = char.preyHunts.max
        end
        -- Myth-crest delve counter resets to 0 each week. Mark this week
        -- as cleanly tracked (validSince) ONLY when priorReset > 0 — i.e.
        -- we witnessed a real boundary, so the 0-baseline is genuine. A
        -- fresh / mid-week install (priorReset == 0) leaves validSince
        -- unset, greying the row until this char's first real reset, so
        -- it never displays an undercounted partial.
        char.crestDelve = char.crestDelve or { count = 0 }
        char.crestDelve.count = 0
        if priorReset and priorReset > 0 then
            char.crestDelve.validSince = currentReset
        end
    end

    -- Register minimap button (LibDBIcon manages show/hide via right-click menu).
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and ns.broker then
        LibDBIcon:Register("Broker_MidnightEvents", ns.broker, db.minimapIcon)
    end

    -- ── Settings panel ────────────────────────────────────────────────────────

    local category = Settings.RegisterVerticalLayoutCategory("Broker: MidnightEvents")

    -- Section: Tooltip Sections (mirror of the tooltip's top-level hierarchy)
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Tooltip Sections", nil))

    local sectionOptions = {
        { key = "now",       label = "Now",                       desc = "Show currently-firing events (Stormarion, Legends, ongoing Abundance, etc.)." },
        { key = "upcoming",  label = "Upcoming (next 24h)",       desc = "Show scheduled events firing within the next 24 hours." },
        { key = "delves",    label = "Bountiful Delves (today)",  desc = "Show today's bountiful Delve rotation with the active story variant. Auto-hidden on chars outside the Midnight continent." },
        { key = "weekly",    label = "This Week",                 desc = "Show the per-character weekly checklist (World Bosses + tracked weekly quests)." },
        { key = "voidforge", label = "Voidforge progress",        desc = "Show per-character Voidforge counters (Voidcores transmuted, Nilhammer empowered) from Decimus in Voidstorm. Auto-hidden until the first time the character visits Decimus." },
    }
    for _, opt in ipairs(sectionOptions) do
        local setting = Settings.RegisterAddOnSetting(
            category, addonName .. "_section_" .. opt.key,
            opt.key, db.enabledSections,
            Settings.VarType.Boolean, opt.label,
            defaults.enabledSections[opt.key])
        setting:SetValueChangedCallback(RefreshUI)
        Settings.CreateCheckbox(category, setting, opt.desc)
    end

    -- Section: This Week rows
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("This Week rows", nil))

    local wbSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_showWorldBosses", "showWorldBosses", db,
        Settings.VarType.Boolean, "World Bosses",
        defaults.showWorldBosses)
    wbSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, wbSetting,
        "Display the World Bosses row inside the This Week section.")

    -- Section: Broker bar
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Broker bar", nil))

    local brokerProgressSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_broker_showProgress", "showProgress", db.broker,
        Settings.VarType.Boolean, "Show weekly progress (N/M)",
        defaults.broker.showProgress)
    brokerProgressSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, brokerProgressSetting,
        "Show the weekly-progress count (e.g. \"Weeklies 3/7\") on the broker bar.")

    local brokerEventSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_broker_showEvent", "showEvent", db.broker,
        Settings.VarType.Boolean, "Show next-event tag",
        defaults.broker.showEvent)
    brokerEventSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, brokerEventSetting,
        "Append the next-firing event (e.g. \"Abundance in 23m\") to the broker bar text.")

    -- Section: Alts panel
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Alts panel", nil))

    local altsAlphaSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_altsPanelBgAlpha", "bgAlpha", db.altsPanel,
        Settings.VarType.Number, "Background opacity", 0.6)
    altsAlphaSetting:SetValueChangedCallback(function()
        if ns.AltsPanel and ns.AltsPanel.RefreshBackground then
            ns.AltsPanel.RefreshBackground()
        end
    end)
    local sliderOptions = Settings.CreateSliderOptions(0.1, 1.0, 0.05)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    Settings.CreateSlider(category, altsAlphaSetting, sliderOptions,
        "Background opacity for the detached Alts panel (Shift-RightClick on the broker). "
        .. "Lower = more see-through.")

    -- "Show hidden characters" toggle — paired with the right-click-row-
    -- to-hide gesture in the Alts panel. When off, hidden chars are
    -- omitted entirely from the panel. When on, they appear extra-dim
    -- and right-clicking them again flips them back to visible.
    local altsShowHiddenSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_altsPanelShowHidden", "showHidden", db.altsPanel,
        Settings.VarType.Boolean, "Show hidden characters",
        false)
    altsShowHiddenSetting:SetValueChangedCallback(function()
        if ns.AltsPanel and ns.AltsPanel.RefreshIfShown then
            ns.AltsPanel.RefreshIfShown()
        end
    end)
    Settings.CreateCheckbox(category, altsShowHiddenSetting,
        "Show characters you've right-clicked-to-hide in the Alts panel, rendered extra-dim. "
        .. "Right-click a hidden row to un-hide it.")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()
end)
