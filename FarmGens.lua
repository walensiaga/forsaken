task.wait(5)

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Ініціалізація глобальних параметрів через getgenv
local DCWebhook = (getgenv and getgenv().DiscordWebhook) or false -- URL вебхука Discord для сповіщень
local GenTime = tonumber(getgenv and getgenv().GeneratorTime) or 2.5 -- Час між активаціями генератора (мін. 2.5, інакше кік)
if DCWebhook == "" then DCWebhook = false end

-- Встановлюємо статичне посилання на зображення
local ProfilePicture = "https://cdn.discordapp.com/attachments/1348413433137074291/1356724513877917937/Made_with_insMind-Sa1K8NjnjNI.jpg?ex=67ed9baa&is=67ec4a2a&hm=440ab33249a88264489c2e5633817ebd2b2494318401efaad89efa39e91e273e&"

-- Повідомлення про завантаження скрипта
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "FarmGens",
    Text = "by Redux Hub",
    Duration = 30,
})

-- Надсилання повідомлення в Discord
local lastWebhookTime = 0
local WebhookCooldown = 5 -- Затримка в секундах між повідомленнями
local function SendWebhook(Title, Description, Color, Footer)
    if not DCWebhook or (tick() - lastWebhookTime < WebhookCooldown) then return end
    lastWebhookTime = tick()

    local request = request or http_request or syn.request
    if not request then return end

    local success, errorMessage = pcall(function()
        request({
            Url = DCWebhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                username = Players.LocalPlayer.DisplayName,
                avatar_url = ProfilePicture,
                embeds = { {
                    title = Title,
                    description = Description,
                    color = Color,
                    footer = { text = Footer },
                } },
            }),
        })
    end)

    if not success then print("Webhook error: " .. errorMessage) end
end

-- Вимкнення Malice через мережевий запит
task.spawn(function()
    pcall(function()
        game:GetService("ReplicatedStorage").Modules.Network.RemoteEvent:FireServer(
            "UpdateSettings",
            Players.LocalPlayer.PlayerData.Settings.Game.MaliceDisabled,
            true
        )
    end)
end)

-- Подія для скасування шляху
if _G.CancelPathEvent then _G.CancelPathEvent:Fire() end
_G.CancelPathEvent = Instance.new("BindableEvent")

-- Вимкнення стандартного управління
local Controller = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
Controller:Disable()

-- Телепортація на випадковий сервер
local function teleportToRandomServer()
    local request = request or http_request or syn.request
    if not request then return end

    local url = "https://games.roblox.com/v1/games/18687417158/servers/Public?sortOrder=Asc&limit=100"
    local attempts, maxAttempts = 0, 10
    local retryDelay = 10

    while attempts < maxAttempts do
        local success, response = pcall(function()
            return request({ Url = url, Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
        end)

        if success and response and response.Body then
            local data = HttpService:JSONDecode(response.Body)
            if data and data.data and #data.data > 0 then
                local server = data.data[math.random(1, #data.data)]
                if server.id then
                    TeleportService:TeleportToPlaceInstance(18687417158, server.id, Players.LocalPlayer)
                    return
                end
            end
        end

        attempts = attempts + 1
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Grahh",
            Text = "Serverhop got ratelimited, retrying...",
            Duration = 11,
        })
        task.wait(retryDelay)
    end
    print("Failed to find a server after " .. maxAttempts .. " attempts.")
end

-- Перевірка таймера раунду для телепортації (збільшено затримку)
task.delay(15, function()
    pcall(function()
        local timer = Players.LocalPlayer.PlayerGui:WaitForChild("RoundTimer", 10).Main.Time.ContentText
        local minutes, seconds = timer:match("(%d+):(%d+)")
        local totalSeconds = tonumber(minutes) * 60 + tonumber(seconds)
        print(totalSeconds .. " seconds left until round ends.")
        if totalSeconds > 90 then teleportToRandomServer() end
    end)
end)

-- Пошук генераторів
local function findGenerators()
    local map = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Ingame") and workspace.Map.Ingame:FindFirstChild("Map")
    if not map then return {} end

    local generators = {}
    for _, g in ipairs(map:GetChildren()) do
        if g.Name == "Generator" and g.Progress.Value < 100 then
            local playersNearby = false
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= Players.LocalPlayer and player:DistanceFromCharacter(g:GetPivot().Position) <= 25 then
                    playersNearby = true
                    break
                end
            end
            if not playersNearby then table.insert(generators, g) end
        end
    end

    table.sort(generators, function(a, b)
        local character = Players.LocalPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then return false end
        local rootPart = character.HumanoidRootPart
        local aPos = a:GetPivot().Position
        local bPos = b:GetPivot().Position
        return (aPos - rootPart.Position).Magnitude < (bPos - rootPart.Position).Magnitude
    end)

    return generators
end

-- Перевірка, чи гравець у генераторі
local function InGenerator()
    for _, v in ipairs(Players.LocalPlayer.PlayerGui.TemporaryUI:GetChildren()) do
        if string.sub(v.Name, 1, 3) == "Gen" then return false end
    end
    return true
end

-- Функція для створення вузлів шляху (для дебагу)
local function createNode(position)
    local part = Instance.new("Part")
    part.Size = Vector3.new(.6, .6, .6)
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(248, 255, 150)
    part.Transparency = 0.5
    part.Anchored = true
    part.CanCollide = false
    part.Position = position + Vector3.new(0, 1.5, 0)
    part.Parent = workspace
    game:GetService("Debris"):AddItem(part, 15)
    return part
end

-- Пошук шляху до генератора з вузлами для дебагу
local function PathFinding(generator)
    local character = Players.LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("Humanoid") then return false end

    local humanoid = character.Humanoid
    local rootPart = character.HumanoidRootPart
    local targetPosition = generator:GetPivot().Position

    local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 1, AgentCanJump = false })
    local success, err = pcall(function() path:ComputeAsync(rootPart.Position, targetPosition) end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        print("Path computation failed: " .. (err or "unknown error"))
        return false
    end

    local waypoints = path:GetWaypoints()
    if #waypoints <= 1 then return false end

    local activeNodes = {}
    for _, waypoint in ipairs(waypoints) do
        local node = createNode(waypoint.Position)
        table.insert(activeNodes, node)
        
        humanoid:MoveTo(waypoint.Position)
        local reached = humanoid.MoveToFinished:Wait(5)
        if not reached then
            for _, n in ipairs(activeNodes) do n:Destroy() end
            return false
        end
    end

    for _, node in ipairs(activeNodes) do node:Destroy() end
    return true
end

-- Виконання всіх генераторів
local function DoAllGenerators()
    for _, g in ipairs(findGenerators()) do
        if (Players.LocalPlayer.Character:GetPivot().Position - g:GetPivot().Position).Magnitude > 500 then break end

        local pathStarted = false
        for attempt = 1, 3 do
            pathStarted = PathFinding(g)
            if pathStarted then break else task.wait(1) end
        end

        if pathStarted then
            task.wait(0.5)
            local prompt = g:FindFirstChild("Main") and g.Main:FindFirstChild("Prompt")
            if prompt then
                fireproximityprompt(prompt)
                task.wait(0.2)
                if not InGenerator() then
                    local positions = {
                        g:GetPivot().Position - g:GetPivot().RightVector * 3,
                        g:GetPivot().Position + g:GetPivot().RightVector * 3,
                    }
                    for i, pos in ipairs(positions) do
                        Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
                        task.wait(0.25)
                        fireproximityprompt(prompt)
                        if InGenerator() then break end
                    end
                end
            end
            for i = 1, 6 do
                if g.Progress.Value < 100 and g:FindFirstChild("Remotes") and g.Remotes:FindFirstChild("RE") then
                    g.Remotes.RE:FireServer()
                end
                if i < 6 and g.Progress.Value < 100 then task.wait(GenTime) end
            end
        else
            return
        end
    end

    SendWebhook(
        "Generator Autofarm",
        "Finished all generators, Current Balance: " .. Players.LocalPlayer.PlayerData.Stats.Currency.Money.Value ..
        "\nTime Played: " .. (function()
            local seconds = Players.LocalPlayer.PlayerData.Stats.General.TimePlayed.Value
            local days = math.floor(seconds / (60 * 60 * 24))
            seconds = seconds % (60 * 60 * 24)
            local hours = math.floor(seconds / (60 * 60))
            seconds = seconds % (60 * 60)
            local minutes = math.floor(seconds / 60)
            seconds = seconds % 60
            return string.format("%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
        end)(),
        0x00FF00,
        "dsc.gg/redux-hub | <3"
    )
    task.wait(1)
    teleportToRandomServer()
end

-- Перевірка входу в гру з перевіркою Spectating
local function AmIInGameYet()
    -- Чекаємо, поки персонаж з’явиться
    Players.LocalPlayer.CharacterAdded:Wait()
    local character = Players.LocalPlayer.Character
    print("Character loaded!")

    local timeout = 60
    local elapsed = 0
    while elapsed < timeout do
        local spectatingFolder = workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Spectating")
        print("Checking if player is in game... Elapsed: " .. elapsed .. "s")
        print("Character exists: " .. (character and "Yes" or "No"))
        print("Character parent: " .. (character and character.Parent and character.Parent.Name or "None"))
        print("Spectating folder exists: " .. (spectatingFolder and "Yes" or "No"))
        print("Team: " .. (Players.LocalPlayer.Team and Players.LocalPlayer.Team.Name or "None"))
        
        -- Дебаг: виводимо, де знаходиться персонаж
        if character and character.Parent then
            print("Character is in: " .. character.Parent:GetFullName())
        end

        -- Перевіряємо, чи гравець НЕ в Spectating
        if character and character.Parent and spectatingFolder and not spectatingFolder:FindFirstChild(Players.LocalPlayer.Name) then
            print("Player is not in Spectating! Assuming in game.")
            task.wait(4)
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, nil)
            DoAllGenerators()
            return
        end

        -- Якщо гравець у Spectating, чекаємо
        if spectatingFolder and spectatingFolder:FindFirstChild(Players.LocalPlayer.Name) then
            print("Player is in Spectating (lobby). Waiting to join game...")
        end

        task.wait(1)
        elapsed = elapsed + 1
    end
    print("Timeout: Player still in Spectating after " .. timeout .. " seconds.")
    teleportToRandomServer()
end

-- Перевірка смерті гравця
local function DidiDie()
    while task.wait(0.5) do
        local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health == 0 then
            SendWebhook(
                "Generator Autofarm",
                "Killer got me! Current Balance: " .. Players.LocalPlayer.PlayerData.Stats.Currency.Money.Value ..
                "\nTime Played: " .. (function()
                    local seconds = Players.LocalPlayer.PlayerData.Stats.General.TimePlayed.Value
                    local days = math.floor(seconds / (60 * 60 * 24))
                    seconds = seconds % (60 * 60 * 24)
                    local hours = math.floor(seconds / (60 * 60))
                    seconds = seconds % (60 * 60)
                    local minutes = math.floor(seconds / 60)
                    seconds = seconds % 60
                    return string.format("%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
                end)(),
                0xFF0000,
                "dsc.gg/redux-hub | <3"
            )
            task.wait(0.5)
            teleportToRandomServer()
            break
        end
    end
end

-- Запуск основних функцій
task.spawn(function() pcall(DidiDie) end)
AmIInGameYet()
