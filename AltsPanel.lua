-- Broker_MidnightEvents - AltsPanel
-- Detached frame showing per-alt weekly completion in a tabular grid.
-- Opened via Shift-RightClick on the broker button (wired in Core.lua).
-- One row per tracked character, sorted by most-recent login first.
-- Stale characters (no login since the most recent weekly reset) render
-- as a dim row of em-dashes — their data doesn't reflect this week.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...
ns.AltsPanel = ns.AltsPanel or {}

-- ── Layout constants ──────────────────────────────────────────────────────────
local FRAME_WIDTH   = 620
local FRAME_HEIGHT  = 380
local ROW_HEIGHT    = 22
local NAME_WIDTH    = 110
local CELL_WIDTH    = 60
local HEADER_HEIGHT = 22

local CHECK = "|A:common-icon-checkmark:14:14|a"
local CROSS = "|A:common-icon-redx:14:14|a"
local DASH  = "—"

-- Private tooltip frame for column-header hover. Same containment rationale
-- as the main tooltip in Core.lua: this addon reads C_UIWidgetManager
-- barValue/barMax and does arithmetic on them (taints control flow under
-- 12.x's protected-data model). Writing to the SHARED GameTooltip from any
-- handler in this addon would propagate the taint to GameTooltip itself —
-- which Blizzard's events-panel tooltip uses, leading to "compare a secret
-- number value" errors deep in widget layout. Containment: our own frame.
local HeaderTip = CreateFrame("GameTooltip",
                              "BrokerMidnightEventsAltsHeaderTip",
                              UIParent,
                              "GameTooltipTemplate")

local panel       -- created lazily on first Toggle()
local rowPool = {}
local cellPoolByRow = setmetatable({}, { __mode = "k" })

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function StripRealm(charKey)
    return charKey:match("/(.+)$") or charKey
end

local function ClampName(name)
    if #name > 10 then return name:sub(1, 9) .. "…" end
    return name
end

local function ClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Build the active column list. Boss + ns.weeklies in declared order, gated
-- by db.showWorldBosses. Mirrors the tooltip's "This Week" row order so the
-- panel reads as a transposed version of the same data.
-- `short` is the header cell text; `label` is the full name shown on the
-- header-cell hover tooltip (so the abbreviations stay decipherable).
local function GetColumns()
    local cols = {}
    local showWB = not ns.db or ns.db.showWorldBosses ~= false
    if showWB then
        cols[#cols + 1] = {
            key = "_boss", short = "WBoss", label = "World Boss", kind = "boss",
        }
    end
    for _, w in ipairs(ns.weeklies or {}) do
        cols[#cols + 1] = {
            key   = w.key,
            short = w.short or w.label or w.key,
            label = w.label or w.short or w.key,
            kind  = "weekly",
        }
    end
    return cols
end

local DEFAULT_BG_ALPHA = 0.6

-- Apply the background opacity from db.altsPanel.bgAlpha to the panel's
-- backing textures. Called at panel creation and again on settings change.
--
-- BasicFrameTemplateWithInset has its dark body backing inside Inset's
-- nine-slice (not a single named .Bg field), so iterate every texture
-- region on both the outer frame and the Inset frame and alpha them.
-- FontStrings + child Frames (scroll content, rows) are unaffected, so
-- text and icons stay fully opaque.
local function alphaTextures(frame, alpha)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(alpha)
        end
    end
end

local function ApplyBackgroundAlpha(f)
    if not f then return end
    local alpha = (ns.db and ns.db.altsPanel and ns.db.altsPanel.bgAlpha)
                  or DEFAULT_BG_ALPHA
    alphaTextures(f, alpha)
    alphaTextures(f.Inset, alpha)
    -- NineSlice mixin (used by Inset) keeps its border art on a child frame
    -- named NineSlice; iterate it too so the body really lets the world
    -- behind show through.
    if f.NineSlice       then alphaTextures(f.NineSlice, alpha)       end
    if f.Inset and f.Inset.NineSlice then alphaTextures(f.Inset.NineSlice, alpha) end
end

function ns.AltsPanel.RefreshBackground()
    ApplyBackgroundAlpha(panel)
end

-- ── Frame plumbing ────────────────────────────────────────────────────────────

local function PersistGeometry()
    if not (panel and ns.db and ns.db.altsPanel) then return end
    local point, _, _, x, y = panel:GetPoint()
    if point then
        ns.db.altsPanel.point = point
        ns.db.altsPanel.x     = x or 0
        ns.db.altsPanel.y     = y or 0
    end
end

local function ApplyGeometry()
    if not (panel and ns.db and ns.db.altsPanel) then return end
    local g = ns.db.altsPanel
    panel:ClearAllPoints()
    panel:SetPoint(g.point or "CENTER", UIParent, g.point or "CENTER",
                   g.x or 0, g.y or 0)
end

-- Row factory. Each row gets a name FontString on the left + a cell per column
-- on the right; cells are created on demand via a pool to handle column-count
-- changes (e.g. if the user toggles showWorldBosses off mid-session).
local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.03)
    row.bg:Hide()

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(NAME_WIDTH - 12)
    row.name:SetWordWrap(false)

    cellPoolByRow[row] = {}
    return row
end

local function GetCell(row, index)
    local pool = cellPoolByRow[row]
    if not pool[index] then
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("LEFT", row, "LEFT", NAME_WIDTH + (index - 1) * CELL_WIDTH, 0)
        fs:SetWidth(CELL_WIDTH)
        fs:SetJustifyH("CENTER")
        pool[index] = fs
    end
    pool[index]:Show()
    return pool[index]
end

local function HideExcessCells(row, usedCount)
    local pool = cellPoolByRow[row]
    if not pool then return end
    for i = usedCount + 1, #pool do
        pool[i]:Hide()
    end
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function PopulateRow(row, charKey, char, columns, currentWeeklyReset)
    local isStale = (char.lastLogin or 0) < (currentWeeklyReset or 0)
    local nameText = ClampName(StripRealm(charKey))
    local r, g, b  = ClassColor(char.class)
    if isStale then
        r, g, b = r * 0.55, g * 0.55, b * 0.55
    end
    row.name:SetText(nameText)
    row.name:SetTextColor(r, g, b)

    local weeklies = char.weeklies or {}
    for i, col in ipairs(columns) do
        local cell = GetCell(row, i)
        if isStale then
            cell:SetText(DASH)
            cell:SetTextColor(0.4, 0.4, 0.4)
        elseif col.kind == "boss" then
            if char.worldBoss and char.worldBoss.done then
                cell:SetText(CHECK)
                cell:SetTextColor(0.55, 0.85, 0.55)
            else
                cell:SetText(CROSS)
                cell:SetTextColor(0.9, 0.55, 0.25)
            end
        else
            if weeklies[col.key] then
                cell:SetText(CHECK)
                cell:SetTextColor(0.55, 0.85, 0.55)
            else
                cell:SetText(CROSS)
                cell:SetTextColor(0.9, 0.55, 0.25)
            end
        end
    end
    HideExcessCells(row, #columns)
end

-- Header-cell hover shows the full column label. Uses the addon's private
-- HeaderTip frame, NOT the shared GameTooltip — our control flow is
-- already tainted by GetEventProgress's widget arithmetic elsewhere in the
-- addon, so touching shared GameTooltip from any of our handlers would
-- propagate taint into Blizzard UI paths that operate on it.
local function HeaderCellOnEnter(self)
    if not self.fullLabel then return end
    HeaderTip:SetOwner(self, "ANCHOR_TOP")
    HeaderTip:SetText(self.fullLabel)
    HeaderTip:Show()
end
local function HeaderCellOnLeave()
    HeaderTip:Hide()
end

local function RenderHeader(columns)
    panel.header:SetWidth(FRAME_WIDTH - 24)
    panel.header.nameLabel:SetText("Char")
    for i, col in ipairs(columns) do
        local cell = panel.header.cells[i]
        if not cell then
            cell = CreateFrame("Frame", nil, panel.header)
            cell:SetSize(CELL_WIDTH, HEADER_HEIGHT)
            cell:SetPoint("LEFT", panel.header, "LEFT",
                          NAME_WIDTH + (i - 1) * CELL_WIDTH, 0)
            local fs = cell:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            fs:SetAllPoints()
            fs:SetJustifyH("CENTER")
            cell.text = fs
            cell:EnableMouse(true)
            cell:SetScript("OnEnter", HeaderCellOnEnter)
            cell:SetScript("OnLeave", HeaderCellOnLeave)
            panel.header.cells[i] = cell
        end
        cell.text:SetText(col.short)
        cell.text:SetTextColor(0.7, 0.85, 0.85)
        cell.fullLabel = col.label ~= col.short and col.label or nil
        cell:Show()
    end
    for i = #columns + 1, #panel.header.cells do
        panel.header.cells[i]:Hide()
    end
end

local function CollectChars()
    local out = {}
    if not (ns.db and ns.db.chars) then return out end
    local hidden = ns.db.hiddenChars or {}
    for charKey, char in pairs(ns.db.chars) do
        if not hidden[charKey] then
            out[#out + 1] = { key = charKey, data = char }
        end
    end
    table.sort(out, function(a, b)
        return (a.data.lastLogin or 0) > (b.data.lastLogin or 0)
    end)
    return out
end

local function Render()
    if not panel or not panel:IsShown() then return end

    local cols = GetColumns()
    RenderHeader(cols)

    local chars = CollectChars()
    local currentWeeklyReset = ns.char and ns.char.weeklyReset or 0

    -- Resize content for scroll math.
    local contentHeight = math.max(1, #chars * ROW_HEIGHT)
    panel.content:SetHeight(contentHeight)
    panel.content:SetWidth(FRAME_WIDTH - 60)

    for i, entry in ipairs(chars) do
        if not rowPool[i] then
            rowPool[i] = CreateRow(panel.content)
        end
        local row = rowPool[i]
        row:SetWidth(panel.content:GetWidth())
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row.bg:SetShown(i % 2 == 0)
        PopulateRow(row, entry.key, entry.data, cols, currentWeeklyReset)
        row:Show()
    end
    for i = #chars + 1, #rowPool do
        rowPool[i]:Hide()
    end

    panel.summary:SetText(string.format("%d tracked", #chars))
end

-- ── Frame creation ────────────────────────────────────────────────────────────

local function CreatePanel()
    local f = CreateFrame("Frame", "BrokerMidnightEventsAltsPanel",
                          UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        PersistGeometry()
    end)
    f:SetScript("OnShow",  function() Render()  end)

    f.TitleText:SetText("Broker_MidnightEvents · Alts")

    -- Summary line (top-right of inset area).
    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.summary:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -32)

    -- Fixed header row above the scrollable content.
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetHeight(HEADER_HEIGHT)
    f.header:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -28 - 8)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28 - 8)
    f.header.nameLabel = f.header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.header.nameLabel:SetPoint("LEFT", 6, 0)
    f.header.nameLabel:SetWidth(NAME_WIDTH - 12)
    f.header.nameLabel:SetJustifyH("LEFT")
    f.header.nameLabel:SetTextColor(0.7, 0.85, 0.85)
    f.header.cells = {}

    -- Scroll frame for char rows.
    local scroll = CreateFrame("ScrollFrame", "$parentScrollFrame", f,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     12, -28 - 8 - HEADER_HEIGHT - 2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 10)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    f.scroll  = scroll
    f.content = content

    ApplyBackgroundAlpha(f)
    return f
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ns.AltsPanel.Show()
    if not panel then panel = CreatePanel() end
    ApplyGeometry()
    panel:Show()
    Render()
end

function ns.AltsPanel.Hide()
    if panel then panel:Hide() end
end

function ns.AltsPanel.Toggle()
    if panel and panel:IsShown() then
        panel:Hide()
    else
        ns.AltsPanel.Show()
    end
end

-- Re-render when shown. Called by Core after weekly-state changes so live
-- updates flow through without the user needing to close/reopen the panel.
function ns.AltsPanel.RefreshIfShown()
    if panel and panel:IsShown() then Render() end
end
