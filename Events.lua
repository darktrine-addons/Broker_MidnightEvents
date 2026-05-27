-- Broker_MidnightEvents - Events
-- Single surface for live event timers. Combines C_EventScheduler (ongoing +
-- scheduled, server-pushed) with a continuous-POI scan via
-- C_AreaPoiInfo.GetEventsForMap on the active continent map (catches Prey
-- and other map-only event POIs not surfaced by the scheduler).
--
-- Read-only public API consumed by Core for broker text + tooltip. The
-- internal cache refreshes on PLAYER_ENTERING_WORLD, EVENT_SCHEDULER_UPDATE,
-- and AREA_POIS_UPDATED, then notifies registered listeners.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...
ns.Events = ns.Events or {}

-- Midnight (Quel'Thalas) continent uiMapID. Verified at runtime via parent-
-- map walk from the player's current map; this constant is a fallback for
-- when the walk fails (e.g. C_Map mid-init, unexpected map data).
local DEFAULT_CONTINENT_ID = 2537
local CONTINENT_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

-- Per-zone uiMapIDs used to warm POI metadata at login (see WarmZonePois).
-- Same set as Data.lua's harvest zones — kept inline here so Events.lua has
-- no dependency on the harvest code path (which is dev-only).
local MIDNIGHT_ZONES = { 2395, 2405, 2413, 2437, 2424, 2393 }

local state = {
    continentMapID  = DEFAULT_CONTINENT_ID,
    active          = {},  -- events firing now (scheduler ongoing + currently-firing scheduled + continuous map-event POIs)
    upcoming        = {},  -- scheduled events with startTime > now, sorted ascending
    bountifulDelves = {},  -- today's bountiful delves on the continent map
    lastUpdate      = 0,
}

local listeners = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Atlas filter for event POIs. Distinguishes events ("ui-eventpoi-*") from
-- delves ("delves-*"), world boss POIs ("worldquest-icon-boss"), etc.
-- Atlases observed in mixed case (e.g. "UI-EventPoi-stormarionassault" vs
-- "ui-eventpoi-hostileactivities") so the match is case-insensitive.
local function LooksLikeEventAtlas(atlas)
    return atlas and atlas:lower():find("^ui%-eventpoi%-") ~= nil
end

-- Widget-text timer fallback.
--
-- Some POIs (observed: Abundance: Mining Voidburrow, poiIDs 8675/8526) report
-- IsAreaPOITimed=true but GetAreaPOISecondsLeft=nil. The countdown the user
-- sees on the map tooltip is rendered from a TextWithState widget in the
-- POI's tooltipWidgetSet, as the plain string "Time Left: 6 Hr 8 Min".
--
-- Parse that string to recover seconds. enUS pattern; non-English locales
-- will miss the parse and the entry will continue to render as untimed
-- "active" (current behaviour, no regression). If we ever care about non-
-- English clients, swap to localized matches via GetLocale-keyed patterns.
-- Strip Blizzard chat-escape codes before parsing widget text.
--
-- Observed widget payload:
--   "|nTime Left: |cnHIGHLIGHT_FONT_COLOR:5 |4Hr:Hr; 58 |4Min:Min; |n"
--
-- Without stripping, `|4Hr:Hr;` (plural escape) contains a literal "4"
-- digit that the Hr-parser would lift as the hours value, producing a
-- frozen "4h 0m" regardless of the real countdown. Replace plural
-- escapes with their singular form so "Hr"/"Min" tokens remain intact
-- and the digits in front of them are the actual numbers.
local function StripEscapes(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("|n", " ")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|cn[%w_]+:", "")
    s = s:gsub("|r", "")
    s = s:gsub("|4([^:]+):[^;]*;", "%1")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    return s
end

-- Parse rendered countdown strings like "Time Left: 6 Hr 4 Min".
-- Uses %D- (non-digit, lazy) instead of %s* because Blizzard tends to inject
-- non-breaking spaces (U+00A0) in formatted time strings, and Lua's %s
-- class only matches ASCII whitespace. If Hr is present in the text we
-- require an Hr+Min parse and don't fall through to Min-only — otherwise
-- "6 Hr 4 Min" would silently degrade to "4m" when the joined parse fails.
local function ParseTimeLeftSeconds(text)
    text = StripEscapes(text)
    if type(text) ~= "string" then return nil end
    if text:find("[Hh]r") then
        local h, m = text:match("(%d+)%D-[Hh]r%D-(%d+)%D-[Mm]in")
        if h and m then return tonumber(h) * 3600 + tonumber(m) * 60 end
        local hOnly = text:match("(%d+)%D-[Hh]r")
        if hOnly then return tonumber(hOnly) * 3600 end
        return nil
    end
    local mOnly = text:match("(%d+)%D-[Mm]in")
    if mOnly then return tonumber(mOnly) * 60 end
    local sOnly = text:match("(%d+)%D-[Ss]ec")
    if sOnly then return tonumber(sOnly) end
    return nil
end

local function SecondsFromWidgetSet(setID)
    if not (setID and C_UIWidgetManager
            and C_UIWidgetManager.GetAllWidgetsBySetID) then
        return nil
    end
    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
    local getText = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo
    if not getText then return nil end
    for _, w in ipairs(widgets) do
        -- 8 = TextWithState. Read via the official getter rather than
        -- guessing the type id, in case the enum shifts in a future patch.
        local info = getText(w.widgetID)
        local secs = info and ParseTimeLeftSeconds(info.text)
        if secs then return secs end
    end
    return nil
end

local function FireChanged()
    for i = 1, #listeners do
        local ok, err = pcall(listeners[i])
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- Walk up parentMapID from the player's current map to find a Continent
-- ancestor. Returns the discovered ID, or DEFAULT_CONTINENT_ID on any
-- failure (no current map, mid-init, malformed map chain).
local function DiscoverContinent()
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetBestMapForUnit) then
        return DEFAULT_CONTINENT_ID
    end
    local cur = C_Map.GetBestMapForUnit("player")
    if not cur then return DEFAULT_CONTINENT_ID end
    local guard = 20
    while cur and guard > 0 do
        guard = guard - 1
        local info = C_Map.GetMapInfo(cur)
        if not info then return DEFAULT_CONTINENT_ID end
        if info.mapType == CONTINENT_TYPE then return cur end
        if not info.parentMapID or info.parentMapID == 0 then
            return DEFAULT_CONTINENT_ID
        end
        cur = info.parentMapID
    end
    return DEFAULT_CONTINENT_ID
end

-- Resolve a POI to a flat info table, applying any displayInfo overrides
-- from the scheduler (atlas swap, hidden description, alternate widget set
-- — mirrors Blizzard's EventScheduler.lua pattern).
--
-- Resilient to nil info from GetAreaPOIInfo: some scheduler entries return
-- a valid areaPoiID but the POI is filtered out by the API in the player's
-- current state (e.g. Skinning Den at Zul'Aman returns nil for chars who
-- aren't physically near). Falls back to a session/account name cache from
-- prior successful resolutions, then to a "Event in <zone>" synthesis from
-- C_EventScheduler.GetEventZoneName. Returns nil only when nothing useful
-- can be assembled at all.
local function ResolvePoi(areaPoiID, displayInfo)
    if not areaPoiID then return nil end

    local mapID = (C_EventScheduler and C_EventScheduler.GetEventUiMapID
                   and C_EventScheduler.GetEventUiMapID(areaPoiID))
                  or state.continentMapID
    local info  = (C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo
                   and C_AreaPoiInfo.GetAreaPOIInfo(mapID, areaPoiID)) or nil

    -- Cache successful name resolutions so a different alt (or a later
    -- session on the same alt) can show the proper name even when the API
    -- starts returning nil for the same POI.
    if info and info.name and ns.db then
        ns.db.eventNameCache = ns.db.eventNameCache or {}
        ns.db.eventNameCache[areaPoiID] = info.name
    end

    -- Name resolution chain:
    --   1. live API
    --   2. account-wide cache (populated from any alt's successful live)
    --   3. ns.knownEventNames (hardcoded for scheduler-only POIs whose
    --      info GetAreaPOIInfo never returns, regardless of map/location)
    --   4. "Event in <zone>" via GetEventZoneName
    local name = info and info.name
    if not name and ns.db and ns.db.eventNameCache then
        name = ns.db.eventNameCache[areaPoiID]
    end
    if not name and ns.knownEventNames then
        name = ns.knownEventNames[areaPoiID]
    end
    local zone = info and info.zoneName
    if not zone and C_EventScheduler and C_EventScheduler.GetEventZoneName then
        zone = C_EventScheduler.GetEventZoneName(areaPoiID)
    end
    if not name and zone then name = "Event in " .. zone end

    local atlas       = info and info.atlasName
    local description = info and info.description
    local widgetSet   = info and info.tooltipWidgetSet
    local iconSet     = info and info.iconWidgetSet
    if displayInfo then
        if displayInfo.overrideAtlas              then atlas       = displayInfo.overrideAtlas end
        if displayInfo.hideDescription            then description = nil end
        if displayInfo.overrideTooltipWidgetSetID then widgetSet   = displayInfo.overrideTooltipWidgetSetID end
    end

    local isTimed = (C_AreaPoiInfo and C_AreaPoiInfo.IsAreaPOITimed
                     and C_AreaPoiInfo.IsAreaPOITimed(areaPoiID)) or false
    local secondsLeft
    if isTimed and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOISecondsLeft then
        secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID)
    end
    if isTimed and not secondsLeft then
        secondsLeft = SecondsFromWidgetSet(widgetSet)
    end

    if not (name or atlas or zone) then return nil end

    return {
        name             = name,
        atlasName        = atlas,
        zoneName         = zone,
        description      = description,
        tooltipWidgetSet = widgetSet,
        iconWidgetSet    = iconSet,
        isTimed          = isTimed,
        secondsLeft      = secondsLeft,
        isLocked         = info and info.isLocked,
        mapID            = mapID,
    }
end

local function BuildSchedulerEntry(ev, poi, source)
    return {
        source           = source,
        areaPoiID        = ev.areaPoiID,
        eventKey         = ev.eventKey,
        eventID          = ev.eventID,
        name             = poi.name,
        atlasName        = poi.atlasName,
        zoneName         = poi.zoneName,
        description      = poi.description,
        tooltipWidgetSet = poi.tooltipWidgetSet,
        iconWidgetSet    = poi.iconWidgetSet,
        isTimed          = poi.isTimed,
        secondsLeft      = poi.secondsLeft,
        startTime        = ev.startTime,
        endTime          = ev.endTime,
        duration         = ev.duration,
        hasReminder      = ev.hasReminder,
        rewardsClaimed   = ev.rewardsClaimed,
    }
end

local function BuildMapEntry(poiID, info, mapID)
    -- Query timing live for map-event POIs. Many of these are actually
    -- timed (Abundance events whose scheduler entry got filtered out for
    -- this char post-reward-claim — the POI stays visible on the map and
    -- still ticks down its remaining-window timer). Without this, every
    -- map-only event renders as untimed "active" grey.
    local isTimed = (C_AreaPoiInfo.IsAreaPOITimed
                     and C_AreaPoiInfo.IsAreaPOITimed(poiID)) or false
    local secondsLeft
    if isTimed and C_AreaPoiInfo.GetAreaPOISecondsLeft then
        secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
    end
    if isTimed and not secondsLeft then
        secondsLeft = SecondsFromWidgetSet(info.tooltipWidgetSet)
    end
    return {
        source           = "map-event",
        areaPoiID        = poiID,
        name             = info.name,
        atlasName        = info.atlasName,
        zoneName         = info.zoneName,
        description      = info.description,
        tooltipWidgetSet = info.tooltipWidgetSet,
        iconWidgetSet    = info.iconWidgetSet,
        isTimed          = isTimed,
        secondsLeft      = secondsLeft,
        isLocked         = info.isLocked,
        mapID            = mapID,
    }
end

-- Warm the account-wide POI name cache for every Midnight zone. Iterating
-- C_AreaPoiInfo.GetEventsForMap forces the client to load zone POI data;
-- without this, GetAreaPOIInfo for a scheduler-active POI returns nil when
-- the player is in a different zone than the POI's host (the data is lazy).
-- Caching the resolved names makes the Now / Upcoming tooltip render proper
-- "Abundance: Skinning Den" labels instead of "Event in Zul'Aman" fallbacks,
-- regardless of which zone the player is currently standing in.
local function WarmZonePois()
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap
            and C_AreaPoiInfo.GetAreaPOIInfo and ns.db) then
        return
    end
    ns.db.eventNameCache = ns.db.eventNameCache or {}
    for _, mapID in ipairs(MIDNIGHT_ZONES) do
        local ids = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
        for _, poiID in ipairs(ids) do
            if not ns.db.eventNameCache[poiID] then
                local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                if info and info.name then
                    ns.db.eventNameCache[poiID] = info.name
                end
            end
        end
    end
end

-- ── Core refresh ──────────────────────────────────────────────────────────────

local function Refresh()
    wipe(state.active)
    wipe(state.upcoming)
    local seen      = {}  -- areaPoiID dedup
    local seenNames = {}  -- name dedup (scheduler and continent map use
                          -- different areaPoiIDs for the same event, e.g.
                          -- Herbalism Grotto = 8527 scheduler / 8676 map)
    local now  = time()

    if not C_EventScheduler then
        state.lastUpdate = now
        FireChanged()
        return
    end
    -- Wait for the server to deliver event data; EVENT_SCHEDULER_UPDATE will
    -- drive us back here once it arrives.
    if C_EventScheduler.HasData and not C_EventScheduler.HasData() then
        state.lastUpdate = now
        FireChanged()
        return
    end

    -- One-shot cleanup of stale account-wide cache from the old
    -- absence-as-claimed heuristic (now removed). Safe to drop unconditionally
    -- — nothing in the current code reads from it.
    if ns.db and ns.db.schedulerNamesSeen ~= nil then
        ns.db.schedulerNamesSeen = nil
    end

    -- 1. Scheduler ongoing → active. Persistent events the scheduler keeps
    --    in the Ongoing list (Stormarion Assault, Legends of the Haranir,
    --    Void Assaults). These don't carry an endTime — countdowns for these
    --    come from wave-cadence overrides or IsAreaPOITimed/GetAreaPOISecondsLeft.
    local rawOngoing = C_EventScheduler.GetOngoingEvents
                       and C_EventScheduler.GetOngoingEvents() or {}
    for _, ev in ipairs(rawOngoing) do
        if not seen[ev.areaPoiID] then
            local poi = ResolvePoi(ev.areaPoiID, ev.displayInfo)
            if poi then
                state.active[#state.active + 1] =
                    BuildSchedulerEntry(ev, poi, "scheduler-ongoing")
                seen[ev.areaPoiID] = true
                if poi.name then seenNames[poi.name] = true end
            end
        end
    end

    -- 2. Scheduler scheduled → upcoming. /mediag dump cross-checked against
    --    the in-game map (2026-05-14) resolved a long-standing ambiguity:
    --    each scheduler-scheduled entry's endTime IS the variant's next
    --    fire time. startTime is a pre-fire "schedule lock-in" timestamp
    --    that can be in the past — past-startTime entries are NOT
    --    currently firing (verified: scheduler entry [2] poi=8525 Skinning
    --    Den had past startTime + future endTime, but the only Abundance
    --    POI visible on any map was Herbalism Grotto, AND that map POI's
    --    secondsLeft expired at exactly the same moment as entry [2]'s
    --    endTime). The variant currently firing comes through the
    --    map-event scan below. Scheduler-scheduled is upcoming only.
    --
    --    Filter by endTime > now (any future fire — past-startTime is OK).
    --    Sort by endTime ascending so the renderer can use endTime - now
    --    as the "in X" countdown. Matches the Blizz events panel ordering.
    local rawScheduled = C_EventScheduler.GetScheduledEvents
                         and C_EventScheduler.GetScheduledEvents() or {}
    for _, ev in ipairs(rawScheduled) do
        if ev.endTime and ev.endTime > now then
            local poi = ResolvePoi(ev.areaPoiID, ev.displayInfo)
            if poi then
                state.upcoming[#state.upcoming + 1] =
                    BuildSchedulerEntry(ev, poi, "scheduler-scheduled")
            end
        end
    end

    -- 3. Continuous map-event POIs → active. Scan the continent map FIRST
    --    (so continent-canonical entries beat zone duplicates in the dedup),
    --    then each Midnight zone map.
    --
    --    Zone scans are mandatory: many event POIs (Void Incursion, Abyss
    --    Anglers, A Sea Voidage, Prey, zone-copy of Stormarion/Haranir) only
    --    register at zone level — GetEventsForMap on the continent returns
    --    just Abundance for a typical week. Without zone scans the Now
    --    section would be empty for every char who hasn't claimed Abundance.
    --
    --    Filter to event atlases + currently-active POIs. Dedup against
    --    scheduler entries via BOTH the areaPoiID seen[] set AND seenNames[]
    --    (scheduler and continent map use different POI IDs for the same
    --    underlying event — name is the canonical key). The same zone POI
    --    can appear on multiple zone maps (Void Incursion sits on 2395,
    --    2413, AND 2437); poiID dedup handles that.
    --
    --    isLocked is preserved on the entry but NOT used as a filter:
    --    "building up" events (Impending Void Incursion) show as locked
    --    until their fill bar hits 100%. We want to surface them with their
    --    progress percentage so the player can decide whether to chase the
    --    location. The Now-section renderer skips locked events that have
    --    no extractable progress data (covers genuinely-unavailable POIs).
    -- Side table: event name → zone label, populated by the per-zone scan
    -- regardless of poiID dedup. Lets us recover the active zone for
    -- multi-zone-rotating events (Void Assaults, Prey, ...) whose canonical
    -- POI lives on the continent map and so doesn't carry zoneName when
    -- the continent scan wins dedup. Filled before merging into state.active
    -- so the post-loop enrichment step can use it without re-scanning.
    local zoneByName = {}
    if C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap then
        local function scanMap(mapID, isZone)
            local ids = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
            for _, poiID in ipairs(ids) do
                local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                if info and info.isCurrentEvent
                   and LooksLikeEventAtlas(info.atlasName) then
                    if isZone and info.name and not zoneByName[info.name] then
                        local mi = C_Map and C_Map.GetMapInfo
                                   and C_Map.GetMapInfo(mapID)
                        if mi and mi.name then
                            zoneByName[info.name] = mi.name
                        end
                    end
                    if not seen[poiID]
                       and not (info.name and seenNames[info.name]) then
                        state.active[#state.active + 1] =
                            BuildMapEntry(poiID, info, mapID)
                        seen[poiID] = true
                        if info.name then seenNames[info.name] = true end
                    end
                end
            end
        end
        scanMap(state.continentMapID, false)
        for _, zoneMapID in ipairs(MIDNIGHT_ZONES) do
            scanMap(zoneMapID, true)
        end
        -- Enrich state.active entries that the continent-variant won
        -- dedup for, by lifting the zone label from the same-named POI
        -- on a Midnight zone map.
        for _, ev in ipairs(state.active) do
            if (not ev.zoneName or ev.zoneName == "")
               and ev.name and zoneByName[ev.name] then
                ev.zoneName = zoneByName[ev.name]
            end
        end
    end

    -- Sort by endTime ascending (= fire time ascending). See the
    -- scheduler-scheduled processing block for the endTime-is-fire-time
    -- discovery.
    table.sort(state.upcoming, function(a, b)
        return (a.endTime or 0) < (b.endTime or 0)
    end)

    -- 4. Bountiful Delves on the continent map. Distinct POI category from
    --    events — pulled via GetDelvesForMap, filtered by the "delves-
    --    bountiful" atlas. The continent-map query returns one canonical
    --    entry per delve (no cross-zone duplicates), so no isPrimaryMapForPOI
    --    dedup is needed here. Rotation refreshes daily; the AREA_POIS_UPDATED
    --    hook on this module catches the swap.
    wipe(state.bountifulDelves)
    if C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap then
        local mapID = state.continentMapID
        local ids   = C_AreaPoiInfo.GetDelvesForMap(mapID) or {}
        for _, poiID in ipairs(ids) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info and info.atlasName == "delves-bountiful" then
                state.bountifulDelves[#state.bountifulDelves + 1] = {
                    areaPoiID        = poiID,
                    name             = info.name,
                    atlasName        = info.atlasName,
                    iconWidgetSet    = info.iconWidgetSet,
                    tooltipWidgetSet = info.tooltipWidgetSet,
                    mapID            = mapID,
                }
            end
        end
        table.sort(state.bountifulDelves, function(a, b)
            return (a.name or "") < (b.name or "")
        end)
    end

    state.lastUpdate = now
    FireChanged()
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Active events firing right now (ongoing + currently-running scheduled +
-- continuous map-event POIs). Order is insertion order: scheduler entries
-- first, then map-event POIs.
function ns.Events.GetActive()
    return state.active
end

-- Upcoming scheduler fires, sorted ascending by fire time (= endTime).
-- Pass `maxAheadSecs` to clip the window by fire time; nil returns the
-- full list. See the Refresh comment on why endTime is the fire time
-- (not startTime).
function ns.Events.GetUpcoming(maxAheadSecs)
    if not maxAheadSecs then return state.upcoming end
    local cutoff = time() + maxAheadSecs
    local out = {}
    for _, ev in ipairs(state.upcoming) do
        if (ev.endTime or 0) <= cutoff then
            out[#out + 1] = ev
        end
    end
    return out
end

-- The single next firing for broker-text purposes. Returns the soonest
-- upcoming event within `maxAheadSecs` (default 24h); if none, falls back
-- to the first active event so the broker text still shows something
-- meaningful when nothing imminent is scheduled. Returns (event, secs).
-- `secs` is nil for already-active events.
function ns.Events.GetNextEvent(maxAheadSecs)
    local now = time()
    local cutoff = now + (maxAheadSecs or 24 * 3600)
    for _, ev in ipairs(state.upcoming) do
        local st = ev.startTime or 0
        if st > now and st <= cutoff then
            return ev, st - now
        end
    end
    if state.active[1] then return state.active[1], nil end
    return nil, nil
end

-- areaPoiID of the first currently-active event, suitable for
-- `OpenMapToEventPoi(...)` click hooks. Returns nil if no active event.
function ns.Events.GetFirstActivePOI()
    local ev = state.active[1]
    return ev and ev.areaPoiID or nil
end

function ns.Events.GetContinentMapID()
    return state.continentMapID
end

-- Today's bountiful delves on the Midnight continent map. Each entry:
--   { areaPoiID, name, atlasName, iconWidgetSet, tooltipWidgetSet, mapID }
-- Sorted alphabetically by name for stable render order. Rotation refreshes
-- daily; the AREA_POIS_UPDATED listener picks the swap up.
function ns.Events.GetBountifulDelves()
    return state.bountifulDelves
end

function ns.Events.GetLastUpdate()
    return state.lastUpdate
end

-- True if the server has sent event-schedule data (after the first
-- successful RequestEvents reply). Consumers should gate display logic on
-- this to avoid flashing empty state during the post-login fetch window.
function ns.Events.HasData()
    return (C_EventScheduler and C_EventScheduler.HasData
            and C_EventScheduler.HasData()) or false
end

-- Register a callback fired after every successful refresh. Callbacks
-- receive no arguments; consumers re-read state via the getters above.
function ns.Events.RegisterListener(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

-- ── Event wiring ──────────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("EVENT_SCHEDULER_UPDATE")
f:RegisterEvent("AREA_POIS_UPDATED")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        state.continentMapID = DiscoverContinent()
        WarmZonePois()
        if C_EventScheduler and C_EventScheduler.RequestEvents then
            C_EventScheduler.RequestEvents()
        end
    end
    Refresh()
end)
