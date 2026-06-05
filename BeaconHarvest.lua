-- Broker_MidnightEvents - BeaconHarvest
-- Development-only module (#@debug@ in TOC). Investigation harness for
-- Midnight delve/weekly quest-ID hunts.
--
-- STATUS: RETIRED (2026-06-03). The Beacon-of-Hope weekly riddle is solved and
-- shipped (v1.0.2) — the weekly is "loot the Nullaeus Cache" (GameObject
-- 618495), detected in production by a LOOT_OPENED hook in Core. The heavy
-- recorders below (flag sampler, item-use correlation, crest probes, and the
-- delve / scenario / loot-source recorders) proved the negative and have done
-- their job, so they are disabled via `ENABLED = false`. The code is kept
-- intact, NOT deleted, so a future ID hunt just flips ENABLED = true and
-- retargets TRACKED_QUEST_IDS / the object IDs — nothing to reconstruct from
-- git history. Dumps live under SavedVariables key Broker_MidnightEventsBeacon.
--
-- The ONE always-on facility (kept ABOVE the kill-switch so it survives the
-- harness being disabled): a lean Arena bonus-event ID catcher.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

-- ── Arena bonus-event ID catcher (lean, always-on) ──────────────────────────
-- The Bonus Event Weekly pool still lacks the Midnight ID for the ARENA
-- variant (83358 is the TWW quest, held out of Data.lua over cross-expansion
-- risk). It only appears during an Arena bonus week — easy to miss — so this
-- watches every QUEST_ACCEPTED for an Arena/Conquest-titled quest, echoes it
-- loudly, and records it, so the ID is captured without remembering to turn a
-- harness on. Deliberately ABOVE the ENABLED kill-switch. Cost: a couple of
-- string.find calls per quest accept.
local ARENA_HINTS = { "Arena", "Conquest" }
local arenaCatcher = CreateFrame("Frame")
arenaCatcher:RegisterEvent("QUEST_ACCEPTED")
arenaCatcher:SetScript("OnEvent", function(_, _, questID)
    if type(questID) ~= "number" then return end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
                  and C_QuestLog.GetTitleForQuestID(questID)
    if not title then return end
    local hit = false
    for _, p in ipairs(ARENA_HINTS) do
        if title:find(p, 1, true) then hit = true; break end
    end
    if not hit then return end
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    Broker_MidnightEventsBeacon.arenaCatch = Broker_MidnightEventsBeacon.arenaCatch or {}
    Broker_MidnightEventsBeacon.arenaCatch[tostring(questID)] = {
        questID = questID, title = title, t = time(),
        char = (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?"),
    }
    print(string.format(
        "|cffffcc00MidnightEvents/Arena|r possible Arena bonus-event quest %d %q "
        .. "— record this ID for the Bonus Event pool (Data.lua).", questID, title))
end)

-- ── Prerequisite probe (lean, always-on) — for issue #1 ─────────────────────
-- Midnight unlock quests AND renown are WARBAND-WIDE: once any character
-- completes an unlock, IsQuestFlaggedCompleted reads true for every char, so we
-- can't observe these quests being accepted fresh — only VALIDATE candidate IDs
-- (found on Wowhead) by confirming they read true on the account. `/meprereq`
-- dumps, for the current char: (1) IsQuestFlaggedCompleted for each candidate
-- unlock quest, and (2) C_MajorFactions.GetMajorFactionData (name + renownLevel)
-- for each Midnight faction ID — which also confirms whether the reputation
-- faction IDs are the same numbers the C_MajorFactions API expects. Add IDs to
-- PREREQ_QUESTS as Wowhead research turns up the unknowns.
local PREREQ_QUESTS = {
    [93932] = "Legends of the Haranir unlock (Legendary Prosperity, Hara'ti R8)",
    [91627] = "Saltheril's Soiree unlock (Saltheril's Haven)",
    [95268] = "Voidforge unlock",
    -- TODO (IDs unknown — fill from Wowhead, then validate here):
    --   Arcantina unlock ("The Arcantina", Kurdran Wildhammer / Arator's Journey)
    --   Prey Hunts unlock (Voidstorm campaign → Astalor Bloodsworn)
    --   Void Assault intro (Void Strike from Ranger Captain Lilatha)
}
-- Midnight renown/major factions (Wowhead reputation IDs; the probe confirms
-- whether C_MajorFactions accepts the same number).
local PREREQ_FACTIONS = {
    [2704] = "Hara'ti",
    [2710] = "Silvermoon Court",
    [2696] = "Amani Tribe",
    [2699] = "The Singularity",
}
SLASH_MEPREREQ1 = "/meprereq"
SlashCmdList.MEPREREQ = function()
    local char = (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    local probe = { char = char, t = time(), quests = {}, factions = {} }
    Broker_MidnightEventsBeacon.prereqProbe = probe
    print("|cffffcc00MidnightEvents/Prereq|r " .. char)
    print("  -- unlock quests (IsQuestFlaggedCompleted; warband-wide once done) --")
    for id, label in pairs(PREREQ_QUESTS) do
        local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
                     and C_QuestLog.IsQuestFlaggedCompleted(id) or false
        probe.quests[tostring(id)] = done
        print(string.format("    quest %d  flagged=%s  (%s)", id, tostring(done), label))
    end
    print("  -- renown (C_MajorFactions.GetMajorFactionData) --")
    for id, label in pairs(PREREQ_FACTIONS) do
        local d = C_MajorFactions and C_MajorFactions.GetMajorFactionData
                  and C_MajorFactions.GetMajorFactionData(id)
        if d then
            probe.factions[tostring(id)] = { name = d.name, renown = d.renownLevel }
            print(string.format("    faction %d  %q  renown=%s  (expected %s)",
                id, tostring(d.name), tostring(d.renownLevel), label))
        else
            probe.factions[tostring(id)] = false
            print(string.format("    faction %d  NO DATA — wrong ID for C_MajorFactions?  (expected %s)",
                id, label))
        end
    end
    print("|cffffcc00  saved to|r Broker_MidnightEventsBeacon.prereqProbe (run /reload to flush)")
end

-- ── Investigation harness (RETIRED — flip to true + retarget IDs to revive) ──
local ENABLED = false
if not ENABLED then return end

-- Quests under investigation. Add IDs here when a new "what triggers
-- this flag?" question comes up. The harvester samples each on a
-- 60s ticker (any zone), opportunistically on every QUEST_TURNED_IN /
-- QUEST_REMOVED event, and records every false→true (and true→false)
-- transition with the instance context at the moment of the flip.
local TRACKED_QUEST_IDS = {
    91190,  -- per-delve reward-chest plumbing (NOT the weekly; weekly = looting
            --   Nullaeus Cache 618495, handled in Core). Kept for reference.
    92799,  -- "A Nightmarish Task" nightmare-hunt ACTIVE flag: true on accepting
            --   hunt 91263, false on turn-in (corrected 2026-06-03 — it is NOT a
            --   lifetime/account flag; nothing to do with Beacons).
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

-- ── Beacon / Bounty item-use correlation ─────────────────────────────────────
-- Hypothesis test for the possession model: a 91190 false→true edge
-- should coincide (within ITEM_GRACE_WINDOW) with the player USING a
-- Beacon of Hope (item count drops by 1 → summons Nullaeus mid-delve)
-- or, for the consume edge, a Delver's Bounty. If a 91190 edge lands
-- with NO nearby item-count decrement, the model is incomplete —
-- something else is flipping the flag.
--
-- Item IDs from the prior harvest (memory: beacon-of-hope-untrackable);
-- VERIFY in-game if the correlation never fires — patch may have shifted
-- them. GetItemCount is cheap; polled on BAG_UPDATE (debounced).
local TRACKED_ITEMS = {
    [253342] = "Beacon of Hope",
    [233071] = "Delver's Bounty",
}
local ITEM_GRACE_WINDOW = 60     -- seconds: how near an item use must be to a 91190 edge
local itemCountPrev     = {}     -- itemID → last observed count (nil until first poll)
local recentItemUses    = {}     -- ring of { t, itemID, name, from, to } (decrements only)
local RECENT_ITEM_RING  = 40

local function PushItemUse(rec)
    recentItemUses[#recentItemUses + 1] = rec
    if #recentItemUses > RECENT_ITEM_RING then
        table.remove(recentItemUses, 1)
    end
end

-- Return the item-use records within ITEM_GRACE_WINDOW of `whenT`.
local function ItemUsesNear(whenT)
    local out = {}
    for _, u in ipairs(recentItemUses) do
        if math.abs(whenT - u.t) <= ITEM_GRACE_WINDOW then
            out[#out + 1] = u
        end
    end
    return out
end

local function PushTransition(questID, fromState, toState)
    local b = Bucket()
    b.transitionCursor = b.transitionCursor + 1
    if b.transitionCursor > TRANSITION_RING then b.transitionCursor = 1 end
    -- Correlate 91190 edges with recent Beacon / Bounty uses AND snapshot
    -- the live item counts at the edge. The counts discriminate the user's
    -- "pre-condition flag" hypothesis: if 91190 flips while holding 0
    -- Beacons and 0 Bounties, the flag can't be beacon/bounty-driven —
    -- it's tracking something else (e.g. just being inside an active
    -- bountiful-delve instance: waystone-discovered → instance-closed).
    local itemContext, itemSummary, itemCounts = nil, nil, nil
    if questID == 91190 then
        local nearby = ItemUsesNear(time())
        itemContext = nearby
        local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
        if getCount then
            itemCounts = {}
            for itemID, name in pairs(TRACKED_ITEMS) do
                itemCounts[name] = getCount(itemID) or 0
            end
        end
        if #nearby > 0 then
            local parts = {}
            for _, u in ipairs(nearby) do
                parts[#parts + 1] = string.format("%s %d→%d (%+ds)",
                    u.name, u.from, u.to, u.t - time())
            end
            itemSummary = table.concat(parts, ", ")
        else
            itemSummary = "NO beacon/bounty use within "
                          .. ITEM_GRACE_WINDOW .. "s"
            if itemCounts then
                itemSummary = itemSummary .. string.format(
                    " | held: Beacon=%d Bounty=%d",
                    itemCounts["Beacon of Hope"] or 0,
                    itemCounts["Delver's Bounty"] or 0)
            end
            itemSummary = itemSummary .. " — UNEXPLAINED"
        end
    end
    b.transitions[b.transitionCursor] = {
        t           = time(),
        questID     = questID,
        from        = fromState,
        to          = toState,
        trigger     = lastTrigger,
        itemContext = itemContext,
        itemCounts  = itemCounts,
        ctx         = InstanceContext(),
    }
    print(string.format(
        "|cffffcc00MidnightEvents/BeaconHarvest|r quest %d: %s → %s [%s] (%s)",
        questID, tostring(fromState), tostring(toState),
        lastTrigger, InstanceContext().name or "?"))
    if itemSummary then
        print("|cffffcc00MidnightEvents/Beacon|r   ↳ item: " .. itemSummary)
    end
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

-- Poll tracked item counts; record DECREMENTS (item used) into
-- recentItemUses so PushTransition can correlate them with 91190 edges.
-- Increments (looted / received an item) are seeded silently — we only
-- care about uses for the "did using a Beacon flip the flag" test, but
-- we still update the baseline so a later decrement reports the right
-- from/to. Also persists a per-char rolling SV ring for post-hoc.
local function PollItems(trigger)
    if not (C_Item and C_Item.GetItemCount or GetItemCount) then return end
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    for itemID, name in pairs(TRACKED_ITEMS) do
        local count = getCount(itemID) or 0
        local prev  = itemCountPrev[itemID]
        if prev ~= nil and count < prev then
            local rec = {
                t = time(), itemID = itemID, name = name,
                from = prev, to = count, trigger = trigger,
                ctx = InstanceContext(),
            }
            PushItemUse(rec)
            -- Persist to SV ring for post-hoc.
            local b = Bucket()
            b.itemUses = b.itemUses or { ring = {}, cursor = 0 }
            b.itemUses.cursor = b.itemUses.cursor + 1
            if b.itemUses.cursor > 60 then b.itemUses.cursor = 1 end
            b.itemUses.ring[b.itemUses.cursor] = rec
            print(string.format(
                "|cffffcc00MidnightEvents/Beacon|r used %s: %d → %d (%s)",
                name, prev, count, InstanceContext().name or "?"))
        end
        itemCountPrev[itemID] = count
    end
end

-- BAG_UPDATE fires in bursts; debounce the poll.
local lastItemPollAt = 0
local itemFrame = CreateFrame("Frame")
itemFrame:RegisterEvent("BAG_UPDATE_DELAYED")
itemFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
itemFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Seed baseline so the first real BAG_UPDATE doesn't misreport.
        PollItems("PEW-seed")
        return
    end
    if (time() - lastItemPollAt) < 1 then return end
    lastItemPollAt = time()
    PollItems("BAG_UPDATE")
end)

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
        if Broker_MidnightEventsBeacon.crestLog then
            Broker_MidnightEventsBeacon.crestLog[CharKey()] = nil
        end
        if Broker_MidnightEventsBeacon.delveLog then
            Broker_MidnightEventsBeacon.delveLog[CharKey()] = nil
        end
        if Broker_MidnightEventsBeacon.scenarioLog then
            Broker_MidnightEventsBeacon.scenarioLog[CharKey()] = nil
        end
        if Broker_MidnightEventsBeacon.lootLog then
            Broker_MidnightEventsBeacon.lootLog[CharKey()] = nil
        end
        lastState = {}
        print("|cffffcc00MidnightEvents/BeaconHarvest|r cleared per-char data (incl. crest + delve + scenario + loot logs).")
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

-- ── Live crest-loot correlation (dev) ────────────────────────────────────────
-- Detects mythic-crest gains from delve coffers in real time and pairs
-- them with quest-objective increments that land in the same window, so
-- we can see WHICH quest tracks the 20-crests weekly (if any) without
-- guessing. Two SV rings under Broker_MidnightEventsBeacon.crestLog[char]:
--   crests   — every crest-currency GAIN while in a delve (scenario):
--              { t, currencyID, name, delta, gainSource, mapID }
--   questIncr — every quest-objective increment while in a delve:
--              { t, questID, title, from, to }
-- Both are timestamped; cross-correlation = find the questIncr whose
-- t is adjacent to a crest gain and whose delta matches. Echoed live to
-- chat so the adjacency is visible as it happens (quest increments only
-- echo within CREST_ECHO_WINDOW of a crest gain to keep chat focused;
-- the SV ring keeps everything for post-hoc).
--
-- Gated to scenario (delve) instanceType so raid / dungeon crest gains
-- are excluded by construction — the exact "don't count other sources"
-- requirement.
local CREST_CRESTS_RING  = 100   -- crest gains are rare; won't be evicted by quest spam
local CREST_QINCR_RING   = 300
local CREST_ECHO_WINDOW  = 12    -- seconds; echo quest increments this long after a crest gain
local crestSnapshot      = nil   -- questID -> { sum, title }; nil until first walk
local lastCrestGainAt    = 0
local lastQincrWalkAt    = 0

local function CrestInScenario()
    local _, itype = IsInInstance()
    return itype == "scenario"
end

local function CrestLogBucket(field, ringCap)
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    local root = Broker_MidnightEventsBeacon
    root.crestLog = root.crestLog or {}
    local key = CharKey()
    local cl = root.crestLog[key]
    if not cl then cl = {}; root.crestLog[key] = cl end
    cl[field] = cl[field] or { ring = {}, cursor = 0, cap = ringCap }
    return cl[field]
end

local function CrestPush(field, ringCap, rec)
    local b = CrestLogBucket(field, ringCap)
    b.cursor = b.cursor + 1
    if b.cursor > b.cap then b.cursor = 1 end
    b.ring[b.cursor] = rec
end

-- Walk quest objectives, summing numFulfilled per quest. Returns the
-- snapshot table { questID -> { sum, title } }.
local function CrestWalkQuests()
    local snap = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return snap end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objs = C_QuestLog.GetQuestObjectives
                         and C_QuestLog.GetQuestObjectives(info.questID) or {}
            local sum = 0
            for _, o in ipairs(objs) do sum = sum + (o.numFulfilled or 0) end
            snap[info.questID] = {
                sum   = sum,
                title = C_QuestLog.GetTitleForQuestID
                        and C_QuestLog.GetTitleForQuestID(info.questID),
            }
        end
    end
    return snap
end

-- Diff against crestSnapshot, return list of increments, update snapshot.
local function CrestDiffQuests()
    local now = CrestWalkQuests()
    local incr = {}
    if crestSnapshot then
        for qid, cur in pairs(now) do
            local prev = crestSnapshot[qid]
            local from = prev and prev.sum or 0
            if cur.sum > from then
                incr[#incr + 1] = {
                    questID = qid, title = cur.title, from = from, to = cur.sum,
                }
            end
        end
    end
    crestSnapshot = now
    return incr
end

local function IsCrestCurrency(currencyID)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info and info.name and info.name:lower():find("crest") then
        return info.name
    end
    return nil
end

local cf = CreateFrame("Frame")
cf:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
cf:RegisterEvent("QUEST_LOG_UPDATE")
cf:SetScript("OnEvent", function(_, event, ...)
    if event == "CURRENCY_DISPLAY_UPDATE" then
        if not CrestInScenario() then return end
        local currencyID, _, quantityChange, gainSource = ...
        if not currencyID or (quantityChange or 0) <= 0 then return end
        local name = IsCrestCurrency(currencyID)
        if not name then return end
        lastCrestGainAt = time()
        CrestPush("crests", CREST_CRESTS_RING, {
            t          = lastCrestGainAt,
            currencyID = currencyID,
            name       = name,
            delta      = quantityChange,
            gainSource = gainSource,
            mapID      = C_Map and C_Map.GetBestMapForUnit
                         and C_Map.GetBestMapForUnit("player") or nil,
        })
        print(string.format(
            "|cffffcc00MidnightEvents/Crest|r +%d %s [gainSource=%s] (delve)",
            quantityChange, name, tostring(gainSource)))
        -- Sweep for a quest increment that landed just before this gain.
        local incr = CrestDiffQuests()
        for _, q in ipairs(incr) do
            CrestPush("questIncr", CREST_QINCR_RING, {
                t = lastCrestGainAt, questID = q.questID,
                title = q.title, from = q.from, to = q.to,
            })
            print(string.format(
                "|cffffcc00MidnightEvents/Crest|r   ↳ quest %d %q  %d→%d",
                q.questID, tostring(q.title), q.from, q.to))
        end
    elseif event == "QUEST_LOG_UPDATE" then
        -- Debounce: QUEST_LOG_UPDATE fires in bursts.
        if (time() - lastQincrWalkAt) < 1 then
            -- still refresh snapshot occasionally so baseline doesn't drift,
            -- but skip the heavy per-increment logging within the debounce.
        end
        lastQincrWalkAt = time()
        local incr = CrestDiffQuests()
        if not CrestInScenario() then return end  -- snapshot stays fresh; don't log outside delves
        local within = (time() - lastCrestGainAt) <= CREST_ECHO_WINDOW
        for _, q in ipairs(incr) do
            CrestPush("questIncr", CREST_QINCR_RING, {
                t = time(), questID = q.questID,
                title = q.title, from = q.from, to = q.to,
            })
            if within then
                print(string.format(
                    "|cffffcc00MidnightEvents/Crest|r quest %d %q  %d→%d (near crest)",
                    q.questID, tostring(q.title), q.from, q.to))
            end
        end
    end
end)

-- ── Delve-wide quest transition recorder (dev) ───────────────────────────────
-- 91190 turned out to be per-delve plumbing: the flag that PLACES the reward
-- chest in the delve's reward room and holds it until looted (fires on every
-- bountiful delve, Beacon=0/Bounty=0). The STILL-OPEN question is what
-- UNLOCKS that chest from looting Nullaeus's cache mid-delve — an unknown
-- quest/flag the targeted TRACKED_QUEST_IDS net can't catch.
--
-- This casts a wide net while inside a delve (scenario instanceType). It logs
-- EVERY quest transition, via two complementary channels:
--   1. Full quest-log diff — catches LOG-VISIBLE quests appearing,
--      disappearing, completing, or changing objective totals.
--   2. Raw quest events — every QUEST_TURNED_IN / QUEST_ACCEPTED /
--      QUEST_REMOVED questID. This is the channel that catches HIDDEN
--      auto-credit quests (e.g. the 75511 "Tracking Quest" / 48642 churn we
--      already saw) — exactly the shape a cache-loot credit is likely to
--      take, since flag-only quests never appear in the log walk.
-- Every record is stamped with `sinceLoot` (seconds since the last
-- LOOT_OPENED/CLOSED) so a cache-loot → chest-unlock link is visible at a
-- glance. Snapshot stays fresh outside delves so the baseline doesn't drift;
-- recording is gated to scenario so the wider world doesn't spam the log.
--
-- SV: Broker_MidnightEventsBeacon.delveLog[char] = { ring, cursor, cap }
local DELVE_RING        = 400
local DELVE_POLL_INTERVAL = 10 -- seconds; cheap log walk, delve-gated. Tighter
                               -- than 60 so a silent (event-less) state change is
                               -- caught with a small sinceLoot for loot correlation.
local delveSnap         = nil  -- questID -> { title, complete, sum, text }
local lastDelveWalkAt   = 0
local lastLootAt        = 0
local delveTrigger      = "quest-log"

local function DelveInScenario()
    local _, itype = IsInInstance()
    return itype == "scenario"
end

local function DelveWalk()
    local snap = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return snap end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local qid  = info.questID
            local objs = C_QuestLog.GetQuestObjectives
                         and C_QuestLog.GetQuestObjectives(qid) or {}
            local sum = 0
            for _, o in ipairs(objs) do sum = sum + (o.numFulfilled or 0) end
            snap[qid] = {
                title    = C_QuestLog.GetTitleForQuestID
                           and C_QuestLog.GetTitleForQuestID(qid),
                complete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid)) or false,
                sum      = sum,
                text     = (objs[1] and objs[1].text) or nil,
            }
        end
    end
    return snap
end

local function DelvePush(rec)
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    local root = Broker_MidnightEventsBeacon
    root.delveLog = root.delveLog or {}
    local key = CharKey()
    local dl  = root.delveLog[key]
    if not dl then dl = { ring = {}, cursor = 0, cap = DELVE_RING }; root.delveLog[key] = dl end
    dl.cursor = dl.cursor + 1
    if dl.cursor > dl.cap then dl.cursor = 1 end
    dl.ring[dl.cursor] = rec
end

local function DelveStamp(rec)
    rec.t         = time()
    rec.trigger   = delveTrigger
    rec.sinceLoot = (lastLootAt > 0) and (time() - lastLootAt) or nil
    rec.ctx       = InstanceContext()
    DelvePush(rec)
    print(string.format(
        "|cff66ccffMidnightEvents/Delve|r %s quest %s %q%s [%s]",
        rec.kind, tostring(rec.questID), tostring(rec.title),
        rec.sinceLoot and string.format(" (+%ds since loot)", rec.sinceLoot) or "",
        delveTrigger))
end

-- Channel 2: raw quest event for a questID (hidden auto-credit catch).
local function DelveEvent(kind, qid)
    if not qid or not DelveInScenario() then return end
    DelveStamp({
        kind    = "event:" .. kind,
        questID = qid,
        title   = C_QuestLog and C_QuestLog.GetTitleForQuestID
                  and C_QuestLog.GetTitleForQuestID(qid) or nil,
    })
end

-- Channel 1: full quest-log diff. Always refreshes the snapshot; only
-- emits records while in a delve.
local function DelveDiff()
    local now = DelveWalk()
    if delveSnap and DelveInScenario() then
        for qid, cur in pairs(now) do
            local prev = delveSnap[qid]
            if not prev then
                DelveStamp({ kind = "added", questID = qid, title = cur.title, text = cur.text })
            else
                if cur.complete and not prev.complete then
                    DelveStamp({ kind = "complete", questID = qid, title = cur.title, text = cur.text })
                end
                if cur.sum ~= prev.sum then
                    DelveStamp({ kind = "progress", questID = qid, title = cur.title,
                                 text = cur.text, from = prev.sum, to = cur.sum })
                end
            end
        end
        for qid, prev in pairs(delveSnap) do
            if not now[qid] then
                DelveStamp({ kind = "removed", questID = qid, title = prev.title })
            end
        end
    end
    delveSnap = now
end

local df = CreateFrame("Frame")
df:RegisterEvent("QUEST_LOG_UPDATE")
df:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
df:RegisterEvent("QUEST_ACCEPTED")
df:RegisterEvent("QUEST_TURNED_IN")
df:RegisterEvent("QUEST_REMOVED")
df:RegisterEvent("LOOT_OPENED")
df:RegisterEvent("LOOT_CLOSED")
df:SetScript("OnEvent", function(_, event, arg1)
    if event == "LOOT_OPENED" or event == "LOOT_CLOSED" then
        -- Anchor the loot moment so subsequent quest transitions carry a
        -- sinceLoot delta. Diff immediately — a cache loot that auto-credits
        -- a hidden quest often lands in the same frame as LOOT_CLOSED.
        lastLootAt   = time()
        delveTrigger = event
        DelveDiff()
        -- The unlock flag can flip a beat AFTER the loot window closes with
        -- no further event; re-diff once shortly after to catch that lag
        -- while sinceLoot is still small.
        if event == "LOOT_CLOSED" and C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                if not DelveInScenario() then return end
                delveTrigger = "post-loot+2s"
                DelveDiff()
                delveTrigger = "quest-log"
            end)
        end
        delveTrigger = "quest-log"
        return
    elseif event == "QUEST_TURNED_IN" then
        DelveEvent("turnedin", arg1)
        delveTrigger = "QUEST_TURNED_IN:" .. tostring(arg1)
    elseif event == "QUEST_ACCEPTED" then
        DelveEvent("accepted", arg1)
        delveTrigger = "QUEST_ACCEPTED:" .. tostring(arg1)
    elseif event == "QUEST_REMOVED" then
        DelveEvent("removed", arg1)
        delveTrigger = "QUEST_REMOVED:" .. tostring(arg1)
    else
        -- QUEST_LOG_UPDATE / UNIT_QUEST_LOG_CHANGED fire in bursts; debounce
        -- the heavy full-log walk to once a second. LOOT_CLOSED above forces
        -- an undebounced diff, so the cache-loot moment is never missed.
        if (time() - lastDelveWalkAt) < 1 then return end
    end
    lastDelveWalkAt = time()
    DelveDiff()
    delveTrigger = "quest-log"
end)

-- Polling backstop: the chest-unlock flag may change with NO event at all,
-- so the event hooks above would never see it. A delve-gated ticker re-diffs
-- on a tight cadence to catch silent transitions. Always-on (the in-delve
-- gate is inside the callback) so it doesn't need start/stop on zone change.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(DELVE_POLL_INTERVAL, function()
        if not DelveInScenario() then return end
        delveTrigger = "delve-ticker"
        DelveDiff()
        delveTrigger = "quest-log"
    end)
end

-- ── Scenario-criteria recorder (dev) ─────────────────────────────────────────
-- 2026-06-03 result: using a Beacon + looting Nullaeus's cache produced ZERO
-- quest signal — no tracked-flag flip (transitionCursor unchanged), no
-- quest-log change, no quest event (delveLog stayed empty). Delve objectives
-- and rewards are driven by SCENARIO CRITERIA (C_ScenarioInfo), not quests, so
-- the quest recorders above are structurally blind to the chest-unlock. This
-- records every scenario-criteria change (added / progress / complete) with the
-- same sinceLoot correlation, so a "cache loot -> a criterion completes ->
-- reward chest unlocks" chain becomes visible. SV: scenarioLog[char].
local SCEN_RING        = 400
local scenSnap         = nil   -- criteriaIndex -> { id, desc, quantity, total, completed }
local scenTrigger      = "scenario"

local function ScenWalk()
    local snap = {}
    if not (C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then return snap end
    for i = 1, 25 do
        local c = C_ScenarioInfo.GetCriteriaInfo(i)
        if not c then break end
        snap[i] = {
            id        = c.criteriaID,
            desc      = c.description,
            quantity  = c.quantity,
            total     = c.totalQuantity,
            completed = c.completed and true or false,
        }
    end
    return snap
end

local function ScenPush(rec)
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    local root = Broker_MidnightEventsBeacon
    root.scenarioLog = root.scenarioLog or {}
    local key = CharKey()
    local sl  = root.scenarioLog[key]
    if not sl then sl = { ring = {}, cursor = 0, cap = SCEN_RING }; root.scenarioLog[key] = sl end
    sl.cursor = sl.cursor + 1
    if sl.cursor > sl.cap then sl.cursor = 1 end
    sl.ring[sl.cursor] = rec
end

local function ScenStamp(kind, c, extra)
    local rec = {
        t         = time(),
        kind      = kind,
        id        = c and c.id,
        desc      = c and c.desc,
        quantity  = c and c.quantity,
        total     = c and c.total,
        completed = c and c.completed,
        trigger   = scenTrigger,
        sinceLoot = (lastLootAt > 0) and (time() - lastLootAt) or nil,
        ctx       = InstanceContext(),
    }
    if extra then for k, v in pairs(extra) do rec[k] = v end end
    ScenPush(rec)
    print(string.format(
        "|cffcc66ffMidnightEvents/Scenario|r %s %q  q=%s/%s done=%s%s [%s]",
        kind, tostring(rec.desc), tostring(rec.quantity), tostring(rec.total),
        tostring(rec.completed),
        rec.sinceLoot and string.format(" (+%ds since loot)", rec.sinceLoot) or "",
        scenTrigger))
end

local function ScenDiff()
    local now = ScenWalk()
    if scenSnap and DelveInScenario() then
        for i, cur in pairs(now) do
            local prev = scenSnap[i]
            if not prev then
                ScenStamp("added", cur)
            elseif cur.completed and not prev.completed then
                ScenStamp("complete", cur)
            elseif cur.quantity ~= prev.quantity then
                ScenStamp("progress", cur, { from = prev.quantity, to = cur.quantity })
            end
        end
    end
    scenSnap = now
end

local scf = CreateFrame("Frame")
scf:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
scf:RegisterEvent("SCENARIO_UPDATE")
scf:RegisterEvent("SCENARIO_POI_UPDATE")
scf:RegisterEvent("CRITERIA_UPDATE")
scf:RegisterEvent("LOOT_OPENED")
scf:RegisterEvent("LOOT_CLOSED")
scf:SetScript("OnEvent", function(_, event)
    if event == "LOOT_OPENED" or event == "LOOT_CLOSED" then
        -- Share the loot anchor (the delve recorder sets it too; idempotent)
        -- and re-diff so a criterion that completes on the cache loot carries a
        -- small sinceLoot. A second pass 2s later catches a lagged completion.
        lastLootAt  = time()
        scenTrigger = event
        ScenDiff()
        if event == "LOOT_CLOSED" and C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                if not DelveInScenario() then return end
                scenTrigger = "post-loot+2s"
                ScenDiff()
                scenTrigger = "scenario"
            end)
        end
        scenTrigger = "scenario"
        return
    end
    scenTrigger = event
    ScenDiff()
    scenTrigger = "scenario"
end)

-- Polling backstop for criteria that change with no event.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(DELVE_POLL_INTERVAL, function()
        if not DelveInScenario() then return end
        scenTrigger = "scen-ticker"
        ScenDiff()
        scenTrigger = "scenario"
    end)
end

-- ── Loot-source recorder (dev) ───────────────────────────────────────────────
-- Identify WHICH container was looted (Nullaeus's cache, the end reward chest,
-- …) by its GameObject ID, plus the items/currency it held. GetLootSourceInfo's
-- GUID encodes the source GameObject (`GameObject-0-…-<objectID>-…`), so this
-- directly answers "did I loot the cache, and what came out" — no quest or
-- scenario flag required. Delve-gated. SV: lootLog[char].
local LOOT_RING = 200

-- Known delve container object IDs (Wowhead), for labelling the echo. The
-- recorder works for ANY container by ID; these just make the cache obvious.
local KNOWN_OBJECTS = {
    [618495] = "Nullaeus Cache",   -- the nemesis cache (object=618495)
}

-- Returns (kind, objectID) from a unit/object GUID; objectID is field 6 for
-- Creature/GameObject/Vehicle GUIDs. nil for Item/Player/other shapes.
local function GUIDObjectID(guid)
    if type(guid) ~= "string" then return nil, nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

local function LootPush(rec)
    Broker_MidnightEventsBeacon = Broker_MidnightEventsBeacon or {}
    local root = Broker_MidnightEventsBeacon
    root.lootLog = root.lootLog or {}
    local key = CharKey()
    local ll  = root.lootLog[key]
    if not ll then ll = { ring = {}, cursor = 0, cap = LOOT_RING }; root.lootLog[key] = ll end
    ll.cursor = ll.cursor + 1
    if ll.cursor > ll.cap then ll.cursor = 1 end
    ll.ring[ll.cursor] = rec
end

local lootF = CreateFrame("Frame")
lootF:RegisterEvent("LOOT_OPENED")
lootF:SetScript("OnEvent", function()
    if not DelveInScenario() then return end  -- only care about in-delve containers
    local n = (GetNumLootItems and GetNumLootItems()) or 0
    local sources, items = {}, {}
    for i = 1, n do
        if GetLootSlotInfo then
            -- icon, name, quantity, currencyID, quality, locked, isQuestItem, questID
            local _, name, qty, currencyID = GetLootSlotInfo(i)
            items[#items + 1] = {
                name       = name,
                qty        = qty,
                currencyID = currencyID,
                link       = GetLootSlotLink and GetLootSlotLink(i) or nil,
            }
        end
        if GetLootSourceInfo then
            -- A slot can have multiple (guid, quantity) source pairs.
            local s = { GetLootSourceInfo(i) }
            for j = 1, #s, 2 do
                local kind, id = GUIDObjectID(s[j])
                if id then sources[id] = kind end
            end
        end
    end
    local srcList = {}
    for id, kind in pairs(sources) do srcList[#srcList + 1] = { id = id, kind = kind } end
    LootPush({ t = time(), sources = srcList, items = items, ctx = InstanceContext() })

    local srcStr = {}
    for _, sv in ipairs(srcList) do
        local label = KNOWN_OBJECTS[sv.id]
        srcStr[#srcStr + 1] = label
            and (label .. " [" .. sv.kind .. ":" .. sv.id .. "]")
            or (sv.kind .. ":" .. sv.id)
    end
    local itemStr = {}
    for _, it in ipairs(items) do
        itemStr[#itemStr + 1] = tostring(it.name)
            .. (it.currencyID and (" (cur " .. it.currencyID .. ")") or "")
    end
    print(string.format(
        "|cff66ff99MidnightEvents/Loot|r from {%s}: %s",
        table.concat(srcStr, ", "),
        (#itemStr > 0) and table.concat(itemStr, ", ") or "(empty)"))
end)
