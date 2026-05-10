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

-- ── Midnight zone uiMapIDs ────────────────────────────────────────────────────
-- Placeholders from the design doc; verify in-game (see README → Verification).
-- Eversong / Zul'Aman / Harandar / Voidstorm.
-- The player's current map is always also scanned, so wrong IDs degrade
-- gracefully to "events visible only from the zone you're standing in."
local MIDNIGHT_ZONES = { 2601, 2602, 2603, 2604 }

-- ── active events ─────────────────────────────────────────────────────────────
-- Rebuilt on AREA_POIS_UPDATED. Each entry:
--   { mapID, poiID, name, atlas, secs, expiresAt }
-- secs / expiresAt are nil for events that aren't timed (zone-week markers).
local activeEvents = {}
local tooltipOwner  -- set while our tooltip is being shown; nil otherwise

-- Compact remaining-time formatter: "now", "45s", "23m", "3h 12m".
local function FormatRemaining(secs)
    if not secs or secs <= 0   then return "now"                              end
    if secs < 60               then return math.floor(secs) .. "s"            end
    if secs < 60 * 60          then return math.floor(secs / 60) .. "m"       end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    return h .. "h " .. m .. "m"
end

-- Live remaining time for a stored event (uses expiresAt to count down without re-scan).
local function CurrentRemaining(ev)
    if not ev.expiresAt then return nil end
    return ev.expiresAt - GetTime()
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
                local secs
                if C_AreaPoiInfo.IsAreaPOITimed(poiID) then
                    secs = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID)
                end
                local entry = {
                    mapID = mapID,
                    poiID = poiID,
                    name  = info.name or "Event",
                    atlas = info.atlasName,
                    secs  = secs,
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
    for _, mapID in ipairs(MIDNIGHT_ZONES) do
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

-- ── broker text ───────────────────────────────────────────────────────────────

local function UpdateBrokerText()
    local soonest, soonestRem
    for _, ev in ipairs(activeEvents) do
        local rem = CurrentRemaining(ev)
        if rem and (not soonestRem or rem < soonestRem) then
            soonest, soonestRem = ev, rem
        end
    end

    if soonest then
        if soonestRem and soonestRem <= 0 then
            broker.text = soonest.name .. "  now!"
        else
            broker.text = soonest.name .. "  " .. FormatRemaining(soonestRem)
        end
    else
        broker.text = "Midnight Events"
    end
end

-- ── tooltip ───────────────────────────────────────────────────────────────────

local function BuildTooltip()
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Midnight Events", CV_r, CV_g, CV_b)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Timed Events", CL_r, CL_g, CL_b)

    if #activeEvents == 0 then
        GameTooltip:AddLine("(no active events)", 0.5, 0.5, 0.5)
    else
        for _, ev in ipairs(activeEvents) do
            local label = ev.atlas
                          and ("|A:" .. ev.atlas .. ":16:16|a " .. ev.name)
                          or  ev.name

            local rem = CurrentRemaining(ev)
            local valueText, vr, vg, vb
            if not rem then
                valueText, vr, vg, vb = "active", 0.6, 0.6, 0.6
            elseif rem <= 0 then
                valueText, vr, vg, vb = "now!", CH_r, CH_g, CH_b
            else
                valueText = FormatRemaining(rem)
                if rem < 5 * 60 then
                    vr, vg, vb = CH_r, CH_g, CH_b      -- urgent: < 5m
                else
                    vr, vg, vb = CV_r, CV_g, CV_b
                end
            end
            GameTooltip:AddDoubleLine(label, valueText, CV_r, CV_g, CV_b, vr, vg, vb)
        end
    end

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

-- ── event frame ───────────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("AREA_POIS_UPDATED")

f:SetScript("OnEvent", function(self, event)
    RefreshActiveEvents()
    UpdateBrokerText()
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
        UpdateBrokerText()
        if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
            BuildTooltip()
        end
    end
end)
