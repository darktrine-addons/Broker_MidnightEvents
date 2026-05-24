-- Broker_MidnightEvents - Core
-- LDB data broker plugin: world event timers and weekly activity tracking for Midnight.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
-- The BigWigs packager substitutes @project-version@ at build time. In a raw
-- source checkout the literal placeholder reaches us instead; show "dev" so
-- the tooltip footer reads "v dev" rather than "v@project-version@".
if addonVersion:sub(1, 1) == "@" then addonVersion = "dev" end

local LDB = LibStub("LibDataBroker-1.1")
local broker = LDB:NewDataObject("Broker_MidnightEvents", {
    type  = "data source",
    label = "MidnightEvents",
    icon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    text  = "...",
})
ns.broker = broker  -- exposed for LibDBIcon registration in Settings.lua

-- ── private tooltip frame ────────────────────────────────────────────────────
-- 12.x's "addon apocalypse" protected-data model: reading values from
-- C_EventScheduler (startTime, endTime, secondsLeft) and doing arithmetic
-- on them taints our control flow. If we then write to the SHARED
-- GameTooltip, the tooltip itself becomes globally tainted — and every
-- subsequent Blizzard operation on GameTooltip (Hide, widget cleanup,
-- other addons' or Blizzard's own tooltips) inherits the taint, hitting
-- "attempt to compare a secret number value" errors deep in widget
-- layout code.
--
-- Containment: use a dedicated GameTooltipTemplate frame for our own UI.
-- Same look and AddLine/AddDoubleLine/atlas-inline behaviour as the
-- shared one, but Blizzard never touches it, so our taint stays scoped.
local Tooltip = CreateFrame("GameTooltip",
                            "BrokerMidnightEventsTooltip",
                            UIParent,
                            "GameTooltipTemplate")

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

-- ── progress cache ───────────────────────────────────────────────────────────
-- Background ticker that pulls each active event's progress percentage
-- once per interval and writes it to a plain Lua table. Render paths
-- (BuildTooltip, UpdateBrokerText, GetSoonest, FormatEventTag) read this
-- table — they never call C_UIWidgetManager themselves.
--
-- Why the indirection: 12.x's protected-data model treats StatusBar
-- barValue / barMax as secret. Any arithmetic on them taints the calling
-- execution context. If a render path does that arithmetic, the entire
-- frame's-worth of execution becomes tainted — and anything it touches
-- (the shared C_UIWidgetManager state, frame state propagated into
-- OnClick, etc.) inherits the taint, breaking unrelated Blizzard UI
-- (events panel widget tooltips, WorldMapFrame:HandleUserActionOpenQuestLog,
-- protected SetPassThroughButtons cascade).
--
-- By doing the arithmetic in a dedicated ticker context that ONLY writes
-- to a plain Lua table, the taint stays inside that one call and dies
-- when the callback returns. Render paths run untainted.
local progressCache = {}  -- areaPoiID → percent (plain number)

local function ProbeProgressForEvent(ev)
    if not (ev and C_UIWidgetManager
            and C_UIWidgetManager.GetAllWidgetsBySetID
            and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo) then
        return nil
    end
    local function probe(setID)
        if not setID then return nil end
        local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
        for _, w in ipairs(widgets) do
            if w.widgetType == 2 then  -- Enum.UIWidgetVisualizationType.StatusBar
                local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(w.widgetID)
                if info and info.barMax and info.barMax > 0 then
                    return (info.barValue or 0) / info.barMax * 100
                end
            end
        end
        return nil
    end
    -- Try POI's own widget sets first, then the per-POI override
    -- (Void Incursion 8718 → 2042; see ns.eventProgressWidgetSet in
    -- Data.lua), then the by-name override (so 8717 Zul'Aman / future
    -- zone variants share the same widget set without per-POI entries).
    local p = probe(ev.tooltipWidgetSet)
              or probe(ev.iconWidgetSet)
    if p then return p end
    local overrideSet = ev.areaPoiID and ns.eventProgressWidgetSet
                        and ns.eventProgressWidgetSet[ev.areaPoiID]
    p = probe(overrideSet)
    if p then return p end
    local nameSet = ev.name and ns.eventProgressWidgetSetByName
                    and ns.eventProgressWidgetSetByName[ev.name]
    return probe(nameSet)
end

-- Parse "Story Variant: <name>" out of a delve POI's tooltipWidgetSet.
-- Returns the story name (color-codes stripped) or nil if the set doesn't
-- expose a story-variant widget. Each bountiful delve POI carries one
-- TextWithState widget whose text starts with "Story Variant:" — the
-- color-coded portion is the daily-rotating story name.
local function ParseDelveStory(setID)
    if not (setID and C_UIWidgetManager
            and C_UIWidgetManager.GetAllWidgetsBySetID
            and C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo) then
        return nil
    end
    for _, w in ipairs(C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}) do
        if w.widgetType == 8 then  -- TextWithState
            local info = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo(w.widgetID)
            local text = info and info.text
            if text and text:find("Story Variant:", 1, true) then
                local body = text:match("Story Variant:%s*(.+)$")
                if body then
                    -- Strip Blizzard color escapes: |cnNAMED_COLOR:, |cffXXXXXX, |r
                    body = body:gsub("|c[nN][%w_]+:", "")
                               :gsub("|c%x+", "")
                               :gsub("|r", "")
                               :gsub("^%s+", "")
                               :gsub("%s+$", "")
                    if body ~= "" then return body end
                end
            end
        end
    end
    return nil
end

-- activeStoryByDelve: delveName → storyName. Populated by the same ticker
-- that drives event progress (RefreshProgressCache below) so widget reads
-- stay inside the taint-isolated ticker context.
local activeStoryByDelve = {}

-- Cheap Levenshtein distance between two strings; used by the delve-story
-- matcher below to tolerate single-character typos in Blizzard's widget
-- data versus their own achievement criterion text. Bounded input length
-- (~30 chars per story name) keeps the O(n*m) cost trivial.
local function levenshtein(a, b)
    if a == b then return 0 end
    if #a == 0 then return #b end
    if #b == 0 then return #a end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local curr = { [0] = i }
        local ach = a:sub(i, i)
        for j = 1, #b do
            local cost = (ach == b:sub(j, j)) and 0 or 1
            curr[j] = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = curr
    end
    return prev[#b]
end

-- Per-character completion lookup for a (delveName, storyName) pair.
-- Indexes into ns.delveStoryAchievement (Data.lua) to find the per-delve
-- sub-achievement, iterates its criteria, returns the completed boolean
-- of the criterion whose name matches the story variant.
--
-- Match policy: exact case-sensitive equality first, then fuzzy
-- (Levenshtein ≤ 2 against lowercased forms). The fuzzy fallback
-- absorbs Blizzard typos like "Captured Widlife" (in the widget) vs
-- "Captured Wildlife" (in the achievement criterion) — observed on
-- Shadowguard Point 2026-05-23. Two criteria per achievement have
-- always been visibly distinct, so a 2-edit allowance can't realistically
-- collide.
--
-- Returns nil when:
--   * The delve isn't in our achievement map
--   * The criteria aren't yet loaded (Blizzard lazy-loads per-achievement;
--     until the player has engaged with the delve's content,
--     GetAchievementCriteriaInfo returns nil → row renders grey)
--   * No criterion within the fuzzy threshold matches
local FUZZY_MATCH_THRESHOLD = 2
local function GetDelveStoryCompletion(delveName, storyName)
    if not (ns.delveStoryAchievement and GetAchievementCriteriaInfo) then
        return nil
    end
    local achievementID = ns.delveStoryAchievement[delveName]
    if not achievementID then return nil end
    local n = GetAchievementNumCriteria
              and GetAchievementNumCriteria(achievementID) or 3

    local lowerStory = storyName:lower()
    local bestDist, bestCompleted = FUZZY_MATCH_THRESHOLD + 1, nil
    for i = 1, n do
        local criteriaString, _, completed = GetAchievementCriteriaInfo(achievementID, i)
        if criteriaString then
            if criteriaString == storyName then
                return completed
            end
            local d = levenshtein(criteriaString:lower(), lowerStory)
            if d < bestDist then
                bestDist, bestCompleted = d, completed
            end
        end
    end
    if bestDist <= FUZZY_MATCH_THRESHOLD then
        return bestCompleted
    end
    return nil
end

-- Probe a Voidforge-style widget set (Data.lua's ns.charProgress entries):
-- one StatusBar widget per set, exposing barValue + barMax. Returns
-- (value, max) or nil when the widget set isn't currently registered
-- (i.e. player isn't near enough Decimus for the live data).
local function ProbeCharProgressWidget(setID)
    if not (setID and C_UIWidgetManager
            and C_UIWidgetManager.GetAllWidgetsBySetID
            and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo) then
        return nil
    end
    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
    for _, w in ipairs(widgets) do
        if w.widgetType == 2 then
            local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(w.widgetID)
            if info and info.barMax and info.barMax > 0 then
                return info.barValue, info.barMax
            end
        end
    end
    return nil
end

-- Periodically rebuild the progressCache from active events AND refresh
-- per-character Voidforge progress. Runs in its own ticker context —
-- the barValue arithmetic taints this call's context only, and writes
-- go to plain Lua tables (no shared frame state).
local function RefreshProgressCache()
    if not ns.Events then return end
    local fresh = {}
    for _, ev in ipairs(ns.Events.GetActive() or {}) do
        if ev.areaPoiID then
            local pct = ProbeProgressForEvent(ev)
            if pct then fresh[ev.areaPoiID] = pct end
        end
    end
    progressCache = fresh

    -- Voidforge: only updates when player is near Decimus. When the
    -- probe returns nil, we leave the existing per-char cache untouched
    -- so the last-observed value stays visible in the tooltip.
    if ns.char and ns.charProgress then
        ns.char.voidforge = ns.char.voidforge or {}
        for _, entry in ipairs(ns.charProgress) do
            local v, m = ProbeCharProgressWidget(entry.widgetSetID)
            if v and m then
                ns.char.voidforge[entry.key] = {
                    value = v, max = m, seenAt = time(),
                }
            end
        end
    end

    -- Delve story variants: parse the bountiful delves' tooltipWidgetSet
    -- for the daily-rotating story name. Indexed by delve name (matches
    -- across continent and zone POIs for the same delve). Completion
    -- status is queried at render time from the achievement criteria.
    local stories = {}
    for _, b in ipairs(ns.Events.GetBountifulDelves() or {}) do
        if b.name and b.tooltipWidgetSet then
            local story = ParseDelveStory(b.tooltipWidgetSet)
            if story then stories[b.name] = story end
        end
    end
    activeStoryByDelve = stories
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(2, RefreshProgressCache)
end

-- Cache reader for render paths. Returns the percentage (plain number) or
-- nil. No widget-API call, no arithmetic on secret values — safe to call
-- from any rendering or click path without tainting.
local function GetEventProgressPct(ev)
    return ev and ev.areaPoiID and progressCache[ev.areaPoiID] or nil
end

-- Derive remaining seconds + a state tag for an event entry from ns.Events.
-- Prefers epoch fields (startTime/endTime) over server-snapshot secondsLeft
-- so countdowns decrement live between Events refreshes.
--   "upcoming" — future fire. secs = time-until-fire.
--                For scheduler-scheduled entries: endTime is the fire time
--                (not "active until"); startTime is a pre-fire schedule
--                lock-in timestamp that can be in the past. We always treat
--                source="scheduler-scheduled" as upcoming with endTime as
--                the fire time.
--                For other sources: startTime > now → fire at startTime.
--   "active"   — currently firing (map-event POIs with secondsLeft, or
--                scheduler-ongoing with an endTime — though ongoing
--                entries typically lack one).
--   "wave"     — continuously-ongoing POI with an internal wave cadence
--                (Stormarion Assault); secs = wall-clock seconds to next wave
--   "ongoing"  — untimed and no cadence override (Legends); secs = nil
local function EventRemaining(ev, now)
    if ev.source == "scheduler-scheduled"
       and ev.endTime and ev.endTime > now then
        return ev.endTime - now, "upcoming"
    end
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

-- Detect rows whose tracking quest is in the active log with all
-- objectives complete (i.e. ready for the player to walk to the NPC and
-- hand in). Distinct from IsWeeklySlotDone, which checks the post-
-- turn-in flagged-complete state.
--
-- For single-questID rows, query directly. For `picks` rows (Liadrin /
-- Bonus Event / Void Assault zone), use the cached active pick so we
-- check only the relevant pool member rather than walking all of them
-- — keeps the check exact and skips any pool member that's been
-- abandoned. For non-picks multi-questID rows, fall back to "any pool
-- member is ready" since they're mutually exclusive by design.
local function IsWeeklyReadyForTurnIn(w)
    if not C_QuestLog or not C_QuestLog.ReadyForTurnIn then return false end
    if w.questID then
        return C_QuestLog.ReadyForTurnIn(w.questID) or false
    end
    if w.picks and ns.char and ns.char.picks then
        local picked = ns.char.picks[w.key]
        if picked then
            return C_QuestLog.ReadyForTurnIn(picked) or false
        end
        return false
    end
    if w.questIDs then
        for _, qid in ipairs(w.questIDs) do
            if C_QuestLog.ReadyForTurnIn(qid) then return true end
        end
    end
    return false
end

-- Detect which pool member the current char has accepted (or completed)
-- this week for every ns.weeklies entry with a `picks` map. Stored on
-- ns.char.picks[<key>] = questID; the tooltip then looks up
-- weeklyEntry.picks[questID] for the human-friendly annotation.
--
-- Detection has two reliable signals:
--   1. Active quest log scan — definitive. If a pool member is in the
--      log right now, that's the pick.
--   2. Cached-and-still-flagged preservation — covers the post-turn-in
--      window. Once a pick is established by signal #1 and the quest
--      gets turned in, the quest leaves the log but its completion
--      flag stays true. Keep the cached pick across that transition.
--
-- We *deliberately do not* fall back to "any pool member flagged
-- complete" — verified 2026-05-24 on Artherio that all 9 Liadrin pool
-- member quest IDs (93769, 93889, 93890, 93892, 93909, 93910, 93911,
-- 94457, 95842) returned IsQuestFlaggedCompleted = true at once. The
-- flags are achievement-style and persist across weekly resets, so
-- "any flagged" is meaningless once a player has rotated through
-- multiple Liadrin picks over the season. Better to show no
-- annotation than to guess wrong.
--
-- Cold-start consequence: a character who completed a Liadrin pick
-- before the feature was deployed AND never opens the addon while
-- the quest is in their log will display the row as done (the slot's
-- own IsWeeklySlotDone signal) but without the "(<choice> picked)"
-- annotation. Acceptable — the completion state is what matters.
local function DetectWeeklyPicks()
    if not (ns.char and C_QuestLog) then return end
    ns.char.picks = ns.char.picks or {}

    -- Pass 1: active quest log (definitive).
    local pickedNow = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader and q.questID then
            for _, w in ipairs(ns.weeklies or {}) do
                if w.picks and w.picks[q.questID] then
                    pickedNow[w.key] = q.questID
                end
            end
        end
    end

    -- Write through with cache preservation: if pass 1 found nothing
    -- for an entry, keep the existing cached pick IFF its flag is
    -- still true (post-turn-in case). Otherwise clear.
    for _, w in ipairs(ns.weeklies or {}) do
        if w.picks then
            if pickedNow[w.key] then
                ns.char.picks[w.key] = pickedNow[w.key]
            else
                local prev = ns.char.picks[w.key]
                if not (prev and C_QuestLog.IsQuestFlaggedCompleted(prev)) then
                    ns.char.picks[w.key] = nil
                end
            end
        end
    end
end

local function RefreshWeeklies()
    if not ns.char or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return
    end

    DetectWeeklyPicks()

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

-- Walk active + upcoming events and pick the row to surface in the broker
-- bar. Priority:
--   1. Any event whose firing heuristic (Data.lua's ns.eventFiringHeuristic)
--      reports it as firing right now. Highest player value — "rush to this
--      NOW" beats every countdown.
--   2. Smallest urgency-seconds across active + upcoming, where active rows
--      with a progress widget contribute synthetic seconds (100-pct)*60.
--      Mirrors the tooltip Now-section sort: a 97% Impending Void Incursion
--      (synthetic 3 min) wins over a real 19-min countdown.
--   3. Fallback to first untimed active event ("ongoing") when nothing has
--      a countdown.
local function GetSoonest()
    if not ns.Events then return nil end
    local now = time()

    local active = ns.Events.GetActive()
    if ns.IsEventFiring then
        for _, ev in ipairs(active) do
            local progPct = GetEventProgressPct(ev)
            if ns.IsEventFiring(ev, progPct) then
                return ev, nil, "firing"
            end
        end
    end

    local soonest, soonestSecs, soonestKind
    local function consider(ev, secs, kind)
        if secs and (not soonestSecs or secs < soonestSecs) then
            soonest, soonestSecs, soonestKind = ev, secs, kind
        end
    end
    for _, ev in ipairs(active) do
        local secs, kind = EventRemaining(ev, now)
        local progPct = GetEventProgressPct(ev)
        if progPct then
            local pctSecs = math.max(0, (100 - progPct) * 60)
            if not secs or pctSecs < secs then
                secs, kind = pctSecs, "building"
            end
        end
        consider(ev, secs, kind)
    end
    for _, ev in ipairs(ns.Events.GetUpcoming(24 * 3600)) do
        local secs, kind = EventRemaining(ev, now)
        consider(ev, secs, kind)
    end
    if not soonest and active[1] then
        soonest, soonestSecs, soonestKind = active[1], nil, "ongoing"
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

-- Reconcile char.bountifulSeen with the live Events list. Wipe on daily
-- reset; otherwise additive. Currently-visible bountifuls get cached so
-- they survive disappearing from the live list (the user-visible signal
-- for "this character completed this delve today").
--
-- Defense in depth:
--   1. Per-reset bulk wipe (primary mechanism)
--   2. Per-entry seenAt timestamp + stale-entry filter — entries with
--      seenAt before the current daily reset get dropped (catches edge
--      cases where the bulk wipe missed, e.g. CurrentDailyResetEpoch
--      returning nil during early-load)
--   3. Settling-window write skip: at the daily reset moment,
--      GetDelvesForMap briefly returns BOTH yesterday's outgoing rotation
--      AND today's incoming rotation in a single snapshot (observed
--      Shatanaris 2026-05-15: 7 entries captured at reset+49s, where the
--      daily cap is 4). For RESET_SETTLING_SEC after reset we skip cache
--      writes entirely, letting the API settle before we trust it. Cache
--      entries already in the table from prior sessions persist; they'll
--      be cleaned at the next daily-reset bulk wipe. Forward-only fix —
--      no retroactive cleanup of polluted state.
--   4. Disjoint-set check: if the live list is non-empty but disjoint
--      from the cache, the rotation shifted independently of the daily
--      clock. Wipe and rebuild rather than carrying yesterday's set forward.
local RESET_SETTLING_SEC = 300

local function UpdateBountifulSeen()
    if not ns.char then return end

    local reset = CurrentDailyResetEpoch()
    if reset and (ns.char.bountifulResetEpoch or 0) < reset then
        ns.char.bountifulSeen       = {}
        ns.char.bountifulResetEpoch = reset
    end
    ns.char.bountifulSeen = ns.char.bountifulSeen or {}

    if reset then
        for poiID, d in pairs(ns.char.bountifulSeen) do
            if not d.seenAt or d.seenAt < reset then
                ns.char.bountifulSeen[poiID] = nil
            end
        end
    end

    local visible = ns.Events and ns.Events.GetBountifulDelves() or {}

    if #visible > 0 and next(ns.char.bountifulSeen) then
        local overlap = false
        for _, d in ipairs(visible) do
            if ns.char.bountifulSeen[d.areaPoiID] then overlap = true; break end
        end
        if not overlap then ns.char.bountifulSeen = {} end
    end

    -- Settling-window write skip: don't add new entries within the first
    -- RESET_SETTLING_SEC after the daily reset — the API may still be
    -- returning a mix of yesterday's and today's rotations.
    local now = time()
    if reset and now < reset + RESET_SETTLING_SEC then
        return
    end

    for _, d in ipairs(visible) do
        if not ns.char.bountifulSeen[d.areaPoiID] then
            ns.char.bountifulSeen[d.areaPoiID] = {
                name      = d.name,
                atlasName = d.atlasName,
                mapID     = d.mapID,
                seenAt    = now,
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
    if kind == "firing" then
        return short .. " FIRING NOW!", true
    end
    if kind == "building" then
        -- Progress-driven entry; render the % rather than the synthetic
        -- countdown. Urgent flag at >=90% so the broker turns amber.
        local progPct = GetEventProgressPct(ev)
        local pct = progPct and math.floor(progPct) or 0
        return short .. " " .. pct .. "% built", (pct >= 90)
    end
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
    Tooltip:ClearLines()
    Tooltip:AddLine("Midnight Events", CV_r, CV_g, CV_b)

    local now = time()
    local CHECK = "|A:common-icon-checkmark:14:14|a"

    -- ── Section: Now ──────────────────────────────────────────────────────────
    -- Events currently firing (scheduler ongoing + currently-active scheduled
    -- + continuous map-event POIs). Sort: most-time-sensitive first.
    --
    --   1. Timed events expiring soonest (ascending by seconds-left)
    --   2. Wave countdowns (Stormarion's "next in Xm")
    --   3. Untimed "ongoing" continuous events (Stormarion when between
    --      waves, Legends of the Haranir) — always available, low urgency,
    --      sink to the bottom of the section.
    --
    -- The user's eye lands on the most urgent / expiring thing first; the
    -- always-on "go do it whenever" events stay visible but de-prioritised.
    if SectionEnabled("now") then
    Tooltip:AddLine(" ")
    Tooltip:AddLine("Now", CL_r, CL_g, CL_b)

    local active = ns.Events and ns.Events.GetActive() or {}
    if #active == 0 then
        Tooltip:AddLine("(no active events)", 0.5, 0.5, 0.5)
    else
        -- LONG_TIMER_CAP (12h): render long timers as untimed "active"
        -- instead of multi-day countdowns. Catches Void Incursion / Rift
        -- variants whose map-POI secondsLeft is time-until-weekly-reset,
        -- and any scheduler entry that snuck into active with a multi-day
        -- duration. Legit Abundance fire windows (up to 8h) stay timed.
        local LONG_TIMER_CAP = 12 * 3600
        local function isLongTimer(ev, secs)
            return secs and secs > LONG_TIMER_CAP
        end

        -- Pre-compute remaining + kind + progress so we can sort, then
        -- render. Locked POIs without extractable progress are skipped —
        -- they're genuinely unavailable (not "building up").
        local rows = {}
        for _, ev in ipairs(active) do
            local secs, kind = EventRemaining(ev, now)
            local progPct = GetEventProgressPct(ev)
            local firing = ns.IsEventFiring
                           and ns.IsEventFiring(ev, progPct)
            if isLongTimer(ev, secs) then
                secs, kind = nil, "ongoing"
            end
            local skip = ev.isLocked and not progPct
            if not skip then
                rows[#rows + 1] = {
                    ev = ev, secs = secs, kind = kind,
                    progPct = progPct, firing = firing,
                }
            end
        end
        -- Sort key:
        --   - Firing events → -1 (pinned to the very top, ahead of every
        --     countdown — they have a name to live up to).
        --   - Events with progress → (100 - pct) * 60 synthetic seconds,
        --     putting a 94% event near a 6-min countdown.
        --   - Untimed "ongoing" continuous events → math.huge (bottom).
        --   - Everything else → seconds-left ascending.
        local function sortKey(r)
            if r.firing then return -1 end
            if r.progPct then
                return math.max(0, (100 - r.progPct) * 60)
            end
            if r.kind == "ongoing" or not r.secs then return math.huge end
            return r.secs
        end
        table.sort(rows, function(a, b)
            local ka, kb = sortKey(a), sortKey(b)
            if ka == kb then return (a.ev.name or "") < (b.ev.name or "") end
            return ka < kb
        end)

        for _, r in ipairs(rows) do
            local ev      = r.ev
            local secs    = r.secs
            local kind    = r.kind
            local progPct = r.progPct
            local firing  = r.firing
            local atlas = ev.atlasName
            local label = atlas
                          and ("|A:" .. atlas .. ":16:16|a " .. (ev.name or "Event"))
                          or  (ev.name or "Event")

            local valueText, vr, vg, vb
            if firing then
                -- Empirical firing detector (see ns.eventFiringHeuristic
                -- in Data.lua). Highest-urgency rendering: amber + caps to
                -- pull the eye. Player should rush to the POI.
                valueText, vr, vg, vb = "FIRING NOW!", CH_r, CH_g, CH_b
            elseif progPct then
                -- Progress bar available (Void Incursion build cycle, etc.).
                -- Render the fill % regardless of isLocked — the bar keeps
                -- meaning post-firing as the countdown to next firing.
                --   ≥ 90%   urgent amber — about to fire, get there
                --   ≥ 50%   white       — meaningful progress
                --   <  50%  dim cyan    — visible but low-priority
                valueText = string.format("%d%% built", math.floor(progPct))
                if progPct >= 90 then
                    vr, vg, vb = CH_r, CH_g, CH_b
                elseif progPct >= 50 then
                    vr, vg, vb = CV_r, CV_g, CV_b
                else
                    vr, vg, vb = 0.65, 0.75, 0.95
                end
            elseif kind == "ongoing" then
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

            Tooltip:AddDoubleLine(label, valueText, CV_r, CV_g, CV_b, vr, vg, vb)
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
        Tooltip:AddLine(" ")
        Tooltip:AddLine("Upcoming (next 24h)", CL_r, CL_g, CL_b)
        for _, ev in ipairs(upcoming) do
            local secs  = (ev.endTime or ev.startTime or 0) - now
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
            Tooltip:AddDoubleLine(label, valueText, CV_r, CV_g, CV_b, vr, vg, vb)
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

        Tooltip:AddLine(" ")
        Tooltip:AddDoubleLine(
            "Bountiful Delves (today)",
            doneCount .. "/" .. total .. " done",
            CL_r, CL_g, CL_b, sr, sg, sb)

        for _, r in ipairs(rows) do
            local label = r.atlasName
                          and ("|A:" .. r.atlasName .. ":16:16|a " .. r.name)
                          or  r.name
            -- Annotate with today's active story variant for this delve.
            -- Active story comes from the ticker-populated activeStoryByDelve;
            -- per-character completion is looked up against the matching
            -- achievement criterion at render time (cheap, no taint).
            local story = activeStoryByDelve[r.name]
            if story then
                local completed = GetDelveStoryCompletion(r.name, story)
                local color, prefix
                if completed == true then
                    -- Atlas icon renders cleanly; Unicode ✓ falls back to a
                    -- glyph square in WoW's default font.
                    color  = "55cc55"
                    prefix = "|A:common-icon-checkmark:12:12|a "
                elseif completed == false then
                    color, prefix = "ddbb88", ""
                else
                    color, prefix = "909090", ""  -- unknown (criteria not loaded yet)
                end
                label = label .. " |cff" .. color .. "(" .. prefix .. story .. ")|r"
            end
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
            Tooltip:AddDoubleLine(label, valueText, lr, lg, lb, vr, vg, vb)
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
                -- Annotation color hierarchy:
                --   * Row name (white, set by AddDoubleLine) — the
                --     actionable label
                --   * Static hint + dynamic-annotation text + parens
                --     (grey #909090) — context / disambiguation, fades
                --     so the row name reads first
                --   * Progress N/M (warm gold #d9c97f) — variable data
                --     the eye should land on within the grey
                --
                -- Per-row annotation rules:
                --   * `picks` present + picksFormat="zoneOnly" → grey
                --     "(<zone>)" — voidAssaultZone
                --   * `picks` present (default) → grey "(<choice> picked"
                --     + gold ", N/M" (when active quest has >1 unfinished
                --     objective) + grey ")" — Liadrin / Bonus Event
                --   * else `hint` present → grey "(<hint>)" — static
                --     disambiguation for opaque weekly names
                --     (Stand Your Ground → Stormarion Assault, etc.)
                local DIM_OPEN  = "|cff909090"
                local PROG_OPEN = "|cffd9c97f"
                local CLOSE     = "|r"

                local pickedID = w.picks and ns.char and ns.char.picks
                                 and ns.char.picks[w.key]
                local pickedLabel = pickedID and w.picks[pickedID]

                if pickedLabel then
                    if w.picksFormat == "zoneOnly" then
                        rowLabel = rowLabel .. " "
                                   .. DIM_OPEN .. "(" .. pickedLabel .. ")" .. CLOSE
                    else
                        local body = pickedLabel .. " picked"
                        local progSeg = ""
                        if C_QuestLog and C_QuestLog.GetQuestObjectives then
                            local objs = C_QuestLog.GetQuestObjectives(pickedID)
                            if objs and objs[1]
                               and not objs[1].finished
                               and objs[1].numRequired and objs[1].numRequired > 1 then
                                progSeg = ", " .. CLOSE .. PROG_OPEN
                                          .. (objs[1].numFulfilled or 0)
                                          .. "/" .. objs[1].numRequired
                                          .. CLOSE .. DIM_OPEN
                            end
                        end
                        rowLabel = rowLabel .. " "
                                   .. DIM_OPEN .. "(" .. body .. progSeg .. ")" .. CLOSE
                    end
                elseif w.hint then
                    rowLabel = rowLabel .. " "
                               .. DIM_OPEN .. "(" .. w.hint .. ")" .. CLOSE
                end
                rows[#rows + 1] = {
                    label          = rowLabel,
                    done           = weeklyState[w.key] or false,
                    readyForTurnIn = IsWeeklyReadyForTurnIn(w),
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
        Tooltip:AddLine(" ")
        Tooltip:AddDoubleLine("This Week (" .. charName .. ")", summary,
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
            elseif r.readyForTurnIn then
                -- Objectives are met but the player hasn't formally handed
                -- the quest in yet. Render in amber to draw attention —
                -- the row LOOKS in-progress at first glance but a single
                -- NPC interaction would flip it to done.
                labelR, labelG, labelB = CV_r, CV_g, CV_b
                valueText = "turn in!"
                vR, vG, vB = CH_r, CH_g, CH_b
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
            Tooltip:AddDoubleLine(r.label, valueText,
                labelR, labelG, labelB, vR, vG, vB)
        end
    end

    -- ── Section: Voidforge progress ──────────────────────────────────────────
    -- Per-character N/M progress rows for Decimus's Voidforge trackers
    -- (Voidcores transmuted, Nilhammer empowered). Three display states:
    --   1. Section disabled in settings → entirely hidden
    --   2. Voidforge not unlocked on this char → dim header + small
    --      explanatory line. Decimus's build chain is warband-wide; one
    --      character on the account needs to complete it.
    --   3. Unlocked but no cached data yet → header + prompt to visit
    --      Decimus so the widget probe can populate the cache.
    --   4. Unlocked + data present → normal N/M rows. Lifetime entries
    --      at completedAt render with a green ✓.
    --
    -- Unlock detection prefers the explicit quest flag (95268), with a
    -- "any observed widget data" fallback for alts whose warband-shared
    -- unlock isn't reflected in their quest log.
    if SectionEnabled("voidforge") and ns.charProgress then
        local unlocked = false
        if ns.voidforgeUnlockQuest and C_QuestLog
           and C_QuestLog.IsQuestFlaggedCompleted
           and C_QuestLog.IsQuestFlaggedCompleted(ns.voidforgeUnlockQuest) then
            unlocked = true
        elseif ns.char and ns.char.voidforge and next(ns.char.voidforge) then
            unlocked = true
        end

        Tooltip:AddLine(" ")
        if not unlocked then
            Tooltip:AddLine("Voidforge progress", 0.28, 0.45, 0.45)
            Tooltip:AddLine(
                "  Not unlocked. Complete Decimus's quest series on one character.",
                0.50, 0.50, 0.50)
        else
            Tooltip:AddLine("Voidforge progress", CL_r, CL_g, CL_b)
            local rows = {}
            if ns.char and ns.char.voidforge then
                for _, entry in ipairs(ns.charProgress) do
                    local p = ns.char.voidforge[entry.key]
                    if p then rows[#rows + 1] = { entry = entry, p = p } end
                end
            end
            if #rows == 0 then
                Tooltip:AddLine(
                    "  Visit Decimus in Voidstorm to populate.",
                    0.55, 0.55, 0.55)
            else
                for _, r in ipairs(rows) do
                    local label = r.entry.label
                    if r.entry.hint then
                        label = label .. " |cff707070(" .. r.entry.hint .. ")|r"
                    end
                    local valueStr = r.p.value .. "/" .. r.p.max
                    local done = r.entry.completedAt
                                 and r.p.value >= r.entry.completedAt
                    local lr, lg, lb = CV_r, CV_g, CV_b
                    local vr, vg, vb = CV_r, CV_g, CV_b
                    if done then
                        lr, lg, lb = 0.55, 0.55, 0.55
                        vr, vg, vb = 0.55, 0.85, 0.55
                        valueStr   = CHECK .. " " .. valueStr
                    end
                    Tooltip:AddDoubleLine(label, valueStr, lr, lg, lb, vr, vg, vb)
                end
            end
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
            Tooltip:AddLine(" ")
            Tooltip:AddLine(
                "Alts (" .. trackedCount .. " tracked, "
                .. activeCount .. " active this reset)",
                CL_r, CL_g, CL_b)

            if not ns.db or ns.db.showWorldBosses ~= false then
                Tooltip:AddDoubleLine("World Boss",
                    wbDoneCount .. "/" .. activeCount .. " done",
                    CV_r, CV_g, CV_b, CV_r, CV_g, CV_b)
            end

            for _, w in ipairs(ns.weeklies or {}) do
                local done = weeklyDoneCount[w.key] or 0
                Tooltip:AddDoubleLine(w.label or w.short,
                    done .. "/" .. activeCount .. " done",
                    CV_r, CV_g, CV_b, CV_r, CV_g, CV_b)
            end
        end
    end

    -- ── Interaction hints ─────────────────────────────────────────────────────
    -- Keyword in orange, description in white (matches Broker: Coords).
    Tooltip:AddLine(" ")
    Tooltip:AddDoubleLine("LeftClick",        "open events panel",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)
    Tooltip:AddDoubleLine("RightClick",       "open settings",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)
    Tooltip:AddDoubleLine("Shift-RightClick", "open alts panel",
                              CH_r, CH_g, CH_b, CV_r, CV_g, CV_b)

    -- ── Footer ────────────────────────────────────────────────────────────────
    Tooltip:AddLine(" ")
    Tooltip:AddDoubleLine("", "Broker: MidnightEvents " .. addonVersion,
                              0, 0, 0, 0.45, 0.45, 0.45)
    Tooltip:Show()
end

broker.OnEnter = function(self)
    tooltipOwner = self
    local _, frameY = self:GetCenter()
    Tooltip:SetOwner(self, "ANCHOR_NONE")
    if frameY and frameY > (GetScreenHeight() / 2) then
        Tooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
    else
        Tooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT")
    end
    BuildTooltip()
end

broker.OnLeave = function(self)
    tooltipOwner = nil
    Tooltip:Hide()
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
    if tooltipOwner and Tooltip:IsOwned(tooltipOwner) then
        BuildTooltip()
    end
end

-- ── event frame ───────────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")

-- Session-local map of recent turn-in timestamps per questID. Used by the
-- QUEST_REMOVED handler to distinguish "removed via turn-in" (preserve
-- cached pick) from "removed via abandon" (clear cached pick). Why we
-- need this: IsQuestFlaggedCompleted is unreliable as the discriminator
-- because Liadrin pool members flag permanently on first completion
-- (see [[wow-isquestflaggedcompleted-lifetime]]) — a player who abandons
-- a re-accepted pool member they've completed in any prior week would
-- look identical to a fresh turn-in via the flag alone.
local recentTurnIn = {}
local TURNIN_WINDOW = 5  -- seconds — QUEST_REMOVED fires right after QUEST_TURNED_IN

-- Clear any cached `picks` entries pointing at this quest, used when we
-- detect an abandon. The cached pool member is no longer the player's
-- current pick — wiping it lets DetectWeeklyPicks's pass-1 active-log
-- scan re-establish a fresh pick if/when the player accepts another.
local function ClearPicksMatching(questID)
    if not (ns.char and ns.char.picks) then return end
    for key, qid in pairs(ns.char.picks) do
        if qid == questID then ns.char.picks[key] = nil end
    end
end

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "QUEST_TURNED_IN" and arg1 then
        recentTurnIn[arg1] = GetTime()
    elseif event == "QUEST_REMOVED" and arg1 then
        local ts = recentTurnIn[arg1]
        if ts and (GetTime() - ts) <= TURNIN_WINDOW then
            -- Paired with a recent QUEST_TURNED_IN: the quest left the
            -- log via successful turn-in. Cache preserved by RefreshWeeklies
            -- below (the cached value remains flagged-complete).
            recentTurnIn[arg1] = nil
        else
            -- Bare QUEST_REMOVED = abandon. Drop the cached pick.
            ClearPicksMatching(arg1)
        end
    end
    if event == "PLAYER_ENTERING_WORLD"
       or event == "QUEST_TURNED_IN"
       or event == "QUEST_REMOVED" then
        RefreshWeeklies()
    end
    UpdateBrokerText()
    if tooltipOwner and Tooltip:IsOwned(tooltipOwner) then
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
        if tooltipOwner and Tooltip:IsOwned(tooltipOwner) then
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
        if tooltipOwner and Tooltip:IsOwned(tooltipOwner) then
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

-- Dev diagnostic: dump every widget in a UIWidgetSet, with the type-specific
-- visualization-info call for each. Used to figure out what fields a given
-- event's tooltipWidgetSet exposes (Impending Void Incursion progress %,
-- Stormarion wave counter, Abundance Shards counter, etc.) so the right
-- field can be wired into the Now-section rendering.
--
--   /mewidget 2042       — Impending Void Incursion
--   /mewidget 1795       — Stormarion Assault
--   /mewidget 1900       — Abundance variants
--
-- Type table per Enum.UIWidgetVisualizationType.
local WIDGET_TYPE_NAMES = {
    [0]  = "IconAndText",
    [1]  = "CaptureBar",
    [2]  = "StatusBar",
    [3]  = "DoubleStatusBar",
    [4]  = "IconTextAndBackground",
    [5]  = "DoubleIconAndText",
    [6]  = "StackedResourceTracker",
    [7]  = "IconTextAndCurrencies",
    [8]  = "TextWithState",
    [9]  = "HorizontalCurrencies",
    [10] = "BulletTextList",
    [22] = "Spell",
    [27] = "TextColumnRow",
}

local WIDGET_INFO_FNS = C_UIWidgetManager and {
    [0]  = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo,
    [1]  = C_UIWidgetManager.GetCaptureBarWidgetVisualizationInfo,
    [2]  = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo,
    [3]  = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo,
    [4]  = C_UIWidgetManager.GetIconTextAndBackgroundWidgetVisualizationInfo,
    [5]  = C_UIWidgetManager.GetDoubleIconAndTextWidgetVisualizationInfo,
    [6]  = C_UIWidgetManager.GetStackedResourceTrackerWidgetVisualizationInfo,
    [7]  = C_UIWidgetManager.GetIconTextAndCurrenciesWidgetVisualizationInfo,
    [8]  = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo,
    [9]  = C_UIWidgetManager.GetHorizontalCurrenciesWidgetVisualizationInfo,
    [10] = C_UIWidgetManager.GetBulletTextListWidgetVisualizationInfo,
    [22] = C_UIWidgetManager.GetSpellDisplayVisualizationInfo,
    [27] = C_UIWidgetManager.GetTextColumnRowVisualizationInfo,
} or {}

-- Dev diagnostic: dump every event-atlas POI from the continent map AND from
-- each Midnight zone map, with the fields that decide whether Refresh() picks
-- it up. Used to figure out why a known-visible POI (e.g. Impending Void
-- Incursion) doesn't show in the Now section — typical causes are:
--   - POI is zone-scoped only; continent map's GetEventsForMap doesn't return
--     it (zone scans below WILL find it)
--   - atlas doesn't match ^ui-eventpoi- so LooksLikeEventAtlas filters it
--   - isCurrentEvent is false even though the POI is rendered
local MIDNIGHT_ZONE_IDS = { 2395, 2405, 2413, 2437, 2424, 2393 }

SLASH_BMEPOIS1 = "/mepois"
SlashCmdList.BMEPOIS = function()
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap
            and C_AreaPoiInfo.GetAreaPOIInfo) then
        print("|cffffcc00MidnightEvents|r — C_AreaPoiInfo unavailable")
        return
    end
    local continentMapID = ns.Events and ns.Events.GetContinentMapID() or 2537
    local function dumpMap(mapID, label)
        local ids = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
        print(string.format("|cffffcc00MidnightEvents|r %s map=%d  events=%d",
            label, mapID, #ids))
        for _, poiID in ipairs(ids) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info then
                local timed = C_AreaPoiInfo.IsAreaPOITimed
                              and C_AreaPoiInfo.IsAreaPOITimed(poiID) or false
                print(string.format(
                    "  poi=%d  cur=%s lock=%s timed=%s  atlas=%s  name=%s  tws=%s iws=%s",
                    poiID,
                    tostring(info.isCurrentEvent), tostring(info.isLocked),
                    tostring(timed),
                    tostring(info.atlasName), tostring(info.name),
                    tostring(info.tooltipWidgetSet),
                    tostring(info.iconWidgetSet)))
            else
                print(string.format("  poi=%d  (no info)", poiID))
            end
        end
    end
    dumpMap(continentMapID, "continent")
    for _, mid in ipairs(MIDNIGHT_ZONE_IDS) do
        dumpMap(mid, "zone")
    end
end

-- Dev diagnostic: capture EVERY relevant API output to SavedVariables in a
-- single call. Designed to skip the chat-paste round-trip — user copies the
-- relevant block out of Broker_MidnightEvents.lua in the SV directory and
-- shares the file content. Overwrites previous dump on each invocation.
--
-- Writes to ns.db._diag (no TOC changes needed — Broker_MidnightEventsDB is
-- always declared). SavedVariables flush to disk on logout / /reload, so
-- the user MUST /reload (or log out) after /mediag for the file to update.
--
-- Captures:
--   * server time, daily/weekly reset countdowns, player map context
--   * C_EventScheduler: HasData + Ongoing + Scheduled with EVERY field
--     including displayInfo subfields, plus GetEventUiMapID per entry and
--     three name-resolution sources (live API, our cache, our hardcoded
--     fallback) so we can see exactly which path each entry resolves through
--   * C_AreaPoiInfo: continent + every Midnight zone, GetEventsForMap and
--     GetDelvesForMap, each POI's full GetAreaPOIInfo flattened plus
--     IsAreaPOITimed / GetAreaPOISecondsLeft
--   * C_UIWidgetManager: for every widget set referenced by any POI in the
--     map scan above PLUS every set in ns.eventProgressWidgetSet, dump the
--     full widget list with type-specific visualization info
--   * our addon's current view (ns.Events.GetActive / GetUpcoming)
--   * the lookup tables (ns.knownEventNames, ns.eventProgressWidgetSet,
--     ns.eventFiringHeuristic) so the analyst doesn't have to cross-ref
local function flattenTable(t, depth)
    if type(t) ~= "table" then return t end
    depth = depth or 0
    if depth > 2 then return "<too deep>" end
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "table" then
            out[k] = flattenTable(v, depth + 1)
        elseif tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            out[k] = v
        end
    end
    return out
end

local function capturePoi(mapID, poiID)
    local info = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo
                 and C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID) or nil
    local out = { _mapID = mapID, _poiID = poiID }
    if info then
        for k, v in pairs(info) do
            local tv = type(v)
            if tv ~= "table" and tv ~= "function" and tv ~= "userdata" then
                out[k] = v
            end
        end
    else
        out._noInfo = true
    end
    if C_AreaPoiInfo and C_AreaPoiInfo.IsAreaPOITimed then
        out._isTimed = C_AreaPoiInfo.IsAreaPOITimed(poiID) or false
        if out._isTimed and C_AreaPoiInfo.GetAreaPOISecondsLeft then
            out._secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
        end
    end
    return out
end

local function captureSchedulerEntry(ev)
    local out = { _raw = flattenTable(ev) }
    out._uiMapID = C_EventScheduler and C_EventScheduler.GetEventUiMapID
                   and C_EventScheduler.GetEventUiMapID(ev.areaPoiID)
    out._zoneName = C_EventScheduler and C_EventScheduler.GetEventZoneName
                    and C_EventScheduler.GetEventZoneName(ev.areaPoiID)
    -- Resolution paths
    if out._uiMapID and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo then
        local info = C_AreaPoiInfo.GetAreaPOIInfo(out._uiMapID, ev.areaPoiID)
        out._liveName = info and info.name
        out._liveAtlas = info and info.atlasName
    end
    out._cacheName = (ns.db and ns.db.eventNameCache)
                     and ns.db.eventNameCache[ev.areaPoiID]
    out._knownEventName = ns.knownEventNames
                          and ns.knownEventNames[ev.areaPoiID]
    return out
end

local function captureWidgetSet(setID)
    local out = { setID = setID, widgets = {} }
    if not (C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) then
        return out
    end
    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
    out.count = #widgets
    for i, w in ipairs(widgets) do
        local infoFn = WIDGET_INFO_FNS[w.widgetType]
        local info = infoFn and infoFn(w.widgetID) or nil
        out.widgets[i] = {
            widgetID    = w.widgetID,
            widgetType  = w.widgetType,
            typeName    = WIDGET_TYPE_NAMES[w.widgetType],
            info        = info and flattenTable(info) or nil,
        }
    end
    return out
end

SLASH_BMEDIAG1 = "/mediag"
SlashCmdList.BMEDIAG = function()
    if not ns.db then
        print("|cffffcc00MidnightEvents|r — SV not yet initialized")
        return
    end

    local D = { _schemaVersion = 1, _capturedAt = time() }
    D.serverTime = GetServerTime and GetServerTime() or nil
    D.realmName  = GetRealmName and GetRealmName() or nil
    D.playerName = UnitName("player")
    D.playerMap  = C_Map and C_Map.GetBestMapForUnit
                   and C_Map.GetBestMapForUnit("player")
    D.continentMapID = ns.Events and ns.Events.GetContinentMapID()
    if C_DateAndTime then
        if C_DateAndTime.GetSecondsUntilDailyReset then
            D.secsUntilDailyReset = C_DateAndTime.GetSecondsUntilDailyReset()
        end
        if C_DateAndTime.GetSecondsUntilWeeklyReset then
            D.secsUntilWeeklyReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
        end
    end

    -- Scheduler
    D.scheduler = {}
    if C_EventScheduler then
        D.scheduler.hasData = C_EventScheduler.HasData
                              and C_EventScheduler.HasData() or false
        D.scheduler.ongoing = {}
        for i, ev in ipairs((C_EventScheduler.GetOngoingEvents and
                             C_EventScheduler.GetOngoingEvents()) or {}) do
            D.scheduler.ongoing[i] = captureSchedulerEntry(ev)
        end
        D.scheduler.scheduled = {}
        for i, ev in ipairs((C_EventScheduler.GetScheduledEvents and
                             C_EventScheduler.GetScheduledEvents()) or {}) do
            D.scheduler.scheduled[i] = captureSchedulerEntry(ev)
        end
    end

    -- Map POIs
    D.mapPois = {}
    local widgetSetSet = {}
    local function noteWS(s) if s then widgetSetSet[s] = true end end
    local function scanMap(mapID, label)
        local block = { mapID = mapID, label = label, events = {}, delves = {} }
        if C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap then
            for _, poiID in ipairs(C_AreaPoiInfo.GetEventsForMap(mapID) or {}) do
                local p = capturePoi(mapID, poiID)
                block.events[#block.events + 1] = p
                noteWS(p.tooltipWidgetSet); noteWS(p.iconWidgetSet)
            end
        end
        if C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap then
            for _, poiID in ipairs(C_AreaPoiInfo.GetDelvesForMap(mapID) or {}) do
                local p = capturePoi(mapID, poiID)
                block.delves[#block.delves + 1] = p
                noteWS(p.tooltipWidgetSet); noteWS(p.iconWidgetSet)
            end
        end
        return block
    end
    local continentMapID = D.continentMapID or 2537
    D.mapPois.continent = scanMap(continentMapID, "continent")
    D.mapPois.zones = {}
    for _, mid in ipairs(MIDNIGHT_ZONE_IDS) do
        D.mapPois.zones[#D.mapPois.zones + 1] = scanMap(mid, "zone")
    end

    -- Add any widget sets we have explicit overrides for
    if ns.eventProgressWidgetSet then
        for _, s in pairs(ns.eventProgressWidgetSet) do noteWS(s) end
    end
    -- And any referenced by scheduler entries' raw displayInfo
    for _, group in ipairs({ D.scheduler.ongoing or {}, D.scheduler.scheduled or {} }) do
        for _, e in ipairs(group) do
            local di = e._raw and e._raw.displayInfo
            if di then noteWS(di.overrideTooltipWidgetSetID) end
        end
    end

    -- Broader POI sweep: GetAreaPOIForMap returns ALL POIs for a map, not
    -- just events/delves. Catches Voidforge-style locations that have
    -- tooltipWidgetSet bars but aren't classified as event POIs.
    D.areaPois = {}
    if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then
        local function scanAreaPois(mapID, label)
            local block = { mapID = mapID, label = label, pois = {} }
            for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
                local p = capturePoi(mapID, poiID)
                block.pois[#block.pois + 1] = p
                noteWS(p.tooltipWidgetSet); noteWS(p.iconWidgetSet)
            end
            return block
        end
        D.areaPois.continent = scanAreaPois(continentMapID, "continent")
        D.areaPois.zones = {}
        for _, mid in ipairs(MIDNIGHT_ZONE_IDS) do
            D.areaPois.zones[#D.areaPois.zones + 1] = scanAreaPois(mid, "zone")
        end
    end

    -- Common widget container frames: many world widgets (top-center
    -- score bars, below-minimap timers, zone-specific progress overlays)
    -- live on these container frames rather than being attached to a POI.
    D.widgetContainers = {}
    for _, name in ipairs({
        "UIWidgetTopCenterContainerFrame",
        "UIWidgetBelowMinimapContainerFrame",
        "UIWidgetPowerBarContainerFrame",
        "UIWidgetTopRightCornerContainer",
        "UIWidgetBottomLeftContainerFrame",
    }) do
        local f = _G[name]
        if f then
            D.widgetContainers[name] = {
                widgetSetID = f.widgetSetID
                              or (f.GetRegisteredWidgetSetID
                                  and f:GetRegisteredWidgetSetID()),
                isShown = f.IsShown and f:IsShown(),
            }
            if D.widgetContainers[name].widgetSetID then
                noteWS(D.widgetContainers[name].widgetSetID)
            end
        end
    end

    -- Brute-force small-barMax StatusBar discovery. The visible Voidforge
    -- bars are "0/8" and "1/4" — barMax values < 20 are vanishingly rare
    -- across the global widget catalogue, so iterating set IDs and
    -- collecting StatusBar widgets with that signature pinpoints the set.
    -- Scan range tuned to cover Midnight-era widget set IDs (1000-3500);
    -- empty IDs return nil from GetAllWidgetsBySetID cheaply.
    D.smallBarFinds = {}
    if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID
       and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
        for setID = 1000, 3500 do
            local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
            for _, w in ipairs(widgets) do
                if w.widgetType == 2 then
                    local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(w.widgetID)
                    if info and info.barMax and info.barMax > 0 and info.barMax < 20 then
                        D.smallBarFinds[#D.smallBarFinds + 1] = {
                            setID    = setID,
                            widgetID = w.widgetID,
                            barMin   = info.barMin,
                            barMax   = info.barMax,
                            barValue = info.barValue,
                        }
                        noteWS(setID)
                    end
                end
            end
        end
    end

    D.widgetSets = {}
    for s in pairs(widgetSetSet) do
        D.widgetSets[s] = captureWidgetSet(s)
    end

    -- Addon's current view
    D.addonView = {}
    if ns.Events then
        D.addonView.active   = flattenTable(ns.Events.GetActive())
        D.addonView.upcoming = flattenTable(ns.Events.GetUpcoming())
        D.addonView.bountifulDelves = flattenTable(ns.Events.GetBountifulDelves())
    end

    -- Lookup tables in effect
    D.lookups = {
        knownEventNames        = flattenTable(ns.knownEventNames),
        eventProgressWidgetSet = flattenTable(ns.eventProgressWidgetSet),
        eventFiringHeuristic   = flattenTable(ns.eventFiringHeuristic),
        eventNameCache         = flattenTable(ns.db.eventNameCache),
    }

    ns.db._diag = D
    print(string.format(
        "|cffffcc00MidnightEvents|r diag captured: sched.ongoing=%d sched.scheduled=%d, "
        .. "continent.events=%d, zones=%d, widgetSets=%d, smallBarFinds=%d",
        #(D.scheduler.ongoing or {}),
        #(D.scheduler.scheduled or {}),
        #D.mapPois.continent.events,
        #D.mapPois.zones,
        (function() local n = 0 for _ in pairs(D.widgetSets) do n = n + 1 end return n end)(),
        #D.smallBarFinds))
    print("|cffffcc00MidnightEvents|r Run /reload (or log out) so SV flushes to disk.")
    print("|cffffcc00  File:|r WTF/Account/<ID>/SavedVariables/Broker_MidnightEvents.lua")
    print("|cffffcc00  Key:|r  Broker_MidnightEventsDB._diag")
end

SLASH_BMEWIDGET1 = "/mewidget"
SlashCmdList.BMEWIDGET = function(msg)
    if not C_UIWidgetManager then
        print("|cffffcc00MidnightEvents|r — C_UIWidgetManager unavailable")
        return
    end
    local setID = tonumber(msg and msg:match("(%d+)"))
    if not setID then
        print("|cffffcc00MidnightEvents|r usage: /mewidget <setID>")
        return
    end
    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
    print(string.format("|cffffcc00MidnightEvents|r widgetSet=%d, count=%d",
                        setID, #widgets))
    for i, w in ipairs(widgets) do
        local tname  = WIDGET_TYPE_NAMES[w.widgetType] or "?"
        local infoFn = WIDGET_INFO_FNS[w.widgetType]
        local info   = infoFn and infoFn(w.widgetID) or nil
        print(string.format("  [%d] id=%d type=%d (%s)%s",
            i, w.widgetID, w.widgetType, tname,
            info and "" or "  no-info-fn"))
        if type(info) == "table" then
            -- Dump useful scalar fields. Filter to the ones likely to carry
            -- progress/status data; skip texture / color tables to keep chat
            -- readable.
            local fields = { "text", "tooltip", "barMin", "barMax", "barValue",
                             "leftBarMin", "leftBarMax", "leftBarValue",
                             "rightBarMin", "rightBarMax", "rightBarValue",
                             "leftBarText", "rightBarText",
                             "iconValue", "fillMin", "fillMax", "fillValue",
                             "stateColor", "shownState", "enabledState",
                             "overrideBarText" }
            for _, k in ipairs(fields) do
                local v = info[k]
                if v ~= nil and type(v) ~= "table" then
                    print(string.format("       %s = %s", k, tostring(v)))
                end
            end
        end
    end
end
