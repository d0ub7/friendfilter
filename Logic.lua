-- Ruleset and faction checks for the friends list.
-- No frames and no saved variables, so the rules can be tested on their own.
-- WoW Forever has no realms. A friend's ruleset shows up in three places:
-- the realm name's suffix (CAMWOWUS2Realm10RPPvP), the rich-presence line
-- ("Forever - Roleplay PvP - Tirisfal Glades"), and the zone line
-- ("Dun Morogh - Normal").

FriendFilterLogic = FriendFilterLogic or {}
local FF = FriendFilterLogic

local SUFFIX_KEY = {
    PvE = "normal",
    PvP = "pvp",
    RP = "rp",
    RPPvP = "rppvp",
}

function FF.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

function FF.Plain(value)
    if FF.IsSecret(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

function FF.RealmSuffix(realm)
    realm = FF.Plain(realm)
    if not realm then return nil end
    return realm:match("Realm%s*%d+%s*(%a+)$")
end

function FF.DefaultPresenceMap()
    return {
        normal = "normal",
        pvp = "pvp",
        roleplay = "rp",
        ["roleplay pvp"] = "rppvp",
        ["roleplay-pvp"] = "rppvp",
        roleplaying = "rp",
        rp = "rp",
        ["rp pvp"] = "rppvp",
        ["rp-pvp"] = "rppvp",
        rppvp = "rppvp",
    }
end

function FF.RememberLabel(map, text, key)
    text = FF.Plain(text)
    if text and map and key then
        map[text:lower()] = key
    end
end

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function TokenKey(map, text)
    text = FF.Plain(text)
    if not text or not map then return nil end
    text = Trim(text):gsub("%s*%b()$", "")
    text = Trim(text):lower()
    return map[text]
end

function FF.RulesetKey(info, map)
    local game = info and info.gameAccountInfo
    if not game then return nil end
    map = map or FF.DefaultPresenceMap()

    local suffix = FF.RealmSuffix(game.realmName) or FF.RealmSuffix(game.realmDisplayName)
    if suffix and SUFFIX_KEY[suffix] then
        return SUFFIX_KEY[suffix]
    end

    local rich = FF.Plain(game.richPresence)
    if rich then
        local middle = rich:match("^.- %- (.-) %- ") or rich:match("^.- %- (.+)$")
        local key = TokenKey(map, middle) or TokenKey(map, rich)
        if key then return key end
    end

    local area = FF.Plain(game.areaName)
    if area then
        local tail = area:match("%-%s*([^%-]+)$")
        local key = TokenKey(map, tail)
        if key then return key end
    end
end

function FF.FactionKey(info)
    local game = info and info.gameAccountInfo
    local name = game and FF.Plain(game.factionName)
    if not name then return nil end
    name = (name:gsub("^%s+", ""):gsub("%s+$", ""))
    if name == "" then return nil end
    local lower = name:lower()
    if lower == "alliance" or name == _G.FACTION_ALLIANCE then return "alliance" end
    if lower == "horde" or name == _G.FACTION_HORDE then return "horde" end
end

-- Ruleset and faction only apply while the friend is in WoW. Offline friends,
-- the Battle.net app, and other games stay listed even if the last session's
-- faction is still on the account.
function FF.InWow(info)
    local game = info and info.gameAccountInfo
    if not game then return false end
    local online = game.isOnline
    if FF.IsSecret(online) or not online then return false end
    local program = FF.Plain(game.clientProgram)
    if not program or program == "" then return true end
    if program == "WoW" then return true end
    if _G.BNET_CLIENT_WOW and program == _G.BNET_CLIENT_WOW then return true end
    return false
end

function FF.FilterActive(db)
    if type(db) ~= "table" then return false end
    local ruleset = db.ruleset
    if type(ruleset) == "table" then
        for _, on in pairs(ruleset) do
            if on == false then return true end
        end
    end
    local faction = db.faction
    if type(faction) == "table" then
        for _, on in pairs(faction) do
            if on == false then return true end
        end
    end
    return false
end

local function Wants(db, group, key)
    local bucket = db and db[group]
    if type(bucket) ~= "table" then return true end
    return bucket[key] ~= false
end

-- A checked box keeps that group. A friend with no ruleset (offline, the
-- Battle.net app, another game) is not in any ruleset, so an unchecked
-- ruleset does not hide them. Same for faction. Both axes apply together.
function FF.Passes(info, db, map)
    if not FF.FilterActive(db) then return true end
    if not info then return true end
    if not FF.InWow(info) then return true end
    local ruleset = FF.RulesetKey(info, map)
    if ruleset and not Wants(db, "ruleset", ruleset) then return false end
    local faction = FF.FactionKey(info)
    if faction and not Wants(db, "faction", faction) then return false end
    return true
end
