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
    print(string.format(
        "|cffffcc00MidnightEvents Probe|r captured: hasData=%s, canShow=%s, ongoing=%d, scheduled=%d. /reload to flush to disk.",
        tostring(snap.hasData), tostring(snap.canShow), #snap.ongoing, #snap.scheduled))
end
