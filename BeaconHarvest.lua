-- Broker_MidnightEvents - BeaconHarvest
-- Development-only module (#@debug@ in TOC). Targeted harvest for the
-- Beacon of Hope / Delver's Bounty weekly lockout investigation.
--
-- Hypothesis (2026-05-26): quest 91190 is the Beacon completion flag.
-- 92799 is co-observed but appears non-Beacon-specific. Confirmation
-- requires post-weekly-reset behaviour (91190 must flip false).
--
-- This module passively samples both flags every 60s while the player
-- is inside a scenario instance (delves are scenario-typed), captures
-- every transition (false→true), and writes to a separate SavedVariable
-- so we don't need to remember /mediag at the right moment.
--
-- Inspect:  WTF/Account/<ID>/SavedVariables/Broker_MidnightEvents.lua
--           key: Broker_MidnightEventsBeacon
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local ENABLED = true
if not ENABLED then return end

-- Quests under investigation. Add IDs here when a new "what triggers
-- this flag?" question comes up. The harvester samples each on a
-- 60s ticker (any zone), opportunistically on every QUEST_TURNED_IN /
-- QUEST_REMOVED event, and records every false→true (and true→false)
-- transition with the instance context at the moment of the flip.
local TRACKED_QUEST_IDS = {
    91190,  -- Delver's Bounty / Hidden Trove (confirmed weekly)
    92799,  -- co-observed during Beacon harvest (lifetime/account flag, kept as control)
    93767,  -- Arcantina weekly visit — credit trigger unknown; flips from
            --   apparently unrelated activity (world boss, Liadrin's weekly).
            --   Goal: identify what flipped it via correlated transitions.
}
local SAMPLE_INTERVAL   = 60   -- seconds; cheap call, no zone gate
local TRANSITION_RING   = 200  -- per-char ring; bounded so always-on sampling can't bloat SV
local SAMPLE_RING       = 300  -- per-char sample ring; ~5h of 60s sampling

local function CharKey()
    return (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
end

local function Bucket()
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    local root = Broker_MidnightEventsBeacon
    root.byChar = root.byChar or {}
    local key = CharKey()
    local b = root.byChar[key]
    if not b then
        b = { transitions = {}, transitionCursor = 0, samples = {}, sampleCursor = 0 }
        root.byChar[key] = b
    end
    return b
end

local function InstanceContext()
    local inInstance, instanceType = IsInInstance()
    local name, _, difficulty = GetInstanceInfo()
    return {
        inInstance   = inInstance,
        instanceType = instanceType,
        name         = name,
        difficulty   = difficulty,
        mapID        = C_Map and C_Map.GetBestMapForUnit
                       and C_Map.GetBestMapForUnit("player") or nil,
    }
end

-- Last-seen state per quest ID, per char. In-memory only; SV holds
-- transitions + samples, not the latest snapshot (we re-derive it
-- live from IsQuestFlaggedCompleted each tick).
local lastState = {}

-- Last context label associated with a transition. Updated by event
-- hooks (QUEST_TURNED_IN, QUEST_REMOVED) so when a flag flips within
-- the same frame as a known quest event, the transition record carries
-- the trigger candidate. Falls back to "ticker" for unattributed flips.
local lastTrigger = "ticker"

local function PushTransition(questID, fromState, toState)
    local b = Bucket()
    b.transitionCursor = b.transitionCursor + 1
    if b.transitionCursor > TRANSITION_RING then b.transitionCursor = 1 end
    b.transitions[b.transitionCursor] = {
        t        = time(),
        questID  = questID,
        from     = fromState,
        to       = toState,
        trigger  = lastTrigger,
        ctx      = InstanceContext(),
    }
    print(string.format(
        "|cffffcc00MidnightEvents/BeaconHarvest|r quest %d: %s → %s [%s] (%s)",
        questID, tostring(fromState), tostring(toState),
        lastTrigger, InstanceContext().name or "?"))
end

local function PushSample(states)
    local b = Bucket()
    b.sampleCursor = b.sampleCursor + 1
    if b.sampleCursor > SAMPLE_RING then b.sampleCursor = 1 end
    b.samples[b.sampleCursor] = {
        t       = time(),
        states  = states,
        trigger = lastTrigger,
        ctx     = InstanceContext(),
    }
end

local function Sample()
    local states = {}
    for _, qid in ipairs(TRACKED_QUEST_IDS) do
        local now = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
                    and C_QuestLog.IsQuestFlaggedCompleted(qid) or false
        states[qid] = now
        local prev = lastState[qid]
        if prev == nil then
            lastState[qid] = now
        elseif prev ~= now then
            PushTransition(qid, prev, now)
            lastState[qid] = now
        end
    end
    PushSample(states)
end

-- Drive the sampler from a single repeating ticker. Cheap enough to run
-- always; the in-delve gate is checked inside Sample() so the ticker
-- doesn't need to start/stop on zone change.
local ticker
local function StartTicker()
    if ticker then return end
    if not C_Timer or not C_Timer.NewTicker then return end
    ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, Sample)
end

-- Take a sample immediately on entering an instance so we capture the
-- pre-activity baseline without waiting up to a full interval. Also
-- sample on every QUEST_TURNED_IN / QUEST_REMOVED so flag transitions
-- get correlated with the specific quest event that may have caused
-- them — invaluable for the Arcantina 93767 mystery where adjacent
-- activity (world boss / Liadrin) flipped the flag without an obvious
-- direct credit path.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" then
        lastTrigger = "QUEST_TURNED_IN:" .. tostring(arg1)
    elseif event == "QUEST_REMOVED" then
        lastTrigger = "QUEST_REMOVED:" .. tostring(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
        lastTrigger = "PLAYER_ENTERING_WORLD"
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        lastTrigger = "ZONE_CHANGED_NEW_AREA"
    end
    StartTicker()
    Sample()
    lastTrigger = "ticker"  -- reset so background ticker samples don't claim event credit
end)

-- Slash command surface — quick at-a-glance status + manual sample trigger.
SLASH_BMEBEACON1 = "/mebeacon"
SlashCmdList.BMEBEACON = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") or ""
    if msg == "clear" then
        Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
        Broker_MidnightEventsBeacon.byChar = Broker_MidnightEventsBeacon.byChar or {}
        Broker_MidnightEventsBeacon.byChar[CharKey()] = nil
        lastState = {}
        print("|cffffcc00MidnightEvents/BeaconHarvest|r cleared per-char data.")
        return
    end
    Sample()  -- force one sample now, even outside delve
    local b = Bucket()
    local ctx = InstanceContext()
    print(string.format(
        "|cffffcc00MidnightEvents/BeaconHarvest|r %s",
        CharKey()))
    for _, qid in ipairs(TRACKED_QUEST_IDS) do
        local v = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
                  and C_QuestLog.IsQuestFlaggedCompleted(qid)
        print(string.format("  quest %d  flagged=%s", qid, tostring(v)))
    end
    print(string.format(
        "  ctx: instanceType=%s name=%s difficulty=%s",
        tostring(ctx.instanceType), tostring(ctx.name), tostring(ctx.difficulty)))
    print(string.format(
        "  transitions=%d  samples=%d  (SV: Broker_MidnightEventsBeacon)",
        b.transitionCursor, b.sampleCursor))
end
