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
local FRAME_HEIGHT  = 380
local ROW_HEIGHT    = 22
local NAME_WIDTH    = 110
local CELL_WIDTH    = 60
local HEADER_HEIGHT = 22
local FRAME_PADDING = 50   -- right-side gutter accommodating the close button + scrollbar

-- Frame width is derived from the active column count at render time. Falls
-- back to a sane minimum if columns aren't built yet.
local function ComputeFrameWidth(columnCount)
    return math.max(360, NAME_WIDTH + columnCount * CELL_WIDTH + FRAME_PADDING)
end

local CHECK = "|A:common-icon-checkmark:14:14|a"
local CROSS = "|A:common-icon-redx:14:14|a"
local DASH  = "—"

-- ── Smoke-glass design tokens ────────────────────────────────────────────────
-- Adopts the visual language of the parent Mythforge web UI:
-- dark zinc backdrop, amber accent border + title, zinc-tone separators.
-- 'backdrop-blur' isn't reachable from WoW Lua; we approximate with a
-- solid dark colour + user-tunable alpha. Border drawn as 4 thin line
-- textures (top/bottom/left/right) tinted amber-700 at 0.3 alpha.
local STYLE = {
    bgR = 0.035, bgG = 0.035, bgB = 0.043,           -- zinc-950 #09090b
    borderR = 0.71, borderG = 0.33, borderB = 0.04,  -- amber-700 #b45309
    borderAlpha   = 0.30,                            -- /30
    titleR = 0.99, titleG = 0.83, titleB = 0.30,     -- amber-300 #fcd34d
    sepR = 0.16, sepG = 0.16, sepB = 0.17,           -- zinc-800 #27272a
    headerR = 0.45, headerG = 0.46, headerB = 0.50,  -- zinc-500 #71717a
    textR = 0.89, textG = 0.89, textB = 0.91,        -- zinc-200 #e4e4e7
    rowAltAlpha = 0.04,                              -- alternating row tint
}

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
            levelMin = 90,  -- World Boss credit gates at max level; cells DASH below it.
        }
    end
    for _, w in ipairs(ns.weeklies or {}) do
        -- Mirror the tooltip's hideInTooltip suppression so suppressed rows
        -- (e.g. Arcantina pending its credit-trigger investigation) don't
        -- clutter the panel either.
        if not w.hideInTooltip then
            cols[#cols + 1] = {
                key      = w.key,
                short    = w.short or w.label or w.key,
                label    = w.label or w.short or w.key,
                kind     = "weekly",
                levelMin = w.levelMin,
                levelMax = w.levelMax,
            }
        end
    end
    return cols
end

local DEFAULT_BG_ALPHA = 0.6

-- Apply the background opacity from db.altsPanel.bgAlpha to the panel's
-- main backdrop only. The amber border + zinc separators keep their
-- intrinsic alpha so the panel's frame stays legible regardless of how
-- transparent the backdrop is set — matches a real smoke-glass look
-- (the pane goes translucent, the bezel/edges stay defined).
local function ApplyBackgroundAlpha(f)
    if not f then return end
    local alpha = (ns.db and ns.db.altsPanel and ns.db.altsPanel.bgAlpha)
                  or DEFAULT_BG_ALPHA
    if f.Bg then f.Bg:SetAlpha(alpha) end
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

-- Right-click handler: toggle this row's character in the hidden set.
-- The character disappears from the panel on next render. To un-hide,
-- flip Settings → "Show hidden characters" — hidden chars then appear
-- dimmed, and right-click flips them back to visible.
local function OnRowMouseUp(self, button)
    if button ~= "RightButton" then return end
    if not (self.charKey and ns.db) then return end
    ns.db.hiddenChars = ns.db.hiddenChars or {}
    if ns.db.hiddenChars[self.charKey] then
        ns.db.hiddenChars[self.charKey] = nil
    else
        ns.db.hiddenChars[self.charKey] = true
    end
    if ns.AltsPanel.RefreshIfShown then ns.AltsPanel.RefreshIfShown() end
end

-- Row factory. Each row gets a name FontString on the left + a cell per column
-- on the right; cells are created on demand via a pool to handle column-count
-- changes (e.g. if the user toggles showWorldBosses off mid-session).
-- Rows accept mouse so right-click can toggle hidden state per character.
local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", OnRowMouseUp)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, STYLE.rowAltAlpha)
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

local function PopulateRow(row, charKey, char, columns, currentWeeklyReset, isHidden)
    row.charKey = charKey  -- consumed by OnRowMouseUp for the toggle
    local isStale = (char.lastLogin or 0) < (currentWeeklyReset or 0)
    local nameText = ClampName(StripRealm(charKey))
    local r, g, b  = ClassColor(char.class)
    if isStale then
        r, g, b = r * 0.55, g * 0.55, b * 0.55
    end
    if isHidden then
        -- Visible only when Settings → "Show hidden characters" is on.
        -- Extra-dim to make the "hidden but currently displayed" state
        -- visually distinct from normal active rows.
        r, g, b = r * 0.45, g * 0.45, b * 0.45
    end
    row.name:SetText(nameText)
    row.name:SetTextColor(r, g, b)

    local weeklies = char.weeklies or {}
    -- charLevel defaults to 0 when we haven't yet observed this character
    -- post-feature deploy. That biases levelMin gates toward "dash" (0 <
    -- 90 = true) — the honest signal for "we can't confirm this row is
    -- available here." levelMax checks (0 > 89 = false) remain safe so an
    -- unknown-level char doesn't get the sub-90-only row dashed by
    -- mistake. Cleared the moment the char logs in once with the addon.
    local charLevel = char.level or 0
    for i, col in ipairs(columns) do
        local cell = GetCell(row, i)
        local levelGated = (col.levelMin and charLevel < col.levelMin)
                        or (col.levelMax and charLevel > col.levelMax)
        if isStale then
            cell:SetText(DASH)
            cell:SetTextColor(0.4, 0.4, 0.4)
        elseif levelGated then
            -- Row unavailable on this character (sub-90 alt, etc.). Render
            -- DASH so the cell is honest about "not applicable" rather than
            -- showing a permanent ✗ that misreads as "they could but didn't".
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
    panel.header:SetWidth(panel:GetWidth() - 24)
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
        cell.text:SetTextColor(STYLE.headerR, STYLE.headerG, STYLE.headerB)
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
    local hidden    = ns.db.hiddenChars or {}
    local showHidden = ns.db.altsPanel and ns.db.altsPanel.showHidden
    for charKey, char in pairs(ns.db.chars) do
        local isHidden = hidden[charKey] and true or false
        if not isHidden or showHidden then
            out[#out + 1] = { key = charKey, data = char, hidden = isHidden }
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
    -- Resize the panel to fit the active column count. Settings can flip
    -- World Boss visibility, levelMin/levelMax can hide rows on character
    -- transitions — so width is computed each render rather than cached.
    local desiredWidth = ComputeFrameWidth(#cols)
    if panel:GetWidth() ~= desiredWidth then
        panel:SetWidth(desiredWidth)
    end
    RenderHeader(cols)

    local chars = CollectChars()
    local currentWeeklyReset = ns.char and ns.char.weeklyReset or 0

    -- Resize content for scroll math.
    local contentHeight = math.max(1, #chars * ROW_HEIGHT)
    panel.content:SetHeight(contentHeight)
    panel.content:SetWidth(desiredWidth - 60)

    for i, entry in ipairs(chars) do
        if not rowPool[i] then
            rowPool[i] = CreateRow(panel.content)
        end
        local row = rowPool[i]
        row:SetWidth(panel.content:GetWidth())
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row.bg:SetShown(i % 2 == 0)
        PopulateRow(row, entry.key, entry.data, cols, currentWeeklyReset, entry.hidden)
        row:Show()
    end
    for i = #chars + 1, #rowPool do
        rowPool[i]:Hide()
    end

    local hiddenCount = 0
    if ns.db and ns.db.hiddenChars then
        for _ in pairs(ns.db.hiddenChars) do hiddenCount = hiddenCount + 1 end
    end
    local title = string.format("Broker_MidnightEvents · Alts  |cff808080(%d tracked", #chars)
    if hiddenCount > 0 then
        title = title .. string.format(", %d hidden", hiddenCount)
    end
    title = title .. ")|r"
    panel.TitleText:SetText(title)
end

-- ── Frame creation ────────────────────────────────────────────────────────────

local function CreatePanel()
    -- Smoke-glass panel built from scratch — no Blizzard frame template.
    -- The previous BasicFrameTemplateWithInset attempt couldn't cleanly
    -- erase the template's child Inset frame's chrome, so we own every
    -- pixel here and lay it out exactly per Mythforge's design language.
    local f = CreateFrame("Frame", "BrokerMidnightEventsAltsPanel", UIParent)
    f:SetSize(ComputeFrameWidth(#GetColumns()), FRAME_HEIGHT)
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
    f:SetScript("OnShow", function() Render() end)

    -- Solid dark backdrop, full panel.
    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetAllPoints(f)
    f.Bg:SetColorTexture(STYLE.bgR, STYLE.bgG, STYLE.bgB, 1)

    -- Four 1px amber lines forming the edge.
    local function edge(parent)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetColorTexture(STYLE.borderR, STYLE.borderG, STYLE.borderB,
                          STYLE.borderAlpha)
        return t
    end
    f.borderT = edge(f); f.borderT:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                         f.borderT:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
                         f.borderT:SetHeight(1)
    f.borderB = edge(f); f.borderB:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
                         f.borderB:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                         f.borderB:SetHeight(1)
    f.borderL = edge(f); f.borderL:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                         f.borderL:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
                         f.borderL:SetWidth(1)
    f.borderR = edge(f); f.borderR:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
                         f.borderR:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                         f.borderR:SetWidth(1)

    -- Title text — amber, anchored at top center.
    f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.TitleText:SetPoint("TOP", f, "TOP", 0, -8)
    f.TitleText:SetTextColor(STYLE.titleR, STYLE.titleG, STYLE.titleB)
    f.TitleText:SetText("Broker_MidnightEvents · Alts")

    -- Title bar separator — thin zinc line under the title (≈28px down).
    f.titleSep = f:CreateTexture(nil, "ARTWORK")
    f.titleSep:SetColorTexture(STYLE.sepR, STYLE.sepG, STYLE.sepB, 1)
    f.titleSep:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -28)
    f.titleSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -28)
    f.titleSep:SetHeight(1)

    -- Close button — minimal X glyph in the top-right corner, no Blizzard
    -- chrome. Hover state brightens the X to amber.
    f.CloseButton = CreateFrame("Button", nil, f)
    f.CloseButton:SetSize(22, 22)
    f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)
    f.CloseButton.text = f.CloseButton:CreateFontString(nil, "OVERLAY",
                                                       "GameFontNormalLarge")
    f.CloseButton.text:SetAllPoints(f.CloseButton)
    f.CloseButton.text:SetText("×")
    f.CloseButton.text:SetTextColor(STYLE.headerR, STYLE.headerG, STYLE.headerB)
    f.CloseButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(STYLE.titleR, STYLE.titleG, STYLE.titleB)
        f.CloseHint:SetTextColor(STYLE.titleR, STYLE.titleG, STYLE.titleB)
    end)
    f.CloseButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(STYLE.headerR, STYLE.headerG, STYLE.headerB)
        f.CloseHint:SetTextColor(STYLE.headerR, STYLE.headerG, STYLE.headerB)
    end)
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    -- "esc" hint anchored left of the close button. Dim zinc-500; hover
    -- on the close button lifts it to amber alongside the X so both
    -- read as the same close affordance.
    f.CloseHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.CloseHint:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
    f.CloseHint:SetText("esc")
    f.CloseHint:SetTextColor(STYLE.headerR, STYLE.headerG, STYLE.headerB)

    -- Register with UISpecialFrames so WoW closes the panel on ESC.
    -- The frame must be globally named (it is — BrokerMidnightEventsAltsPanel).
    tinsert(UISpecialFrames, "BrokerMidnightEventsAltsPanel")

    -- Fixed header row above the scrollable content.
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetHeight(HEADER_HEIGHT)
    f.header:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -28 - 8)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28 - 8)
    f.header.nameLabel = f.header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.header.nameLabel:SetPoint("LEFT", 6, 0)
    f.header.nameLabel:SetWidth(NAME_WIDTH - 12)
    f.header.nameLabel:SetJustifyH("LEFT")
    f.header.nameLabel:SetTextColor(STYLE.headerR, STYLE.headerG, STYLE.headerB)

    -- Subtle separator below the header row, matching the title bar one.
    f.headerSep = f:CreateTexture(nil, "ARTWORK")
    f.headerSep:SetColorTexture(STYLE.sepR, STYLE.sepG, STYLE.sepB, 1)
    f.headerSep:SetPoint("TOPLEFT",  f.header, "BOTTOMLEFT",  0, -1)
    f.headerSep:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -1)
    f.headerSep:SetHeight(1)
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
