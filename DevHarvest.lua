-- Broker_MidnightEvents - DevHarvest
-- Development-only module: dumps quest log data into the
-- Broker_MidnightEventsHarvest saved variable so it can be read off-disk
-- without copy/paste from chat. Set ENABLED = false (or delete the file
-- from the TOC load order) to disable.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local ENABLED = true
if not ENABLED then return end

-- Only collect quest IDs at or above this threshold. Midnight-era quests
-- are well above this; raises the noise floor without filtering useful data.
local ID_THRESHOLD = 85000

local function CharKey()
    return (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
end

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

local function Refresh()
    Broker_MidnightEventsHarvest = Broker_MidnightEventsHarvest or {}
    Broker_MidnightEventsHarvest[CharKey()] = {
        timestamp   = time(),
        playerLevel = UnitLevel and UnitLevel("player") or 0,
        completed   = CollectCompleted(),
        active      = CollectActive(),
    }
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_REMOVED")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= addonName then return end
    Refresh()
end)
