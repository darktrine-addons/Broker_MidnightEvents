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

-- Derive remaining seconds + a state tag for an event entry from ns.Events.
-- Prefers epoch fields (startTime/endTime) over server-snapshot secondsLeft
-- so countdowns decrement live between Events refreshes.
--   "upcoming" — startTime > now; secs = startTime - now
--   "active"   — currently firing; secs = endTime - now (or secondsLeft fallback)
--   "wave"     — continuously-ongoing POI with an internal wave cadence
--                (Stormarion Assault); secs = wall-clock seconds to next wave
--   "ongoing"  — untimed and no cadence override (Legends); secs = nil
local function EventRemaining(ev, now)
    if ev.startTime and ev.startTime > now then
        return ev.startTime - now, "upcoming"
    end
    if ev.endTime and ev.endTime > now then
        return ev.endTime - now, "active"
    end
    if ev.secondsLeft and ev.secondsLeft > 0 then
        return ev.secondsLeft, "active"
    end
    -- Untimed POI: try a wave-cadence prediction before falling back to
    -- ambient "ongoing" state. Stormarion Assault is the current user.
    if ns.GetWaveCountdown then
        local waveSecs = ns.GetWaveCountdown(ev.name)
        if waveSecs then return waveSecs, "wave" end
    end
    return nil, "ongoing"
end

-- ── weekly completion tracking ────────────────────────────────────────────────
-- Midnight weeklies (and world bosses) register via quest credit, not the
-- legacy raid-lockout system. We poll IsQuestFlaggedCompleted on PEW and on
-- quest events to keep ns.char.weeklies and ns.char.worldBoss fresh.

-- Resolves a single ns.weeklies row to a boolean completion state. Supports
-- two row shapes:
--   { questID = N }       — single quest; row done iff N is flagged complete
--   { questIDs = {a, b…} } — pool/rotation slot; row done iff any pool
--                            member is flagged complete (suits Lady Liadrin's
--                            choose-N-of-pool umbrella and the Void Assault
--                            zone rotation pair)
local function IsWeeklySlotDone(w)
    if w.questID then
        return C_QuestLog.IsQuestFlaggedCompleted(w.questID) or false
    end
    if w.questIDs then
        for _, qid in ipairs(w.questIDs) do
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then return true end
        end
    end
    return false
end

local function RefreshWeeklies()
    if not ns.char or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return
    end

    -- Per-row binary weeklies.
    ns.char.weeklies = ns.char.weeklies or {}
    for _, w in ipairs(ns.weeklies or {}) do
        ns.char.weeklies[w.key] = IsWeeklySlotDone(w)
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

-- Walk active + upcoming events and pick the row with the smallest non-nil
-- remaining-seconds. Falls back to the first untimed active event ("ongoing")
-- when nothing has a countdown.
local function GetSoonest()
    if not ns.Events then return nil end
    local now = time()
    local soonest, soonestSecs, soonestKind

    for _, ev in ipairs(ns.Events.GetActive()) do
        local secs, kind = EventRemaining(ev, now)
        if secs and (not soonestSecs or secs < soonestSecs) then
            soonest, soonestSecs, soonestKind = ev, secs, kind
        end
    end
    for _, ev in ipairs(ns.Events.GetUpcoming(24 * 3600)) do
        local secs, kind = EventRemaining(ev, now)
        if secs and (not soonestSecs or secs < soonestSecs) then
            soonest, soonestSecs, soonestKind = ev, secs, kind
        end
    end
    if not soonest then
        local active = ns.Events.GetActive()
        if active[1] then
            soonest, soonestSecs, soonestKind = active[1], nil, "ongoing"
        end
    end
    return soonest, soonestSecs, soonestKind
end

-- Current-character weekly progress: how many enabled rows are done out of
-- the total enabled set. World Boss counts as one row when its display
-- toggle is on. Returns (done, total).
local function WeeklyProgress()
    if not ns.char then return 0, 0 end
    local done, total = 0, 0
    local showWB = not ns.db or ns.db.showWorldBosses ~= false
    if showWB then
        total = total + 1
        if ns.char.worldBoss and ns.char.worldBoss.done then
            done = done + 1
        end
    end
    if ns.weeklies and ns.char.weeklies then
        for _, w in ipairs(ns.weeklies) do
            total = total + 1
            if ns.char.weeklies[w.key] then
                done = done + 1
            end
        end
    end
    return done, total
end

-- Render the right-hand event tag for the broker text. Returns (text, urgent).
-- `urgent` flags the firing-now / soon-firing cases so the caller can pick an
-- amber color override over the default.
local function FormatEventTag(ev, secs, kind)
    if not ev then return nil, false end
    local short = ShortName(ev.name)
    if kind == "ongoing" then
        return short .. " ongoing", false
    end
    if kind == "upcoming" then
        return short .. " in " .. FormatRemaining(secs), (secs and secs <= 5 * 60)
    end
    if kind == "wave" then
        if not secs or secs <= 0 then
            return short .. " wave!", true
        end
        return short .. " next " .. FormatRemaining(secs), (secs <= 5 * 60)
    end
    -- "active"
    if not secs or secs <= 0 then
        return short .. " now!", true
    end
    return short .. " " .. FormatRemaining(secs), (secs <= 5 * 60)
end

-- Display toggles for the broker bar. Default both on if the SV hasn't been
-- populated yet (early-load race window or fresh install).
local function BrokerShow(key)
    local b = ns.db and ns.db.broker
    if not b then return true end
    return b[key] ~= false
end

local function UpdateBrokerText()
    local done, total = WeeklyProgress()
    local showProgress = BrokerShow("showProgress")
    local showEvent    = BrokerShow("showEvent")

    local ev, secs, kind
    if showEvent and ns.Events and ns.Events.HasData() then
        ev, secs, kind = GetSoonest()
    end
    local eventTag, eventUrgent = FormatEventTag(ev, secs, kind)

    local body, hex

    -- Compose progress chunk (left side).
    local progress
    if showProgress and total > 0 then
        if done >= total then
            progress = "All done"
        else
            progress = "Weeklies " .. done .. "/" .. total
        end
    end

    if progress and eventTag then
        body = progress .. " · " .. eventTag
        if eventUrgent then
            hex = "ff9919"
        elseif done >= total then
            hex = "55cc55"
        else
            hex = "ffffff"
        end
    elseif progress then
        if done >= total then
            body = (showEvent and "All done this week") or progress  -- "All done" alone reads odd; expand it when event tag is suppressed too
            hex  = "5a8a5a"
        else
            body = progress
            hex  = "ffffff"
        end
    elseif eventTag then
        body = eventTag
        hex  = eventUrgent and "ff9919" or "ffffff"
    else
        -- Both halves suppressed or no data — placeholder so the bar isn't blank.
        body = "Midnight Events"
        hex  = "808080"
    end

    broker.text = "|cff" .. hex .. body .. "|r"
end

-- ── tooltip ───────────────────────────────────────────────────────────────────

-- Per-section visibility. Defaults to true before db.enabledSections is
-- populated (rare race window between addon load and BuildTooltip).
local function SectionEnabled(key)
    local s = ns.db and ns.db.enabledSections
    if not s then return true end
    return s[key] ~= false
end

local function BuildTooltip()
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Midnight Events", CV_r, CV_g, CV_b)

    local now = time()

    -- ── Section: Now ──────────────────────────────────────────────────────────
    -- Events currently firing (scheduler ongoing + currently-active scheduled
    -- + continuous map-event POIs). Order: insertion order from ns.Events,
    -- which puts scheduler entries before map-event entries.
    if SectionEnabled("now") then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Now", CL_r, CL_g, CL_b)

    local active = ns.Events and ns.Events.GetActive() or {}
    if #active == 0 then
        GameTooltip:AddLine("(no active events)", 0.5, 0.5, 0.5)
    else
        for _, ev in ipairs(active) do
            local secs, kind = EventRemaining(ev, now)
            local atlas = ev.atlasName
            local label = atlas
                          and ("|A:" .. atlas .. ":16:16|a " .. (ev.name or "Event"))
                          or  (ev.name or "Event")

            local valueText, vr, vg, vb
            if kind == "ongoing" then
                valueText, vr, vg, vb = "active", 0.6, 0.6, 0.6
            elseif kind == "wave" then
                -- Continuous POI with an internal wave cycle. Show the
                -- countdown to the next wave, rendered like an upcoming row.
                if secs and secs <= 0 then
                    valueText, vr, vg, vb = "wave now!", CH_r, CH_g, CH_b
                else
                    valueText = "next in " .. FormatRemaining(secs)
                    if secs and secs < 5 * 60 then
                        vr, vg, vb = CH_r, CH_g, CH_b
                    else
                        vr, vg, vb = 0.65, 0.75, 0.95
                    end
                end
            elseif secs and secs <= 0 then
                valueText, vr, vg, vb = "now!", CH_r, CH_g, CH_b
            else
                valueText = FormatRemaining(secs) .. " left"
                if secs and secs < 5 * 60 then
                    vr, vg, vb = CH_r, CH_g, CH_b
                else
                    vr, vg, vb = CV_r, CV_g, CV_b
                end
            end
            GameTooltip:AddDoubleLine(label, valueText, CV_r, CV_g, CV_b, vr, vg, vb)
        end
    end
    end  -- SectionEnabled("now")

    -- ── Section: Upcoming (next 24h) ──────────────────────────────────────────
    -- Scheduler-fed list of future event firings within the next day. Already
    -- sorted by startTime ascending in ns.Events. Section is suppressed when
    -- empty so the tooltip doesn't grow a stub header for nothing.
    if SectionEnabled("upcoming") then
    local upcoming = ns.Events and ns.Events.GetUpcoming(24 * 3600) or {}
    if #upcoming > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Upcoming (next 24h)", CL_r, CL_g, CL_b)
        for _, ev in ipairs(upcoming) do
            local secs  = (ev.startTime or 0) - now
            local atlas = ev.atlasName
            local label = atlas
                          and ("|A:" .. atlas .. ":16:16|a " .. (ev.name or "Event"))
                          or  (ev.name or "Event")
            local valueText = "in " .. FormatRemaining(secs)
            local vr, vg, vb
            if secs < 5 * 60 then
                vr, vg, vb = CH_r, CH_g, CH_b
            else
                vr, vg, vb = 0.65, 0.75, 0.95
            end
            GameTooltip:AddDoubleLine(label, valueText, CV_r, CV_g, CV_b, vr, vg, vb)
        end
    end
    end  -- SectionEnabled("upcoming")

    -- ── Section: Bountiful Delves (today) ─────────────────────────────────────
    -- Daily-rotating bountiful Delve POIs surfaced via C_AreaPoiInfo, not the
    -- event scheduler. Per-Delve completion tracking will land in a later
    -- phase once we harvest per-Delve kill-credit quest IDs; for now we just
    -- show the active list so the user knows which delves are bountiful
    -- today. Section is suppressed when the list is empty (cross-expansion
    -- char, mid-init, etc.) so the tooltip doesn't grow a stub header.
    if SectionEnabled("delves") then
    local delves = ns.Events and ns.Events.GetBountifulDelves() or {}
    if #delves > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(
            "Bountiful Delves (today)",
            #delves .. " active",
            CL_r, CL_g, CL_b, CV_r, CV_g, CV_b)
        for _, d in ipairs(delves) do
            local label = d.atlasName
                          and ("|A:" .. d.atlasName .. ":16:16|a " .. (d.name or "Delve"))
                          or  (d.name or "Delve")
            GameTooltip:AddLine(label, CV_r, CV_g, CV_b)
        end
    end
    end  -- SectionEnabled("delves")

    -- ── Section: This Week (CharName) ─────────────────────────────────────────
    -- Outstanding rows render at the top in white with an orange ✗ icon (or
    -- green 'available' for the world boss, where we want a positive prompt
    -- to check the map rather than a nag). Done rows fall to the bottom in
    -- dim grey with a green ✓ icon. The section header carries an at-a-glance
    -- 'X/Y done' summary so the player knows the status without scanning.
    local showWB = not ns.db or ns.db.showWorldBosses ~= false
    local hasWeeklies = ns.weeklies and #ns.weeklies > 0
    if SectionEnabled("weekly") and (showWB or hasWeeklies) then
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

    -- ── Section: Alts (roll-up summary) ──────────────────────────────────────
    -- Aggregates per-activity completion across every tracked character that
    -- has logged in since the most recent weekly reset. Stale-data characters
    -- (no login since reset) are excluded from both the active count and the
    -- per-activity denominators, so progress reflects only fresh observations.
    -- Hidden entirely when the user is the only tracked char.
    local currentReset = ns.char and ns.char.weeklyReset or 0
    if SectionEnabled("alts") and ns.db and ns.db.chars and currentReset > 0 then
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
    GameTooltip:AddDoubleLine("LeftClick",   "open events panel",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)
    GameTooltip:AddDoubleLine("RightClick",  "open settings",
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
    if button == "LeftButton" then
        -- Drop the user into Blizzard's native events panel:
        --   1. Open the world map with the quest log / side-panel shown.
        --   2. Switch the side panel to the Events tab.
        --   3. Ping the first active event POI so the eye lands on it.
        -- OpenMapToEventPoi alone doesn't force the side panel open or pick
        -- the Events tab (it just opens the map + pings) — the world map
        -- remembers whichever tab the user last viewed, so we drive each step
        -- explicitly to land on Events reliably.
        local poiID = ns.Events and ns.Events.GetFirstActivePOI()
        local mapID = ns.Events and ns.Events.GetContinentMapID()

        if WorldMapFrame and WorldMapFrame.HandleUserActionOpenQuestLog then
            WorldMapFrame:HandleUserActionOpenQuestLog(mapID)
        elseif OpenWorldMap and mapID then
            OpenWorldMap(mapID)
        end

        if QuestMapFrame and QuestMapFrame.SetDisplayMode
           and QuestLogDisplayMode and QuestLogDisplayMode.Events then
            QuestMapFrame:SetDisplayMode(QuestLogDisplayMode.Events)
        end

        if poiID and EventRegistry and EventRegistry.TriggerEvent then
            EventRegistry:TriggerEvent("PingAreaPOIEvent", poiID)
        end
    elseif button == "RightButton" and not IsShiftKeyDown() then
        if ns.settingsCategoryID then
            Settings.OpenToCategory(ns.settingsCategoryID)
        end
    end
    -- Shift-RightClick reserved for the Alts detail panel (Phase 8).
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
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD"
       or event == "QUEST_TURNED_IN"
       or event == "QUEST_REMOVED" then
        RefreshWeeklies()
    end
    UpdateBrokerText()
    if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
        BuildTooltip()
    end
end)

-- Subscribe to Events module refreshes (server-pushed EVENT_SCHEDULER_UPDATE,
-- AREA_POIS_UPDATED for continuous map-only POIs, and PEW continent rediscovery).
if ns.Events and ns.Events.RegisterListener then
    ns.Events.RegisterListener(function()
        UpdateBrokerText()
        if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
            BuildTooltip()
        end
    end)
end

-- 1-second ticker decrements the broker countdown smoothly between Events
-- refreshes. Uses live startTime/endTime epochs via EventRemaining, so no
-- internal mutation needed — just re-render.
local tickerElapsed = 0
f:SetScript("OnUpdate", function(self, dt)
    tickerElapsed = tickerElapsed + dt
    if tickerElapsed >= 1.0 then
        tickerElapsed = 0
        UpdateBrokerText()
        if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
            BuildTooltip()
        end
    end
end)
