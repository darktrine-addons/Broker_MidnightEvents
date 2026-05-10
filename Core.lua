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

-- ── world boss lockouts ───────────────────────────────────────────────────────
-- GetSavedWorldBossInfo only enumerates LOCKED bosses (i.e. already killed this
-- week). The full per-week roster (and which are spawned in any given week)
-- isn't exposed by the public API, so the tooltip only shows the kills we can
-- prove. UPDATE_INSTANCE_INFO is the canonical "raid lockout state changed"
-- signal; we kick a refresh on PEW and a delayed one on BOSS_KILL.

local function RefreshWorldBosses()
    if not ns.char or not GetNumSavedWorldBosses then return end
    local locked = {}
    for i = 1, GetNumSavedWorldBosses() do
        local name, instanceID, reset = GetSavedWorldBossInfo(i)
        if name and reset and reset > 0 then
            locked[tostring(instanceID or name)] = name
        end
    end
    ns.char.worldBossesDone = locked
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
    local showWB = not ns.db or ns.db.showWorldBosses ~= false
    if showWB then
        local charName = UnitName("player") or "?"
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This Week (" .. charName .. ")", CL_r, CL_g, CL_b)

        -- World Bosses — list locked names, or "none yet" when zero.
        local bossLabel = "World Bosses"
        local bosses    = ns.char and ns.char.worldBossesDone or {}
        local names     = {}
        for _, n in pairs(bosses) do names[#names + 1] = n end
        table.sort(names)
        if #names == 0 then
            GameTooltip:AddDoubleLine(bossLabel, "none yet",
                                      CV_r, CV_g, CV_b, 0.6, 0.6, 0.6)
        else
            local value = table.concat(names, " \194\183 ") .. "  (" .. #names .. ")"
            GameTooltip:AddDoubleLine(bossLabel, value,
                                      CV_r, CV_g, CV_b, CV_r, CV_g, CV_b)
        end
    end

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
f:RegisterEvent("UPDATE_INSTANCE_INFO")
f:RegisterEvent("BOSS_KILL")

f:SetScript("OnEvent", function(self, event)
    if event == "BOSS_KILL" then
        -- Server takes a moment to register the lockout; ask for fresh raid
        -- info shortly, which will fire UPDATE_INSTANCE_INFO.
        if RequestRaidInfo then C_Timer.After(2, RequestRaidInfo) end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "AREA_POIS_UPDATED" then
        RefreshActiveEvents()
        UpdateBrokerText()
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_INSTANCE_INFO" then
        RefreshWorldBosses()
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
        UpdateBrokerText()
        if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
            BuildTooltip()
        end
    end
end)
