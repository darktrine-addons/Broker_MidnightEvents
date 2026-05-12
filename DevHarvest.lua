-- Broker_MidnightEvents - DevHarvest
-- Development-only module. Two layers:
--   1. Broker_MidnightEventsHarvest      — per-char snapshot, overwritten on
--      every refresh. Captures:
--          completed   — quest IDs above ID_THRESHOLD that have been
--                        flagged complete
--          active      — current quest log (title, frequency, mapID)
--          currencies  — visible currency list with weekly-cap shape
--                        (quantity, maxQuantity, maxWeeklyQuantity,
--                         quantityEarnedThisWeek, recharging fields).
--                        Lets us observe spending vs. earning behaviour
--                        across the harvest week.
--          eventState  — C_EventScheduler.GetOngoingEvents snapshot keyed
--                        by areaPoiID with name + rewardsClaimed. Updates
--                        on EVENT_SCHEDULER_UPDATE so the post-completion
--                        rewardsClaimed value lands without re-probing —
--                        the experiment that resolves Q15.
--   2. Broker_MidnightEventsQuestCatalogue — account-wide write-once index
--      keyed by questID, capturing first-acceptance metadata (giver, source,
--      zone, frequency, title). Accumulates across every char that ever
--      accepts a new high-ID quest, so weekly IDs we missed on one char get
--      caught the moment a different alt picks them up.
-- Set ENABLED = false (or remove the file from the TOC) to disable both.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local ENABLED = true
if not ENABLED then return end

-- Only collect quest IDs at or above this threshold. Midnight-era quests
-- are well above this; raises the noise floor without filtering useful data.
local ID_THRESHOLD = 85000

-- Soft tag for catalogue entries. uiMapIDs that we consider "Midnight-relevant"
-- for the purpose of fast curation. Quests outside this set are still
-- catalogued (so we don't miss an event auto-push in an unexpected zone) —
-- they just come in with midnightZone = false. Silvermoon City is included
-- because it's the hub for Midnight weekly handouts. Verify Silvermoon's
-- uiMapID on first capture and adjust if needed.
local HARVEST_ZONES = {
    [2395] = true,   -- Eversong Woods
    [2405] = true,   -- Voidstorm
    [2413] = true,   -- Harandar
    [2437] = true,   -- Zul'Aman
    [2393] = true,   -- Silvermoon City (retail Midnight; confirmed via Artherio harvest)
}

local function CharKey()
    return (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
end

-- ── Layer 1: per-char snapshot (existing behaviour) ───────────────────────────

local function CollectCompleted()
    local out = {}
    local list = C_QuestLog.GetAllCompletedQuestIDs() or {}
    for _, id in ipairs(list) do
        if id >= ID_THRESHOLD then
            out[tostring(id)] = C_QuestLog.GetTitleForQuestID(id) or "?"
        end
    end
    return out
end

local function CollectActive()
    local out = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader and q.questID then
            out[tostring(q.questID)] = {
                title      = q.title or "?",
                frequency  = q.frequency,           -- 1 = daily, 2 = weekly
                campaignID = q.campaignID,
                mapID      = C_QuestLog.GetQuestUiMapID and
                             C_QuestLog.GetQuestUiMapID(q.questID),
            }
        end
    end
    return out
end

-- Known Midnight currency IDs (event-tied + reward + crests). Primary lookup
-- source because GetCurrencyListSize() returns 0 until the player opens the
-- currency UI at least once per session — useless at PEW. Harvested-known
-- IDs avoid that lazy-init dependency. Visible-list scan below catches
-- anything we haven't IDed yet.
local CURRENCY_PROBE_IDS = {
    3376,  -- Shard of Dundun         (Abundance weekly budget, max 8)
    3378,  -- Dawnlight Manaflux      (Soiree-related budget, max 8)
    3405,  -- Field Accolade          (Void Assaults reward)
    3377,  -- Unalloyed Abundance     (Abundance reward currency)
    3379,  -- Brimming Arcana
    3316,  -- Voidlight Marl
    3373,  -- Angler Pearls
    3400,  -- Uncontaminated Void Sample
    3212,  -- Radiant Spark Dust
    3310,  -- Coffer Key Shards
    3028,  -- Restored Coffer Key
    3056,  -- Kej
    3383,  -- Adventurer Dawncrest
    3341,  -- Veteran Dawncrest
    3343,  -- Champion Dawncrest
    3345,  -- Hero Dawncrest
    3347,  -- Myth Dawncrest
}

-- Per-char currency snapshot. Captures the full weekly-cap shape across
-- chars so we can observe spending-vs-earning behaviour over the harvest
-- week. Two-pass: known-ID probe first (reliable), visible-list scan
-- second (catches new currencies).
local function CollectCurrencies()
    local out  = {}
    local seen = {}
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return out end

    local function record(id, info)
        if not (info and info.name and info.name ~= "") or seen[id] then return end
        seen[id] = true
        out[#out + 1] = {
            currencyID                = id,
            name                      = info.name,
            quantity                  = info.quantity,
            maxQuantity               = info.maxQuantity,
            maxWeeklyQuantity         = info.maxWeeklyQuantity,
            quantityEarnedThisWeek    = info.quantityEarnedThisWeek,
            canEarnPerWeek            = info.canEarnPerWeek,
            rechargingAmountPerCycle  = info.rechargingAmountPerCycle,
            rechargingCycleDurationMS = info.rechargingCycleDurationMS,
        }
    end

    for _, id in ipairs(CURRENCY_PROBE_IDS) do
        record(id, C_CurrencyInfo.GetCurrencyInfo(id))
    end

    local n = C_CurrencyInfo.GetCurrencyListSize
              and C_CurrencyInfo.GetCurrencyListSize() or 0
    for i = 1, n do
        local info = C_CurrencyInfo.GetCurrencyListInfo
                     and C_CurrencyInfo.GetCurrencyListInfo(i) or nil
        if info and not info.isHeader and info.currencyTypesID then
            record(info.currencyTypesID, info)
        end
    end

    return out
end

-- Per-char C_EventScheduler snapshot of every event firing right now —
-- BOTH the Ongoing list (Stormarion, Legends) AND scheduled entries with
-- past startTime + future endTime (Abundance variants in progress, Void
-- Assaults week-long). Captures rewardsClaimed per area POI so we can
-- finally resolve Q15: pre/post a reward-claim, does the field flip?
-- Refreshes on EVENT_SCHEDULER_UPDATE so the post-completion value lands
-- without needing a manual probe.
local function CollectEventState()
    local out  = {}
    local seen = {}
    if not (C_EventScheduler and C_EventScheduler.GetOngoingEvents) then return out end
    if C_EventScheduler.HasData and not C_EventScheduler.HasData() then return out end

    local function append(ev, source)
        if seen[ev.areaPoiID] then return end
        seen[ev.areaPoiID] = true
        local name
        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo
           and C_EventScheduler.GetEventUiMapID then
            local mapID = C_EventScheduler.GetEventUiMapID(ev.areaPoiID)
            if mapID then
                local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, ev.areaPoiID)
                name = info and info.name
            end
        end
        out[#out + 1] = {
            areaPoiID      = ev.areaPoiID,
            rewardsClaimed = ev.rewardsClaimed,
            name           = name,
            source         = source,
        }
    end

    for _, ev in ipairs(C_EventScheduler.GetOngoingEvents() or {}) do
        append(ev, "ongoing")
    end

    local now       = time()
    local scheduled = C_EventScheduler.GetScheduledEvents
                      and C_EventScheduler.GetScheduledEvents() or {}
    for _, ev in ipairs(scheduled) do
        if (ev.startTime or 0) <= now and (ev.endTime or 0) > now then
            append(ev, "scheduled-active")
        end
    end

    return out
end

local function Refresh()
    Broker_MidnightEventsHarvest = Broker_MidnightEventsHarvest or {}
    Broker_MidnightEventsHarvest[CharKey()] = {
        timestamp   = time(),
        playerLevel = UnitLevel and UnitLevel("player") or 0,
        completed   = CollectCompleted(),
        active      = CollectActive(),
        currencies  = CollectCurrencies(),
        eventState  = CollectEventState(),
    }
end

-- ── Layer 2: account-wide write-once quest catalogue ──────────────────────────

-- Set on QUEST_DETAIL (player opens NPC dialogue), consumed on the next
-- QUEST_ACCEPTED. Auto-pushed quests skip QUEST_DETAIL entirely, so a nil
-- pendingGiver at acceptance time is itself a signal ("source = auto").
local pendingGiver = nil

-- Look up frequency for a questID by scanning the active quest log. Returns
-- nil if the quest isn't currently in the log (e.g. catalogued post-turnin).
local function FrequencyFor(questID)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and q.questID == questID then return q.frequency end
    end
    return nil
end

local function RecordQuest(questID, source)
    if not questID or questID < ID_THRESHOLD then return end
    Broker_MidnightEventsQuestCatalogue = Broker_MidnightEventsQuestCatalogue or {}
    local cat = Broker_MidnightEventsQuestCatalogue
    local key = tostring(questID)
    if cat[key] then return end  -- write-once: first sighting wins

    local questMapID  = C_QuestLog.GetQuestUiMapID and C_QuestLog.GetQuestUiMapID(questID) or nil
    local acceptMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local title       = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or "?"
    local frequency   = FrequencyFor(questID)
    local inMidnight  = (questMapID  and HARVEST_ZONES[questMapID])
                     or (acceptMapID and HARVEST_ZONES[acceptMapID])
                     or false

    cat[key] = {
        title        = title,
        firstSeen    = time(),
        char         = CharKey(),
        source       = source,        -- "accept" | "auto" | "pew-scan"
        giver        = pendingGiver,  -- nil for auto / pew-scan
        questMapID   = questMapID,
        acceptMapID  = acceptMapID,
        frequency    = frequency,
        midnightZone = inMidnight and true or false,
    }
end

-- On PLAYER_ENTERING_WORLD, walk the current quest log and catalogue anything
-- we haven't seen yet. Catches chars who had a Midnight weekly accepted before
-- this module shipped, or before this char first ran with it.
local function ScanActiveLog()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader and q.questID then
            RecordQuest(q.questID, "pew-scan")
        end
    end
end

-- ── Event wiring ──────────────────────────────────────────────────────────────

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
-- Catches rewardsClaimed flips when the player completes an event run.
-- Also fires after RequestEvents on login, ensuring the post-login snapshot
-- has fresh scheduler data.
f:RegisterEvent("EVENT_SCHEDULER_UPDATE")
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        Refresh()
        return
    end

    if event == "QUEST_DETAIL" then
        -- Player opened an NPC quest dialogue. Stash the giver name so the
        -- next QUEST_ACCEPTED can attribute it. Cleared on accept; the next
        -- QUEST_DETAIL overwrites if no accept fires.
        --
        -- Don't fall through to UnitName("npc") — observed leaking the
        -- player's own name on quests accepted via gossip-selector flows
        -- (e.g. Lady Liadrin's choice-of-4 weekly). "target" is a safer
        -- secondary because the player is usually targeting the NPC.
        -- Guard explicitly: if either resolves to the player, record nil
        -- (= unknown giver) rather than a wrong attribution.
        local me   = UnitName("player")
        local name = UnitName("questnpc")
        if not name or name == me then name = UnitName("target") end
        if name == me then name = nil end
        pendingGiver = name
        return
    end

    if event == "QUEST_ACCEPTED" then
        -- Signature in modern retail: (questID) — older clients passed
        -- (questLogIndex, questID), so we accept either ordering.
        local questID = arg1
        if type(arg2) == "number" and arg2 > arg1 then
            questID = arg2  -- legacy (logIndex, questID) form
        end
        RecordQuest(questID, pendingGiver and "accept" or "auto")
        pendingGiver = nil
        Refresh()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        ScanActiveLog()
        Refresh()
        return
    end

    -- QUEST_TURNED_IN, QUEST_REMOVED: just refresh the per-char snapshot so
    -- the active/completed lists stay current. No catalogue write — those
    -- events don't reveal new acceptance metadata.
    Refresh()
end)
