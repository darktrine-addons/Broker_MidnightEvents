-- Broker_MidnightEvents - Core
-- LDB data broker plugin: world event timers and weekly activity tracking for Midnight.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

local LDB = LibStub("LibDataBroker-1.1")
local broker = LDB:NewDataObject("Broker_MidnightEvents", {
    type  = "data source",
    label = "MidnightEvents",
    icon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    text  = "...",
})
ns.broker = broker  -- exposed for LibDBIcon registration in Settings.lua

-- ── tooltip colors ────────────────────────────────────────────────────────────
local CL_r, CL_g, CL_b = 0.40, 0.80, 0.80   -- teal   (label / section)
local CV_r, CV_g, CV_b = 1.00, 1.00, 1.00   -- white  (value)
local CH_r, CH_g, CH_b = 1.00, 0.60, 0.10   -- orange (urgent / now)

-- Trim everything after the first ": " — broker bars are narrow, the event
-- type is what matters there. The full name still appears in the tooltip.
local function ShortName(name)
    return name and (name:match("^(.-): ") or name) or "Event"
end

-- ── active events ─────────────────────────────────────────────────────────────
-- Rebuilt on AREA_POIS_UPDATED. Each entry:
--   { mapID, poiID, name, atlas, secs, expiresAt, pending }
-- secs / expiresAt are nil for events that aren't timed (zone-week markers).
-- `pending` is true when secs is "time until next firing" (schedule fallback);
-- false/nil when secs is "time until current run ends" (server-pushed).
local activeEvents = {}
local tooltipOwner  -- set while our tooltip is being shown; nil otherwise

-- Compact remaining-time formatter: "now", "45s", "23m", "3h 12m", "2d 7h 18m".
local function FormatRemaining(secs)
    if not secs or secs <= 0  then return "now"                        end
    if secs < 60              then return math.floor(secs) .. "s"      end
    if secs < 3600            then return math.floor(secs / 60) .. "m" end
    if secs < 86400 then
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        return h .. "h " .. m .. "m"
    end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    return d .. "d " .. h .. "h " .. m .. "m"
end

-- Live remaining time for a stored event (uses expiresAt to count down without re-scan).
local function CurrentRemaining(ev)
    if not ev.expiresAt then return nil end
    return ev.expiresAt - GetTime()
end

-- After a predicted firing passes, keep showing 'now!' for the grace window,
-- then roll the prediction forward to the next cadence mark. We deliberately
-- don't try to verify against GetAreaPOISecondsLeft — every TWW Theatre
-- Troupe tracker tried that path and abandoned it (the API returns values
-- misaligned with reality for player-action events of this class).
local function RefreshPendingPredictions()
    local now   = GetTime()
    local grace = ns.scheduleGracePeriod or 600
    for _, ev in ipairs(activeEvents) do
        if ev.pending and ev.expiresAt
           and (now - ev.expiresAt) > grace then
            local newSecs = ns.ScheduleFallbackSecs(ev.name)
            if newSecs then
                ev.secs      = newSecs
                ev.expiresAt = now + newSecs
            end
        end
    end
end

-- Visibility filter applied uniformly across broker text and tooltip rendering.
-- Honors per-event toggles and the "hide distant events" master switch.
local function IsVisible(ev)
    local db = ns.db
    if not db then return true end
    local key = ns.GetEventToggleKey and ns.GetEventToggleKey(ev.name)
    if key and db.events and db.events[key] == false then
        return false
    end
    if db.hideDistant then
        local rem = CurrentRemaining(ev)
        if rem and rem > 24 * 3600 then return false end
    end
    return true
end

-- Scan one map for current-event POIs; append to `out`, dedupe via `seenPOIs`.
local function ScanMap(mapID, out, seenPOIs)
    if not mapID then return end
    local pois = C_AreaPoiInfo.GetEventsForMap(mapID)
    if not pois then return end
    for _, poiID in ipairs(pois) do
        if not seenPOIs[poiID] then
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info and info.isCurrentEvent then
                local secs, pending
                if C_AreaPoiInfo.IsAreaPOITimed(poiID) then
                    secs = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
                end
                if not secs then
                    secs    = ns.ScheduleFallbackSecs(info.name)
                    pending = secs ~= nil
                end
                local entry = {
                    mapID   = mapID,
                    poiID   = poiID,
                    name    = info.name or "Event",
                    atlas   = info.atlasName,
                    secs    = secs,
                    pending = pending,
                }
                if secs then entry.expiresAt = GetTime() + secs end
                out[#out + 1] = entry
                seenPOIs[poiID] = true
            end
        end
    end
end

local function RefreshActiveEvents()
    wipe(activeEvents)
    local seen = {}
    for _, mapID in ipairs(ns.zones) do
        ScanMap(mapID, activeEvents, seen)
    end
    -- Defensive: also scan whatever zone the player is currently in.
    ScanMap(C_Map.GetBestMapForUnit("player"), activeEvents, seen)

    -- Sort: timed events ascending by remaining seconds, untimed at the bottom.
    table.sort(activeEvents, function(a, b)
        local sa = a.secs or math.huge
        local sb = b.secs or math.huge
        if sa == sb then return a.name < b.name end
        return sa < sb
    end)
end

-- ── weekly completion tracking ────────────────────────────────────────────────
-- Midnight weeklies (and world bosses) register via quest credit, not the
-- legacy raid-lockout system. We poll IsQuestFlaggedCompleted on PEW and on
-- quest events to keep ns.char.weeklies and ns.char.worldBoss fresh.

local function RefreshWeeklies()
    if not ns.char or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return
    end

    -- Per-row binary weeklies.
    ns.char.weeklies = ns.char.weeklies or {}
    for _, w in ipairs(ns.weeklies or {}) do
        ns.char.weeklies[w.key] = C_QuestLog.IsQuestFlaggedCompleted(w.questID) or false
    end

    -- World boss: per-boss credit IDs are the source of truth. The earlier
    -- approach of using the 93913 'Midnight: World Boss' umbrella as a single
    -- boolean gave false positives — that umbrella behaves like the rest of
    -- the 'Midnight: <X>' family (one-time intro/unlock that flags as soon as
    -- a char first engages, never resets), so it would mark every alt that
    -- has ever interacted with world-boss content as "done."
    local bossName
    for _, b in ipairs(ns.worldBosses or {}) do
        if C_QuestLog.IsQuestFlaggedCompleted(b.questID) then
            bossName = b.name
            break
        end
    end
    ns.char.worldBoss = { done = bossName ~= nil, name = bossName }
end

-- ── broker text ───────────────────────────────────────────────────────────────

local function UpdateBrokerText()
    local soonest, soonestRem
    for _, ev in ipairs(activeEvents) do
        if IsVisible(ev) then
            local rem = CurrentRemaining(ev)
            if rem and (not soonestRem or rem < soonestRem) then
                soonest, soonestRem = ev, rem
            end
        end
    end

    if soonest then
        local short = ShortName(soonest.name)
        local body, hex
        if soonestRem and soonestRem <= 0 then
            body = short .. "  now!"
            hex  = "ff9919"                       -- orange (now firing)
        elseif soonest.pending then
            body = short .. " in " .. FormatRemaining(soonestRem)
            hex  = soonestRem < 5 * 60 and "ff9919" or "a6bff2"  -- urgent / soft blue
        else
            body = short .. "  " .. FormatRemaining(soonestRem) .. " left"
            hex  = soonestRem < 5 * 60 and "ff9919" or "ffffff"  -- urgent / white
        end
        broker.text = "|cff" .. hex .. body .. "|r"
    else
        broker.text = "Midnight Events"
    end
end

-- ── tooltip ───────────────────────────────────────────────────────────────────

local function BuildTooltip()
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Midnight Events", CV_r, CV_g, CV_b)

    -- ── Section 1: Timed Events ───────────────────────────────────────────────
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Timed Events", CL_r, CL_g, CL_b)

    local visible = {}
    for _, ev in ipairs(activeEvents) do
        if IsVisible(ev) then visible[#visible + 1] = ev end
    end

    if #visible == 0 then
        GameTooltip:AddLine("(no active events)", 0.5, 0.5, 0.5)
    else
        for _, ev in ipairs(visible) do
            local label = ev.atlas
                          and ("|A:" .. ev.atlas .. ":16:16|a " .. ev.name)
                          or  ev.name

            local rem = CurrentRemaining(ev)
            local valueText, vr, vg, vb
            if not rem then
                valueText, vr, vg, vb = "active", 0.6, 0.6, 0.6
            elseif rem <= 0 then
                valueText, vr, vg, vb = "now!", CH_r, CH_g, CH_b
            elseif ev.pending then
                -- Time until the event next starts.
                valueText = "in " .. FormatRemaining(rem)
                if rem < 5 * 60 then
                    vr, vg, vb = CH_r, CH_g, CH_b      -- about to fire
                else
                    vr, vg, vb = 0.65, 0.75, 0.95      -- soft blue: future
                end
            else
                -- Time until the currently-running event expires.
                valueText = FormatRemaining(rem) .. " left"
                if rem < 5 * 60 then
                    vr, vg, vb = CH_r, CH_g, CH_b      -- about to expire
                else
                    vr, vg, vb = CV_r, CV_g, CV_b
                end
            end
            GameTooltip:AddDoubleLine(label, valueText, CV_r, CV_g, CV_b, vr, vg, vb)
        end
    end

    -- ── Section 2: This Week (CharName) ───────────────────────────────────────
    -- Outstanding rows render at the top in white with an orange ✗ icon (or
    -- green 'available' for the world boss, where we want a positive prompt
    -- to check the map rather than a nag). Done rows fall to the bottom in
    -- dim grey with a green ✓ icon. The section header carries an at-a-glance
    -- 'X/Y done' summary so the player knows the status without scanning.
    local showWB = not ns.db or ns.db.showWorldBosses ~= false
    local hasWeeklies = ns.weeklies and #ns.weeklies > 0
    if showWB or hasWeeklies then
        local CHECK = "|A:common-icon-checkmark:14:14|a"
        local CROSS = "|A:common-icon-redx:14:14|a"

        local wb = ns.char and ns.char.worldBoss or {}
        local weeklyState = ns.char and ns.char.weeklies or {}

        -- Build a unified row list so outstanding-first sort applies uniformly.
        local rows = {}
        if showWB then
            rows[#rows + 1] = {
                label       = "World Boss",
                done        = wb.done or false,
                isWorldBoss = true,
                bossName    = wb.name,
            }
        end
        if hasWeeklies then
            for _, w in ipairs(ns.weeklies) do
                rows[#rows + 1] = {
                    label = w.label,
                    done  = weeklyState[w.key] or false,
                }
            end
        end

        -- Header with completion summary.
        local total, done = #rows, 0
        for _, r in ipairs(rows) do if r.done then done = done + 1 end end
        local summary = done .. "/" .. total .. " done"
        local sr, sg, sb = CV_r, CV_g, CV_b
        if done == total then sr, sg, sb = 0.6, 0.6, 0.6 end  -- fully done

        local charName = UnitName("player") or "?"
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("This Week (" .. charName .. ")", summary,
            CL_r, CL_g, CL_b, sr, sg, sb)

        -- Stable sort: outstanding before done, original order within each group.
        local indexed = {}
        for i, r in ipairs(rows) do indexed[i] = { row = r, idx = i } end
        table.sort(indexed, function(a, b)
            if a.row.done ~= b.row.done then return not a.row.done end
            return a.idx < b.idx
        end)

        for _, s in ipairs(indexed) do
            local r = s.row
            local labelR, labelG, labelB
            local valueText, vR, vG, vB

            if r.done then
                -- Done: dim grey label, green checkmark, plus boss name when relevant.
                labelR, labelG, labelB = 0.55, 0.55, 0.55
                if r.isWorldBoss and r.bossName then
                    valueText = CHECK .. "  " .. r.bossName
                else
                    valueText = CHECK
                end
                vR, vG, vB = 0.6, 0.6, 0.6
            elseif r.isWorldBoss then
                -- World boss outstanding: special green 'available' instead of ✗.
                labelR, labelG, labelB = CV_r, CV_g, CV_b
                valueText = "available"
                vR, vG, vB = 0.30, 0.85, 0.30
            else
                -- Weekly outstanding: white label, orange ✗.
                labelR, labelG, labelB = CV_r, CV_g, CV_b
                valueText = CROSS
                vR, vG, vB = CH_r, CH_g, CH_b
            end
            GameTooltip:AddDoubleLine(r.label, valueText,
                labelR, labelG, labelB, vR, vG, vB)
        end
    end

    -- ── Section 3: Alts (roll-up summary) ────────────────────────────────────
    -- Aggregates per-activity completion across every tracked character that
    -- has logged in since the most recent weekly reset. Stale-data characters
    -- (no login since reset) are excluded from both the active count and the
    -- per-activity denominators, so progress reflects only fresh observations.
    -- Hidden entirely when the user is the only tracked char.
    local showAlts = not ns.db or ns.db.showAltSummary ~= false
    local currentReset = ns.char and ns.char.weeklyReset or 0
    if showAlts and ns.db and ns.db.chars and currentReset > 0 then
        local trackedCount, activeCount = 0, 0
        local wbDoneCount = 0
        local weeklyDoneCount = {}            -- weekly key → completion count
        for _, c in pairs(ns.db.chars) do
            trackedCount = trackedCount + 1
            if (c.lastLogin or 0) >= currentReset then
                activeCount = activeCount + 1
                if c.worldBoss and c.worldBoss.done then
                    wbDoneCount = wbDoneCount + 1
                end
                if c.weeklies then
                    for k, done in pairs(c.weeklies) do
                        if done then
                            weeklyDoneCount[k] = (weeklyDoneCount[k] or 0) + 1
                        end
                    end
                end
            end
        end

        if trackedCount > 1 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                "Alts (" .. trackedCount .. " tracked, "
                .. activeCount .. " active this reset)",
                CL_r, CL_g, CL_b)

            if not ns.db or ns.db.showWorldBosses ~= false then
                GameTooltip:AddDoubleLine("World Boss",
                    wbDoneCount .. "/" .. activeCount .. " done",
                    CV_r, CV_g, CV_b, CV_r, CV_g, CV_b)
            end

            for _, w in ipairs(ns.weeklies or {}) do
                local done = weeklyDoneCount[w.key] or 0
                GameTooltip:AddDoubleLine(w.label,
                    done .. "/" .. activeCount .. " done",
                    CV_r, CV_g, CV_b, CV_r, CV_g, CV_b)
            end
        end
    end

    -- ── Interaction hints ─────────────────────────────────────────────────────
    -- Keyword in orange, description in white (matches Broker: Coords).
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Shift-RightClick", "open settings",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)

    -- ── Footer ────────────────────────────────────────────────────────────────
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("", "Broker: MidnightEvents  v" .. addonVersion,
                              0, 0, 0, 0.45, 0.45, 0.45)
    GameTooltip:Show()
end

broker.OnEnter = function(self)
    tooltipOwner = self
    local _, frameY = self:GetCenter()
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    if frameY and frameY > (GetScreenHeight() / 2) then
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
    else
        GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
    end
    BuildTooltip()
end

broker.OnLeave = function(self)
    tooltipOwner = nil
    GameTooltip:Hide()
end

broker.OnClick = function(self, button)
    if button == "RightButton" and IsShiftKeyDown() and ns.settingsCategoryID then
        Settings.OpenToCategory(ns.settingsCategoryID)
    end
end

-- Exposed so Settings.lua callbacks can refresh both surfaces immediately
-- after a toggle changes.
ns.UpdateBrokerText = UpdateBrokerText
function ns.RebuildTooltipIfOpen()
    if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
        BuildTooltip()
    end
end

-- ── event frame ───────────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("AREA_POIS_UPDATED")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "AREA_POIS_UPDATED" then
        RefreshActiveEvents()
        UpdateBrokerText()
    end
    if event == "PLAYER_ENTERING_WORLD"
       or event == "QUEST_TURNED_IN"
       or event == "QUEST_REMOVED" then
        RefreshWeeklies()
    end
    if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
        BuildTooltip()
    end
end)

-- 1-second ticker decrements the broker countdown smoothly between server pushes
-- (AREA_POIS_UPDATED can be minutes apart). Tooltip refresh is also driven here
-- whenever it's open, so the "23m" → "22m" step is visible without leaving and
-- re-entering the broker button.
local tickerElapsed = 0
f:SetScript("OnUpdate", function(self, dt)
    tickerElapsed = tickerElapsed + dt
    if tickerElapsed >= 1.0 then
        tickerElapsed = 0
        RefreshPendingPredictions()
        UpdateBrokerText()
        if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
            BuildTooltip()
        end
    end
end)
