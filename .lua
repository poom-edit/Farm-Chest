-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    FlySpeed = 150,
    ServerHopWhenEmpty = true
}

local noclipConn = nil
local currentTween = nil

-- 1. ระบบ Noclip ป้องกันการติดบล็อก
local function setNoclip(enable)
    if enable then
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.CanCollide = false
                        end
                    end
                end
            end)
        end
    else
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end
    end
end

-- 2. สแกนหากล่องใกล้ที่สุด
local function getClosestChest()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    
    local hrp = char.HumanoidRootPart
    local closestChest = nil
    local shortestDistance = math.huge

    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Chest") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part and part.Parent and part:IsDescendantOf(Workspace) then
                local dist = (hrp.Position - part.Position).Magnitude
                if dist < shortestDistance then
                    shortestDistance = dist
                    closestChest = part
                end
            end
        end
    end

    return closestChest
end

-- 3. ระบบ Tween ไปหา CFrame ของกล่อง (แก้ปัญหากระเด้งกลับ)
local function tweenToChest(chestPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not chestPart or not chestPart.Parent then return end
    
    local hrp = char.HumanoidRootPart
    local humanoid = char:FindFirstChildWhichIsA("Humanoid")
    
    setNoclip(true)

    -- คำนวณระยะทางและเวลาในการบิน
    local targetCFrame = chestPart.CFrame * CFrame.new(0, 1.5, 0)
    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    local tweenTime = distance / CONFIG.FlySpeed

    -- ปรับปรุง: ล้างค่าความเร็ว/แรงต้านก่อนบิน ป้องกันตัวกระเด้งกลับที่เดิม
    if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Flying) end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    local tweenInfo = TweenInfo.new(
        tweenTime,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
    )

    currentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    currentTween:Play()

    local completed = false
    local conn
    conn = currentTween.Completed:Connect(function()
        completed = true
        if conn then conn:Disconnect() end
    end)

    local startTime = tick()
    repeat 
        task.wait(0.02)
        -- ล้างค่าแรงโน้มถ่วงตลอดการบินเพื่อป้องกัน Rubberband
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    until completed or not CONFIG.AutoFarm or (tick() - startTime) > (tweenTime + 1) or not chestPart.Parent

    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end

    -- แตะกล่องเมื่อถึงพิกัด
    if CONFIG.AutoFarm and chestPart and chestPart.Parent then
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        
        if firetouchinterest then
            firetouchinterest(hrp, chestPart, 0)
            task.wait(0.08)
            firetouchinterest(hrp, chestPart, 1)
        end
    end

    setNoclip(false)
end

-- 4. ระบบ Server Hop
local function serverHop()
    Rayfield:Notify({Title = "Server Hop", Content = "ไม่พบหีบแล้ว กำลังเปลี่ยนเซิร์ฟเวอร์...", Duration = 3})
    
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    local foundServer = nil
    local cursor = ""

    for page = 1, 5 do
        local url = "https://games.roblox.com/v1/places/" .. placeId .. "/servers/0?sortOrder=Desc&limit=100"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end

        local success, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if success and res and res.data then
            cursor = res.nextPageCursor or ""
            for _, s in ipairs(res.data) do
                if s.id ~= currentJobId and s.playing < s.maxPlayers - 1 and s.playing > 1 then
                    foundServer = s.id
                    break
                end
            end
        end

        if foundServer or cursor == "" then break end
    end

    if foundServer then
        TeleportService:TeleportToPlaceInstance(placeId, foundServer, LocalPlayer)
    else
        TeleportService:Teleport(placeId, LocalPlayer)
    end
end

-- 5. ลูปทำงานหลัก (สแกน -> Tween -> สแกนหาใหม่ทันที)
local function startTweenFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local nearestChest = getClosestChest()
            
            if nearestChest and nearestChest.Parent then
                tweenToChest(nearestChest)
                task.wait(0.05)
            else
                setNoclip(false)
                if CONFIG.ServerHopWhenEmpty then
                    serverHop()
                    break
                else
                    task.wait(2)
                end
            end
        end
        
        if currentTween then
            currentTween:Cancel()
        end
        setNoclip(false)
    end)
end

-- 6. Rayfield UI Setup
local Window = Rayfield:CreateWindow({
   Name = "Fixed Direct Tween Farm",
   LoadingTitle = "Loading Stable System...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chest (Fixed Rubberband)",
   CurrentValue = false,
   Flag = "Toggle_FixBounce",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startTweenFarmLoop()
       elseif currentTween then
           currentTween:Cancel()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty",
   CurrentValue = true,
   Flag = "Toggle_HopFixBounce",
   Callback = function(Value)
       CONFIG.ServerHopWhenEmpty = Value
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed",
   Range = {50, 300},
   Increment = 10,
   Suffix = " Speed",
   CurrentValue = 150,
   Flag = "Slider_SpeedBounce",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
