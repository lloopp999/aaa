local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local configs = ReplicatedStorage.Data.Assets.Configs
local sourceIdAttribute = "StealAnimationId"
local root = workspace:FindFirstChild("AnimationLoader")

if root and not root:IsA("Folder") then
    warn("[Steal_animationLoader] Workspace.AnimationLoader 已存在，但不是 Folder，导入已中止")
    return
end

if not root then
    root = Instance.new("Folder")
    root.Name = "AnimationLoader"
    root.Parent = workspace
end

local succeeded = 0
local failed = 0
local skipped = 0
local failedConfigs = 0

local function loadAnimalAnimations(configModule)
    local ok, config = pcall(require, configModule)
    if not ok then
        failedConfigs += 1
        warn(string.format("[Steal_animationLoader] 配置读取失败 %s — %s",
            configModule:GetFullName(), tostring(config)))
        return
    end

    if type(config) ~= "table" or type(config._id) ~= "string" or config._id == ""
        or type(config.Animations) ~= "table" then
        return
    end

    local animalId = config._id
    local folder = root:FindFirstChild(animalId)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = animalId
        folder.Parent = root
    end

    for name, animation in pairs(config.Animations) do
        if typeof(animation) ~= "Instance" or not animation:IsA("Animation") then
            continue
        end

        local animationName = tostring(name)
        local path = animalId .. "/" .. animationName
        if not folder:IsA("Folder") then
            failed += 1
            warn(string.format("[Steal_animationLoader] 加载失败 %s — 动物目录被同名节点占用", path))
            continue
        end

        local existing = folder:FindFirstChild(animationName)
        if existing then
            if existing:IsA("KeyframeSequence") then
                skipped += 1
            else
                failed += 1
                warn(string.format("[Steal_animationLoader] 加载失败 %s — 序列名称被同名节点占用", path))
            end
            continue
        end

        local animationId = animation.AnimationId
        if animationId == "" then
            failed += 1
            warn(string.format("[Steal_animationLoader] 加载失败 %s — AnimationId 为空", path))
            continue
        end

        local loaded, sequence = pcall(function()
            return KeyframeSequenceProvider:GetKeyframeSequenceAsync(animationId)
        end)
        if not loaded or typeof(sequence) ~= "Instance" or not sequence:IsA("KeyframeSequence") then
            failed += 1
            warn(string.format("[Steal_animationLoader] 加载失败 %s (%s) — %s",
                path, animationId, tostring(sequence)))
            continue
        end

        sequence.Name = animationName
        sequence:SetAttribute(sourceIdAttribute, animationId)
        sequence.Parent = folder
        succeeded += 1
        print(string.format("[Steal_animationLoader] 加载成功 %s (%s)", path, animationId))
    end
end

for _, configModule in ipairs(configs:GetDescendants()) do
    if configModule:IsA("ModuleScript") then
        loadAnimalAnimations(configModule)
    end
end

print(string.format("[Steal_animationLoader] 导入结束，成功 %d，失败 %d，已存在跳过 %d，配置读取失败 %d",
    succeeded, failed, skipped, failedConfigs))
