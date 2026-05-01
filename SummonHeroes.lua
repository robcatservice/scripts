-- Summon Heroes Bot — Mobile-Friendly Edition
-- Made by Rob123 and Sprout
-- SaveManager/InterfaceManager are NOT used — we handle our own JSON persistence.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

repeat task.wait() until writefile and readfile and isfile

-- ─── Files ───────────────────────────────────────────────────────────────────

local DATA_FILE   = "SummonHeroesResult.json"
local CONFIG_FILE = "SummonHeroesConfig.json"

local defaultConfig = {
    BotActive             = false,
    ReadyDelay            = "2",
    RewardDelay           = "0.5",
    VoteDelay             = "0.2",
    VoteChoice            = "Retry",
    AutoStart             = false,
    AutoQueue             = false,
    WebhookURL            = "",
    SummonPack            = "Pack1",
    SummonAmount          = "1",
    SummonInterval        = "3",
    FuseRare              = false,
    FuseEpic              = true,
    FuseLegendary         = true,
    FuseMythic            = false,
    FuseTargetStars       = "5",
    FuseDelay             = "0.5",
    SellRare              = true,
    SellEpic              = false,
    SellLegendary         = false,
    SellMythic            = false,
    SellDelay             = "0.3",
    SellInterval          = "30",
    ShopItemTarget        = "",
    ShopAutoBuy           = false,
    NightmareRetryEnabled = false,
}

-- ─── JSON helpers ─────────────────────────────────────────────────────────────

local function SafeReadFile(file)
    local ok, result = pcall(readfile, file)
    return ok and result or nil
end

local function SafeWriteFile(file, content)
    local ok, err = pcall(writefile, file, content)
    if not ok then warn("[SaveLoad] writefile failed:", file, err) end
    return ok
end

local function LoadJSON(file, fallback)
    if not isfile(file) then
        SafeWriteFile(file, HttpService:JSONEncode(fallback))
        return fallback
    end
    local raw = SafeReadFile(file)
    if not raw or raw == "" then
        SafeWriteFile(file, HttpService:JSONEncode(fallback))
        return fallback
    end
    local ok, result = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok or type(result) ~= "table" then
        SafeWriteFile(file, HttpService:JSONEncode(fallback))
        return fallback
    end
    for k, v in pairs(fallback) do
        if result[k] == nil then result[k] = v end
    end
    return result
end

local function SaveJSON(file, data)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then warn("[SaveLoad] JSONEncode failed:", file, encoded) return false end
    return SafeWriteFile(file, encoded)
end

local function N(val, fallback)
    return tonumber(val) or fallback or 0
end

local config      = LoadJSON(CONFIG_FILE, defaultConfig)
local sessionData = LoadJSON(DATA_FILE, {})

-- ─── Rarity helpers ──────────────────────────────────────────────────────────

local rarityTable = {
    Rare      = {"AcademyWitch","Archer","Bandit","BearTamer","Deckhand","FireMage","IceMage","Ninja","Swordsman","StreetRat"},
    Epic      = {"Captain","CyberDJ","DemonHunter","Diver","Dragoon","DualWielder","Mermaid","Necromancer","Outlaw","SlimeSummoner","Spellblade","Vampire","WindSamurai","Specter","Thief","Construct"},
    Legendary = {"AbyssLord","LaserCyborg","DemonKnight","Jester","KitsuneMage","Sniper","Framerate","Technomancer","TankCommander","Ranger","Sage"},
    Mythic    = {"Divine","Reaper","Seraph","Emperor","B-4RB.E.T.","Matriarch","Rend"},
}

local function GetUnitRarity(unitName)
    local clean = unitName:gsub("%s",""):gsub("[^%w%-]","")
    for rarity, units in pairs(rarityTable) do
        for _, name in ipairs(units) do
            if name:lower() == clean:lower() then return rarity end
        end
    end
    return "Unknown"
end

local function GetRaritySet(prefix)
    local set = {}
    for _, r in ipairs({"Rare","Epic","Legendary","Mythic"}) do
        if config[prefix .. r] then set[r] = true end
    end
    return set
end

-- ─── Shop Algorithm ──────────────────────────────────────────────────────────

local ShopData = require(ReplicatedStorage:WaitForChild("Systems"):WaitForChild("RotatingShops"):WaitForChild("ShopData"))

local function GetShopSeed(shopName)
    return math.floor(workspace:GetServerTimeNow() / (ShopData[shopName].IntervalTime * 60))
end

local function GetTimeToNextRefresh(shopName)
    local iv = ShopData[shopName].IntervalTime
    return (GetShopSeed(shopName) + 1) * (iv * 60) - workspace:GetServerTimeNow()
end

local function GetCurrentShopItems(shopName)
    local entry = ShopData[shopName]
    local pool  = {}
    for i, v in ipairs(entry.PossibleItems) do pool[i] = v end
    local rng   = Random.new(GetShopSeed(shopName))
    local count = #pool
    local items = {}
    for _ = 1, math.min(entry.ItemCount, count) do
        local idx  = rng:NextInteger(1, count)
        local item = pool[idx]
        if item.ItemName == "RandomItem" then
            table.insert(items, item.PossibleItems[rng:NextInteger(1, #item.PossibleItems)])
        else
            table.insert(items, pool[idx])
        end
        table.remove(pool, idx)
        count -= 1
    end
    return items
end

local function FindItemSlot(shopName, targetName)
    for i, item in ipairs(GetCurrentShopItems(shopName)) do
        if item.ItemName == targetName then return i, item end
    end
    return nil, nil
end

-- ─── Selected Shop Items ─────────────────────────────────────────────────────

local selectedShopItems = {}

local function UpdateShopItemTarget()
    local parts = {}
    for item, qty in pairs(selectedShopItems) do
        if qty > 0 then table.insert(parts, item .. ":" .. qty) end
    end
    config.ShopItemTarget = table.concat(parts, ",")
end

local function LoadShopItemTarget()
    selectedShopItems = {}
    for entry in (config.ShopItemTarget or ""):gmatch("[^,]+") do
        local item, qty = entry:match("^(.+):(%d+)$")
        if item and qty then selectedShopItems[item] = tonumber(qty) end
    end
end

LoadShopItemTarget()

-- ─── Game References ─────────────────────────────────────────────────────────

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

local Sys                = ReplicatedStorage:WaitForChild("Systems")
local ReadyRemote        = Sys:WaitForChild("Waves"):WaitForChild("Ready")
local VoteRemote         = Sys:WaitForChild("Voting"):WaitForChild("Vote")
local QueueRemote        = Sys:WaitForChild("Queue"):WaitForChild("RequestEnterQueue")
local SummonRemote       = Sys:WaitForChild("Summon"):WaitForChild("BuyPack")
local FuseRemote         = Sys:WaitForChild("UnitFusion"):WaitForChild("PurchaseFuse")
local SellRemote         = Sys:WaitForChild("Inventory"):WaitForChild("SellItems")
local ShopRemote         = Sys:WaitForChild("RotatingShops"):WaitForChild("BuyItem")
local BuyRerollRemote    = Sys:WaitForChild("UnitUpgrades"):WaitForChild("BuyStatReroll")
local RerollActionRemote = Sys:WaitForChild("UnitUpgrades"):WaitForChild("RerollAction")

local RoundEnd       = player:WaitForChild("PlayerGui"):WaitForChild("RoundEnd")
local rewardsList    = RoundEnd:WaitForChild("Frame"):WaitForChild("Contents"):WaitForChild("Rewards"):WaitForChild("List")
local UnitsFolder    = player:WaitForChild("PlayerGui"):WaitForChild("Profile"):WaitForChild("Inventory"):WaitForChild("Units")
local WorkspaceUnits = workspace:WaitForChild("Units")

-- ─── State ───────────────────────────────────────────────────────────────────

local botRunning            = false
local fusionRunning         = false
local summonLoopRunning     = false
local shopBuyRunning        = false
local sellLoopRunning       = false
local totalRounds           = 0
local wipeDetected          = false
local nightmareRetryEnabled = config.NightmareRetryEnabled
local traitRerollsBought    = sessionData["_traitRerollsBought"] or 0

-- ─── Core Functions ──────────────────────────────────────────────────────────

local function AddItem(name, amount)
    sessionData[name] = (sessionData[name] or 0) + amount
end

local function CollectRewards()
    for _, item in ipairs(rewardsList:GetChildren()) do
        if not item:IsA("TextButton") then continue end
        local container = item:FindFirstChild("Container")
        if not container then continue end
        local countLabel = container:FindFirstChild("InventoryCount")
        if not countLabel then continue end
        local digits = tostring(countLabel.Text or "0"):match("%d+")
        local amount = math.min(tonumber(digits) or 1, 2147483647)
        local name   = tostring(item.Name)
        if name ~= "" then AddItem(name, amount) end
    end
end

local function CollectChests()
    local ok, err = pcall(function()
        local map = workspace:FindFirstChild("Map")
        if not map then return end
        local chests = map:WaitForChild("BonusChests", 5)
        for _, chest in ipairs(chests:GetChildren()) do
            local att    = chest:FindFirstChild("Attachment")
            if not att then continue end
            local prompt = att:FindFirstChildOfClass("ProximityPrompt")
            if not prompt then continue end
            hrp.CFrame = att.WorldCFrame + Vector3.new(0, 3, 0)
            task.wait(0.25)
            fireproximityprompt(prompt)
            task.wait(0.2)
        end
    end)
    if not ok then warn("[Chests] Failed:", err) end
end

local function EnterQueue()
    local ok, err = pcall(function()
        local model = workspace:WaitForChild("LobbyMap",10):WaitForChild("Queues",10):WaitForChild("Model",10)
        QueueRemote:InvokeServer(model)
    end)
    if ok then
        Fluent:Notify({ Title = "Queue Entered", Content = "Successfully entered the match queue.", Duration = 4 })
    else
        warn("[Queue] Failed:", err)
        Fluent:Notify({ Title = "Queue Failed", Content = tostring(err), Duration = 5 })
    end
    return ok
end

local function FireVote()
    local choice = tostring(config.VoteChoice)
    if choice == "" or choice == "nil" then choice = "Retry" end
    local ok, err = pcall(function() VoteRemote:FireServer(choice) end)
    if not ok then warn("[Vote] Failed:", err) end
    return ok
end

local function SendWebhook(roundNumber)
    if not config.WebhookURL or config.WebhookURL == "" then return end
    local fields = {{ name = "Trait Rerolls Bought", value = tostring(traitRerollsBought), inline = false }}
    for k, v in pairs(sessionData) do
        if k ~= "_traitRerollsBought" then
            table.insert(fields, { name = tostring(k), value = tostring(v), inline = true })
        end
    end
    if #fields == 1 then
        table.insert(fields, { name = "Items", value = "Nothing collected yet.", inline = false })
    end
    pcall(function()
        request({
            Url     = config.WebhookURL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({
                username = "Summon Heroes Bot",
                embeds   = {{
                    title       = "Round #" .. roundNumber .. " Complete",
                    description = "Session stats after round " .. roundNumber .. ".",
                    color       = 0x5865F2,
                    fields      = fields,
                    footer      = { text = "Summon Heroes Bot • " .. os.date("%Y-%m-%d %H:%M:%S") },
                }}
            })
        })
    end)
end

-- ─── Nightmare Circus ────────────────────────────────────────────────────────

local function IsMyUnit(unit) return unit:GetAttribute("OwnerName") == player.Name end

local function CountAliveMyUnits()
    local n = 0
    for _, unit in ipairs(WorkspaceUnits:GetChildren()) do
        if IsMyUnit(unit) then
            local h = unit:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then n += 1 end
        end
    end
    return n
end

local function WatchUnit(unit)
    if not IsMyUnit(unit) then return end
    local h = unit:FindFirstChildOfClass("Humanoid")
    if not h then return end
    h.Died:Connect(function()
        if not nightmareRetryEnabled or wipeDetected then return end
        if CountAliveMyUnits() == 0 then
            wipeDetected = true
            Fluent:Notify({ Title = "All Units Dead", Content = "Waiting 10s before retry...", Duration = 10 })
            task.wait(10)
            if not RoundEnd.Enabled then FireVote() end
            task.delay(10, function() wipeDetected = false end)
        end
    end)
end

for _, unit in ipairs(WorkspaceUnits:GetChildren()) do WatchUnit(unit) end
WorkspaceUnits.ChildAdded:Connect(function(unit)
    task.wait(0.5)
    WatchUnit(unit)
    if nightmareRetryEnabled and CountAliveMyUnits() > 0 then wipeDetected = false end
end)

-- ─── Auto Summon ─────────────────────────────────────────────────────────────

local function DoSummon(amount, pack)
    local ok, err = pcall(function() SummonRemote:FireServer(pack, amount, "Gems") end)
    if ok then
        Fluent:Notify({ Title = "Summoned!", Content = "Bought " .. amount .. "x from " .. pack, Duration = 3 })
    else
        warn("[Summon] Failed:", err)
        Fluent:Notify({ Title = "Summon Failed", Content = tostring(err), Duration = 4 })
    end
end

-- ─── Auto Fusion ─────────────────────────────────────────────────────────────

local function DoFusion()
    if fusionRunning then return end
    fusionRunning = true
    local allowed = GetRaritySet("Fuse")
    local target  = N(config.FuseTargetStars, 5)
    local delay   = N(config.FuseDelay, 0.5)
    local done    = 0
    Fluent:Notify({ Title = "Fusion Started", Content = "Fusing until " .. target .. " stars.", Duration = 4 })
    while fusionRunning do
        local groups = {}
        for _, unit in ipairs(UnitsFolder:GetChildren()) do
            local stars  = unit:GetAttribute("StarCount")
            local locked = unit:GetAttribute("Locked")
            local rarity = GetUnitRarity(unit.Name)
            if not stars or locked or not allowed[rarity] or stars >= target then continue end
            if not groups[stars] then groups[stars] = {} end
            table.insert(groups[stars], unit)
        end
        local base, sacrifices = nil, nil
        for _, units in pairs(groups) do
            if #units >= 4 then
                base       = units[1]
                sacrifices = { units[2], units[3], units[4] }
                break
            end
        end
        if not base then
            Fluent:Notify({ Title = "Fusion Done", Content = "No more fusable units. Total: " .. done, Duration = 5 })
            break
        end
        local ok, err = pcall(function() FuseRemote:InvokeServer(base, sacrifices) end)
        if ok then done += 1
        else
            warn("[Fusion] Failed:", err)
            Fluent:Notify({ Title = "Fusion Error", Content = tostring(err), Duration = 4 })
            break
        end
        task.wait(delay)
    end
    fusionRunning = false
end

-- ─── Auto Sell ───────────────────────────────────────────────────────────────

local function DoSell()
    local allowed = GetRaritySet("Sell")
    local toSell  = {}
    for _, unit in ipairs(UnitsFolder:GetChildren()) do
        if not unit:GetAttribute("Locked") and allowed[GetUnitRarity(unit.Name)] then
            table.insert(toSell, unit)
        end
    end
    if #toSell == 0 then return end
    local totalSold = 0
    for i = 1, #toSell, 10 do
        local batch = {}
        for j = i, math.min(i + 9, #toSell) do table.insert(batch, toSell[j]) end
        local ok, err = pcall(function() SellRemote:FireServer(batch) end)
        if ok then totalSold += #batch
        else warn("[Sell] Failed:", err) break end
        task.wait(N(config.SellDelay, 0.3))
    end
    if totalSold > 0 then
        Fluent:Notify({ Title = "Sold", Content = totalSold .. " units sold.", Duration = 4 })
    end
end

-- ─── Auto Shop Buy ───────────────────────────────────────────────────────────

local function DoShopBuy(targetItem, quantity)
    quantity = quantity or 1
    local slot, itemData = FindItemSlot("ItemShop", targetItem)
    if not slot then return false end
    local purchases = player.PlayerGui
        :WaitForChild("Profile"):WaitForChild("RotatingShops")
        :WaitForChild("Purchases"):WaitForChild("ItemShop")
    local slotVal      = purchases:FindFirstChild(tostring(slot))
    local currentStock = slotVal and slotVal.Value or 0
    local toBuy        = math.min(quantity, (itemData.Stock or 1) - currentStock)
    if toBuy <= 0 then return false end
    local bought = 0
    for _ = 1, toBuy do
        local ok, err = pcall(function() ShopRemote:FireServer("ItemShop", slot) end)
        if ok then bought += 1 else warn("[Shop] Failed:", err) break end
        task.wait(0.2)
    end
    if bought > 0 then
        Fluent:Notify({ Title = "Shop Purchase", Content = "Bought " .. bought .. "x " .. targetItem, Duration = 4 })
        if targetItem == "TraitReroll" then
            traitRerollsBought += bought
            sessionData["_traitRerollsBought"] = traitRerollsBought
            SaveJSON(DATA_FILE, sessionData)
        end
        return true
    end
    return false
end

local function BuyAllSelectedItems()
    for item, qty in pairs(selectedShopItems) do
        if qty > 0 then DoShopBuy(item, qty) task.wait(0.3) end
    end
end

local function StartShopBuyLoop()
    if shopBuyRunning then return end
    shopBuyRunning = true
    task.spawn(function()
        while shopBuyRunning do
            BuyAllSelectedItems()
            local left = GetTimeToNextRefresh("ItemShop")
            task.wait(left > 5 and left + 2 or 12)
        end
    end)
    Fluent:Notify({ Title = "Auto Shop", Content = "Watching shop for selected items.", Duration = 4 })
end

-- ─── Stat Reroller ───────────────────────────────────────────────────────────

local gradeOrder   = { D=1, C=2, B=3, A=4, S=5, X=6 }
local gradeOptions = { "D","C","B","A","S","X" }
local statNames    = { "Attack","Health","Speed","Cooldown" }
local rerollRunning    = false
local rerollTargets    = { Attack="X", Health="X", Speed="X", Cooldown="X" }
local rerollTargetUnit = ""
local rerollDelay      = 0.5
local currentGrades    = {}

local function GetUnitNames()
    local names = {}
    for _, u in ipairs(UnitsFolder:GetChildren()) do table.insert(names, u.Name) end
    return names
end

local function AllStatsAtTarget(unit)
    for _, stat in ipairs(statNames) do
        local cur = unit:GetAttribute(stat)
        if not cur then continue end
        if (gradeOrder[cur] or 0) < (gradeOrder[rerollTargets[stat]] or 0) then return false end
    end
    return true
end

local function DoStatReroll(unit)
    local done = 0
    currentGrades = {
        Attack   = unit:GetAttribute("Attack")   or "D",
        Health   = unit:GetAttribute("Health")   or "D",
        Speed    = unit:GetAttribute("Speed")    or "D",
        Cooldown = unit:GetAttribute("Cooldown") or "D",
    }
    local function allDone()
        for _, s in ipairs(statNames) do
            if (gradeOrder[currentGrades[s]] or 0) < (gradeOrder[rerollTargets[s]] or 0) then return false end
        end
        return true
    end
    local function buildLocked()
        local locked, set = {}, {}
        for _, s in ipairs(statNames) do
            if (gradeOrder[currentGrades[s]] or 0) >= (gradeOrder[rerollTargets[s]] or 0) then
                table.insert(locked, s) ; set[s] = true
            end
        end
        return locked, set
    end
    while rerollRunning do
        if allDone() then
            Fluent:Notify({ Title = "Reroll Complete", Content = unit.Name .. " reached all targets!", Duration = 6 })
            break
        end
        local locked, lockedSet = buildLocked()
        local newStats
        local ok, err = pcall(function() newStats = BuyRerollRemote:InvokeServer(unit, locked) end)
        if not ok or type(newStats) ~= "table" then
            warn("[Reroll] Failed:", err or tostring(newStats))
            Fluent:Notify({ Title = "Reroll Error", Content = tostring(err), Duration = 4 })
            break
        end
        done += 1
        local improved = false
        for _, s in ipairs(statNames) do
            if not lockedSet[s] and (gradeOrder[newStats[s]] or 0) > (gradeOrder[currentGrades[s]] or 0) then
                improved = true
            end
        end
        if improved then
            pcall(function() RerollActionRemote:InvokeServer("UseNew") end)
            for _, s in ipairs(statNames) do
                if not lockedSet[s] and newStats[s] then currentGrades[s] = newStats[s] end
            end
        else
            pcall(function() RerollActionRemote:InvokeServer("KeepCurrent") end)
        end
        task.wait(rerollDelay)
    end
    print("[Reroll] Finished. Total rolls:", done)
    rerollRunning = false
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  WINDOW
-- ═══════════════════════════════════════════════════════════════════════════════

local Window = Fluent:CreateWindow({
    Title       = "Summon Heroes Bot",
    SubTitle    = "by Rob123 & Sprout",
    TabWidth    = 150,
    Size        = UDim2.fromOffset(560, 460),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Main   = Window:AddTab({ Title = "Main",   Icon = "home" }),
    Summon = Window:AddTab({ Title = "Summon", Icon = "sparkles" }),
    Fusion = Window:AddTab({ Title = "Fusion", Icon = "flame" }),
    Sell   = Window:AddTab({ Title = "Sell",   Icon = "dollar-sign" }),
    Shop   = Window:AddTab({ Title = "Shop",   Icon = "shopping-bag" }),
    Reroll = Window:AddTab({ Title = "Reroll", Icon = "refresh-cw" }),
    Stats  = Window:AddTab({ Title = "Stats",  Icon = "bar-chart-2" }),
    Config = Window:AddTab({ Title = "Config", Icon = "settings" }),
}

-- ═══════════════════════════════════════════════════════════════════════════════
--  MAIN TAB
-- ═══════════════════════════════════════════════════════════════════════════════

local StatusParagraph = Tabs.Main:AddParagraph({
    Title   = "Status",
    Content = "Idle  |  Rounds: 0",
})

local function UpdateStatus()
    StatusParagraph:SetDesc(
        (botRunning and "Running" or "Idle") .. "  |  Rounds: " .. totalRounds
    )
end

Tabs.Main:AddToggle("BotToggle", {
    Title    = "Bot Active",
    Default  = config.BotActive,
    Callback = function(state)
        botRunning       = state
        config.BotActive = state
        wipeDetected     = false
        UpdateStatus()
        if state then
            Fluent:Notify({ Title = "Bot Started", Content = "Now farming rounds.", Duration = 4 })
            CollectChests()
            task.wait(N(config.ReadyDelay, 2))
            ReadyRemote:FireServer()
        else
            Fluent:Notify({ Title = "Bot Stopped", Content = "Bot deactivated.", Duration = 3 })
        end
    end,
})

Tabs.Main:AddToggle("NightmareToggle", {
    Title    = "Nightmare Circus — Auto Retry",
    Default  = config.NightmareRetryEnabled,
    Callback = function(state)
        nightmareRetryEnabled        = state
        config.NightmareRetryEnabled = state
        wipeDetected                 = false
        Fluent:Notify({
            Title   = state and "Nightmare Retry ON" or "Nightmare Retry OFF",
            Content = state and "Auto-retries 10s after full wipe." or "Disabled.",
            Duration = 4,
        })
    end,
})

Tabs.Main:AddButton({
    Title    = "Enter Queue",
    Callback = function() EnterQueue() end,
})

Tabs.Main:AddButton({
    Title    = "Cast Vote Now",
    Callback = function()
        local ok = FireVote()
        Fluent:Notify({
            Title   = ok and "Vote Sent" or "Vote Failed",
            Content = ok and ("Voted: " .. config.VoteChoice) or "Remote error.",
            Duration = 3,
        })
    end,
})

Tabs.Main:AddButton({
    Title    = "Send Stats to Discord",
    Callback = function()
        if config.WebhookURL == "" then
            Fluent:Notify({ Title = "No Webhook", Content = "Set a URL in Config first.", Duration = 4 })
            return
        end
        SendWebhook(totalRounds)
        Fluent:Notify({ Title = "Webhook Sent", Content = "Stats sent to Discord.", Duration = 3 })
    end,
})

Tabs.Main:AddButton({
    Title    = "Save Data",
    Callback = function()
        local ok = SaveJSON(DATA_FILE, sessionData)
        Fluent:Notify({
            Title   = ok and "Saved" or "Save Failed",
            Content = ok and "Session data saved." or "Check console.",
            Duration = 3,
        })
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  SUMMON TAB
-- ═══════════════════════════════════════════════════════════════════════════════

Tabs.Summon:AddDropdown("SummonPack", {
    Title    = "Pack",
    Values   = {"Pack1","Pack2","Pack3"},
    Default  = config.SummonPack,
    Callback = function(v) config.SummonPack = v end,
})

Tabs.Summon:AddDropdown("SummonAmount", {
    Title    = "Units per Summon",
    Values   = {"1","2","3","4","5","6","7","8","9","10"},
    Default  = tostring(config.SummonAmount),
    Callback = function(v) config.SummonAmount = v end,
})

Tabs.Summon:AddDropdown("SummonInterval", {
    Title    = "Loop Interval (seconds)",
    Values   = {"1","2","3","5","7","10","15","20","30"},
    Default  = tostring(config.SummonInterval),
    Callback = function(v) config.SummonInterval = v end,
})

Tabs.Summon:AddButton({
    Title    = "Summon Now",
    Callback = function() DoSummon(N(config.SummonAmount, 1), config.SummonPack) end,
})

local SummonStatusParagraph = Tabs.Summon:AddParagraph({ Title = "Auto Summon", Content = "Off" })

Tabs.Summon:AddToggle("SummonLoop", {
    Title    = "Auto Summon Loop",
    Default  = false,
    Callback = function(state)
        summonLoopRunning = state
        SummonStatusParagraph:SetDesc(state and "Running" or "Off")
        if state then
            task.spawn(function()
                while summonLoopRunning do
                    DoSummon(N(config.SummonAmount, 1), config.SummonPack)
                    task.wait(N(config.SummonInterval, 3))
                end
                SummonStatusParagraph:SetDesc("Off")
            end)
        end
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  FUSION TAB
-- ═══════════════════════════════════════════════════════════════════════════════

for _, r in ipairs({"Rare","Epic","Legendary","Mythic"}) do
    local key = "Fuse" .. r
    Tabs.Fusion:AddToggle(key, {
        Title    = "Fuse " .. r,
        Default  = config[key],
        Callback = function(state) config[key] = state end,
    })
end

local starOptions = {}
for i = 2, 10 do table.insert(starOptions, tostring(i)) end

Tabs.Fusion:AddDropdown("FuseTargetStars", {
    Title    = "Stop At Stars",
    Values   = starOptions,
    Default  = tostring(config.FuseTargetStars),
    Callback = function(v) config.FuseTargetStars = v end,
})

Tabs.Fusion:AddDropdown("FuseDelay", {
    Title    = "Delay Between Fusions (s)",
    Values   = {"0.1","0.2","0.3","0.5","0.75","1.0","1.5","2.0","3.0"},
    Default  = tostring(config.FuseDelay),
    Callback = function(v) config.FuseDelay = v end,
})

local FusionStatusParagraph = Tabs.Fusion:AddParagraph({ Title = "Fusion", Content = "Idle" })

Tabs.Fusion:AddButton({
    Title    = "Start Auto Fusion",
    Callback = function()
        FusionStatusParagraph:SetDesc("Running...")
        task.spawn(function()
            DoFusion()
            FusionStatusParagraph:SetDesc("Idle")
        end)
    end,
})

Tabs.Fusion:AddButton({
    Title    = "Stop Auto Fusion",
    Callback = function()
        fusionRunning = false
        FusionStatusParagraph:SetDesc("Stopped")
        Fluent:Notify({ Title = "Fusion Stopped", Content = "Auto fusion stopped.", Duration = 3 })
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  SELL TAB
-- ═══════════════════════════════════════════════════════════════════════════════

for _, r in ipairs({"Rare","Epic","Legendary","Mythic"}) do
    local key = "Sell" .. r
    Tabs.Sell:AddToggle(key, {
        Title    = "Sell " .. r,
        Default  = config[key],
        Callback = function(state) config[key] = state end,
    })
end

Tabs.Sell:AddDropdown("SellDelay", {
    Title    = "Delay Between Batches (s)",
    Values   = {"0.1","0.2","0.3","0.5","0.75","1.0","1.5","2.0"},
    Default  = tostring(config.SellDelay),
    Callback = function(v) config.SellDelay = v end,
})

Tabs.Sell:AddDropdown("SellInterval", {
    Title    = "Auto Sell Every (s)",
    Values   = {"5","10","15","20","30","45","60","90","120"},
    Default  = tostring(config.SellInterval),
    Callback = function(v) config.SellInterval = v end,
})

Tabs.Sell:AddButton({
    Title    = "Sell Now",
    Callback = function() task.spawn(DoSell) end,
})

local SellStatusParagraph = Tabs.Sell:AddParagraph({ Title = "Auto Sell", Content = "Off" })

Tabs.Sell:AddToggle("AutoSell", {
    Title    = "Auto Sell Loop",
    Default  = false,
    Callback = function(state)
        sellLoopRunning = state
        SellStatusParagraph:SetDesc(state and "Running" or "Off")
        if state then
            task.spawn(function()
                while sellLoopRunning do
                    DoSell()
                    task.wait(N(config.SellInterval, 30))
                end
                SellStatusParagraph:SetDesc("Off")
            end)
        end
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  SHOP TAB
-- ═══════════════════════════════════════════════════════════════════════════════

local shopItemsList = {
    "TraitReroll","EpicFusionCrystal","LegendaryFusionCrystal","RareFusionCrystal",
    "SummonTicket","Cupcake","Donut","Candy","RiceCake","Fries","Boba",
}
local currentShopItem = shopItemsList[1]
local currentShopQty  = 1

Tabs.Shop:AddDropdown("ShopItem", {
    Title    = "Item",
    Values   = shopItemsList,
    Default  = shopItemsList[1],
    Callback = function(v) currentShopItem = v end,
})

Tabs.Shop:AddDropdown("ShopQty", {
    Title    = "Quantity (0 = remove from list)",
    Values   = {"0","1","2","3","4","5","6","7","8","9","10"},
    Default  = "1",
    Callback = function(v) currentShopQty = tonumber(v) or 1 end,
})

Tabs.Shop:AddButton({
    Title    = "Add / Update Item",
    Callback = function()
        if currentShopQty == 0 then
            selectedShopItems[currentShopItem] = nil
            Fluent:Notify({ Title = "Shop", Content = "Removed: " .. currentShopItem, Duration = 3 })
        else
            selectedShopItems[currentShopItem] = currentShopQty
            Fluent:Notify({ Title = "Shop", Content = "Added: " .. currentShopItem .. " x" .. currentShopQty, Duration = 3 })
        end
        UpdateShopItemTarget()
    end,
})

Tabs.Shop:AddButton({
    Title    = "Clear All Items",
    Callback = function()
        selectedShopItems = {}
        UpdateShopItemTarget()
        Fluent:Notify({ Title = "Shop", Content = "Cleared all selected items.", Duration = 3 })
    end,
})

local SelectedItemsParagraph = Tabs.Shop:AddParagraph({ Title = "Selected Items", Content = "None" })

Tabs.Shop:AddButton({
    Title    = "Show Selected Items",
    Callback = function()
        local lines = {}
        for item, qty in pairs(selectedShopItems) do table.insert(lines, item .. "  x" .. qty) end
        SelectedItemsParagraph:SetDesc(#lines > 0 and table.concat(lines, "\n") or "None")
    end,
})

local ShopInfoParagraph = Tabs.Shop:AddParagraph({ Title = "Shop Info", Content = "Press Refresh to check." })

Tabs.Shop:AddButton({
    Title    = "Refresh Shop Info",
    Callback = function()
        local ok, err = pcall(function()
            local items = GetCurrentShopItems("ItemShop")
            local left  = math.floor(GetTimeToNextRefresh("ItemShop"))
            local lines = {}
            for i, item in ipairs(items) do table.insert(lines, "Slot " .. i .. ": " .. item.ItemName) end
            table.insert(lines, "Refreshes in: " .. left .. "s")
            ShopInfoParagraph:SetDesc(table.concat(lines, "\n"))
        end)
        if not ok then warn("[Shop] Refresh failed:", err) end
    end,
})

Tabs.Shop:AddButton({
    Title    = "Buy Now",
    Callback = function()
        local any = false
        for _, qty in pairs(selectedShopItems) do if qty > 0 then any = true break end end
        if not any then Fluent:Notify({ Title = "Shop", Content = "No items selected.", Duration = 3 }) return end
        task.spawn(BuyAllSelectedItems)
    end,
})

Tabs.Shop:AddToggle("ShopAutoBuy", {
    Title    = "Auto Buy on Refresh",
    Default  = config.ShopAutoBuy,
    Callback = function(state)
        config.ShopAutoBuy = state
        if state then StartShopBuyLoop()
        else
            shopBuyRunning = false
            Fluent:Notify({ Title = "Auto Shop", Content = "Auto buy stopped.", Duration = 3 })
        end
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  REROLL TAB
-- ═══════════════════════════════════════════════════════════════════════════════

local unitDropdown = Tabs.Reroll:AddDropdown("RerollUnit", {
    Title    = "Unit",
    Values   = GetUnitNames(),
    Default  = GetUnitNames()[1] or "",
    Callback = function(v) rerollTargetUnit = v end,
})

Tabs.Reroll:AddButton({
    Title    = "Refresh Unit List",
    Callback = function()
        unitDropdown:SetValues(GetUnitNames())
        Fluent:Notify({ Title = "Reroll", Content = "Unit list refreshed.", Duration = 3 })
    end,
})

for _, stat in ipairs(statNames) do
    local s = stat
    Tabs.Reroll:AddDropdown("Reroll" .. s, {
        Title    = s .. " Target",
        Values   = gradeOptions,
        Default  = rerollTargets[s],
        Callback = function(v) rerollTargets[s] = v end,
    })
end

Tabs.Reroll:AddDropdown("RerollDelay", {
    Title    = "Delay Between Rolls (s)",
    Values   = {"0.3","0.5","0.75","1.0","1.5","2.0","3.0"},
    Default  = "0.5",
    Callback = function(v) rerollDelay = tonumber(v) or 0.5 end,
})

local RerollStatusParagraph = Tabs.Reroll:AddParagraph({ Title = "Reroll",         Content = "Idle" })
local CurrentStatsParagraph = Tabs.Reroll:AddParagraph({ Title = "Current Grades", Content = "Press Check Stats." })

Tabs.Reroll:AddButton({
    Title    = "Start Rerolling",
    Callback = function()
        if rerollRunning then Fluent:Notify({ Title = "Reroll", Content = "Already running!", Duration = 3 }) return end
        if rerollTargetUnit == "" then Fluent:Notify({ Title = "Reroll", Content = "No unit selected.", Duration = 3 }) return end
        local unit = UnitsFolder:FindFirstChild(rerollTargetUnit)
        if not unit then Fluent:Notify({ Title = "Reroll", Content = "Unit not found.", Duration = 4 }) return end
        if AllStatsAtTarget(unit) then Fluent:Notify({ Title = "Reroll", Content = "Already at target grades!", Duration = 4 }) return end
        rerollRunning = true
        RerollStatusParagraph:SetDesc("Running — " .. rerollTargetUnit)
        task.spawn(function()
            DoStatReroll(unit)
            RerollStatusParagraph:SetDesc("Idle")
        end)
    end,
})

Tabs.Reroll:AddButton({
    Title    = "Stop Rerolling",
    Callback = function()
        rerollRunning = false
        RerollStatusParagraph:SetDesc("Stopped")
        Fluent:Notify({ Title = "Reroll Stopped", Content = "Reroller stopped.", Duration = 3 })
    end,
})

Tabs.Reroll:AddButton({
    Title    = "Check Current Stats",
    Callback = function()
        if rerollTargetUnit == "" then Fluent:Notify({ Title = "Reroll", Content = "No unit selected.", Duration = 3 }) return end
        local unit = UnitsFolder:FindFirstChild(rerollTargetUnit)
        if not unit then Fluent:Notify({ Title = "Reroll", Content = "Unit not found.", Duration = 3 }) return end
        local grades = next(currentGrades) and currentGrades or {
            Attack   = unit:GetAttribute("Attack")   or "?",
            Health   = unit:GetAttribute("Health")   or "?",
            Speed    = unit:GetAttribute("Speed")    or "?",
            Cooldown = unit:GetAttribute("Cooldown") or "?",
        }
        local lines = {}
        for _, s in ipairs(statNames) do
            local cur = grades[s] or "?"
            local tgt = rerollTargets[s] or "X"
            local hit = (gradeOrder[cur] or 0) >= (gradeOrder[tgt] or 0)
            table.insert(lines, s .. ": " .. cur .. " / " .. tgt .. (hit and " ✓" or ""))
        end
        CurrentStatsParagraph:SetDesc(table.concat(lines, "\n"))
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  STATS TAB
-- ═══════════════════════════════════════════════════════════════════════════════

local StatsParagraph = Tabs.Stats:AddParagraph({ Title = "Session Loot", Content = "Nothing collected yet." })

Tabs.Stats:AddButton({
    Title    = "Refresh",
    Callback = function()
        local lines = {}
        for k, v in pairs(sessionData) do
            if k ~= "_traitRerollsBought" then table.insert(lines, k .. ": " .. tostring(v)) end
        end
        table.sort(lines)
        table.insert(lines, "Trait Rerolls Bought: " .. traitRerollsBought)
        StatsParagraph:SetDesc(#lines > 0 and table.concat(lines, "\n") or "Nothing collected yet.")
    end,
})

Tabs.Stats:AddButton({
    Title    = "Reset Session Data",
    Callback = function()
        sessionData        = {}
        traitRerollsBought = 0
        local ok = SaveJSON(DATA_FILE, sessionData)
        StatsParagraph:SetDesc("Nothing collected yet.")
        Fluent:Notify({
            Title   = ok and "Reset" or "Reset Failed",
            Content = ok and "Session data cleared." or "File write failed.",
            Duration = 3,
        })
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  CONFIG TAB
-- ═══════════════════════════════════════════════════════════════════════════════

Tabs.Config:AddInput("WebhookURL", {
    Title       = "Discord Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Default     = config.WebhookURL,
    Callback    = function(v) config.WebhookURL = v end,
})

Tabs.Config:AddDropdown("VoteChoice", {
    Title    = "Vote Choice",
    Values   = {"Retry","Next","Lobby"},
    Default  = config.VoteChoice,
    Callback = function(v) config.VoteChoice = v end,
})

Tabs.Config:AddDropdown("ReadyDelay", {
    Title    = "Ready Delay (s)",
    Values   = {"1","1.5","2","2.5","3","4","5"},
    Default  = tostring(config.ReadyDelay),
    Callback = function(v) config.ReadyDelay = v end,
})

Tabs.Config:AddDropdown("RewardDelay", {
    Title    = "Reward Collect Delay (s)",
    Values   = {"0.1","0.2","0.3","0.5","0.75","1.0","1.5","2.0"},
    Default  = tostring(config.RewardDelay),
    Callback = function(v) config.RewardDelay = v end,
})

Tabs.Config:AddDropdown("VoteDelay", {
    Title    = "Vote Delay (s)",
    Values   = {"0.1","0.2","0.3","0.5","0.75","1.0","1.5","2.0"},
    Default  = tostring(config.VoteDelay),
    Callback = function(v) config.VoteDelay = v end,
})

Tabs.Config:AddToggle("AutoStart", {
    Title    = "Auto-Start Bot on Load",
    Default  = config.AutoStart,
    Callback = function(v) config.AutoStart = v end,
})

Tabs.Config:AddToggle("AutoQueue", {
    Title    = "Auto-Enter Queue on Load",
    Default  = config.AutoQueue,
    Callback = function(v) config.AutoQueue = v end,
})

Tabs.Config:AddButton({
    Title    = "Save Settings",
    Callback = function()
        config.NightmareRetryEnabled = nightmareRetryEnabled
        local ok = SaveJSON(CONFIG_FILE, config)
        Fluent:Notify({
            Title   = ok and "Settings Saved" or "Save Failed",
            Content = ok and "Config saved." or "Check console.",
            Duration = 4,
        })
    end,
})

Tabs.Config:AddButton({
    Title    = "Reset to Defaults",
    Callback = function()
        for k, v in pairs(defaultConfig) do config[k] = v end
        local ok = SaveJSON(CONFIG_FILE, config)
        Fluent:Notify({
            Title   = ok and "Reset" or "Reset Failed",
            Content = ok and "Settings reset to defaults." or "File write failed.",
            Duration = 4,
        })
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  ROUND LOOP
-- ═══════════════════════════════════════════════════════════════════════════════

RoundEnd:GetPropertyChangedSignal("Enabled"):Connect(function()
    if not RoundEnd.Enabled or not botRunning then return end
    task.wait(N(config.RewardDelay, 0.5))
    CollectRewards()
    SaveJSON(DATA_FILE, sessionData)
    totalRounds += 1
    UpdateStatus()
    if config.WebhookURL ~= "" then SendWebhook(totalRounds) end
    Fluent:Notify({ Title = "Round #" .. totalRounds .. " Done", Content = "Voting: " .. config.VoteChoice, Duration = 3 })
    task.wait(N(config.VoteDelay, 0.2))
    FireVote()
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  AUTO-START
-- ═══════════════════════════════════════════════════════════════════════════════

if config.AutoQueue then
    task.wait(3)
    EnterQueue()
end

if config.BotActive then
    task.wait(1)
    botRunning   = true
    wipeDetected = false
    UpdateStatus()
    Fluent:Notify({ Title = "Bot Restored", Content = "Bot Active loaded from config.", Duration = 4 })
    CollectChests()
    task.wait(N(config.ReadyDelay, 2))
    ReadyRemote:FireServer()
end

if config.ShopAutoBuy then StartShopBuyLoop() end

if config.NightmareRetryEnabled then
    nightmareRetryEnabled = true
    wipeDetected          = false
end

-- Only show on touch-enabled devices (phones/tablets)
-- Also renders on PC as a fallback — draggable so it won't get in the way
local screenGui = Instance.new("ScreenGui")
screenGui.Name             = "CursedPeanutsToggle"
screenGui.ResetOnSpawn     = false
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder     = 999
screenGui.Parent           = playerGui
 
local btn = Instance.new("TextButton")
btn.Name              = "MenuToggle"
btn.Size              = UDim2.fromOffset(52, 52)
btn.Position          = UDim2.new(1, -66, 0.5, -26)  -- right-center by default
btn.AnchorPoint       = Vector2.new(0, 0)
btn.BackgroundColor3  = Color3.fromRGB(30, 30, 35)
btn.BorderSizePixel   = 0
btn.Text              = "☰"
btn.TextColor3        = Color3.fromRGB(220, 220, 220)
btn.TextSize          = 22
btn.Font              = Enum.Font.GothamBold
btn.AutoButtonColor   = false
btn.Parent            = screenGui
 
-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent       = btn
 
-- Subtle border ring
local stroke = Instance.new("UIStroke")
stroke.Color     = Color3.fromRGB(80, 80, 100)
stroke.Thickness = 1.5
stroke.Parent    = btn
 
-- Hover tint (works on PC; touch devices skip hover)
btn.MouseEnter:Connect(function()
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
end)
btn.MouseLeave:Connect(function()
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
end)
 
-- ── Drag logic ────────────────────────────────────────────────
local dragging    = false
local dragStart   = Vector2.zero
local startPos    = Vector2.zero
local DRAG_THRESHOLD = 6   -- pixels before we count it as a drag, not a tap
 
btn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        startPos  = Vector2.new(btn.Position.X.Offset, btn.Position.Y.Offset)
    end
end)
 
btn.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.Touch or
        input.UserInputType == Enum.UserInputType.MouseMovement
    ) then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        -- Clamp inside screen
        local vp   = workspace.CurrentCamera.ViewportSize
        local newX = math.clamp(startPos.X + delta.X, 0, vp.X - 52)
        local newY = math.clamp(startPos.Y + delta.Y, 0, vp.Y - 52)
        btn.Position = UDim2.fromOffset(newX, newY)
    end
end)
 
btn.InputEnded:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        -- Only toggle if the finger barely moved (it was a tap, not a drag)
        if delta.Magnitude < DRAG_THRESHOLD then
            Window:Minimize()
        end
        dragging = false
    end
end)

print("[SummonHeroesBot] Loaded.")
