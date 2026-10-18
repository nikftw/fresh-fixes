local _, FF = ...
-- CVar catalog adapted from Forever Visibility for Fresh Fixes Graphics.
-- `best` = max-visibility; `levels[i]` = value from preset i (1 Free … 4 Max
-- graphics); personal rows are never preset. `preset = true` rows write first
-- (they reset detail CVars). `raid` = Raid/BG twin. Probe before write —
-- nothing here proves the CVar exists.
local ns = {}
FF.GraphicsCatalog = ns

local LEVEL_LABEL = function(value) return tostring(value + 1) end
local PERCENT = function(value) return math.floor(value * 100 + 0.5) .. "%" end
local ON_OFF = { [true] = "On", [false] = "Off" }

local function VideoSupport(name)
    return function()
        local check = C_VideoOptions and C_VideoOptions[name]
        return type(check) == "function" and check() == true
    end
end

-- Preset 0 is maximum visibility; each later one raises the rows of its tier.
ns.PRESETS = {
    [0] = { name = "Max visibility", tip = "Every setting at its clearest value." },
    { name = "Free only", tip = "Max visibility, with the settings that cost no visibility raised." },
    { name = "Balanced", tip = "Free only, with the settings that cost a little visibility raised too." },
    { name = "Scenic", tip = "Balanced, with the settings that cost moderate visibility raised too." },
    { name = "Max graphics", tip = "Every setting at its prettiest value." },
}
ns.TIERS = { "No visibility cost", "Small visibility cost", "Moderate visibility cost", "Large visibility cost" }

ns.SECTIONS = {
    {
        kind = "picture", title = "Your picture: brightness, contrast and gamma",
        note = "Set these yourself: they change how the whole game looks and depend on your monitor and taste. Presets never change them.",
        entries = {
            { key = "brightness", cvar = "Brightness", where = "Options > Graphics", personal = true,
              label = "Brightness", kind = "range", min = 0, max = 100, step = 1,
              tip = "Same range as Blizzard's Brightness slider. Blizzard's default is 50." },
            { key = "contrast", cvar = "Contrast", where = "Options > Graphics", personal = true,
              label = "Contrast", kind = "range", min = 0, max = 100, step = 1,
              tip = "Same range as Blizzard's Contrast slider. Higher makes darks darker and brights brighter. Blizzard's default is 50." },
            { key = "gamma", cvar = "Gamma", where = "Options > Graphics", personal = true,
              label = "Gamma", kind = "range", min = 0.3, max = 2.8, step = 0.1,
              tip = "Same range as Blizzard's Gamma slider. Higher lifts caves, nights and shade but washes out bright scenes and the sky. Blizzard's default is 1.0." },
        },
    },
    {
        kind = "tier", tier = 1,
        entries = {
            { key = "antiAliasing", cvar = "ffxAntiAliasingMode", where = "Options > Graphics",
              label = "Image anti-aliasing", kind = "choice", values = { 0, 1, 2, 3, 4 },
              labels = { [0] = "None", "FXAA Low", "FXAA High", "CMAA", "CMAA2" },
              best = 0, levels = { [1] = 4 }, looks = 2, cost = 0, gpu = 1, ownUntilPreset = true,
              tip = "Blizzard's image-based anti-aliasing: smooths jagged edges on buildings, trees and characters. CMAA2 keeps edges and text sharpest." },
            { key = "msaa", cvar = "MSAAQuality", where = "Options > Graphics",
              label = "Multisample anti-aliasing", kind = "choice", values = { 0, 1, 2, 3 },
              labels = { [0] = "None", "2x", "4x", "8x" },
              best = 0, levels = { [1] = 2 }, looks = 1, cost = 0, gpu = 3, ownUntilPreset = true,
              tip = "Blizzard's multisample anti-aliasing: cleaner edges on leaves, fences and grass. Heavy on the GPU at high resolutions." },
            { key = "liquidDetail", cvar = "graphicsLiquidDetail", where = "Options > Graphics", raid = "raidGraphicsLiquidDetail", preset = true,
              label = "Water detail", kind = "choice", values = { 0, 1, 2, 3 },
              labels = { [0] = "Low", "Fair", "Medium", "High" },
              best = 0, levels = { [1] = 3 }, looks = 2, cost = 0, gpu = 1, ownUntilPreset = true,
              tip = "Water reflections, refraction and ripples. Only water surfaces change; Low removes their glare." },
            { key = "pbrLiquidDetail", cvar = "graphicsPBRLiquidDetail", where = "Options > Graphics", raid = "raidGraphicsPBRLiquidDetail", preset = true,
              label = "PBR water detail", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Low", "High", "Ultra" },
              supported = VideoSupport("IsPBRWaterSupported"),
              best = 0, levels = { [1] = 2 }, looks = 2, cost = 0, gpu = 1, ownUntilPreset = true,
              tip = "Physically based water shading. Low gives plainer, less reflective water." },
            { key = "computeEffects", cvar = "graphicsComputeEffects", where = "Options > Graphics", raid = "raidGraphicsComputeEffects", preset = true,
              label = "Compute effects", kind = "choice", values = { 0, 1, 2, 3, 4 },
              labels = { [0] = "Disabled", "Low", "Medium", "High", "Ultra" },
              best = 3, levels = { [1] = 4 }, looks = 1, cost = 0, gpu = 2, ownUntilPreset = true,
              tip = "Blizzard's Compute Effects option: GPU lighting and effects quality, and the quality of volumetric fog when that is on. High is Blizzard's default." },
        },
    },
    {
        kind = "tier", tier = 2,
        entries = {
            { key = "groundClutter", cvar = "graphicsGroundClutter", where = "Options > Graphics", raid = "raidGraphicsGroundClutter", preset = true,
              label = "Ground clutter", kind = "range", min = 0, max = 9, step = 1, best = 0, format = LEVEL_LABEL,
              levels = { [2] = 4, [4] = 9 }, looks = 3, cost = 1, gpu = 1,
              tip = "Blizzard's Ground Clutter slider (1-10): grass and small plants. Near you they look lush; at range they can cover herbs and small characters' feet." },
            { key = "groundEffectDensity", cvar = "groundEffectDensity", where = false, raid = "RAIDgroundEffectDensity",
              label = "Grass density", kind = "range", min = 16, max = 256, step = 8, best = 16,
              levels = { [2] = 64, [4] = 256 }, looks = 3, cost = 1, gpu = 1,
              tip = "Number of grass and clutter plants. 16 is the lowest density; dense grass hides more at range." },
            { key = "groundEffectDist", cvar = "groundEffectDist", where = false, raid = "RAIDgroundEffectDist",
              label = "Grass distance", kind = "range", min = 40, max = 500, step = 10, best = 40,
              levels = { [2] = 70, [4] = 300 }, looks = 2, cost = 1, gpu = 1,
              tip = "How far away grass is drawn, in yards. 40 is the lowest this client allows." },
            { key = "ssao", cvar = "graphicsSSAO", where = "Options > Graphics", raid = "raidGraphicsSSAO", preset = true,
              label = "Ambient occlusion", kind = "choice", values = { 0, 1, 2, 3, 4 },
              labels = { [0] = "Disabled", "Low", "Medium", "High", "Ultra" }, best = 0,
              levels = { [2] = 3 }, looks = 2, cost = 1, gpu = 2,
              tip = "Soft shading in corners, under objects and where characters meet the ground. It darkens corners and crevices a little." },
            { key = "weatherDensity", cvar = "weatherDensity", where = false, raid = "RAIDweatherDensity",
              label = "Weather", kind = "choice", values = { 0, 1, 2, 3 },
              labels = { [0] = "Off", "Low", "Medium", "High" }, best = 0,
              levels = { [2] = 1, [4] = 3 }, looks = 2, cost = 1, gpu = 1,
              tip = "Rain, snow and sandstorm particles. Low keeps storms thin; High storms block the view at range." },
            { key = "ffxGlow", cvar = "ffxGlow", where = false,
              label = "Full-screen glow", kind = "bool", best = false, labels = ON_OFF,
              levels = { [2] = true }, looks = 1, cost = 1, gpu = 0,
              tip = "The soft glow around skies and bright surfaces. It washes out bright scenes slightly." },
            -- 0.16.2: client 1.60.1.70425 dropped Blizzard's Low/High Bloom
            -- (graphicsBloomUserMult, in the graphics quality block) for a
            -- 0 to 1 slider in 0.2 steps on bloomUserMult, the multiplier the
            -- old choice set (Blizzard_SettingsDefinitions_Shared/Graphics.lua,
            -- "Bloom", shown only with linear lighting). Saved 0 and 1 (Low and
            -- High) are the slider's ends, so they carry over unchanged. It
            -- has no raid copy: the client has no RAIDbloomUserMult on
            -- 1.60.1.70425 (laptop, 16 October 2026, Forever Diagnostics'
            -- fix test), where an addon's write of bloomUserMult took (0.16.3).
            -- 0.16.4: Balanced takes a softer 0.6 (the slider's middle steps
            -- are new), Scenic and Max graphics full Bloom.
            { key = "bloom", cvar = "bloomUserMult", where = "Options > Graphics",
              label = "Bloom", kind = "range", min = 0, max = 1, step = 0.2, best = 0,
              supported = VideoSupport("IsLinearEnabledOnStart"),
              levels = { [2] = 0.6, [3] = 1 }, looks = 1, cost = 1, gpu = 0,
              tip = "Blizzard's Bloom slider (0 to 1): how strongly lights and bright spells glow. Only available when the client started with linear lighting." },
        },
    },
    {
        kind = "tier", tier = 3,
        entries = {
            { key = "sunShafts", cvar = "sunShafts", where = false, raid = "RAIDsunShafts",
              label = "Sun shafts", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Off", "Low", "High" }, best = 0,
              levels = { [3] = 2 }, looks = 2, cost = 2, gpu = 1,
              tip = "Beams of light through trees and around the sun, with glare when you face it." },
            { key = "depthEffects", cvar = "graphicsDepthEffects", where = "Options > Graphics", raid = "raidGraphicsDepthEffects", preset = true,
              label = "Depth effects", kind = "choice", values = { 0, 1, 2, 3 },
              labels = { [0] = "Disabled", "Low", "Medium", "High" }, best = 0,
              levels = { [3] = 3 }, looks = 2, cost = 2, gpu = 1,
              tip = "Blizzard's Depth Effects option: heat haze and distortion over fire, lava and some spells." },
        },
    },
    {
        kind = "tier", tier = 4,
        entries = {
            { key = "volumeFog", cvar = "volumeFog", where = false, raid = "RAIDvolumeFog",
              label = "Volumetric fog", kind = "bool", best = false, labels = ON_OFF,
              levels = { [4] = true }, looks = 3, cost = 3, gpu = 2,
              tip = "Layered fog and light in the air: each zone's intended mood. The haze lowers contrast on distant players and terrain." },
            { key = "shadows", cvar = "graphicsShadowQuality", where = "Options > Graphics", raid = "raidGraphicsShadowQuality", preset = true,
              label = "Shadow quality", kind = "choice", values = { 0, 1, 2, 3, 4, 5 },
              labels = { [0] = "Low", "Fair", "Medium", "High", "Ultra", "Ultra High" }, best = 0,
              levels = { [4] = 5 }, looks = 2, cost = 3, gpu = 3,
              -- 0.16.4: Low again. 0.3.1 to 0.16.3 used Medium because Low flooded
              -- the sky with glare on 1.60.1.70205; Blizzard's notes for
              -- 1.60.1.70425 fix "extra bright fog at lower shadow settings", and
              -- the user chose to take that as fixed (16 October 2026).
              tip = "Higher levels shade more of the distant scene, so players in shade at range are harder to spot. Low shades the least." },
        },
    },
    {
        kind = "immersion", title = "Immersion",
        note = "Camera and screen effects that add atmosphere. The dot shows the first preset that turns each on.",
        entries = {
            { key = "deathEffect", cvar = "ffxDeath", where = false,
              label = "Death screen effect", kind = "bool", best = false, labels = ON_OFF,
              levels = { [2] = true }, looks = 1, cost = 1, gpu = 0,
              tip = "Grey full-screen filter while you are dead." },
            { key = "terrainTilt", cvar = "cameraTerrainTilt", where = "Options > Controls",
              label = "Tilt with terrain", kind = "bool", best = false, labels = ON_OFF,
              levels = { [2] = true }, looks = 1, cost = 1, gpu = 0,
              tip = "Blizzard's Follow Terrain option: the camera tilts with slopes. Off keeps the horizon level." },
            { key = "bobbing", cvar = "cameraBobbing", where = "Options > Controls",
              label = "Head bob", kind = "bool", best = false, labels = ON_OFF,
              levels = { [3] = true }, looks = 1, cost = 2, gpu = 0,
              tip = "Blizzard's Head Bob option: the camera moves with your steps." },
            { key = "shakeCamera", howNote = "Blizzard's menu sets it and Interface shake together with one choice.", cvar = "ShakeStrengthCamera", where = "Options > Accessibility",
              label = "Camera shake", kind = "range", min = 0, max = 1, step = 0.05, best = 0, format = PERCENT,
              levels = { [4] = 1 }, looks = 1, cost = 3, gpu = 0,
              tip = "Screen shake from spells and explosions. 0% keeps the view steady." },
            { key = "shakeUI", howNote = "Blizzard's menu sets it and Camera shake together with one choice.", cvar = "ShakeStrengthUI", where = "Options > Accessibility",
              label = "Interface shake", kind = "range", min = 0, max = 1, step = 0.05, best = 0, format = PERCENT,
              levels = { [4] = 1 }, looks = 1, cost = 3, gpu = 0,
              tip = "Shaking of interface elements from spells and explosions." },
        },
    },
    {
        kind = "always", title = "Distance and detail",
        note = "Higher distance settings cost GPU time in busy areas.",
        entries = {
            { key = "viewDistance", cvar = "graphicsViewDistance", where = "Options > Graphics", raid = "raidGraphicsViewDistance", preset = true,
              label = "View distance preset", kind = "range", min = 0, max = 9, step = 1, best = 9, format = LEVEL_LABEL,
              tip = "Blizzard's View Distance slider (1-10). Sets the far clip and terrain distances below." },
            { key = "environmentDetail", cvar = "graphicsEnvironmentDetail", where = "Options > Graphics", raid = "raidGraphicsEnvironmentDetail", preset = true,
              label = "Environment detail preset", kind = "range", min = 0, max = 9, step = 1, best = 9, format = LEVEL_LABEL,
              tip = "Blizzard's Environment Detail slider (1-10): how far world objects are drawn before they pop in." },
            { key = "farclip", cvar = "farclip", where = false, raid = "RAIDfarclip",
              label = "Far clip distance", kind = "range", min = 200, max = 10000, step = 100, best = 10000,
              tip = "Maximum rendered distance, in yards. The client clamps values above its limit." },
            { key = "horizonStart", cvar = "horizonStart", where = false, raid = "RAIDhorizonStart",
              label = "Horizon detail start", kind = "range", min = 200, max = 10000, step = 100, best = 10000,
              tip = "Distance at which full-detail terrain changes to low-detail horizon terrain." },
            { key = "horizonClip", cvar = "horizonClip", where = false, raid = "RAIDhorizonClip",
              label = "Horizon clip distance", kind = "range", min = 200, max = 10000, step = 100, best = 10000,
              tip = "Farthest distance at which horizon terrain is drawn." },
            { key = "terrainLodDist", cvar = "terrainLodDist", where = false, raid = "RAIDterrainLodDist",
              label = "Terrain detail distance", kind = "range", min = 100, max = 650, step = 10, best = 650,
              tip = "Distance before terrain switches to lower detail. Keeps distant hills and slopes accurate." },
            -- From here down, the maximums are past what Blizzard's top
            -- presets set (wmoLodDist 800, lodObjectFadeScale and
            -- doodadLodScale 150, lodObjectCullSize 14 at Environment detail
            -- 10 in this installation's Config.wtf). The client's own limits
            -- are unknown; it reports a clamp as Client limit.
            { key = "wmoLodDist", cvar = "wmoLodDist", where = false, raid = "RAIDwmoLodDist",
              label = "Building detail distance", kind = "range", min = 100, max = 2000, step = 10, best = 2000,
              tip = "Distance before buildings and large structures switch to lower detail. Blizzard's top setting is 800; higher values are tried, and the status shows if the client limits them." },
            { key = "wmoLodScale", cvar = "wmoLodDistScale", where = false,
              label = "Building detail scale", kind = "range", min = 0.5, max = 2, step = 0.1, best = 2,
              format = function(value) return string.format("%.1fx", value) end,
              tip = "Multiplies the distance at which buildings switch to lower detail. 1.0x is Blizzard's value." },
            { key = "objectFade", cvar = "lodObjectFadeScale", where = false, raid = "RAIDlodObjectFadeScale",
              label = "Object fade distance", kind = "range", min = 50, max = 300, step = 10, best = 300,
              tip = "How far away trees, rocks and other objects are still drawn before they fade out. Blizzard's top setting is 150." },
            { key = "doodadDetail", cvar = "doodadLodScale", where = false, raid = "RAIDdoodadLodScale",
              label = "Scenery detail distance", kind = "range", min = 50, max = 300, step = 10, best = 300,
              tip = "How far away scenery objects keep their full detail. Blizzard's top setting is 150." },
            { key = "objectCull", cvar = "lodObjectCullSize", where = false, raid = "RAIDlodObjectCullSize",
              label = "Small object culling", kind = "range", min = 0, max = 30, step = 1, best = 0,
              tip = "Objects smaller than this are left out at a distance; lower draws more of them. Blizzard's top setting is 14. 0 leaves out the fewest." },
            { key = "textureResolution", cvar = "graphicsTextureResolution", where = "Options > Graphics", raid = "raidGraphicsTextureResolution", preset = true,
              label = "Texture resolution", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Low", "Fair", "High" }, best = 2,
              tip = "High keeps textures sharp; low-resolution textures blur distant players into the scenery." },
            { key = "textureFiltering", cvar = "textureFilteringMode", where = "Options > Graphics",
              label = "Texture filtering", kind = "choice", values = { 0, 1, 2, 3, 4, 5 },
              labels = { [0] = "Bilinear", "Trilinear", "2x Aniso", "4x Aniso", "8x Aniso", "16x Aniso" }, best = 5,
              tip = "Anisotropic filtering keeps ground and walls sharp at shallow angles and long distances." },
            -- 0.16.0: Blizzard's Render Scale (Graphics.lua, Resolution). Its
            -- slider runs between GetMinRenderScale and GetMaxRenderScale,
            -- which are in no generated doc, so this row keeps a fixed range
            -- and the status shows any Client limit. At 50% Mana Shield's
            -- outline did not show; at 100% it did (laptop, 1.60.1.70374,
            -- 15 October 2026).
            { key = "renderScale", cvar = "RenderScale", where = "Options > Graphics",
              label = "Render scale", kind = "range", min = 0.25, max = 2, step = 0.05, best = 1, format = PERCENT,
              ownUntilPreset = true,
              tip = "Blizzard's Render Scale: the resolution the world is drawn at, as a share of your screen's. Below 100% thin, faint effects such as shield outlines blur away and distant players soften; above 100% is sharper still at a large GPU cost. 100% is Blizzard's default." },
        },
    },
    {
        kind = "always", title = "Spell effects",
        entries = {
            { key = "particleDensity", cvar = "graphicsParticleDensity", where = "Options > Graphics", raid = "raidGraphicsParticleDensity", preset = true,
              label = "Particle density", kind = "choice", values = { 1, 2, 3, 4, 5 },
              labels = { "Low", "Fair", "Medium", "High", "Ultra" },
              best = 5, ownUntilPreset = true,
              tip = "Particles per effect. Ultra draws every particle of every spell effect, so no combat cue is thinned out. Disabled is not offered: Blizzard warns it removes combat cues." },
            { key = "spellDensity", cvar = "graphicsSpellDensity", where = "Options > Graphics", raid = "raidGraphicsSpellDensity", preset = true,
              label = "Spell density", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Essential", "Reduced", "Full" }, best = 2,
              supported = VideoSupport("IsSpellVisualDensitySystemSupported"),
              tip = "Which spell visuals are drawn in crowded fights. Full shows every spell effect. Reduced and Essential hide some visuals, including other players' spells." },
            { key = "projectedTextures", cvar = "graphicsProjectedTextures", where = "Options > Graphics", raid = "raidGraphicsProjectedTextures", preset = true,
              label = "Ground spell markers", kind = "choice", values = { 0, 1 },
              labels = { [0] = "Disabled", "Enabled" }, best = 1,
              tip = "Projected textures: area-effect circles on the ground. Keep enabled so ground effects stay visible." },
            -- 0.15.0: Blizzard's Lighting Mode (GraphicsOverrides.lua, shown
            -- only where C_VideoOptions.IsSecondaryLightingSupported). Added
            -- for a faint Mana Shield, but on 1.60.1.70374 (laptop, 15
            -- October 2026) the shield looked the same at Fair, Medium and
            -- High, so the tip promises nothing about spell glows (0.15.1).
            { key = "lightMode", cvar = "graphicsLightMode", where = "Options > Graphics", raid = "raidGraphicsLightMode", preset = true,
              label = "Lighting mode", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Fair", "Medium", "High" }, best = 2, ownUntilPreset = true,
              supported = VideoSupport("IsSecondaryLightingSupported"),
              tip = "Blizzard's Lighting Mode: how fully the game draws its lights. High is Blizzard's default. Higher costs some GPU." },
        },
    },
    {
        kind = "always", title = "You",
        entries = {
            { key = "outlineMode", cvar = "graphicsOutlineMode", where = "Options > Graphics", raid = "raidGraphicsOutlineMode", preset = true,
              label = "Unit outlines", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Disabled", "Medium", "High" }, best = 2,
              supported = VideoSupport("IsOutlineModeSupported"),
              tip = "Outlines on your target and mouseover. High makes them clearest. Quest item sparkles show only while this is Disabled." },
            { key = "silhouette", cvar = "occludedSilhouettePlayer", where = "Options > Combat",
              label = "Your silhouette behind objects", kind = "bool", best = true, labels = ON_OFF,
              tip = "Draws your character's silhouette when walls or trees block the camera's view of you." },
            { key = "findAnywhere", howNote = "Blizzard's menu sets the four self highlight rows together with one choice.", cvar = "findYourselfAnywhere", where = "Options > Combat",
              label = "Self highlight everywhere", kind = "bool", best = true, labels = ON_OFF,
              tip = "Show the self highlight outside raids and battlegrounds too." },
            { key = "findCircle", howNote = "Blizzard's menu sets the four self highlight rows together with one choice.", cvar = "findYourselfModeCircle", where = "Options > Combat",
              label = "Self highlight circle", kind = "bool", best = true, labels = ON_OFF,
              tip = "A circle under your character." },
            { key = "findOutline", howNote = "Blizzard's menu sets the four self highlight rows together with one choice.", cvar = "findYourselfModeOutline", where = "Options > Combat",
              label = "Self highlight outline", kind = "bool", labels = ON_OFF,
              best = true, ownUntilPreset = true,
              tip = "An outline around your character, so you stand out in crowds and spell effects." },
            { key = "findIcon", howNote = "Blizzard's menu sets the four self highlight rows together with one choice.", cvar = "findYourselfModeIcon", where = "Options > Combat",
              label = "Self highlight icon", kind = "bool", labels = ON_OFF,
              best = false, ownUntilPreset = true,
              tip = "An icon above your character. Off: the circle and outline already mark you without covering what is above you." },
        },
    },
    {
        kind = "always", title = "Distant players", personal = true,
        note = "Names drawn over characters. Presets never change these.",
        entries = {
            { key = "nameMinSize", cvar = "WorldTextMinSize", where = "Options > Accessibility", personal = true, blizzard = 0,
              label = "Minimum name size", kind = "range", min = 0, max = 20, step = 2,
              format = function(value) return value == 0 and "Off" or tostring(value) end,
              tip = "Names shrink with distance; this keeps them from getting smaller than the size you pick, so far-away names stay readable while close ones stay as they are. Blizzard's Minimum Character Name Size slider. Off is Blizzard's default." },
            { key = "friendlyNames", cvar = "UnitNameFriendlyPlayerName", where = "Options > Nameplates", personal = true,
              label = "Friendly player names", kind = "bool", labels = ON_OFF,
              tip = "Names over players on your side. Blizzard's Friendly Players option." },
            { key = "enemyNames", cvar = "UnitNameEnemyPlayerName", where = "Options > Nameplates", personal = true,
              label = "Enemy player names", kind = "bool", labels = ON_OFF,
              tip = "Names over enemy players. Blizzard's Enemy Players option." },
            { key = "friendlyMinionNames", cvar = "UnitNameFriendlyMinionName", where = "Options > Nameplates", personal = true,
              label = "Friendly pet names", kind = "bool", labels = ON_OFF,
              tip = "Names over friendly players' pets, guardians and totems. Blizzard's Minions option under Friendly Players." },
            { key = "enemyMinionNames", cvar = "UnitNameEnemyMinionName", where = "Options > Nameplates", personal = true,
              label = "Enemy pet names", kind = "bool", labels = ON_OFF,
              tip = "Names over enemy players' pets, guardians and totems. Blizzard's Minions option under Enemy Players." },
            { key = "guildNames", cvar = "UnitNamePlayerGuild", where = false, personal = true,
              label = "Guild names", kind = "bool", labels = ON_OFF,
              tip = "The <Guild> line under player names." },
            { key = "guildRanks", cvar = "UnitNameGuildTitle", where = false, personal = true,
              label = "Guild ranks", kind = "bool", labels = ON_OFF,
              tip = "The guild rank with the guild name, where the game shows one." },
            { key = "playerTitles", cvar = "UnitNamePlayerPVPTitle", where = false, personal = true,
              label = "Player titles", kind = "bool", labels = ON_OFF,
              tip = "Titles shown with player names, such as PvP rank titles." },
        },
    },
    {
        kind = "always", title = "Loot and interaction",
        entries = {
            -- Not in the source mirror: an engine CVar, set by name and
            -- probed like every row. `outlinesOff` names the row whose CVars
            -- must read 0 for the sparkle to show (Core.ApplyEntry).
            { key = "lootSparkle", cvar = "outlineModeShowLootEffectWhenDisabled", where = false, outlinesOff = "outlineMode",
              label = "Quest item sparkles", kind = "bool", best = true, labels = ON_OFF,
              tip = "Glitter on quest items you can loot, such as quest crates and plants. The game draws it only while outlines are off: where this client cannot draw outlines, On turns them off for you; where it can, set Unit outlines to Disabled." },
            { key = "interactIconObjects", howNote = "Blizzard's menu sets both interact icon rows together with one choice.", cvar = "SoftTargetIconGameObject", where = "Options > Accessibility",
              label = "Interact icon on objects", kind = "bool", best = true, labels = ON_OFF,
              tip = "An icon over the chest, herb, ore or other object the interact key would use. Shows only with Interact key targeting on." },
            { key = "interactIconCharacters", howNote = "Blizzard's menu sets both interact icon rows together with one choice.", cvar = "SoftTargetIconInteract", where = "Options > Accessibility",
              label = "Interact icon on characters", kind = "bool", best = true, labels = ON_OFF,
              tip = "An icon over the character the interact key would talk to. Shows only with Interact key targeting on." },
        },
    },
    {
        kind = "always", title = "Interact targeting", personal = true,
        note = "How far / which way the game picks the interact-key target (herb, ore, NPC). Presets never change these.",
        entries = {
            { key = "nodeReach", cvar = "SoftTargetInteractRange", where = false, personal = true, blizzard = 10, trySecure = true,
              label = "Interact reach", kind = "range", min = 10, max = 40, step = 1,
              format = function(value) return string.format("%d yd", value) end,
              tip = "How far away the game picks what your interact key would use. Blizzard's default is 10 yards." },
            { key = "nodeArc", cvar = "SoftTargetInteractArc", where = false, personal = true, blizzard = 0,
              label = "Interact direction", kind = "choice", values = { 0, 1, 2 },
              labels = { [0] = "Straight ahead", "In front", "All around" },
              tip = "Where the game looks: straight ahead (default), a cone in front, or all around." },
        },
    },
    {
        kind = "always", title = "Camera",
        entries = {
            { key = "maxZoom", cvar = "cameraDistanceMaxZoomFactor", where = "Options > Controls",
              label = "Max camera distance", kind = "range", min = 1, max = 2.6, step = 0.1, best = 2.6,
              format = function(value) return string.format("%.1f", value) end,
              tip = "How far you can zoom the camera out. 2.6 is the client maximum." },
            { key = "fov", cvar = "cameraFov", where = "Options > Graphics",
              label = "Field of view", kind = "range", min = 50, max = 90, step = 5, best = "max", limits = "fov",
              tip = "Blizzard's Field of View slider. Wider shows more around you. Range comes from the client." },
            { key = "indirectVisibility", cvar = "cameraIndirectVisibility", where = false,
              label = "Camera sees past obstacles", kind = "bool", best = true, labels = ON_OFF,
              tip = "Lets the camera stay out behind small obstacles instead of zooming in on you." },
            { key = "indirectOffset", cvar = "cameraIndirectOffset", where = false,
              label = "Obstacle tolerance", kind = "range", min = 1, max = 10, step = 1, best = 10,
              tip = "How much an obstacle may block the camera before it zooms in. Needs the option above." },
        },
    },
    {
        kind = "always", title = "Screen warnings",
        entries = {
            { key = "altScreenEffects", cvar = "overrideScreenFlash", where = "Options > Accessibility",
              label = "Alternate screen effects", kind = "bool", labels = ON_OFF,
              best = false, ownUntilPreset = true,
              tip = "Replaces full-screen flashes with alternatives. Off keeps Blizzard's own screen cues." },
            { key = "lowHealthFlash", howNote = "Blizzard's tick box for it works the other way round: ticked, the screen does not flash.", cvar = "doNotFlashLowHealthWarning", where = "Options > Combat", invert = true,
              label = "Low-health screen flash", kind = "bool", labels = ON_OFF,
              best = false, ownUntilPreset = true,
              tip = "The red flashing screen edge at low health. Every preset turns it off; set it On here to keep it." },
            { key = "netherEffect", cvar = "ffxNether", where = false,
              label = "Nether screen effect", kind = "bool", labels = ON_OFF,
              best = false, ownUntilPreset = true,
              tip = "Full-screen distortion used by some phasing and invisibility effects. Every preset turns it off; set it On here to keep it." },
        },
    },
}

-- Quick choices for the brightness, contrast and gamma rows, shown as tick
-- boxes beside their warning. Suggested is what the player settled on in
-- client on 5 October 2026 (1.60.1.70205); Blizzard default is each slider's
-- default in this client's CVar scan.
ns.PICTURE_CHOICES = {
    { key = "suggested", label = "Suggested", values = { brightness = 50, contrast = 85, gamma = 1.5 },
      tip = "Brightness 50, contrast 85, gamma 1.5: gamma lifts dark and middle tones, and the higher contrast keeps blacks deep and colours vivid." },
    { key = "blizzard", label = "Blizzard default", values = { brightness = 50, contrast = 50, gamma = 1 },
      tip = "Brightness 50, contrast 50, gamma 1.0: the game as Blizzard ships it." },
}

-- Blizzard's Enable Interact Key checkbox (Controls.lua:72-86) sets
-- softTargetInteract to Any when ticked and Gamepad when not.
local FLAGS = Enum and Enum.SoftTargetEnableFlags
if FLAGS and FLAGS.Gamepad and FLAGS.Any then
    for _, section in ipairs(ns.SECTIONS) do
        if section.title == "Loot and interaction" then
            table.insert(section.entries, 2, { key = "interactKey", cvar = "softTargetInteract", where = "Options > Controls",
                label = "Interact key targeting", kind = "choice", values = { FLAGS.Gamepad, FLAGS.Any },
                labels = { [FLAGS.Gamepad] = "Gamepad only", [FLAGS.Any] = "Always" }, best = FLAGS.Any,
                tip = "Blizzard's Enable Interact Key option. Always picks the nearest thing you can interact with, with mouse and keyboard too, so the interact icons below can mark it and the Interact key binding can use it. Gamepad only is Blizzard's default." })
        end
    end
end

-- `firstLevel`: the first preset that raises a row, for its tier dot.
ns.ENTRIES, ns.BY_KEY = {}, {}
for _, section in ipairs(ns.SECTIONS) do
    if section.kind == "tier" then section.title = ns.TIERS[section.tier] end
    for _, entry in ipairs(section.entries) do
        if entry.kind == "choice" then
            entry.min, entry.max = entry.values[1], entry.values[#entry.values]
        end
        for index = 1, #ns.PRESETS do
            if entry.levels and entry.levels[index] ~= nil and not entry.firstLevel then entry.firstLevel = index end
        end
        entry.section = section
        ns.ENTRIES[#ns.ENTRIES + 1] = entry
        ns.BY_KEY[entry.key] = entry
    end
end
