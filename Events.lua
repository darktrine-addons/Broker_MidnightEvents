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

    -- 2. Scheduler scheduled → upcoming. Entries describe NEXT firings, not
    --    currently-firing events: each entry's startTime is when its variant
    --    next fires (per the Blizz Events panel "Event Schedule" rendering).
    --
    --    Entries with startTime in the past are rotation window artifacts —
    --    Blizz seems to keep the LAST firing's entry around with endTime
    --    extended to the NEXT firing's start, framing a "current rotation
    --    window." That entry is NOT actually firing (the Blizz events panel
    --    doesn't render it as ongoing either). The genuinely-firing variant
    --    comes through the map-event scan below with the right name + timer.
    --    Skipping past-start entries entirely avoids the misclassification.
    local rawScheduled = C_EventScheduler.GetScheduledEvents
                         and C_EventScheduler.GetScheduledEvents() or {}
    for _, ev in ipairs(rawScheduled) do
        if ev.startTime and ev.startTime > now then
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
    if C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap then
        local function scanMap(mapID)
            local ids = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
            for _, poiID in ipairs(ids) do
                if not seen[poiID] then
                    local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                    if info and info.isCurrentEvent
                       and LooksLikeEventAtlas(info.atlasName)
                       and not (info.name and seenNames[info.name]) then
                        state.active[#state.active + 1] =
                            BuildMapEntry(poiID, info, mapID)
                        seen[poiID] = true
                        if info.name then seenNames[info.name] = true end
                    end
                end
            end
        end
        scanMap(state.continentMapID)
        for _, zoneMapID in ipairs(MIDNIGHT_ZONES) do
            scanMap(zoneMapID)
        end
    end

    table.sort(state.upcoming, function(a, b)
        return (a.startTime or 0) < (b.startTime or 0)
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

-- Scheduled events with `startTime > now`. Pass `maxAheadSecs` to clip the
-- window; nil returns the full ~72h list. Sorted by startTime ascending.
function ns.Events.GetUpcoming(maxAheadSecs)
    if not maxAheadSecs then return state.upcoming end
    local cutoff = time() + maxAheadSecs
    local out = {}
    for _, ev in ipairs(state.upcoming) do
        if (ev.startTime or 0) <= cutoff then
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
