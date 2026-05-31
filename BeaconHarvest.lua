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
    89289,  -- Saltheril's Soiree weekly turn-in ("Favor of the Court") —
            --   suspected weekly reset; need to confirm post-2026-06-02 reset
            --   that the flag clears (vs. lifetime persistence trap).
}

-- Quest titles / giver substrings that, when seen on QUEST_ACCEPTED,
-- flag a discovery worth recording. Used to enumerate the Soiree
-- pick / sub-quest pool dynamically as the player engages with the
-- event over coming resets — we don't know all the questIDs yet, so
-- match by accept-time metadata and log everything that smells right.
local DISCOVERY_PATTERNS = {
    titleContains = {
        "Soiree",
        "Saltheril",
        "Favor of the Court",
        "Fortify the Runestones",  -- 4 pinnacle weeklies (90573-90576)
        "High Esteem",              -- one-time unlock chain
        "Subtle Game",
    },
    giverContains = {
        "Saltheril",
        "Lord Saltheril",
        -- Subfaction vendors — Favor tokens spent here unlock the
        -- ~30 sub-weeklies in the pool. Every QUEST_ACCEPTED from
        -- one of these names is interesting evidence.
        "Caeris Fairdawn",
        "Apprentice Diell",
        "Armorer Goldcrest",
        "Ranger Allorn",
        "Neriv",
        "Talenia Flamesong",
    },
}
-- Sampling cadence. Temporarily fast (15s) while hunting the Delver's
-- Bounty 91190 lifecycle — the suspected loot→consume sequence can flip
-- the flag false→true→false within a couple of minutes, which the old
-- 60s + 2-sample-confirmation cadence could miss entirely. Restore to
-- 60 / 2 once the possession-vs-completion model is confirmed.
local SAMPLE_INTERVAL   = 15   -- seconds; cheap call, no zone gate
local TRANSITION_RING   = 200  -- per-char ring; bounded so always-on sampling can't bloat SV
local SAMPLE_RING       = 300  -- per-char sample ring; ~75min at 15s cadence

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

-- Candidate-flip buffer for transition confirmation. C_QuestLog
-- .IsQuestFlaggedCompleted returns false during the quest-log hydration
-- window right after PLAYER_ENTERING_WORLD even for genuinely-completed
-- quests, then snaps back to true once the cache fills. Recording those
-- transient flips would (and did) drown the real signal in noise.
--
-- Approach: when a sample disagrees with lastState, hold it as a
-- candidate and require it to persist for N consecutive samples before
-- promoting to a real transition. Resets if the value reverts before
-- the threshold.
-- Temporarily 1 (immediate) while hunting 91190's fast loot→consume
-- edges — a 2-sample requirement at 15s would still need the state to
-- hold 30s, risking a miss on a quick consume. The PEW debounce below
-- still filters the worst hydration-window noise on its own. Restore
-- to 2 alongside SAMPLE_INTERVAL once the model is confirmed.
local CONFIRMATION_SAMPLES = 1  -- count AFTER the first observation
local candidate = {}            -- qid → { newState, samplesSeen, firstSeenAt, firstTrigger }

-- Loading-screen debounce: ignore samples for this many seconds after a
-- PLAYER_ENTERING_WORLD *or* ZONE_CHANGED_NEW_AREA. IsQuestFlaggedCompleted
-- reads unreliable across the whole hydration window — empirically the
-- false<->true bounces from a mage-portal delve exit spanned ~35s, so 10s
-- was too short. 45s covers it. The multi-flip filter in Sample() is the
-- primary defence (catches mid-session noise too); this window adds
-- belt-and-braces coverage for single-quest hydration bounces during
-- loads, which the multi-flip check can't see.
local SAMPLE_DEBOUNCE_AFTER_PEW = 45
local lastPEWAt = 0

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

local function PushSample(states, note)
    local b = Bucket()
    b.sampleCursor = b.sampleCursor + 1
    if b.sampleCursor > SAMPLE_RING then b.sampleCursor = 1 end
    b.samples[b.sampleCursor] = {
        t       = time(),
        states  = states,
        trigger = lastTrigger,
        note    = note,   -- e.g. "noise:multiflip"; nil for ordinary samples
        ctx     = InstanceContext(),
    }
end

local function Sample()
    -- Read all tracked flags first so we can detect SYNCHRONIZED flips.
    -- The quest-log cache momentarily reads every completed quest as
    -- false during a loading screen (mage portal / delve exit), then
    -- snaps them all back — so 2+ tracked quests flipping in the SAME
    -- sample is hydration noise, never a real player action (which
    -- touches one quest at a time). Detect and drop the whole batch.
    local now = {}
    local changedCount = 0
    for _, qid in ipairs(TRACKED_QUEST_IDS) do
        now[qid] = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
                   and C_QuestLog.IsQuestFlaggedCompleted(qid) or false
        local prev = lastState[qid]
        if prev ~= nil and prev ~= now[qid] then
            changedCount = changedCount + 1
        end
    end
    if changedCount >= 2 then
        -- Coherent multi-quest flip = hydration noise. Record the sample
        -- (with a marker) for forensic visibility but do NOT advance
        -- lastState or open candidates — let the values snap back on the
        -- next clean tick without polluting the transition log.
        PushSample(now, "noise:multiflip")
        return
    end

    -- Loading-screen debounce: inside the hydration window after a
    -- PEW / zone change, still record the raw sample (so a real edge
    -- isn't invisible) but skip transition promotion — the flag reads
    -- aren't trustworthy enough to commit as a transition yet.
    if lastPEWAt > 0 and (time() - lastPEWAt) < SAMPLE_DEBOUNCE_AFTER_PEW then
        PushSample(now, "debounce:hydration")
        return
    end

    local states = now
    for _, qid in ipairs(TRACKED_QUEST_IDS) do
        local now = states[qid]
        states[qid] = now
        local prev = lastState[qid]
        if prev == nil then
            -- First observation seeds lastState without firing a transition.
            lastState[qid] = now
            candidate[qid] = nil
        elseif prev ~= now then
            -- Disagreement with established state. Open or extend the
            -- candidate flip; promote to a recorded transition once the
            -- new value has been seen for CONFIRMATION_SAMPLES samples.
            -- samplesSeen counts the CURRENT sample, so CONFIRMATION_SAMPLES
            -- = 1 fires immediately on first observation; = 2 needs one
            -- confirming follow-up; etc. The threshold is checked in one
            -- place after (re)establishing the candidate so the meaning of
            -- the constant is consistent regardless of branch.
            local c = candidate[qid]
            if c and c.newState == now then
                c.samplesSeen = c.samplesSeen + 1
            else
                c = {
                    newState     = now,
                    samplesSeen  = 1,
                    firstSeenAt  = time(),
                    firstTrigger = lastTrigger,
                }
                candidate[qid] = c
            end
            if c.samplesSeen >= CONFIRMATION_SAMPLES then
                -- Attribute to the trigger active when the new value was
                -- FIRST observed — the moment the player did the thing
                -- that flipped the flag, not a later confirming sample.
                local savedTrigger = lastTrigger
                lastTrigger = c.firstTrigger or lastTrigger
                PushTransition(qid, prev, now)
                lastTrigger = savedTrigger
                lastState[qid] = now
                candidate[qid] = nil
            end
        else
            -- Value reverted to lastState before confirmation: drop the
            -- candidate flip as transient noise.
            candidate[qid] = nil
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

-- Saltheril's Soiree discovery logger. On QUEST_ACCEPTED, if the new
-- quest's title or giver matches the Soiree DISCOVERY_PATTERNS, push
-- a record into Broker_MidnightEventsBeacon.discoveries with title +
-- giver + frequency and echo to chat so the player can see at a glance
-- "we just learned about quest 12345 'Patron's Favor' from Lady X".
-- Lets us enumerate the pick + sub-quest pool over coming resets
-- without manual /mediag-and-grep cycles.
local function MatchesDiscovery(title, giver)
    if title then
        for _, pat in ipairs(DISCOVERY_PATTERNS.titleContains) do
            if title:find(pat, 1, true) then return true end
        end
    end
    if giver then
        for _, pat in ipairs(DISCOVERY_PATTERNS.giverContains) do
            if giver:find(pat, 1, true) then return true end
        end
    end
    return false
end

local function LogDiscovery(questID)
    if not questID then return end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
                  and C_QuestLog.GetTitleForQuestID(questID)
    -- Giver isn't directly query-able from a questID alone; the harvest
    -- catalogue (DevHarvest.lua) captures it on the QUEST_ACCEPTED
    -- pendingGiver path, so cross-reference the catalogue here.
    local cat = Broker_MidnightEventsQuestCatalogue or {}
    local rec = cat[tostring(questID)]
    local giver = rec and rec.giver
    local freq  = rec and rec.frequency
    if not MatchesDiscovery(title, giver) then return end
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    Broker_MidnightEventsBeacon.discoveries = Broker_MidnightEventsBeacon.discoveries or {}
    local key = tostring(questID)
    if Broker_MidnightEventsBeacon.discoveries[key] then return end  -- already known
    Broker_MidnightEventsBeacon.discoveries[key] = {
        questID   = questID,
        title     = title or "?",
        giver     = giver or "?",
        frequency = freq,
        firstSeen = time(),
        char      = CharKey(),
        context   = InstanceContext(),
    }
    print(string.format(
        "|cffffcc00MidnightEvents/Soiree|r discovered quest %d %q from %s (freq=%s)",
        questID, title or "?", giver or "?", tostring(freq)))
end

-- Take a sample immediately on entering an instance so we capture the
-- pre-activity baseline without waiting up to a full interval. Also
-- sample on every QUEST_TURNED_IN / QUEST_REMOVED so flag transitions
-- get correlated with the specific quest event that may have caused
-- them — invaluable for the Arcantina 93767 mystery where adjacent
-- activity (world boss / Liadrin) flipped the flag without an obvious
-- direct credit path. QUEST_ACCEPTED triggers Soiree discovery
-- logging in addition to the transition sample.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_REMOVED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" then
        lastTrigger = "QUEST_TURNED_IN:" .. tostring(arg1)
    elseif event == "QUEST_REMOVED" then
        lastTrigger = "QUEST_REMOVED:" .. tostring(arg1)
    elseif event == "QUEST_ACCEPTED" then
        lastTrigger = "QUEST_ACCEPTED:" .. tostring(arg1)
        LogDiscovery(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
        lastTrigger = "PLAYER_ENTERING_WORLD"
        lastPEWAt   = time()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        lastTrigger = "ZONE_CHANGED_NEW_AREA"
        lastPEWAt   = time()  -- portals fire this too; debounce the hydration bounce
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

-- ── Crest-weekly signal probe ────────────────────────────────────────────────
-- /mecrest — hunt for the signal behind "loot 20 mythic crests from
-- bountiful delves per week". Three angles, printed to chat AND saved
-- to Broker_MidnightEventsBeacon.crestProbe:
--   1. Quest log scan — every quest (incl. tracked/hidden where the API
--      exposes them) whose title or any objective text mentions "crest",
--      plus any objective with numRequired >= 10 (catches an "x/20"
--      counter that doesn't spell out the word). The crest weekly, if
--      it's a quest, will surface here.
--   2. Currency scan — every currency whose name contains "crest", with
--      its weekly-earned / weekly-cap fields (quantityEarnedThisWeek,
--      maxWeeklyQuantity). If the weekly is currency-tracked rather than
--      quest-tracked, the delta lives here.
--   3. Context — instanceType so we know whether the probe was run
--      inside a delve (scenario) when the crests were fresh.
-- Run right after looting a bountiful-delve coffer for the cleanest read.
local function ScanCrestQuests()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return out end
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local title = C_QuestLog.GetTitleForQuestID
                          and C_QuestLog.GetTitleForQuestID(info.questID)
            local objs  = C_QuestLog.GetQuestObjectives
                          and C_QuestLog.GetQuestObjectives(info.questID) or {}
            local hit, why = false, nil
            if title and title:lower():find("crest") then hit, why = true, "title" end
            for _, o in ipairs(objs) do
                if o.text and o.text:lower():find("crest") then hit, why = true, "objtext" end
                if o.numRequired and o.numRequired >= 10 then
                    hit = true; why = why or ("numReq=" .. o.numRequired)
                end
            end
            if hit then
                local first = objs[1] or {}
                out[#out + 1] = {
                    questID  = info.questID,
                    title    = title or "?",
                    why      = why,
                    fulfilled = first.numFulfilled,
                    required  = first.numRequired,
                    objText   = first.text,
                }
            end
        end
    end
    return out
end

local function ScanCrestCurrencies()
    local out = {}
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then return out end
    local size = C_CurrencyInfo.GetCurrencyListSize() or 0
    for i = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo
                     and C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and not info.isHeader and info.name
           and info.name:lower():find("crest") then
            out[#out + 1] = {
                name              = info.name,
                quantity          = info.quantity,
                earnedThisWeek    = info.quantityEarnedThisWeek,
                maxWeekly         = info.maxWeeklyQuantity,
            }
        end
    end
    return out
end

SLASH_BMECREST1 = "/mecrest"
SlashCmdList.BMECREST = function()
    local quests     = ScanCrestQuests()
    local currencies = ScanCrestCurrencies()
    local _, itype   = IsInInstance()

    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    Broker_MidnightEventsBeacon.crestProbe = {
        t            = time(),
        char         = CharKey(),
        instanceType = itype,
        quests       = quests,
        currencies   = currencies,
    }

    print(string.format(
        "|cffffcc00MidnightEvents/Crest|r probe — %s, instance=%s, quests=%d currencies=%d",
        CharKey(), tostring(itype), #quests, #currencies))
    for _, q in ipairs(quests) do
        print(string.format("  quest %d  %q  [%s]  %s/%s  obj=%q",
            q.questID, q.title, tostring(q.why),
            tostring(q.fulfilled), tostring(q.required), tostring(q.objText)))
    end
    for _, c in ipairs(currencies) do
        print(string.format("  currency %q  have=%s  thisWeek=%s/%s",
            c.name, tostring(c.quantity),
            tostring(c.earnedThisWeek), tostring(c.maxWeekly)))
    end
    print("|cffffcc00  saved to|r Broker_MidnightEventsBeacon.crestProbe (run /reload to flush)")
end
