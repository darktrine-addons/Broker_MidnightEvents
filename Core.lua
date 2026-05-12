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

-- Find the Liadrin pool questIDs from ns.weeklies. Returns a set for O(1)
-- lookup, or nil if the Liadrin row isn't defined.
local function GetLiadrinPool()
    for _, w in ipairs(ns.weeklies or {}) do
        if w.key == "liadrin" and w.questIDs then
            local set = {}
            for _, qid in ipairs(w.questIDs) do set[qid] = true end
            return set
        end
    end
    return nil
end

-- Detect which Liadrin pool member the current char has accepted (or
-- completed) this week. Stored on ns.char.liadrinChoice as the questID;
-- the tooltip looks up ns.liadrinLabels for a human-friendly annotation.
-- Cleared only when the cached choice is no longer in the active log AND
-- not flagged complete (covers the case where the user abandoned without
-- picking another).
local function DetectLiadrinChoice()
    if not (ns.char and C_QuestLog) then return end
    local pool = GetLiadrinPool()
    if not pool then return end

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader and pool[q.questID] then
            ns.char.liadrinChoice = q.questID
            return
        end
    end

    -- Not in active log. Keep the cached choice if it's flagged complete
    -- (the user completed it; we still want the "(X picked)" annotation
    -- next to the green checkmark). Otherwise it was abandoned — clear.
    local prev = ns.char.liadrinChoice
    if prev and not C_QuestLog.IsQuestFlaggedCompleted(prev) then
        ns.char.liadrinChoice = nil
    end
end

local function RefreshWeeklies()
    if not ns.char or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return
    end

    DetectLiadrinChoice()

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

-- Epoch of the most recent daily reset (drives bountiful-delve cache TTL).
-- Returns nil if the API isn't ready (rare, early-load).
local function CurrentDailyResetEpoch()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local s = C_DateAndTime.GetSecondsUntilDailyReset()
        if s and s > 0 then
            return time() + s - 86400
        end
    end
    return nil
end

-- Set of event names that the scheduler API currently knows about — either
-- in the Ongoing list, currently-firing Scheduled, or future Scheduled
-- within the cached window. Drives the "claimed today" detection heuristic.
local function CurrentSchedulerNames()
    local set = {}
    if not ns.Events then return set end
    for _, ev in ipairs(ns.Events.GetActive()) do
        if ev.name and (ev.source == "scheduler-ongoing"
                        or ev.source == "scheduler-scheduled") then
            set[ev.name] = true
        end
    end
    for _, ev in ipairs(ns.Events.GetUpcoming()) do
        if ev.name then set[ev.name] = true end
    end
    return set
end

-- Heuristic test: is this event entry presumed to be claimed today by the
-- current char?
--
--   ev.source == "map-event"  — comes via continent-map scan, not scheduler
--   ev.isTimed                — has a finite firing window, so it's a
--                                scheduler-eligible event (rules out Prey
--                                and other untimed continuous POIs)
--   not current[ev.name]      — scheduler is currently filtering it out
--
-- All three together: the scheduler stopped returning this scheduler-
-- eligible event for this char, but it's still visible on the world map.
-- That's the disappearance-as-completion signal Blizzard's API gives us.
--
-- Works cold (player logs in already-claimed) — the per-session cache
-- approach I tried before couldn't catch that case.
local function IsLikelyClaimed(ev, currentScheduler)
    return ev.source == "map-event"
       and ev.isTimed
       and ev.name
       and not currentScheduler[ev.name]
end

-- Reconcile char.bountifulSeen with the live Events list. Wipe on daily
-- reset; otherwise additive. Currently-visible bountifuls get cached so
-- they survive disappearing from the live list (the user-visible signal
-- for "this character completed this delve today").
--
-- Belt-and-suspenders: if the live list is non-empty but disjoint from the
-- cache, the rotation shifted independently of the daily clock (rare). Wipe
-- and rebuild rather than carrying yesterday's set forward.
local function UpdateBountifulSeen()
    if not ns.char then return end

    local reset = CurrentDailyResetEpoch()
    if reset and (ns.char.bountifulResetEpoch or 0) < reset then
        ns.char.bountifulSeen       = {}
        ns.char.bountifulResetEpoch = reset
    end
    ns.char.bountifulSeen = ns.char.bountifulSeen or {}

    local visible = ns.Events and ns.Events.GetBountifulDelves() or {}

    if #visible > 0 and next(ns.char.bountifulSeen) then
        local overlap = false
        for _, d in ipairs(visible) do
            if ns.char.bountifulSeen[d.areaPoiID] then overlap = true; break end
        end
        if not overlap then ns.char.bountifulSeen = {} end
    end

    for _, d in ipairs(visible) do
        if not ns.char.bountifulSeen[d.areaPoiID] then
            ns.char.bountifulSeen[d.areaPoiID] = {
                name      = d.name,
                atlasName = d.atlasName,
                mapID     = d.mapID,
            }
        end
    end
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
    local currentScheduler = CurrentSchedulerNames()
    local CHECK = "|A:common-icon-checkmark:14:14|a"

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

            -- Scheduler-filtered events surface via the continent-map
            -- branch with source="map-event". Heuristic: a timed map-event
            -- whose name isn't in the current scheduler view is presumed
            -- claimed today on this char. Works cold (no session cache).
            local isClaimed = IsLikelyClaimed(ev, currentScheduler)

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

            -- "Claimed today" override: dim the label + value, append the
            -- checkmark to the value. Player can still see the row (event
            -- is still playable for other rewards) but knows the per-event
            -- bonus is already collected for this char.
            if isClaimed then
                vr, vg, vb = 0.55, 0.85, 0.55  -- green, like a ✓ row
                valueText = CHECK .. " " .. valueText
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
    -- event scheduler. GetDelvesForMap filters out delves the current char
    -- has already completed today, so disappearance from the live list IS
    -- the completion signal — no per-Delve quest-ID tracking needed. We
    -- snapshot first-seen entries into char.bountifulSeen and render the
    -- union with ✓ marks for entries no longer visible.
    if SectionEnabled("delves") then
    local seen = ns.char and ns.char.bountifulSeen or {}
    local visible = ns.Events and ns.Events.GetBountifulDelves() or {}

    -- Visible set for fast "currently bountiful?" lookup.
    local visibleByID = {}
    for _, d in ipairs(visible) do visibleByID[d.areaPoiID] = true end

    -- Materialise the cache into a sorted row list. Entries in `seen` but not
    -- in `visible` are marked done.
    local rows = {}
    for poiID, d in pairs(seen) do
        rows[#rows + 1] = {
            poiID     = poiID,
            name      = d.name or "Delve",
            atlasName = d.atlasName,
            done      = not visibleByID[poiID],
        }
    end
    table.sort(rows, function(a, b)
        if a.done ~= b.done then return not a.done end  -- outstanding first
        return (a.name or "") < (b.name or "")
    end)

    if #rows > 0 then
        local CHECK = "|A:common-icon-checkmark:14:14|a"
        local CROSS = "|A:common-icon-redx:14:14|a"

        local doneCount = 0
        for _, r in ipairs(rows) do if r.done then doneCount = doneCount + 1 end end
        local total = #rows
        local sr, sg, sb = CV_r, CV_g, CV_b
        if doneCount == total then sr, sg, sb = 0.6, 0.6, 0.6 end

        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(
            "Bountiful Delves (today)",
            doneCount .. "/" .. total .. " done",
            CL_r, CL_g, CL_b, sr, sg, sb)

        for _, r in ipairs(rows) do
            local label = r.atlasName
                          and ("|A:" .. r.atlasName .. ":16:16|a " .. r.name)
                          or  r.name
            local valueText, lr, lg, lb, vr, vg, vb
            if r.done then
                valueText = CHECK
                lr, lg, lb = 0.55, 0.55, 0.55
                vr, vg, vb = 0.6, 0.6, 0.6
            else
                valueText = CROSS
                lr, lg, lb = CV_r, CV_g, CV_b
                vr, vg, vb = CH_r, CH_g, CH_b
            end
            GameTooltip:AddDoubleLine(label, valueText, lr, lg, lb, vr, vg, vb)
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
                local rowLabel = w.label
                -- Liadrin row: append "(X picked)" annotation when the
                -- current char has accepted (or completed) a pool member.
                if w.key == "liadrin"
                   and ns.char and ns.char.liadrinChoice
                   and ns.liadrinLabels then
                    local picked = ns.liadrinLabels[ns.char.liadrinChoice]
                    if picked then
                        rowLabel = rowLabel .. " (" .. picked .. " picked)"
                    end
                end
                rows[#rows + 1] = {
                    label = rowLabel,
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
                GameTooltip:AddDoubleLine(w.short or w.label,
                    done .. "/" .. activeCount .. " done",
                    CV_r, CV_g, CV_b, CV_r, CV_g, CV_b)
            end
        end
    end

    -- ── Interaction hints ─────────────────────────────────────────────────────
    -- Keyword in orange, description in white (matches Broker: Coords).
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("LeftClick",        "open events panel",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)
    GameTooltip:AddDoubleLine("RightClick",       "open settings",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)
    GameTooltip:AddDoubleLine("Shift-RightClick", "open alts panel",
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
    elseif button == "RightButton" then
        if IsShiftKeyDown() then
            if ns.AltsPanel and ns.AltsPanel.Toggle then
                ns.AltsPanel.Toggle()
            end
        elseif ns.settingsCategoryID then
            Settings.OpenToCategory(ns.settingsCategoryID)
        end
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
    if ns.AltsPanel and ns.AltsPanel.RefreshIfShown then
        ns.AltsPanel.RefreshIfShown()
    end
end)

-- Subscribe to Events module refreshes (server-pushed EVENT_SCHEDULER_UPDATE,
-- AREA_POIS_UPDATED for continuous map-only POIs, and PEW continent rediscovery).
if ns.Events and ns.Events.RegisterListener then
    ns.Events.RegisterListener(function()
        UpdateBountifulSeen()
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

-- Dev diagnostic: dump the raw C_EventScheduler view to chat so we can
-- diagnose "Upcoming shows only one entry" or "wrong event shown" issues
-- without round-tripping through SavedVariables.
SLASH_BMESCHED1 = "/mesched"
SlashCmdList.BMESCHED = function()
    if not C_EventScheduler then
        print("|cffffcc00MidnightEvents|r — C_EventScheduler unavailable")
        return
    end
    local ongoing   = C_EventScheduler.GetOngoingEvents   and C_EventScheduler.GetOngoingEvents()   or {}
    local scheduled = C_EventScheduler.GetScheduledEvents and C_EventScheduler.GetScheduledEvents() or {}
    print(string.format(
        "|cffffcc00MidnightEvents|r scheduler: ongoing=%d, scheduled=%d, hasData=%s, time=%d",
        #ongoing, #scheduled,
        tostring(C_EventScheduler.HasData and C_EventScheduler.HasData()),
        time()))
    local function resolveName(poiID)
        if not (C_EventScheduler.GetEventUiMapID and C_AreaPoiInfo
                and C_AreaPoiInfo.GetAreaPOIInfo) then return "?" end
        local mid = C_EventScheduler.GetEventUiMapID(poiID)
        if not mid then return "?" end
        local info = C_AreaPoiInfo.GetAreaPOIInfo(mid, poiID)
        return info and info.name or "?"
    end
    print("|cffffcc00Ongoing:|r")
    for i, ev in ipairs(ongoing) do
        print(string.format("  [%d] poi=%d  claimed=%s  %s",
            i, ev.areaPoiID, tostring(ev.rewardsClaimed), resolveName(ev.areaPoiID)))
    end
    print("|cffffcc00Scheduled (first 10):|r")
    for i = 1, math.min(10, #scheduled) do
        local ev = scheduled[i]
        local dt = (ev.startTime or 0) - time()
        local when = dt > 0 and string.format("+%dm", math.floor(dt / 60))
                            or string.format("-%dm (active until +%dm)",
                                math.floor(-dt / 60),
                                math.floor(((ev.endTime or 0) - time()) / 60))
        print(string.format("  [%d] poi=%d  start %s  %s",
            i, ev.areaPoiID, when, resolveName(ev.areaPoiID)))
    end
end
