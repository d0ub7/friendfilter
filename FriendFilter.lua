-- Checkboxes on the friends list: four rulesets, two factions, and the Battle.net app.
--
-- EllesmereUI's friends list stays in charge of groups, invites, and whispers.
-- A whisper breaks if an addon writes the friends list Blizzard builds, so
-- nothing here changes that list, its anchors, or its search flags. Unchecking
-- a box covers the list with the friends that still match. Checking them all
-- again removes the cover.

local Logic = FriendFilterLogic
if not Logic then return end

local BAR_H = 44
local ROW_H = 34
local HEAD_H = 20
local LINK_FORMAT = "|HBNplayer:%s:%d:0:BN_WHISPER:%s|h%s|h"
local LINK_FILLER = string.rep("M", 48)
local FAV = "_favorites"
local UNGROUPED = "_ungrouped"

local RULESETS = {
    { key = "normal", label = _G.GDAPI_REALMTYPE_NORMAL or "Normal" },
    { key = "pvp", label = _G.GDAPI_REALMTYPE_PVP or "PvP" },
    { key = "rp", label = _G.GDAPI_REALMTYPE_RP or "Roleplay" },
    { key = "rppvp", label = _G.GDAPI_REALMTYPE_PVP_RP or "RP-PvP" },
}

local FACTIONS = {
    { key = "alliance", label = _G.FACTION_ALLIANCE or "Alliance", r = 0.45, g = 0.68, b = 1 },
    { key = "horde", label = _G.FACTION_HORDE or "Horde", r = 1, g = 0.35, b = 0.28 },
}

local PRESENCE = {
    { key = "app", label = "In App" },
}

local RULESET_LABEL = {
    normal = RULESETS[1].label,
    pvp = RULESETS[2].label,
    rp = RULESETS[3].label,
    rppvp = RULESETS[4].label,
}

local sessions = {}
local attached = {}
local customRoots = {}
local hooked = {}
local pendingRoute = {}
local presenceMap
local refreshHooked
local searchHooked = {}
local rereadToken = 0
local Apply
local Reread

local function DB()
    if type(FriendFilterDB) ~= "table" then FriendFilterDB = {} end
    if type(FriendFilterDB.ruleset) ~= "table" then FriendFilterDB.ruleset = {} end
    if type(FriendFilterDB.faction) ~= "table" then FriendFilterDB.faction = {} end
    if type(FriendFilterDB.presence) ~= "table" then FriendFilterDB.presence = {} end
    return FriendFilterDB
end

local function Active()
    return Logic.FilterActive(DB())
end

local function Map()
    if presenceMap then return presenceMap end
    presenceMap = Logic.DefaultPresenceMap()
    Logic.RememberLabel(presenceMap, _G.GDAPI_REALMTYPE_NORMAL, "normal")
    Logic.RememberLabel(presenceMap, _G.GDAPI_REALMTYPE_PVP, "pvp")
    Logic.RememberLabel(presenceMap, _G.GDAPI_REALMTYPE_RP, "rp")
    Logic.RememberLabel(presenceMap, _G.GDAPI_REALMTYPE_PVP_RP, "rppvp")
    return presenceMap
end

local function Passes(info)
    return Logic.Passes(info, DB(), Map())
end

local function AccountAt(index)
    if not C_BattleNet or not C_BattleNet.GetFriendAccountInfo then return nil end
    local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, index)
    if ok then return info end
end

local function BNetCount()
    if not BNGetNumFriends then return 0 end
    local ok, n = pcall(BNGetNumFriends)
    if ok and type(n) == "number" then return n end
    return 0
end

local function Hook(frame, script, fn)
    if not frame or type(frame.HookScript) ~= "function" then return end
    local bag = hooked[frame]
    if not bag then
        bag = {}
        hooked[frame] = bag
    end
    if bag[script] then return end
    bag[script] = true
    frame:HookScript(script, fn)
end

local function Pixel(parent, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    if tex.SetColorTexture then
        tex:SetColorTexture(1, 1, 1, 1)
    end
    return tex
end

local function CustomListUp()
    local kit = _G.EllesmereUI and _G.EllesmereUI.FriendsKit
    return kit ~= nil and kit._listShown == true
end

local function CustomRoot(view)
    local cached = customRoots[view]
    if cached and cached.GetPoint then return cached end
    local div = view and view.TopDivider
    if not div or type(view.GetChildren) ~= "function" then return nil end
    local floor = (view:GetFrameLevel() or 0) + 20
    local best, bestLevel
    local children = { view:GetChildren() }
    for i = 1, #children do
        local f = children[i]
        if f.GetNumPoints and f.GetFrameLevel then
            local level = f:GetFrameLevel() or 0
            -- EllesmereUI's list is an unnamed frame it anchors to the divider.
            local named = f.GetName and f:GetName()
            if level >= floor and not named then
                for p = 1, f:GetNumPoints() do
                    local point, rel = f:GetPoint(p)
                    if point == "TOPLEFT" and rel == div and (not best or level > bestLevel) then
                        best, bestLevel = f, level
                    end
                end
            end
        end
    end
    if best then customRoots[view] = best end
    return best
end

local function RouteCatch(catch)
    if not catch or type(catch.SetPassThroughButtons) ~= "function" then return end
    if InCombatLockdown and InCombatLockdown() then
        pendingRoute[#pendingRoute + 1] = catch
        return
    end
    catch:SetPassThroughButtons("RightButton")
    if catch.SetPropagateMouseMotion then
        catch:SetPropagateMouseMotion(true)
    end
    catch:Show()
end

local function RoutePending()
    for i = #pendingRoute, 1, -1 do
        local catch = pendingRoute[i]
        pendingRoute[i] = nil
        if catch and catch.SetPassThroughButtons and not (InCombatLockdown and InCombatLockdown()) then
            catch:SetPassThroughButtons("RightButton")
            if catch.SetPropagateMouseMotion then
                catch:SetPropagateMouseMotion(true)
            end
            catch:Show()
        elseif catch then
            pendingRoute[#pendingRoute + 1] = catch
        end
    end
end

local function SyncChecks(session)
    local saved = DB()
    local function sync(boxes, group)
        for i = 1, #boxes do
            local box = boxes[i]
            box:SetChecked(saved[group][box.key] ~= false)
        end
    end
    sync(session.rulesetBoxes, "ruleset")
    sync(session.factionBoxes, "faction")
    sync(session.presenceBoxes, "presence")
end

local function FitHit(box)
    local text = box.label
    local w = text and text.GetStringWidth and text:GetStringWidth() or 0
    if not w or w < 8 then w = 64 end
    box:SetHitRectInsets(0, -(w + 6), -3, -3)
end

local function LayoutChecks(session)
    local bar = session.bar
    local width = bar:GetWidth() or 0
    if width < 20 then return end
    local slot = width / #RULESETS
    for i = 1, #session.rulesetBoxes do
        local box = session.rulesetBoxes[i]
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * slot + 6, -4)
        FitHit(box)
    end
    for i = 1, #session.factionBoxes do
        local box = session.factionBoxes[i]
        box:ClearAllPoints()
        box:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6 + (i - 1) * 118, 4)
        FitHit(box)
    end
    for i = 1, #session.presenceBoxes do
        local box = session.presenceBoxes[i]
        box:ClearAllPoints()
        box:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6 + (#FACTIONS + i - 1) * 118, 4)
        FitHit(box)
    end
end

local function MakeCheck(parent, entry, group)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(16, 16)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box:SetChecked(DB()[group][entry.key] ~= false)

    local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(entry.label)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    if entry.r then text:SetTextColor(entry.r, entry.g, entry.b) end
    box.label = text
    box.group = group
    box.key = entry.key

    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.label, 1, 1, 1)
        if group == "presence" then
            GameTooltip:AddLine("Uncheck to hide friends who are in the Battle.net app.", 0.85, 0.85, 0.85, true)
        else
            local which = group == "ruleset" and "ruleset" or "faction"
            GameTooltip:AddLine("Uncheck to hide friends on this " .. which .. ".", 0.85, 0.85, 0.85, true)
            GameTooltip:AddLine("Shift-click to show only this one.", 0.7, 0.7, 0.7, true)
        end
        if group == "ruleset" then
            GameTooltip:AddLine("Friends in another version of WoW are hidden while a ruleset is unchecked.", 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine("Diablo, Heroes, and other games are hidden while a ruleset stays checked.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine("Offline friends stay listed. Other games return when every ruleset box is off.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box:SetScript("OnClick", function(self)
        local saved = DB()
        local lists = { ruleset = RULESETS, faction = FACTIONS, presence = PRESENCE }
        if IsShiftKeyDown() and group ~= "presence" then
            local list = lists[group]
            for i = 1, #list do
                saved[group][list[i].key] = list[i].key == self.key
            end
        else
            saved[group][self.key] = self:GetChecked() and true or false
        end
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        Reread()
    end)
    return box
end

-- A secret value errors if Lua tests it, so the secret check has to come first.
local function FieldOn(t, key)
    if type(t) ~= "table" then return false end
    local value = t[key]
    if Logic.IsSecret(value) or not value then return false end
    return true
end

local function StatusKey(info)
    local game = info and info.gameAccountInfo
    if not FieldOn(game, "isOnline") then return "offline" end
    if FieldOn(info, "isDND") or FieldOn(game, "isGameBusy") then return "busy" end
    if FieldOn(info, "isAFK") or FieldOn(game, "isGameAFK") then return "away" end
    return "online"
end

local STATUS_ATLAS = {
    online = "friends-status-online",
    away = "friends-status-away",
    busy = "friends-status-busy",
    offline = "friends-status-offline",
}

local function SetLine(fs, text)
    if not fs then return end
    local ok = pcall(fs.SetText, fs, text or "")
    if not ok then pcall(fs.SetText, fs, "") end
end

local function PaintStatus(tex, info)
    local key = StatusKey(info)
    if tex.SetAtlas then
        pcall(tex.SetAtlas, tex, STATUS_ATLAS[key] or STATUS_ATLAS.offline)
    end
    tex:SetAlpha(key == "offline" and 0.45 or 1)
    tex:Show()
end

local function PaintClass(tex, info)
    local game = info and info.gameAccountInfo
    local file = game and Logic.Plain(game.classFilename)
    if not file or not tex.SetAtlas then
        tex:Hide()
        return
    end
    local ok = pcall(tex.SetAtlas, tex, "classicon-" .. file:lower())
    if ok then tex:Show() else tex:Hide() end
end

local function PaintBNetName(fs, info)
    local base
    if FriendsListUtil and FriendsListUtil.BuildFriendNameDisplayText then
        local ok, text = pcall(FriendsListUtil.BuildFriendNameDisplayText, info)
        if ok then base = text end
    end
    if base == nil then
        base = Logic.Plain(info.battleTag) or Logic.Plain(info.accountName) or ""
    end

    local game = info.gameAccountInfo
    local char = game and Logic.Plain(game.characterName)
    local level = game and game.characterLevel
    local plain = Logic.Plain(base)
    if plain and char and not Logic.IsSecret(level) and type(level) == "number" then
        SetLine(fs, plain .. " (" .. char .. " Lvl " .. level .. ")")
    else
        SetLine(fs, base)
    end

    local file = game and Logic.Plain(game.classFilename)
    local color = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if color then
        fs:SetTextColor(color.r, color.g, color.b)
    elseif game and game.isOnline then
        fs:SetTextColor(0.95, 0.91, 0.8)
    else
        fs:SetTextColor(0.55, 0.55, 0.55)
    end
end

local function DetailLine(info)
    local game = info and info.gameAccountInfo
    if not FieldOn(game, "isOnline") then return "Offline" end
    local zone = Logic.Plain(game.areaName)
    local ruleset = RULESET_LABEL[Logic.RulesetKey(info, Map()) or ""]
    if zone and ruleset then
        local tail = zone:match("%-%s*([^%-]+)$")
        if tail and tail:lower() == ruleset:lower() then return zone end
        return zone .. " - " .. ruleset
    end
    if zone then return zone end
    if ruleset then return ruleset end
    return Logic.Plain(game.richPresence) or "Online"
end

local function MakeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = Pixel(row, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetVertexColor(1, 1, 1, 0.04)

    row.class = row:CreateTexture(nil, "ARTWORK")
    row.class:SetSize(16, 16)
    row.class:SetPoint("TOPLEFT", 6, -3)
    row.class:Hide()

    row.status = row:CreateTexture(nil, "ARTWORK")
    row.status:SetSize(12, 12)
    row.status:SetPoint("TOPLEFT", 26, -5)
    row.status:Hide()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetHeight(14)

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetJustifyH("LEFT")
    row.info:SetWordWrap(false)
    row.info:SetHeight(12)
    row.info:SetTextColor(0.65, 0.65, 0.65)

    local ok, hit = pcall(CreateFrame, "Frame", nil, row, "InlineHyperlinkFrameTemplate")
    if ok and hit then
        hit:SetAllPoints()
        hit:SetFrameLevel(row:GetFrameLevel() + 2)
        hit:EnableMouse(true)
        local link = hit:CreateFontString(nil, "ARTWORK")
        local font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        link:SetFont(font, ROW_H + 6, "")
        link:SetAlpha(0)
        link:SetPoint("TOPLEFT", hit, "TOPLEFT", -2, 4)
        link:SetPoint("RIGHT", hit, "RIGHT", 8, 0)
        link:SetJustifyH("LEFT")
        link:SetJustifyV("TOP")
        link:SetWordWrap(false)
        row.link = link

        local catch = CreateFrame("Frame", nil, row)
        catch:SetAllPoints()
        catch:SetFrameLevel(row:GetFrameLevel() + 4)
        catch:EnableMouse(true)
        catch:Hide()
        catch:SetScript("OnEnter", function()
            row.bg:SetVertexColor(1, 0.95, 0.8, 0.1)
        end)
        catch:SetScript("OnLeave", function()
            local tint = row.tint
            if tint then
                row.bg:SetVertexColor(tint[1], tint[2], tint[3], tint[4])
            end
        end)
        row.catch = catch
        RouteCatch(catch)
    end

    row:Hide()
    return row
end

local function Tint(row, faction, online)
    local tint
    if not online then
        tint = { 1, 1, 1, 0.025 }
    elseif faction == "alliance" then
        tint = { 0.45, 0.65, 1, 0.08 }
    elseif faction == "horde" then
        tint = { 1, 0.35, 0.25, 0.08 }
    else
        tint = { 1, 1, 1, 0.04 }
    end
    row.tint = tint
    row.bg:SetVertexColor(tint[1], tint[2], tint[3], tint[4])
end

local function SortName(entry)
    if entry.kind == "wow" then
        local name = entry.wow and Logic.Plain(entry.wow.name)
        return name and name:lower() or ""
    end
    local info = entry.info
    local tag = info and Logic.Plain(info.battleTag)
    if tag then
        tag = tag:match("^(.-)#") or tag
        return tag:lower()
    end
    local account = info and Logic.Plain(info.accountName)
    return account and account:lower() or ""
end

local function SortRank(entry)
    if entry.kind == "wow" then
        return FieldOn(entry.wow, "connected") and 1 or 3
    end
    local game = entry.info and entry.info.gameAccountInfo
    if FieldOn(game, "isOnline") then
        if Logic.RulesetKey(entry.info, Map()) then return 0 end
        return 2
    end
    return 3
end

local function GroupStore()
    local g = _G.EllesmereUIDB and _G.EllesmereUIDB.global
    if type(g) ~= "table" then return nil end
    return g
end

local function GroupKey(info)
    local tag = info and Logic.Plain(info.battleTag)
    local g = GroupStore()
    if tag and g and type(g.friendGroupsByTag) == "table" then
        local name = g.friendGroupsByTag[tag]
        if type(name) == "string" and name ~= "" and name ~= FAV and name ~= UNGROUPED then
            return name
        end
    end
    if FieldOn(info, "isFavorite") then return FAV end
    return UNGROUPED
end

local function GroupRank(key)
    if key == FAV then return 0 end
    if key == UNGROUPED then return 10000 end
    local g = GroupStore()
    local order = g and g.friendGroupOrder
    if type(order) == "table" then
        for i = 1, #order do
            if order[i] == key then return i end
        end
    end
    return 5000
end

local function GroupLabel(key)
    if key == FAV then return _G.FAVORITES or "Favorites" end
    if key == UNGROUPED then return _G.FRIENDS or "Friends" end
    return key
end

local function EntryOnline(entry)
    if entry.kind == "wow" then
        return FieldOn(entry.wow, "connected")
    end
    local game = entry.info and entry.info.gameAccountInfo
    return FieldOn(game, "isOnline")
end

local function SearchOn(view)
    local bar = view.FilterBar and view.FilterBar.SearchBar
    if not bar or type(bar.GetText) ~= "function" then return false end
    local text = bar:GetText()
    if Logic.IsSecret(text) then return true end
    return type(text) == "string" and text ~= ""
end

local function BlizzardFilterOn(view)
    local selected = view.selectedSearchFilterOptions
    if type(selected) ~= "table" then return false end
    for _, on in pairs(selected) do
        if on then return true end
    end
    return false
end

local function NodeData(node)
    if type(node) ~= "table" or type(node.GetData) ~= "function" then return nil end
    local ok, data = pcall(node.GetData, node)
    if ok and type(data) == "table" then return data end
end

local function ProviderRoot(view)
    local box = view and view.ScrollBox
    if not box or not box.GetDataProvider then return nil end
    local ok, provider = pcall(box.GetDataProvider, box)
    if not ok or type(provider) ~= "table" or type(provider.GetRootNode) ~= "function" then
        return nil
    end
    local rootOk, root = pcall(provider.GetRootNode, provider)
    if rootOk then return root end
end

-- Friends Blizzard's own search or filter menu left in the list. Read only.
-- nil means that menu is not narrowing the list.
local function NarrowKeys(view)
    if not SearchOn(view) and not BlizzardFilterOn(view) then return nil end
    local root = ProviderRoot(view)
    if not root or type(root.GetNodes) ~= "function" then return nil end
    local ok, nodes = pcall(root.GetNodes, root)
    if not ok or type(nodes) ~= "table" then return nil end
    local set = {}
    local bnetType = _G.FRIENDS_BUTTON_TYPE_BNET
    local wowType = _G.FRIENDS_BUTTON_TYPE_WOW
    local function mark(kind, id)
        if id == nil or Logic.IsSecret(id) then return end
        local keyOk, key = pcall(function() return kind .. ":" .. id end)
        if keyOk and key then set[key] = true end
    end
    local function walk(list, depth)
        if depth > 4 or type(list) ~= "table" then return end
        for i = 1, #list do
            local node = list[i]
            local data = NodeData(node)
            if data and not Logic.IsSecret(data.friendIndex) and data.friendIndex ~= nil then
                mark("bnet", data.friendIndex)
            elseif data and not Logic.IsSecret(data.id) and data.id ~= nil and bnetType and data.buttonType == bnetType then
                mark("bnet", data.id)
            elseif data and not Logic.IsSecret(data.id) and data.id ~= nil and wowType and data.buttonType == wowType then
                mark("wow", data.id)
            end
            -- A section still holds its friends when the header is collapsed.
            if type(node) == "table" and type(node.GetNodes) == "function" then
                local kidsOk, kids = pcall(node.GetNodes, node)
                if kidsOk and type(kids) == "table" and #kids > 0 then
                    walk(kids, depth + 1)
                end
            end
        end
    end
    walk(nodes, 1)
    return set
end

local function Allowed(keys, kind, index)
    if not keys then return true end
    return keys[kind .. ":" .. index] == true
end

local function Collect(view)
    local keys = NarrowKeys(view)
    local list = {}
    local bnet = BNetCount()
    for i = 1, bnet do
        if Allowed(keys, "bnet", i) then
            local info = AccountAt(i)
            if info and Passes(info) then
                list[#list + 1] = {
                    kind = "bnet", index = i, info = info, group = GroupKey(info),
                }
            end
        end
    end
    local wow = 0
    if C_FriendList and C_FriendList.GetNumFriends then
        local ok, n = pcall(C_FriendList.GetNumFriends)
        if ok and type(n) == "number" then wow = n end
    end
    for i = 1, wow do
        if Allowed(keys, "wow", i) and C_FriendList.GetFriendInfoByIndex then
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and type(info) == "table" then
                local shaped = { gameAccountInfo = { areaName = info.area, isOnline = info.connected } }
                if Passes(shaped) then
                    list[#list + 1] = {
                        kind = "wow", index = i, wow = info, group = UNGROUPED,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local ga, gb = GroupRank(a.group), GroupRank(b.group)
        if ga ~= gb then return ga < gb end
        if a.group ~= b.group then return tostring(a.group) < tostring(b.group) end
        local ra, rb = SortRank(a), SortRank(b)
        if ra ~= rb then return ra < rb end
        local na, nb = SortName(a), SortName(b)
        if na ~= nb then return na < nb end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.index < b.index
    end)

    local grouped = false
    for i = 1, #list do
        if list[i].group ~= UNGROUPED then grouped = true end
    end
    if not grouped then return list end

    local out, header, last = {}, nil, nil
    for i = 1, #list do
        local entry = list[i]
        if entry.group ~= last then
            header = {
                kind = "header", group = entry.group, label = GroupLabel(entry.group),
                shown = 0, online = 0,
            }
            out[#out + 1] = header
            last = entry.group
        end
        header.shown = header.shown + 1
        if EntryOnline(entry) then header.online = header.online + 1 end
        out[#out + 1] = entry
    end
    return out
end

local function PlaceText(row, header)
    row.name:ClearAllPoints()
    row.info:ClearAllPoints()
    if header then
        row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        return
    end
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -3)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
    row.info:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 42, 3)
    row.info:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
end

local function PaintRow(row, entry, width)
    row:SetWidth(width > 0 and width or 200)
    if entry.kind == "header" then
        row:SetHeight(HEAD_H)
        row.class:Hide()
        row.status:Hide()
        PlaceText(row, true)
        SetLine(row.name, entry.label .. "  (" .. entry.online .. "/" .. entry.shown .. ")")
        if entry.group == FAV then
            row.name:SetTextColor(0.45, 0.9, 0.5)
        else
            row.name:SetTextColor(0.85, 0.8, 0.55)
        end
        SetLine(row.info, "")
        row.tint = { 0, 0, 0, 0.35 }
        row.bg:SetVertexColor(0, 0, 0, 0.35)
        if row.link then SetLine(row.link, "") end
        row:Show()
        return
    end

    row:SetHeight(ROW_H)
    PlaceText(row, false)
    if entry.kind == "bnet" then
        local info = entry.info
        PaintClass(row.class, info)
        PaintStatus(row.status, info)
        PaintBNetName(row.name, info)
        SetLine(row.info, DetailLine(info))
        local game = info.gameAccountInfo
        Tint(row, Logic.FactionKey(info), FieldOn(game, "isOnline"))
        if row.link then
            local id = info.bnetAccountID
            if not Logic.IsSecret(id) and id then
                pcall(row.link.SetFormattedText, row.link, LINK_FORMAT, info.accountName, id, info.accountName, LINK_FILLER)
            else
                SetLine(row.link, "")
            end
        end
    else
        local info = entry.wow
        row.class:Hide()
        if row.status.SetAtlas then
            pcall(row.status.SetAtlas, row.status, (FieldOn(info, "connected") and STATUS_ATLAS.online) or STATUS_ATLAS.offline)
        end
        row.status:Show()
        local name = Logic.Plain(info.name) or ""
        local className = Logic.Plain(info.className)
        if FieldOn(info, "connected") and className and not Logic.IsSecret(info.level) and info.level then
            SetLine(row.name, name .. "  " .. info.level .. " " .. className)
        else
            SetLine(row.name, name)
        end
        local connected = FieldOn(info, "connected")
        row.name:SetTextColor(connected and 0.95 or 0.55, connected and 0.91 or 0.55, connected and 0.8 or 0.55)
        local area = Logic.Plain(info.area)
        SetLine(row.info, connected and (area or "Online") or "Offline")
        Tint(row, nil, connected)
        if row.link then SetLine(row.link, "") end
    end
    row:Show()
end

local function RebuildOverlay(session)
    local overlay = session.overlay
    if not overlay or not overlay:IsShown() then return end
    local sf = session.scroll
    local content = session.content
    local width = sf:GetWidth() or 0
    if width < 1 then width = overlay:GetWidth() or 200 end
    content:SetWidth(width)

    local list = Collect(session.view)
    local friends = 0
    local y = 0
    local rows = session.rows
    for i = 1, #list do
        local entry = list[i]
        if entry.kind ~= "header" then friends = friends + 1 end
        local row = rows[i]
        if not row then
            row = MakeRow(content)
            rows[i] = row
        end
        local h = entry.kind == "header" and HEAD_H or ROW_H
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        PaintRow(row, entry, width)
        y = y + h
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
    end
    session.visibleCount = friends
    content:SetHeight(math.max(1, y))
    local maxScroll = content:GetHeight() - (sf:GetHeight() or 0)
    if maxScroll < 0 then maxScroll = 0 end
    if sf:GetVerticalScroll() > maxScroll then
        sf:SetVerticalScroll(maxScroll)
    end
    if session.empty then
        session.empty:SetShown(friends == 0)
    end
end

local function UpdateCount(session)
    local text = session.count
    if not text then return end
    if not Active() then
        text:SetText("")
        return
    end
    local n = session.visibleCount or 0
    text:SetText(n == 1 and "1 shown" or (n .. " shown"))
end

local function SyncOverlay(session)
    local overlay = session.overlay
    local box = session.view.ScrollBox
    if not overlay or not box then return end
    local bar = session.view.ScrollBar
    local custom = CustomListUp()
    if session.hidScroll and custom then
        session.hidScroll = false
    end
    local cover = Active()
    if cover then
        local root = custom and CustomRoot(session.view)
        if root and root.IsShown and root:IsShown() then
            session.hidRoot = root
            root:Hide()
        end
        if not custom then
            if not session.hidScroll then
                session.hidScroll = true
            end
            box:SetAlpha(0)
            if bar then bar:SetAlpha(0) end
        end
        overlay:SetFrameLevel((session.view:GetFrameLevel() or 1) + 80)
        overlay:Show()
        RebuildOverlay(session)
    else
        overlay:Hide()
        if session.hidRoot then
            if custom and session.hidRoot.Show then session.hidRoot:Show() end
            session.hidRoot = nil
        end
        if session.hidScroll and not custom then
            box:SetAlpha(1)
            if bar then bar:SetAlpha(1) end
        end
        session.hidScroll = false
        session.visibleCount = nil
    end
end

local function BuildOverlay(session)
    local view = session.view
    local box = view.ScrollBox
    local overlay = CreateFrame("Frame", nil, view)
    overlay:SetAllPoints(box)
    overlay:EnableMouse(true)
    overlay:Hide()
    local bg = Pixel(overlay, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetVertexColor(0.05, 0.05, 0.06, 0.97)

    local sf = CreateFrame("ScrollFrame", nil, overlay)
    sf:SetAllPoints()
    sf:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local height = content:GetHeight() - self:GetHeight()
        if height < 0 then height = 0 end
        local nextScroll = self:GetVerticalScroll() - delta * (ROW_H * 2)
        if nextScroll < 0 then nextScroll = 0 end
        if nextScroll > height then nextScroll = height end
        self:SetVerticalScroll(nextScroll)
    end)
    sf:SetScript("OnSizeChanged", function()
        if overlay:IsShown() then RebuildOverlay(session) end
    end)

    local empty = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER", 0, 8)
    empty:SetText("No friends match the checked filters.")
    empty:SetTextColor(0.7, 0.7, 0.7)
    empty:Hide()

    session.overlay = overlay
    session.scroll = sf
    session.content = content
    session.rows = {}
    session.empty = empty
end

local function ShellFor(view, social)
    if social and _G.SocialUIFrame then return _G.SocialUIFrame end
    if _G.FriendsFrame then return _G.FriendsFrame end
    return view
end

local function PlaceBar(bar, shell)
    bar:ClearAllPoints()
    local top = shell.GetTop and shell:GetTop()
    local screen = GetScreenHeight and GetScreenHeight()
    if top and screen and top > screen - (BAR_H + 12) then
        bar:SetPoint("TOPLEFT", shell, "BOTTOMLEFT", 8, 1)
        bar:SetPoint("TOPRIGHT", shell, "BOTTOMRIGHT", -8, 1)
    else
        bar:SetPoint("BOTTOMLEFT", shell, "TOPLEFT", 8, -1)
        bar:SetPoint("BOTTOMRIGHT", shell, "TOPRIGHT", -8, -1)
    end
    local strata = shell.GetFrameStrata and shell:GetFrameStrata()
    if strata then bar:SetFrameStrata(strata) end
    bar:SetFrameLevel((shell:GetFrameLevel() or 0) + 40)
end

local function BuildBar(view, social)
    local shell = ShellFor(view, social)
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetHeight(BAR_H)
    bar:EnableMouse(true)
    bar:Hide()
    PlaceBar(bar, shell)

    local bg = Pixel(bar, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetVertexColor(0.07, 0.07, 0.08, 0.96)

    local line = Pixel(bar, "BORDER")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetVertexColor(0.85, 0.75, 0.4, 0.35)

    local rulesetBoxes = {}
    for i = 1, #RULESETS do
        rulesetBoxes[i] = MakeCheck(bar, RULESETS[i], "ruleset")
    end
    local factionBoxes = {}
    for i = 1, #FACTIONS do
        factionBoxes[i] = MakeCheck(bar, FACTIONS[i], "faction")
    end
    local presenceBoxes = {}
    for i = 1, #PRESENCE do
        presenceBoxes[i] = MakeCheck(bar, PRESENCE[i], "presence")
    end

    local count = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("BOTTOMRIGHT", -8, 5)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(0.65, 0.65, 0.65)

    local session = {
        view = view,
        shell = shell,
        bar = bar,
        rulesetBoxes = rulesetBoxes,
        factionBoxes = factionBoxes,
        presenceBoxes = presenceBoxes,
        count = count,
    }
    bar:SetScript("OnSizeChanged", function() LayoutChecks(session) end)
    LayoutChecks(session)

    local function ShowBar()
        if view:IsShown() and shell:IsShown() then
            PlaceBar(bar, shell)
            bar:Show()
            LayoutChecks(session)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, Apply)
            else
                Apply()
            end
        end
    end
    Hook(view, "OnShow", ShowBar)
    Hook(view, "OnHide", function() bar:Hide() end)
    Hook(shell, "OnShow", ShowBar)
    Hook(shell, "OnHide", function() bar:Hide() end)
    if view:IsShown() then ShowBar() end
    return session
end

local function HookCustomRefresh()
    if refreshHooked or not hooksecurefunc then return end
    local list = _G.EllesmereUI and _G.EllesmereUI.FriendsList
    if not list or type(list.Refresh) ~= "function" then return end
    refreshHooked = true
    hooksecurefunc(list, "Refresh", function()
        if Active() then Apply() end
    end)
end

-- Blizzard's Filter menu fills its list after the click, then again when the
-- search returns. Reading once on our click can miss that. This reads now,
-- on the next frame, and once more shortly after. It never calls Blizzard's
-- search. It only reads the list Blizzard already built.
function Reread()
    rereadToken = rereadToken + 1
    local token = rereadToken
    Apply()
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(0, function()
        if token ~= rereadToken then return end
        Apply()
    end)
    C_Timer.After(0.25, function()
        if token ~= rereadToken then return end
        Apply()
    end)
end

local function HookBlizzardSearch(view)
    if searchHooked[view] or not hooksecurefunc then return end
    if type(view.RefreshSearchResults) ~= "function" then return end
    searchHooked[view] = true
    hooksecurefunc(view, "RefreshSearchResults", function()
        if not Active() then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, Apply)
        else
            Apply()
        end
    end)
end

local function Attach(view, social)
    if not view or attached[view] or not view.ScrollBox then return end
    attached[view] = true
    local session = BuildBar(view, social)
    BuildOverlay(session)
    sessions[#sessions + 1] = session
    HookCustomRefresh()
    HookBlizzardSearch(view)
end

function Apply()
    for i = 1, #sessions do
        local session = sessions[i]
        SyncOverlay(session)
        SyncChecks(session)
        UpdateCount(session)
    end
end

local function ResetFilters()
    local saved = DB()
    for i = 1, #RULESETS do saved.ruleset[RULESETS[i].key] = true end
    for i = 1, #FACTIONS do saved.faction[FACTIONS[i].key] = true end
    for i = 1, #PRESENCE do saved.presence[PRESENCE[i].key] = true end
    Reread()
end

local function TryAttachAll()
    HookCustomRefresh()
    local social = _G.SocialUIFrame and _G.SocialUIFrame.FriendsList
    if social and social.ScrollBox then Attach(social, true) end
    local legacy = _G.FriendsListFrame
    if legacy and legacy.ScrollBox and legacy ~= social then Attach(legacy, false) end
end

local function Watch(frame)
    Hook(frame, "OnShow", function()
        TryAttachAll()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, Apply)
        else
            Apply()
        end
    end)
end

local function FriendsOpen()
    if CustomListUp() then return true end
    for i = 1, #sessions do
        if sessions[i].view:IsShown() then return true end
    end
    return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("BN_FRIEND_INFO_CHANGED")
events:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
events:RegisterEvent("FRIENDLIST_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        RoutePending()
        return
    end
    if event == "ADDON_LOADED" and name ~= "EllesmereUI" and name ~= "Blizzard_SocialUI" and name ~= "Blizzard_FriendsFrame" then
        return
    end
    TryAttachAll()
    Watch(_G.SocialUIFrame)
    Watch(_G.FriendsFrame)
    if event == "PLAYER_LOGIN" or FriendsOpen() then
        Apply()
    end
end)

SLASH_FRIENDFILTER1 = "/friendfilter"
SLASH_FRIENDFILTER2 = "/ffilter"
SlashCmdList.FRIENDFILTER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""
    if msg == "reset" then
        ResetFilters()
        print("|cff33ff99Friend Filter:|r showing every ruleset, faction, and Battle.net app friends.")
        return
    end
    print("|cff33ff99Friend Filter:|r checkboxes sit on top of the friends window. Uncheck a ruleset, faction, or In App to hide it. Shift-click a ruleset or faction to show only that one. /friendfilter reset")
end
