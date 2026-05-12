-- Broker_MidnightEvents - EventProbe
-- Development-only one-shot probe: dumps the C_EventScheduler surface into
-- the per-char block of Broker_MidnightEventsHarvest, with each event's POI
-- info resolved alongside. Lets us inspect field shapes (especially
-- rewardsClaimed semantics) off-disk after a /reload.
-- Remove this file from the TOC load order before publishing a release.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local ENABLED = true
if not ENABLED then return end

local function CharKey()
    return (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
end

-- Resolve a POI info blob for an event. The Blizzard EventScheduler.lua
-- pattern is: GetAreaPOIInfo(GetEventUiMapID(areaPoiID), areaPoiID), with
-- displayInfo overrides applied. We capture the raw plus the overrides
-- separately so we can see which fields actually differ.
local function ResolvePoi(areaPoiID, displayInfo)
    if not (areaPoiID and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo) then
        return nil
    end
    local mapID = C_EventScheduler and C_EventScheduler.GetEventUiMapID
                  and C_EventScheduler.GetEventUiMapID(areaPoiID)
    local zone  = C_EventScheduler and C_EventScheduler.GetEventZoneName
                  and C_EventScheduler.GetEventZoneName(areaPoiID)
    local raw   = C_AreaPoiInfo.GetAreaPOIInfo(mapID, areaPoiID)
    if not raw then return { mapID = mapID, zoneName = zone, _missing = true } end

    -- Capture only the fields we care about — avoid hauling around tables
    -- we can't inspect anyway.
    local out = {
        mapID            = mapID,
        zoneName         = zone,
        name             = raw.name,
        atlasName        = raw.atlasName,
        textureIndex     = raw.textureIndex,
        description      = raw.description,
        tooltipWidgetSet = raw.tooltipWidgetSet,
        isCurrentEvent   = raw.isCurrentEvent,
        addPaddingAboveTooltipWidgets = raw.addPaddingAboveTooltipWidgets,
    }
    if displayInfo then
        out._displayInfo = {
            hideTimeLeft               = displayInfo.hideTimeLeft,
            hideDescription            = displayInfo.hideDescription,
            overrideAtlas              = displayInfo.overrideAtlas,
            overrideTooltipWidgetSetID = displayInfo.overrideTooltipWidgetSetID,
        }
    end
    -- Convenience: is this event timed, and how much time is left?
    if C_AreaPoiInfo.IsAreaPOITimed then
        local timed = C_AreaPoiInfo.IsAreaPOITimed(areaPoiID)
        out.isTimed = timed
        if timed and C_AreaPoiInfo.GetAreaPOISecondsLeft then
            out.secondsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID)
        end
    end
    return out
end

-- Cheap recursive copy for dumping API tables into SVs. Bounded depth so
-- self-referential or absurd trees can't hang us; widget data sometimes
-- contains references that would otherwise cause issues.
local function CopyTable(t, depth)
    if type(t) ~= "table" or (depth or 0) > 6 then return t end
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = CopyTable(v, (depth or 0) + 1)
        elseif type(v) ~= "function" and type(v) ~= "userdata" then
            out[k] = v
        end
    end
    return out
end

-- Walk the player's visible currency list and dump everything. Cheap (the
-- list is short) and self-documenting — we get IDs + names + per-currency
-- weekly cap / earned fields in one pass without guessing IDs.
local function CollectCurrencies()
    local out = {}
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize then return out end
    local n = C_CurrencyInfo.GetCurrencyListSize() or 0
    for i = 1, n do
        local listInfo = C_CurrencyInfo.GetCurrencyListInfo and C_CurrencyInfo.GetCurrencyListInfo(i) or nil
        if listInfo and not listInfo.isHeader then
            local id = listInfo.currencyTypesID
            local detail = id and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id) or nil
            out[#out + 1] = {
                listIndex      = i,
                currencyID     = id,
                listInfo       = CopyTable(listInfo),
                detail         = CopyTable(detail),
            }
        end
    end
    return out
end

-- Probe both GetDelvesForMap and GetEventsForMap for every map we can
-- discover under the player's current continent. Initial hardcoded list
-- missed Isle of Quel'Danas (Parhelion Plaza bountiful delve), so the
-- dynamic walk is the source of truth; the static set below is just a
-- fallback in case the walk fails.
local FALLBACK_ZONES = {
    [2395] = "Eversong Woods",
    [2405] = "Voidstorm",
    [2413] = "Harandar",
    [2437] = "Zul'Aman",
    [2393] = "Silvermoon City",
}

-- Walk up parentMapID chain from the player's current map until we hit a
-- Continent (or run out of parents). Returns the continent uiMapID, or the
-- highest ancestor if no Continent type was found.
local function FindContinentRoot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local current = C_Map.GetBestMapForUnit("player")
    if not current then return nil end
    local guard = 20
    while current and guard > 0 do
        guard = guard - 1
        local info = C_Map.GetMapInfo(current)
        if not info then return current end
        if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then
            return current
        end
        if not info.parentMapID or info.parentMapID == 0 then
            return current
        end
        current = info.parentMapID
    end
    return current
end

-- Walk all descendants of a root map. Bounded depth guards against cycles.
local function WalkMapTree(rootID, into, depth)
    if not rootID or (depth or 0) > 6 or into[rootID] then return end
    into[rootID] = true
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    local children = C_Map.GetMapChildrenInfo(rootID) or {}
    for _, child in ipairs(children) do
        WalkMapTree(child.mapID, into, (depth or 0) + 1)
    end
end

local function CollectMapPOIs()
    local out = {}
    if not C_AreaPoiInfo then return out end

    local toProbe = {}
    -- 1. Fallback set (always covered).
    for mapID in pairs(FALLBACK_ZONES) do toProbe[mapID] = true end
    -- 2. Dynamic walk from continent root.
    local continent = FindContinentRoot()
    if continent then WalkMapTree(continent, toProbe, 0) end
    -- 3. Always include the player's current map even if the walk skipped it.
    local current = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if current then toProbe[current] = true end

    for mapID in pairs(toProbe) do
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) or nil
        local entry = {
            mapID     = mapID,
            mapName   = mapInfo and mapInfo.name or FALLBACK_ZONES[mapID],
            mapType   = mapInfo and mapInfo.mapType,
            parentMapID = mapInfo and mapInfo.parentMapID,
            delves    = nil,
            events    = nil,
        }
        if C_AreaPoiInfo.GetDelvesForMap then
            local ids = C_AreaPoiInfo.GetDelvesForMap(mapID) or {}
            entry.delves = {}
            for _, poiID in ipairs(ids) do
                local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                entry.delves[#entry.delves + 1] = info and CopyTable(info) or { areaPoiID = poiID, _missing = true }
            end
        end
        if C_AreaPoiInfo.GetEventsForMap then
            local ids = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
            entry.events = {}
            for _, poiID in ipairs(ids) do
                local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                entry.events[#entry.events + 1] = info and CopyTable(info) or { areaPoiID = poiID, _missing = true }
            end
        end
        -- Drop maps with neither delves nor events to keep the snapshot lean.
        if (entry.delves and #entry.delves > 0) or (entry.events and #entry.events > 0) then
            out[#out + 1] = entry
        end
    end
    return out
end

-- Dump full widget content for the tooltipWidgetSet IDs we observe on
-- ongoing/scheduled events. This is how Blizzard renders "Shards 6/8",
-- wave counters, etc. in the events panel tooltip. If Slayer's Rise is a
-- sub-widget of Stormarion (setID 1795), it should appear here.
local function CollectWidgets(setIDs)
    local out = {}
    if not C_UIWidgetManager or not C_UIWidgetManager.GetAllWidgetsBySetID then return out end
    for _, setID in ipairs(setIDs) do
        local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID) or {}
        out[#out + 1] = {
            setID   = setID,
            widgets = CopyTable(widgets),
        }
    end
    return out
end

local function Snapshot()
    if not C_EventScheduler then return nil end
    local snap = {
        capturedAt  = time(),
        canShow     = C_EventScheduler.CanShowEvents and C_EventScheduler.CanShowEvents() or nil,
        hasData     = C_EventScheduler.HasData       and C_EventScheduler.HasData()       or nil,
        continent   = C_EventScheduler.GetActiveContinentName and C_EventScheduler.GetActiveContinentName() or nil,
        -- zoneName is per-event (takes areaPoiID); resolved inside _poi instead.
        ongoing     = {},
        scheduled   = {},
    }

    local ongoing = C_EventScheduler.GetOngoingEvents and C_EventScheduler.GetOngoingEvents() or {}
    for i, ev in ipairs(ongoing) do
        snap.ongoing[i] = {
            areaPoiID      = ev.areaPoiID,
            rewardsClaimed = ev.rewardsClaimed,
            displayInfo    = ev.displayInfo and {
                hideTimeLeft               = ev.displayInfo.hideTimeLeft,
                hideDescription            = ev.displayInfo.hideDescription,
                overrideAtlas              = ev.displayInfo.overrideAtlas,
                overrideTooltipWidgetSetID = ev.displayInfo.overrideTooltipWidgetSetID,
            } or nil,
            _poi = ResolvePoi(ev.areaPoiID, ev.displayInfo),
        }
    end

    local scheduled = C_EventScheduler.GetScheduledEvents and C_EventScheduler.GetScheduledEvents() or {}
    for i, ev in ipairs(scheduled) do
        snap.scheduled[i] = {
            eventKey       = ev.eventKey,
            eventID        = ev.eventID,
            areaPoiID      = ev.areaPoiID,
            startTime      = ev.startTime,
            endTime        = ev.endTime,
            duration       = ev.duration,
            hasReminder    = ev.hasReminder,
            rewardsClaimed = ev.rewardsClaimed,
            displayInfo    = ev.displayInfo and {
                hideTimeLeft               = ev.displayInfo.hideTimeLeft,
                hideDescription            = ev.displayInfo.hideDescription,
                overrideAtlas              = ev.displayInfo.overrideAtlas,
                overrideTooltipWidgetSetID = ev.displayInfo.overrideTooltipWidgetSetID,
            } or nil,
            _poi = ResolvePoi(ev.areaPoiID, ev.displayInfo),
        }
    end

    -- Collect unique tooltipWidgetSet IDs from everything we've seen so we
    -- can dump their widget content (Shards counter, wave widget, etc.).
    local widgetSeen = {}
    local function noteWidgetSet(ev)
        local ws = ev and ev._poi and ev._poi.tooltipWidgetSet
        if ws then widgetSeen[ws] = true end
    end
    for _, ev in ipairs(snap.ongoing)   do noteWidgetSet(ev) end
    for _, ev in ipairs(snap.scheduled) do noteWidgetSet(ev) end
    local setIDs = {}
    for ws in pairs(widgetSeen) do setIDs[#setIDs + 1] = ws end

    snap.currencies = CollectCurrencies()
    snap.mapPOIs    = CollectMapPOIs()
    snap.widgets    = CollectWidgets(setIDs)

    return snap
end

local function Save(reason)
    Broker_MidnightEventsHarvest = Broker_MidnightEventsHarvest or {}
    local key = CharKey()
    Broker_MidnightEventsHarvest[key] = Broker_MidnightEventsHarvest[key] or {}
    Broker_MidnightEventsHarvest[key].eventProbe = Snapshot()
    if Broker_MidnightEventsHarvest[key].eventProbe then
        Broker_MidnightEventsHarvest[key].eventProbe._lastReason = reason
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("EVENT_SCHEDULER_UPDATE")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Ask the server for fresh event data. Throttled by Blizzard.
        if C_EventScheduler and C_EventScheduler.RequestEvents then
            C_EventScheduler.RequestEvents()
        end
        -- Snapshot whatever's already cached locally; will be overwritten
        -- when EVENT_SCHEDULER_UPDATE arrives with fresh data.
        Save("PEW")
    elseif event == "EVENT_SCHEDULER_UPDATE" then
        Save("EVENT_SCHEDULER_UPDATE")
    end
end)

-- Manual trigger for impatient probing — /mep dumps and prints a one-line
-- status to chat so you know the snapshot is fresh before /reload-ing.
SLASH_MEPROBE1 = "/mep"
SlashCmdList.MEPROBE = function()
    if C_EventScheduler and C_EventScheduler.RequestEvents then
        C_EventScheduler.RequestEvents()
    end
    Save("/mep")
    local key  = CharKey()
    local snap = Broker_MidnightEventsHarvest
                 and Broker_MidnightEventsHarvest[key]
                 and Broker_MidnightEventsHarvest[key].eventProbe
    if not snap then
        print("|cffffcc00MidnightEvents Probe|r snapshot failed — C_EventScheduler missing?")
        return
    end
    local widgetCount = 0
    if snap.widgets then for _, w in ipairs(snap.widgets) do widgetCount = widgetCount + (w.widgets and #w.widgets or 0) end end
    local delveCount = 0
    if snap.mapPOIs then for _, m in ipairs(snap.mapPOIs) do delveCount = delveCount + (m.delves and #m.delves or 0) end end
    print(string.format(
        "|cffffcc00MidnightEvents Probe|r captured: hasData=%s ongoing=%d scheduled=%d currencies=%d delves=%d widgets=%d. /reload to flush.",
        tostring(snap.hasData), #snap.ongoing, #snap.scheduled,
        snap.currencies and #snap.currencies or 0, delveCount, widgetCount))
end
