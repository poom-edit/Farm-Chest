-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    FlySpeed = 150
}

local noclipConn = nil
local currentTween = nil

-- 1. Noclip กันติดบล็อก
local function setNoclip(enable)
    if enable then
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
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

-- 2. สแกนหา CFrame ทั้งหมด + เรียงลำดับจาก "ใกล้ไปไกล"
local function getAllChestDataSorted()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return {} end
    local hrpPos = char.HumanoidRootPart.Position

    local chestList = {}

    -- ดึงกล่องทั้งหมดในแมพ
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name == "Chest1" or obj.Name == "Chest2" or obj.Name == "Chest3" or obj.Name:find("Chest")) then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part and part.Parent and part:IsDescendantOf(Workspace) then
                local dist = (hrpPos - part.Position).Magnitude
                table.insert(chestList, {
                    Model = obj,
                    Part = part,
                    CFrame = part.CFrame,
                    Distance = dist
                })
            end
        end
    end

    -- [จุดสำคัญ] เรียงลำดับใน Table จากระยะทางน้อยที่สุดไปมากที่สุด (ใกล้ -> ไกล)
    table.sort(chestList, function(a, b)
        return a.Distance < b.Distance
    end)

    return chestList
end

-- 3. ระบบ Tween บินไปที่ CFrame
local function flyToChestCFrame(chestData)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart

    local targetCFrame = chestData.CFrame
    local targetPart = chestData.Part
    local targetModel = chestData.Model

    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    local time = distance / CONFIG.FlySpeed

    setNoclip(true)

    local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    currentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    currentTween:Play()

    local startTime = tick()
    while CONFIG.AutoFarm do
        task.wait(0.05)
        
        -- เช็กว่ากล่องหายไปจากแมพแล้วหรือยัง
        local isChestGone = not targetModel.Parent or not targetPart.Parent or not targetPart:IsDescendantOf(Workspace)
        
        if isChestGone or (tick() - startTime) >= (time + 0.5) then
            break
        end
    end

    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end

    if targetPart and targetPart.Parent and firetouchinterest then
        firetouchinterest(hrp, targetPart, 0)
        task.wait(0.05)
        firetouchinterest(hrp, targetPart, 1)
    end

    setNoclip(false)
end

-- 4. ลูปหลัก: สแกนหา CFrame -> เรียงลำดับใกล้ไปไกล -> บินเก็บตามคิว
local function startSortedListFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            -- ดึงลิสต์กล่องที่เรียงลำดับจากใกล้สุดไปไกลสุดแล้ว
            local sortedChestList = getAllChestDataSorted()

            if #sortedChestList > 0 then
                for index, chestData in ipairs(sortedChestList) do
                    if not CONFIG.AutoFarm then break end
                    
                    -- ตรวจสอบก่อนบินอีกครั้งว่ากล่องตรงพิกัดนี้ยังไม่ถูกเก็บ
                    if chestData.Part and chestData.Part.Parent then
                        flyToChestCFrame(chestData)
                        task.wait(0.05)
                    end
                end
            else
                task.wait(3)
            end
        end
    end)
end

-- 5. Rayfield UI Setup
local Window = Rayfield:CreateWindow({
   Name = "Sorted CFrame Chest Hub",
   LoadingTitle = "Sorting Chests by Distance...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chests (เรียงลำดับใกล้ไปไกล)",
   CurrentValue = false,
   Flag = "Toggle_SortedFarm",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startSortedListFarmLoop()
       elseif currentTween then
           currentTween:Cancel()
       end
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed",
   Range = {50, 300},
   Increment = 10,
   Suffix = " Speed",
   CurrentValue = 150,
   Flag = "Slider_SortedSpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
