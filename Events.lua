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
local function ResolvePoi(areaPoiID, displayInfo)
    if not (areaPoiID and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo) then
        return nil
    end
    local mapID = (C_EventScheduler and C_EventScheduler.GetEventUiMapID
                   and C_EventScheduler.GetEventUiMapID(areaPoiID))
                  or state.continentMapID
    local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, areaPoiID)
    if not info then return nil end

    local atlas       = info.atlasName
    local description = info.description
    local widgetSet   = info.tooltipWidgetSet
    if displayInfo then
        if displayInfo.overrideAtlas then atlas = displayInfo.overrideAtlas end
        if displayInfo.hideDescription then description = nil end
        if displayInfo.overrideTooltipWidgetSetID then
            widgetSet = displayInfo.overrideTooltipWidgetSetID
        end
    end

    local isTimed = (C_AreaPoiInfo.IsAreaPOITimed
                     and C_AreaPoiInfo.IsAreaPOITimed(areaPoiID)) or false
    local secondsLeft
    if isTimed and C_AreaPoiInfo.GetAreaPOISecondsLeft then
        secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID)
    end

    local zone = info.zoneName
    if not zone and C_EventScheduler and C_EventScheduler.GetEventZoneName then
        zone = C_EventScheduler.GetEventZoneName(areaPoiID)
    end

    return {
        name             = info.name,
        atlasName        = atlas,
        zoneName         = zone,
        description      = description,
        tooltipWidgetSet = widgetSet,
        isTimed          = isTimed,
        secondsLeft      = secondsLeft,
        isLocked         = info.isLocked,
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
        isTimed          = poi.isTimed,
        secondsLeft      = poi.secondsLeft,
        startTime        = ev.startTime,
        endTime          = ev.endTime,
        duration         = ev.duration,
        hasReminder      = ev.hasReminder,
        rewardsClaimed   = ev.rewardsClaimed,
    }
end

local function BuildMapEntry(poiID, info)
    return {
        source           = "map-event",
        areaPoiID        = poiID,
        name             = info.name,
        atlasName        = info.atlasName,
        zoneName         = info.zoneName,
        description      = info.description,
        tooltipWidgetSet = info.tooltipWidgetSet,
        isTimed          = false,
        isLocked         = info.isLocked,
    }
end

-- ── Core refresh ──────────────────────────────────────────────────────────────

local function Refresh()
    wipe(state.active)
    wipe(state.upcoming)
    local seen = {}
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

    -- 1. Scheduled-currently-firing → active. These carry startTime/endTime
    --    epochs so the tooltip can render a live "Xh Ym left" countdown.
    --    Processed BEFORE Ongoing because Ongoing entries for the same POI
    --    lack endTime — using them would lose the countdown info.
    local rawScheduled = C_EventScheduler.GetScheduledEvents
                         and C_EventScheduler.GetScheduledEvents() or {}
    for _, ev in ipairs(rawScheduled) do
        local poi = ResolvePoi(ev.areaPoiID, ev.displayInfo)
        if poi then
            local entry = BuildSchedulerEntry(ev, poi, "scheduler-scheduled")
            local st = ev.startTime or 0
            local et = ev.endTime or 0
            if st <= now and et > now then
                if not seen[ev.areaPoiID] then
                    state.active[#state.active + 1] = entry
                    seen[ev.areaPoiID] = true
                end
            elseif st > now then
                state.upcoming[#state.upcoming + 1] = entry
            end
        end
    end

    -- 2. Scheduler ongoing → active. Picks up persistent events that the
    --    scheduler doesn't put in the Scheduled list (Stormarion Assault,
    --    Legends of the Haranir). Dedup against scheduler-scheduled keeps
    --    the priority right.
    local rawOngoing = C_EventScheduler.GetOngoingEvents
                       and C_EventScheduler.GetOngoingEvents() or {}
    for _, ev in ipairs(rawOngoing) do
        if not seen[ev.areaPoiID] then
            local poi = ResolvePoi(ev.areaPoiID, ev.displayInfo)
            if poi then
                state.active[#state.active + 1] =
                    BuildSchedulerEntry(ev, poi, "scheduler-ongoing")
                seen[ev.areaPoiID] = true
            end
        end
    end

    -- 3. Continuous map-event POIs (Prey, etc.) on the continent map → active.
    --    Filter to event atlases, current events, and unlocked POIs. Dedup
    --    against scheduler entries via the `seen` set.
    if C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap then
        local mapID = state.continentMapID
        local ids   = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
        for _, poiID in ipairs(ids) do
            if not seen[poiID] then
                local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                if info and info.isCurrentEvent and not info.isLocked
                   and LooksLikeEventAtlas(info.atlasName) then
                    state.active[#state.active + 1] = BuildMapEntry(poiID, info)
                    seen[poiID] = true
                end
            end
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
        if C_EventScheduler and C_EventScheduler.RequestEvents then
            C_EventScheduler.RequestEvents()
        end
    end
    Refresh()
end)
