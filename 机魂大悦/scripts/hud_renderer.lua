-- ============================================================================
-- hud_renderer.lua — 锁定系统 + NanoVG HUD 渲染
-- 从 main.lua L3556-4657 提取
-- ============================================================================

local CONFIG = require "config"
local GS = require "game_state"
local ShieldSystem = require "shield_system"

local HUD = {}

-- ============================================================================
-- 锁定系统
-- ============================================================================

--- 更新所有敌人的锁定状态
---@param dt number
function HUD.UpdateLockOn(dt)
    local camera = GS.tpCamera:GetCamera()
    local camNode = GS.tpCamera:GetNode()
    local camPos = camNode.worldPosition
    local camFwd = camNode.worldRotation * Vector3.FORWARD
    local pw = GS.scene:GetComponent("PhysicsWorld")
    local dpr = graphics:GetDPR()
    local screenH = graphics:GetHeight() / dpr

    for _, enemy in ipairs(GS.enemies) do
        local vh = enemy.visualHeight or 3.5
        local targetPos = enemy.node.worldPosition + Vector3(0, vh * 0.5, 0)
        local toTarget = targetPos - camPos
        local dist = toTarget:Length()

        local inFront = toTarget:DotProduct(camFwd) > 0

        local onScreen = false
        local sx, sy = 0.5, 0.5
        if inFront then
            local sp = camera:WorldToScreenPoint(targetPos)
            sx, sy = sp.x, sp.y
            onScreen = sx >= 0.02 and sx <= 0.98 and sy >= 0.02 and sy <= 0.98
        end

        local visible = onScreen
        if visible and pw then
            local ray = Ray(camPos, toTarget:Normalized())
            local result = pw:RaycastSingle(ray, dist - 0.5, CollisionLayerStatic)
            if result and result.body then
                -- 检查命中的是不是敌人自身节点（避免 BOSS 等有碰撞体的敌人被自身遮挡）
                local hitNode = result.body:GetNode()
                local isOwn = false
                if enemy.node then
                    local check = hitNode
                    while check do
                        if check == enemy.node then isOwn = true; break end
                        check = check.parent
                    end
                end
                -- BOSS 调试：记录射线命中信息
                if enemy.isBoss then
                    HUD._bossRayHitName = hitNode.name or "unnamed"
                    HUD._bossRayIsOwn = isOwn
                end
                if not isOwn then
                    visible = false
                end
            else
                if enemy.isBoss then
                    HUD._bossRayHitName = "none"
                    HUD._bossRayIsOwn = nil
                end
            end
        end

        -- 收集 BOSS 瞄准调试信息（调试模式下屏幕显示）
        if enemy.isBoss then
            HUD._bossLockDebug = {
                inFront = inFront,
                onScreen = onScreen,
                visible = visible,
                sx = sx,
                sy = sy,
                dist = dist,
                lockValue = enemy.lockValue,
                locked = enemy.locked,
                bossPos = enemy.node.worldPosition,
                targetPos = targetPos,
                rayHitNode = HUD._bossRayHitName or "none",
                rayIsOwn = HUD._bossRayIsOwn,
            }
        end

        if visible then
            enemy.lockValue = math.min(GS.LOCK_MAX, enemy.lockValue + GS.LOCK_GAIN_RATE * dt)
        else
            enemy.lockValue = math.max(0, enemy.lockValue - GS.LOCK_DECAY_RATE * dt)
        end

        if enemy.lockValue >= GS.LOCK_MAX then
            enemy.locked = true
        elseif enemy.lockValue <= 0 then
            enemy.locked = false
        end

        local screenSize = 64
        if inFront then
            local bottomPos = enemy.node.worldPosition
            local topPos = bottomPos + Vector3(0, vh, 0)
            local spBottom = camera:WorldToScreenPoint(bottomPos)
            local spTop = camera:WorldToScreenPoint(topPos)
            local pixelH = math.abs(spBottom.y - spTop.y)
            screenSize = pixelH * screenH * 0.5
        end

        enemy.screenX = sx
        enemy.screenY = sy
        enemy.dist = dist
        enemy.onScreen = onScreen
        enemy.inFront = inFront
        enemy.screenSize = math.max(32, screenSize)
        enemy.isPrimary = false
    end

    -- 主要目标
    local bestEnemy = nil
    local bestScreenDist = math.huge
    for _, enemy in ipairs(GS.enemies) do
        if enemy.lockValue > 0 then
            local dx = enemy.screenX - 0.5
            local dy = enemy.screenY - 0.5
            local sd = dx * dx + dy * dy
            if sd < bestScreenDist then
                bestScreenDist = sd
                bestEnemy = enemy
            end
        end
    end
    if bestEnemy then
        bestEnemy.isPrimary = true
    end
end

-- ============================================================================
-- 屏幕边缘方向指示
-- ============================================================================

--- 绘制屏幕边缘敌人方向指示箭头
---@param w number
---@param h number
function HUD.DrawOffScreenIndicators(w, h)
    local vg = GS.vg
    local margin = 40
    local arrowSize = 10
    local cx, cy = w / 2, h / 2

    local camNode = GS.tpCamera and GS.tpCamera:GetNode()
    if not camNode then return end
    local camInvRot = camNode.worldRotation:Inverse()

    local camFwd = camNode.worldRotation * Vector3.FORWARD
    local camFwdFlat = Vector3(camFwd.x, 0, camFwd.z)
    local camFwdFlatLen = camFwdFlat:Length()
    if camFwdFlatLen > 0.001 then camFwdFlat = camFwdFlat / camFwdFlatLen end

    local angle120 = math.rad(120)
    local angleRange = math.rad(60)

    for _, enemy in ipairs(GS.enemies) do
        if enemy.dead or enemy.onScreen then goto continue end

        local enemyPos = enemy.node.worldPosition
        local camPos = camNode.worldPosition
        local toEnemyFlat = Vector3(enemyPos.x - camPos.x, 0, enemyPos.z - camPos.z)
        local flatLen = toEnemyFlat:Length()
        if flatLen < 0.1 then goto continue end

        local toEnemyFlatNorm = toEnemyFlat / flatLen
        local dotH = camFwdFlat:DotProduct(toEnemyFlatNorm)
        local angleFromFwd = math.acos(math.max(-1, math.min(1, dotH)))

        local yWeight = 1.0
        if angleFromFwd > angle120 then
            yWeight = math.max(0, 1.0 - (angleFromFwd - angle120) / angleRange)
        end

        local viewDirFlat = camInvRot * toEnemyFlat
        local dx_h = viewDirFlat.x
        local dy_h = -viewDirFlat.z
        local lenH = math.sqrt(dx_h * dx_h + dy_h * dy_h)
        if lenH > 0.001 then dx_h, dy_h = dx_h / lenH, dy_h / lenH end

        local vh = enemy.visualHeight or 3.5
        local toEnemy3D = Vector3(toEnemyFlat.x, (enemyPos.y + vh * 0.5) - camPos.y, toEnemyFlat.z)
        local viewDir3D = camInvRot * toEnemy3D
        local dx_3d = viewDir3D.x
        local dy_3d = -viewDir3D.y
        local len3D = math.sqrt(dx_3d * dx_3d + dy_3d * dy_3d)
        if len3D > 0.001 then dx_3d, dy_3d = dx_3d / len3D, dy_3d / len3D end

        local dx = dx_h * (1 - yWeight) + dx_3d * yWeight
        local dy = dy_h * (1 - yWeight) + dy_3d * yWeight

        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.001 then goto continue end
        local ndx, ndy = dx / len, dy / len

        local ax, ay = cx, cy
        local edgeL, edgeR = margin, w - margin
        local edgeT, edgeB = margin, h - margin
        local tMin = math.huge
        if ndx > 0.001 then
            tMin = math.min(tMin, (edgeR - cx) / ndx)
        elseif ndx < -0.001 then
            tMin = math.min(tMin, (edgeL - cx) / ndx)
        end
        if ndy > 0.001 then
            tMin = math.min(tMin, (edgeB - cy) / ndy)
        elseif ndy < -0.001 then
            tMin = math.min(tMin, (edgeT - cy) / ndy)
        end
        ax = cx + ndx * tMin
        ay = cy + ndy * tMin

        local distFade = math.max(0.4, 1.0 - enemy.dist / 300)
        local alpha = math.floor(200 * distFade)

        local angle = math.atan(ndy, ndx)
        local tipX = ax + math.cos(angle) * arrowSize
        local tipY = ay + math.sin(angle) * arrowSize
        local baseX1 = ax + math.cos(angle + 2.5) * arrowSize
        local baseY1 = ay + math.sin(angle + 2.5) * arrowSize
        local baseX2 = ax + math.cos(angle - 2.5) * arrowSize
        local baseY2 = ay + math.sin(angle - 2.5) * arrowSize

        nvgBeginPath(vg)
        nvgMoveTo(vg, tipX, tipY)
        nvgLineTo(vg, baseX1, baseY1)
        nvgLineTo(vg, baseX2, baseY2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 80, 60, alpha))
        nvgFill(vg)

        ::continue::
    end
end

-- ============================================================================
-- 锁定 UI
-- ============================================================================

--- 绘制锁定 UI
---@param w number
---@param h number
function HUD.DrawLockOnUI(w, h)
    local vg = GS.vg

    for _, enemy in ipairs(GS.enemies) do
        if enemy.lockValue <= 0 then goto continue end

        local sx = enemy.screenX * w
        local sy = enemy.screenY * h
        local dist = enemy.dist
        local radius = enemy.screenSize
        local progress = enemy.lockValue / GS.LOCK_MAX
        local locked = enemy.locked
        local isPrimary = enemy.isPrimary

        local cr, cg, cb
        if locked then
            cr, cg, cb = 255, 40, 40
        else
            cr, cg, cb = 40, 200, 255
        end

        local baseStroke = math.max(1, radius * 0.03)
        local arcStroke = math.max(1.2, radius * 0.04)
        local fontSize = math.max(10, radius * 0.25)

        -- 外圈底环
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, radius)
        nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, 50))
        nvgStrokeWidth(vg, baseStroke)
        nvgStroke(vg)

        -- 进度弧线
        if progress > 0.01 then
            local startAngle = -math.pi / 2
            local endAngle = startAngle + math.pi * 2 * progress
            nvgBeginPath(vg)
            nvgArc(vg, sx, sy, radius, startAngle, endAngle, NVG_CW)
            nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, 220))
            nvgStrokeWidth(vg, arcStroke)
            nvgStroke(vg)
        end

        -- 主目标装饰
        if isPrimary then
            local tickLen = radius * 0.25
            local gap = radius + baseStroke * 2
            local s45 = 0.7071
            local gd = gap * s45
            local t1x, t1y = tickLen * s45, tickLen * s45

            nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, 200))
            nvgStrokeWidth(vg, baseStroke)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + gd - t1x, sy - gd + t1y)
            nvgLineTo(vg, sx + gd + t1x, sy - gd - t1y)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx - gd - t1x, sy + gd + t1y)
            nvgLineTo(vg, sx - gd + t1x, sy + gd - t1y)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx - gd - t1x, sy - gd - t1y)
            nvgLineTo(vg, sx - gd + t1x, sy - gd + t1y)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + gd - t1x, sy + gd - t1y)
            nvgLineTo(vg, sx + gd + t1x, sy + gd + t1y)
            nvgStroke(vg)
        end

        -- 飞弹锁定标记（右肩）
        if GS.missileLockR then
            local missileCount = 0
            for _, t in ipairs(GS.missileLockTargetsR) do
                if t.enemy == enemy then missileCount = missileCount + 1 end
            end
            if missileCount > 0 then
                local mkSize = math.max(8, radius * 0.2)
                nvgBeginPath(vg)
                nvgMoveTo(vg, sx - radius - mkSize * 2, sy - mkSize)
                nvgLineTo(vg, sx - radius - mkSize, sy)
                nvgLineTo(vg, sx - radius - mkSize * 2, sy + mkSize)
                nvgLineTo(vg, sx - radius - mkSize * 3, sy)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 200, 40, 220))
                nvgFill(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(10, mkSize * 1.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 200, 40, 255))
                nvgText(vg, sx - radius - mkSize * 2, sy + mkSize * 2,
                    string.format("SR x%d", missileCount))
            end
        end
        -- 飞弹锁定标记（左肩）
        if GS.missileLockL then
            local missileCount = 0
            for _, t in ipairs(GS.missileLockTargetsL) do
                if t.enemy == enemy then missileCount = missileCount + 1 end
            end
            if missileCount > 0 then
                local mkSize = math.max(8, radius * 0.2)
                nvgBeginPath(vg)
                nvgMoveTo(vg, sx + radius + mkSize * 2, sy - mkSize)
                nvgLineTo(vg, sx + radius + mkSize * 3, sy)
                nvgLineTo(vg, sx + radius + mkSize * 2, sy + mkSize)
                nvgLineTo(vg, sx + radius + mkSize, sy)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 220))
                nvgFill(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(10, mkSize * 1.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
                nvgText(vg, sx + radius + mkSize * 2, sy + mkSize * 2,
                    string.format("SL x%d", missileCount))
            end
        end

        -- 距离文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, 180))
        nvgText(vg, sx, sy + radius + fontSize * 0.3, string.format("%dm", math.floor(dist)))

        -- 标签
        if enemy == GS.elite then
            nvgFontSize(vg, math.max(11, fontSize * 0.8))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(255, 200, 40, 220))
            nvgText(vg, sx, sy - radius - fontSize * 0.2, "ELITE")
        elseif enemy.rebelType then
            local label = enemy.rebelType == "tank" and "TANK" or "HELI"
            nvgFontSize(vg, math.max(10, fontSize * 0.7))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(255, 120, 60, 200))
            nvgText(vg, sx, sy - radius - fontSize * 0.2, label)
        elseif enemy.meleeType then
            nvgFontSize(vg, math.max(10, fontSize * 0.7))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(255, 60, 60, 220))
            nvgText(vg, sx, sy - radius - fontSize * 0.2, "MELEE")
        end

        ::continue::
    end

    -- 飞弹锁定全局提示
    if GS.missileLockR or GS.missileLockL then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local yOff = 40
        if GS.missileLockR then
            nvgFillColor(vg, nvgRGBA(255, 200, 40, 220))
            nvgText(vg, w / 2, yOff,
                string.format("SR LOCK %d/%d - Release E to fire",
                    #GS.missileLockTargetsR, GS.missileLockMaxR))
            yOff = yOff + 20
        end
        if GS.missileLockL then
            nvgFillColor(vg, nvgRGBA(100, 200, 255, 220))
            nvgText(vg, w / 2, yOff,
                string.format("SL LOCK %d/%d - Release Q to fire",
                    #GS.missileLockTargetsL, GS.missileLockMaxL))
        end
    end
end

-- ============================================================================
-- HUD 绘制函数
-- ============================================================================

--- 绘制玩家生命值条
function HUD.DrawPlayerHPBar(w, h)
    local vg = GS.vg
    local shortSide = math.min(w, h)
    local barW = shortSide * 0.3
    local barH = shortSide * 0.016
    local barX = (w - barW) / 2
    local barY = h - shortSide * 0.08
    local pct = GS.playerHp / GS.playerMaxHp

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 2, barY - 2, barW + 4, barH + 4, 5)
    nvgFillColor(vg, nvgRGBA(10, 10, 20, 170))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 1, barY - 1, barW + 2, barH + 2, 4)
    nvgStrokeColor(vg, nvgRGBA(180, 60, 60, 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if pct > 0.005 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * pct, barH, 3)
        local cr = math.floor(255 * (1.0 - pct))
        local cg = math.floor(200 * pct)
        local grad = nvgLinearGradient(vg, barX, barY, barX + barW * pct, barY,
            nvgRGBA(cr, cg + 40, 30, 230), nvgRGBA(cr + 20, cg, 20, 230))
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, shortSide * 0.013)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 220, 240, 210))
    nvgText(vg, barX + barW / 2, barY + barH / 2,
        string.format("HP  %d / %d", math.max(0, math.floor(GS.playerHp)), GS.playerMaxHp))
end

--- 绘制能量条
function HUD.DrawEnergyBar(w, h)
    local vg = GS.vg
    local shortSide = math.min(w, h)
    local barW = shortSide * 0.3
    local barH = shortSide * 0.018
    local barX = (w - barW) / 2
    local barY = h - shortSide * 0.05
    local pct = GS.energy / GS.MAX_ENERGY

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 2, barY - 2, barW + 4, barH + 4, 6)
    nvgFillColor(vg, nvgRGBA(10, 10, 20, 170))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 1, barY - 1, barW + 2, barH + 2, 5)
    nvgStrokeColor(vg, nvgRGBA(70, 110, 170, 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if pct > 0.005 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * pct, barH, 4)
        if GS.isBoosting then
            local grad = nvgLinearGradient(vg, barX, barY, barX + barW * pct, barY,
                nvgRGBA(255, 180, 40, 240), nvgRGBA(255, 90, 20, 240))
            nvgFillPaint(vg, grad)
        else
            local grad = nvgLinearGradient(vg, barX, barY, barX + barW * pct, barY,
                nvgRGBA(40, 160, 255, 230), nvgRGBA(80, 210, 255, 230))
            nvgFillPaint(vg, grad)
        end
        nvgFill(vg)
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, shortSide * 0.013)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 235, 255, 210))
    nvgText(vg, w / 2, barY + barH / 2,
        string.format("ENERGY  %d / %d", math.floor(GS.energy), GS.MAX_ENERGY))

    if GS.energy < GS.JUMP_COST then
        nvgFontSize(vg, shortSide * 0.012)
        nvgFillColor(vg, nvgRGBA(255, 80, 60, 200))
        nvgText(vg, w / 2, barY + barH + shortSide * 0.014, "ENERGY LOW")
    end
end

--- 绘制推进/冲刺状态指示
function HUD.DrawBoostIndicator(w, h)
    local vg = GS.vg
    local shortSide = math.min(w, h)
    local barY = h - shortSide * 0.08
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, shortSide * 0.016)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)

    if GS.isJetting then
        nvgFillColor(vg, nvgRGBA(60, 200, 255, 240))
        nvgText(vg, w / 2, barY - shortSide * 0.008, ">>> JET <<<")
    elseif GS.isDashing then
        nvgFillColor(vg, nvgRGBA(100, 255, 180, 230))
        nvgText(vg, w / 2, barY - shortSide * 0.008, ">>> DASH <<<")
    elseif GS.isBoosting then
        nvgFillColor(vg, nvgRGBA(255, 180, 40, 230))
        nvgText(vg, w / 2, barY - shortSide * 0.008, ">>> BOOST <<<")
    end

    -- ================================================================
    -- 技能图标按钮（Shift 冲刺 / C 喷射）
    -- ================================================================
    local btnR = shortSide * 0.028           -- 按钮半径
    local btnGap = btnR * 2.8                -- 两按钮间距
    local btnCY = barY - shortSide * 0.04    -- 按钮中心 Y
    local dashBtnCX = w / 2 - btnGap / 2     -- 冲刺按钮 X
    local jetBtnCX  = w / 2 + btnGap / 2     -- 喷射按钮 X

    -- ---- Shift 冲刺按钮 ----
    local dashCdRemain = GS.DASH_COOLDOWN - (time.elapsedTime - GS.lastDashTime)
    local dashOnCD = dashCdRemain > 0 and not GS.isDashing

    -- 背景圆
    nvgBeginPath(vg)
    nvgCircle(vg, dashBtnCX, btnCY, btnR)
    if GS.isDashing then
        nvgFillColor(vg, nvgRGBA(100, 255, 180, 80))
    else
        nvgFillColor(vg, nvgRGBA(20, 25, 35, 160))
    end
    nvgFill(vg)
    -- 边框
    nvgBeginPath(vg)
    nvgCircle(vg, dashBtnCX, btnCY, btnR)
    nvgStrokeColor(vg, nvgRGBA(100, 255, 180, dashOnCD and 60 or 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, btnR * 0.7)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 255, 180, dashOnCD and 80 or 230))
    nvgText(vg, dashBtnCX, btnCY - btnR * 0.05, "SHIFT")
    -- 冷却扇形遮罩
    if dashOnCD then
        local pct = math.max(0, math.min(1, dashCdRemain / GS.DASH_COOLDOWN))
        local startAngle = -math.pi / 2
        local endAngle = startAngle + pct * math.pi * 2
        nvgBeginPath(vg)
        nvgMoveTo(vg, dashBtnCX, btnCY)
        nvgArc(vg, dashBtnCX, btnCY, btnR, startAngle, endAngle, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)
        -- 冷却数字
        nvgFontSize(vg, btnR * 0.55)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 200))
        nvgText(vg, dashBtnCX, btnCY + btnR * 0.05, string.format("%.1f", dashCdRemain))
    end

    -- ---- C 喷射按钮 ----
    local jetOnCD = GS.jetCooldownTimer > 0 and not GS.isJetting

    -- 背景圆
    nvgBeginPath(vg)
    nvgCircle(vg, jetBtnCX, btnCY, btnR)
    if GS.isJetting then
        nvgFillColor(vg, nvgRGBA(60, 200, 255, 80))
    else
        nvgFillColor(vg, nvgRGBA(20, 25, 35, 160))
    end
    nvgFill(vg)
    -- 边框
    nvgBeginPath(vg)
    nvgCircle(vg, jetBtnCX, btnCY, btnR)
    nvgStrokeColor(vg, nvgRGBA(60, 200, 255, jetOnCD and 60 or 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 文字
    nvgFontSize(vg, btnR * 0.85)
    nvgFillColor(vg, nvgRGBA(60, 200, 255, jetOnCD and 80 or 230))
    nvgText(vg, jetBtnCX, btnCY - btnR * 0.05, "C")
    -- 冷却扇形遮罩
    if jetOnCD then
        local pct = math.max(0, math.min(1, GS.jetCooldownTimer / GS.JET_COOLDOWN))
        local startAngle = -math.pi / 2
        local endAngle = startAngle + pct * math.pi * 2
        nvgBeginPath(vg)
        nvgMoveTo(vg, jetBtnCX, btnCY)
        nvgArc(vg, jetBtnCX, btnCY, btnR, startAngle, endAngle, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)
        -- 冷却秒数
        nvgFontSize(vg, btnR * 0.55)
        nvgFillColor(vg, nvgRGBA(200, 220, 255, 200))
        nvgText(vg, jetBtnCX, btnCY + btnR * 0.05, string.format("%.0f", math.ceil(GS.jetCooldownTimer)))
    end

    -- 护盾状态
    local shieldStatus = ShieldSystem.GetStatus()
    if shieldStatus then
        local sBarW = shortSide * 0.12
        local sBarH = shortSide * 0.008
        local sX = w / 2 - sBarW / 2
        local sY = barY - shortSide * 0.085
        local sPct = 1.0 - shieldStatus.progress

        nvgBeginPath(vg)
        nvgRoundedRect(vg, sX - 1, sY - 1, sBarW + 2, sBarH + 2, 3)
        nvgFillColor(vg, nvgRGBA(10, 10, 30, 170))
        nvgFill(vg)

        if sPct > 0.01 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sX, sY, sBarW * sPct, sBarH, 2)
            nvgFillColor(vg, nvgRGBA(40, 180, 255, 220))
            nvgFill(vg)
        end

        nvgFontSize(vg, shortSide * 0.011)
        nvgFillColor(vg, nvgRGBA(80, 200, 255, 220))
        local absorbRemain = shieldStatus.maxAbsorb - shieldStatus.absorbed
        nvgText(vg, w / 2, sY - shortSide * 0.006,
            string.format("SHIELD %d HP", math.floor(absorbRemain)))
    end
end

--- 绘制弧形弹药 HUD
function HUD.DrawAmmoHUD(w, h)
    local vg = GS.vg
    local shortSide = math.min(w, h)

    -- 目标中心
    local targetCx, targetCy = w / 2, h / 2
    for _, enemy in ipairs(GS.enemies) do
        if enemy.isPrimary and enemy.lockValue > 0 then
            targetCx = enemy.screenX * w
            targetCy = enemy.screenY * h
            break
        end
    end

    -- 缓动插值
    if GS.ammoHudCx == nil then
        GS.ammoHudCx = targetCx
        GS.ammoHudCy = targetCy
    else
        local speed = 8.0
        local dt = GS.lastDt
        local t = 1.0 - math.exp(-speed * dt)
        GS.ammoHudCx = GS.ammoHudCx + (targetCx - GS.ammoHudCx) * t
        GS.ammoHudCy = GS.ammoHudCy + (targetCy - GS.ammoHudCy) * t
    end
    local cx, cy = GS.ammoHudCx, GS.ammoHudCy
    local innerRadius = h * 0.15
    local outerRadius = h * 0.19
    local strokeW = math.max(6, h * 0.008)

    local arcs = {
        { start = math.rad(135), fin = math.rad(180), weapon = GS.playerWeapons and GS.playerWeapons.handL,     radius = innerRadius, fromEnd = false },
        { start = math.rad(0),   fin = math.rad(45),  weapon = GS.playerWeapons and GS.playerWeapons.handR,     radius = innerRadius, fromEnd = true },
        { start = math.rad(135), fin = math.rad(180), weapon = GS.playerWeapons and GS.playerWeapons.shoulderL, radius = outerRadius, fromEnd = false, isLeftShoulder = true },
        { start = math.rad(0),   fin = math.rad(45),  weapon = GS.playerWeapons and GS.playerWeapons.shoulderR, radius = outerRadius, fromEnd = true },
    }

    nvgLineCap(vg, NVG_ROUND)

    -- 内圈底层圆环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, innerRadius)
    nvgStrokeColor(vg, nvgRGBA(220, 235, 255, 40))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 计算目标距离
    local targetDist = math.huge
    if GS.mechNode then
        local playerPos = GS.mechNode.worldPosition
        for _, enemy in ipairs(GS.enemies) do
            if enemy.isPrimary and enemy.lockValue > 0 and enemy.node then
                targetDist = (enemy.node.worldPosition - playerPos):Length()
                break
            end
        end
    end

    for _, arc in ipairs(arcs) do
        local weapon = arc.weapon
        if not weapon then goto continue end

        local outOfRange = false
        if weapon.def and targetDist < math.huge then
            local maxRange = weapon.def.bulletSpeed * weapon.def.bulletLife
            if targetDist > maxRange then
                outOfRange = true
            end
        end

        local span = arc.fin - arc.start
        local progress, cr, cg, cb

        local isRailgunCharging = (GS.railgunCharging and weapon == (GS.playerWeapons and GS.playerWeapons.shoulderR))
            or (GS.railgunChargingL and weapon == (GS.playerWeapons and GS.playerWeapons.shoulderL))

        if isRailgunCharging then
            if arc.isLeftShoulder then
                progress = math.min(1.0, GS.railgunChargeTimerL / GS.railgunChargeTimeL)
            else
                progress = math.min(1.0, GS.railgunChargeTimer / GS.railgunChargeTime)
            end
            cr, cg, cb = 80, 160, 255
        elseif weapon.reloading then
            progress = 1.0 - (weapon.reloadTimer / weapon.reloadTime)
            cr, cg, cb = 255, 165, 30
        else
            progress = weapon.ammo / weapon.magazineSize
            cr, cg, cb = 220, 235, 255
        end

        local alphaScale = outOfRange and 0.25 or 1.0
        local r = arc.radius

        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, r, arc.start, arc.fin, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, math.floor(20 * alphaScale)))
        nvgStrokeWidth(vg, strokeW)
        nvgStroke(vg)

        if progress > 0.01 then
            local fillStart, fillEnd
            if arc.fromEnd then
                fillStart = arc.fin - span * progress
                fillEnd = arc.fin
            else
                fillStart = arc.start
                fillEnd = arc.start + span * progress
            end

            nvgBeginPath(vg)
            nvgArc(vg, cx, cy, r, fillStart, fillEnd, NVG_CW)
            if isRailgunCharging then
                local chargeAlpha = math.floor((200 + 55 * progress) * alphaScale)
                nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, chargeAlpha))
                nvgStrokeWidth(vg, strokeW * (1.0 + 0.5 * progress))
            else
                nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, math.floor(168 * alphaScale)))
                nvgStrokeWidth(vg, strokeW)
            end
            nvgStroke(vg)
        end

        if isRailgunCharging then
            nvgFontSize(vg, shortSide * 0.012)
            nvgFillColor(vg, nvgRGBA(120, 200, 255, math.floor(220 * alphaScale)))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local labelX = cx + r * math.cos(arc.fin) + strokeW * 2
            local labelY = cy + r * math.sin(arc.fin)
            nvgText(vg, labelX, labelY, string.format("%d%%", math.floor(progress * 100)))
        end

        ::continue::
    end

    -- 主目标HP弧
    local primaryEnemy = nil
    for _, enemy in ipairs(GS.enemies) do
        if enemy.isPrimary and enemy.lockValue > 0 then
            primaryEnemy = enemy
            break
        end
    end
    if primaryEnemy then
        local hpRatio = primaryEnemy.hp / primaryEnemy.maxHp
        local hpRadius = innerRadius
        local hpSpan = math.rad(60)
        local hpStart = math.rad(-90) - hpSpan / 2
        local hpEnd = math.rad(-90) + hpSpan / 2

        local hr = math.floor(120 + (255 - 120) * (1.0 - hpRatio))
        local hg = math.floor(230 + (50 - 230) * (1.0 - hpRatio))
        local hb = math.floor(120 + (30 - 120) * (1.0 - hpRatio))

        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, hpRadius, hpStart, hpEnd, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(hr, hg, hb, 20))
        nvgStrokeWidth(vg, strokeW)
        nvgStroke(vg)

        if hpRatio > 0.01 then
            local fillHalf = hpSpan * hpRatio / 2
            local center = math.rad(-90)
            nvgBeginPath(vg)
            nvgArc(vg, cx, cy, hpRadius, center - fillHalf, center + fillHalf, NVG_CW)
            nvgStrokeColor(vg, nvgRGBA(hr, hg, hb, 180))
            nvgStrokeWidth(vg, strokeW)
            nvgStroke(vg)
        end
    end

    -- 中央准星
    local crossSize = 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - crossSize, cy)
    nvgLineTo(vg, cx + crossSize, cy)
    nvgMoveTo(vg, cx, cy - crossSize)
    nvgLineTo(vg, cx, cy + crossSize)
    nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 96))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

--- 绘制战术面板
function HUD.DrawTacticalPanel(w, h)
    if not GS.mechNode then return end
    local vg = GS.vg

    local shortSide = math.min(w, h)
    local panelW = shortSide * 0.22
    local panelH = shortSide * 0.38
    local px = shortSide * 0.02
    local py = 62
    local cut = 8

    -- 背景面板
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + cut, py)
    nvgLineTo(vg, px + panelW, py)
    nvgLineTo(vg, px + panelW, py + panelH - cut)
    nvgLineTo(vg, px + panelW - cut, py + panelH)
    nvgLineTo(vg, px, py + panelH)
    nvgLineTo(vg, px, py + cut)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(5, 12, 25, 140))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + cut, py)
    nvgLineTo(vg, px + panelW, py)
    nvgLineTo(vg, px + panelW, py + panelH - cut)
    nvgLineTo(vg, px + panelW - cut, py + panelH)
    nvgLineTo(vg, px, py + panelH)
    nvgLineTo(vg, px, py + cut)
    nvgClosePath(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 180, 220, 90))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 左上角装饰
    nvgBeginPath(vg)
    nvgMoveTo(vg, px, py + cut)
    nvgLineTo(vg, px + cut, py)
    nvgLineTo(vg, px + cut + panelW * 0.3, py)
    nvgStrokeColor(vg, nvgRGBA(80, 210, 255, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 右下角装饰
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + panelW, py + panelH - cut)
    nvgLineTo(vg, px + panelW - cut, py + panelH)
    nvgLineTo(vg, px + panelW - cut - panelW * 0.25, py + panelH)
    nvgStrokeColor(vg, nvgRGBA(80, 210, 255, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题栏
    local titleY = py + 6
    local titleH = shortSide * 0.026
    local sepY = titleY + titleH + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 6, sepY)
    nvgLineTo(vg, px + panelW - 6, sepY)
    nvgStrokeColor(vg, nvgRGBA(60, 180, 220, 70))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    local iconX = px + 12
    local iconY = titleY + titleH * 0.5
    local iconR = titleH * 0.18
    nvgBeginPath(vg)
    nvgMoveTo(vg, iconX, iconY - iconR)
    nvgLineTo(vg, iconX + iconR, iconY)
    nvgLineTo(vg, iconX, iconY + iconR)
    nvgLineTo(vg, iconX - iconR, iconY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(80, 220, 255, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, titleH)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 220, 255, 220))
    nvgText(vg, iconX + iconR + 6, iconY, "TACTICAL DATA")

    -- 数据区
    local pos = GS.mechNode.worldPosition
    local yaw = 0
    if GS.character then yaw = GS.character.controls.yaw end
    yaw = yaw % 360
    if yaw < 0 then yaw = yaw + 360 end

    local enemyCount = 0
    for _, e in ipairs(GS.enemies) do
        if e.hp and e.hp > 0 then enemyCount = enemyCount + 1 end
    end

    local function YawToCompass(deg)
        local dirs = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                       "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" }
        local idx = math.floor((deg + 11.25) / 22.5) % 16 + 1
        return dirs[idx]
    end

    local labelSize = shortSide * 0.017
    local valueSize = shortSide * 0.024
    local rowH = shortSide * 0.055
    local dataX = px + 14
    local dataValX = px + panelW - 12
    local startY = sepY + rowH * 0.55

    local rows = {
        { label = "COORD S/N", value = string.format("%.1f / %.1f", pos.x, pos.z) },
        { label = "ALTITUDE",  value = string.format("%.1f m", pos.y) },
        { label = "HEADING",   value = string.format("%03.0f\xC2\xB0 %s", yaw, YawToCompass(yaw)) },
        { label = "HOSTILES",  value = tostring(enemyCount), alert = enemyCount > 0 },
    }

    for i, row in ipairs(rows) do
        local ry = startY + (i - 1) * rowH

        if i > 1 then
            nvgBeginPath(vg)
            local dotY = ry - rowH * 0.22
            local dotStart = dataX
            local dotEnd = px + panelW - 12
            local dotStep = 4
            for dx = dotStart, dotEnd, dotStep do
                nvgRect(vg, dx, dotY, 1.5, 0.5)
            end
            nvgFillColor(vg, nvgRGBA(60, 160, 200, 50))
            nvgFill(vg)
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, labelSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(80, 160, 200, 160))
        nvgText(vg, dataX, ry, row.label)

        nvgFontSize(vg, valueSize)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        if row.alert then
            local pulse = math.floor(math.abs(math.sin(os.clock() * 3.0)) * 80 + 175)
            nvgFillColor(vg, nvgRGBA(255, 80, 60, pulse))
        else
            nvgFillColor(vg, nvgRGBA(200, 240, 255, 220))
        end
        nvgText(vg, dataValX, ry, row.value)
    end

    -- 底部扫描线动画
    local scanLineY = py + panelH - 22
    local scanPhase = (os.clock() * 0.3) % 1.0
    local scanX = px + 6 + (panelW - 12) * scanPhase
    local scanGradW = panelW * 0.15
    nvgBeginPath(vg)
    nvgRect(vg, px + 6, scanLineY, panelW - 12, 1)
    nvgFillColor(vg, nvgRGBA(40, 140, 180, 30))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, scanX - scanGradW * 0.5, scanLineY, scanGradW, 1)
    nvgFillColor(vg, nvgRGBA(80, 220, 255, 120))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, shortSide * 0.013)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(60, 160, 200, 100))
    nvgText(vg, px + 8, scanLineY + 4, "SYS ONLINE")

    local dotAlpha = math.floor(math.abs(math.sin(os.clock() * 2.0)) * 140 + 60)
    nvgBeginPath(vg)
    nvgCircle(vg, px + panelW - 14, scanLineY + 10, 3)
    nvgFillColor(vg, nvgRGBA(60, 220, 180, dotAlpha))
    nvgFill(vg)
end

--- 绘制操作提示
function HUD.DrawInstructions(w)
    local vg = GS.vg
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 140))
    nvgText(vg, w / 2, 8, "WASD: 移动 | 鼠标: 视角 | Space: 跳跃/推进 | Shift: 冲刺 | C: 喷射 | T: 测试死亡")
end

--- 绘制退出按钮
function HUD.DrawExitButton(w, h)
    if GS.exitDialog then return end
    local vg = GS.vg

    local btnW = 40
    local btnH = 40
    local margin = 12
    local bx = margin
    local by = margin

    GS.exitBtnRect.x = bx
    GS.exitBtnRect.y = by
    GS.exitBtnRect.w = btnW
    GS.exitBtnRect.h = btnH

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    nvgStrokeColor(vg, nvgRGBA(180, 190, 220, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local cx = bx + btnW / 2
    local cy = by + btnH / 2
    local iconSize = 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - iconSize, cy - iconSize)
    nvgLineTo(vg, cx + iconSize, cy + iconSize)
    nvgMoveTo(vg, cx + iconSize, cy - iconSize)
    nvgLineTo(vg, cx - iconSize, cy + iconSize)
    nvgStrokeColor(vg, nvgRGBA(220, 225, 240, 220))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
end

--- 绘制叛军关卡 HUD
function HUD.DrawRebellionHUD(w, h)
    local st = GS.rebellionState
    if not st then return end
    local vg = GS.vg

    local panelW = 160
    local panelH = 70
    local px = w - panelW - 12
    local py = 60

    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(10, 10, 20, 160))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 120, 60, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 180, 80, 230))
    local waveLabel
    if st.isContinuous then
        waveLabel = "SUPPRESSION"
    else
        waveLabel = string.format("WAVE %d / %d", st.currentWave or 0, st.totalWaves or 0)
    end
    nvgText(vg, px + 8, py + 6, waveLabel)

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(220, 220, 230, 200))
    local killTarget = st.killsToWin or st.totalToSpawn
    local killLabel = string.format("击杀: %d / %d", st.totalKills, killTarget)
    nvgText(vg, px + 8, py + 24, killLabel)

    local barX = px + 8
    local barY = py + 42
    local barW = panelW - 16
    local barH = 6
    local pct = killTarget > 0 and (st.totalKills / killTarget) or 0

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(40, 40, 50, 180))
    nvgFill(vg)

    if pct > 0.005 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * pct, barH, 3)
        nvgFillColor(vg, nvgRGBA(255, 140, 50, 230))
        nvgFill(vg)
    end

    local aliveCount = 0
    for _, e in ipairs(GS.enemies) do
        if e.rebelType and not e.dead then aliveCount = aliveCount + 1 end
    end
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(180, 190, 210, 180))
    nvgText(vg, px + 8, py + 54, string.format("场上: %d", aliveCount))
end

-- ============================================================================
-- 调试：BOSS 瞄准信息（左下角）
-- ============================================================================

--- 绘制 BOSS 瞄准调试信息
---@param w number
---@param h number
function HUD.DrawDebugBossLockInfo(w, h)
    local d = HUD._bossLockDebug
    if not d then return end
    local vg = GS.vg

    local lineH = 18
    local lines = {
        string.format("BOSS Lock Debug"),
        string.format("inFront: %s  onScreen: %s", tostring(d.inFront), tostring(d.onScreen)),
        string.format("visible: %s  locked: %s", tostring(d.visible), tostring(d.locked)),
        string.format("screen: (%.2f, %.2f)", d.sx, d.sy),
        string.format("dist: %.1f  lockValue: %.1f", d.dist, d.lockValue),
        string.format("rayHit: %s  isOwn: %s", tostring(d.rayHitNode), tostring(d.rayIsOwn)),
        string.format("bossPos: (%.1f, %.1f, %.1f)", d.bossPos.x, d.bossPos.y, d.bossPos.z),
        string.format("targetPos: (%.1f, %.1f, %.1f)", d.targetPos.x, d.targetPos.y, d.targetPos.z),
    }

    local panelH = #lines * lineH + 12
    local panelW = 320
    local px = 10
    local py = h - panelH - 10

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, px, py, panelW, panelH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    for i, line in ipairs(lines) do
        local isHeader = (i == 1)
        -- 关键字段高亮：visible=false 或 onScreen=false 时红色
        local color = nvgRGBA(200, 200, 200, 255)
        if isHeader then
            color = nvgRGBA(0, 255, 200, 255)
        elseif i == 2 and (not d.inFront or not d.onScreen) then
            color = nvgRGBA(255, 80, 80, 255)
        elseif i == 3 and not d.visible then
            color = nvgRGBA(255, 80, 80, 255)
        end
        nvgFillColor(vg, color)
        nvgText(vg, px + 8, py + 6 + (i - 1) * lineH, line)
    end
end

-- ============================================================================
-- 调试：BOSS 炮塔开火条件
-- ============================================================================
function HUD.DrawDebugTurretInfo(w, h)
    local d = GS._bossTurretDebug
    if not d then return end
    local vg = GS.vg

    local lineH = 18
    local lines = {
        "BOSS Turret Debug",
        string.format("targetWorldPitch: %.1f°", d.targetWorldPitch),
        string.format("bodyTilt(smoothPitch): %.1f°", d.smoothPitch),
        string.format("targetLocalPitch: %.1f°", d.targetLocalPitch),
        string.format("clampedPitch: %.1f° [%.0f, %.0f]", d.clampedPitch, d.minPitch, d.maxPitch),
        string.format("pitchError: %.1f°  yawError: %.1f°", d.pitchError, d.yawError),
        string.format("pitchInRange: %s  canFire: %s", tostring(d.pitchInRange), tostring(d.canFire)),
        string.format("turretYaw: %.1f°  subPitchL: %.1f°", d.p1TurretYaw, d.p1SubPitchL),
    }

    local panelH = #lines * lineH + 12
    local panelW = 340
    -- 放在 BOSS Lock Debug 面板上方
    local lockPanel = HUD._bossLockDebug and (8 * lineH + 12 + 10) or 0
    local px = 10
    local py = h - panelH - 10 - lockPanel

    nvgBeginPath(vg)
    nvgRect(vg, px, py, panelW, panelH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    for i, line in ipairs(lines) do
        local color = nvgRGBA(200, 200, 200, 255)
        if i == 1 then
            color = nvgRGBA(255, 200, 0, 255)  -- 黄色标题
        elseif i == 7 then
            -- pitchInRange / canFire 高亮
            if not d.pitchInRange then
                color = nvgRGBA(255, 80, 80, 255)  -- 红色：不在范围
            elseif d.canFire then
                color = nvgRGBA(80, 255, 80, 255)  -- 绿色：可开火
            end
        end
        nvgFillColor(vg, color)
        nvgText(vg, px + 8, py + 6 + (i - 1) * lineH, line)
    end
end

-- ============================================================================
-- 调试：碰撞球可视化
-- ============================================================================

--- 绘制敌人碰撞球（调试模式下）
---@param w number
---@param h number
function HUD.DrawDebugCollisionSpheres(w, h)
    local vg = GS.vg
    local camera = GS.tpCamera and GS.tpCamera:GetCamera()
    local camNode = GS.tpCamera and GS.tpCamera:GetNode()
    if not camera or not camNode then return end

    local camPos = camNode.worldPosition
    local camFwd = camNode.worldRotation * Vector3.FORWARD

    nvgFontFace(vg, "sans")

    for _, enemy in ipairs(GS.enemies) do
        if enemy.dead or not enemy.node then goto continue end

        -- 只对有碰撞体的 BOSS / 有 hitRadiusBonus 的敌人绘制
        local sphereRadius = 0
        local sphereCenter = enemy.node.worldPosition

        if enemy.isBoss then
            -- BOSS 碰撞球: SetSphere(12.0) * node.scale
            local nodeScale = enemy.node.scale
            local scaleMax = math.max(nodeScale.x, math.max(nodeScale.y, nodeScale.z))
            if enemy.bossPhase == "phase1" then
                sphereRadius = 24.0 * scaleMax   -- Phase1: SetSphere(24.0) on root (scale=1.0) = 24m
            elseif enemy.bossPhase == "phase2" then
                -- Phase2: SetBox(3.5, 3.0, 6.0) → 用最大维度的半值作为等效球半径
                sphereRadius = math.max(3.5, math.max(3.0, 6.0)) * scaleMax * 0.5
                sphereCenter = sphereCenter + Vector3(0, 1.5 * scaleMax, 0)  -- box center offset
            end
        end

        if sphereRadius <= 0 then goto continue end

        -- 检查是否在相机前方
        local toTarget = sphereCenter - camPos
        if toTarget:DotProduct(camFwd) <= 0 then goto continue end

        -- 将球心投影到屏幕
        local sp = camera:WorldToScreenPoint(sphereCenter)
        if sp.x < -0.2 or sp.x > 1.2 or sp.y < -0.2 or sp.y > 1.2 then goto continue end

        local sx = sp.x * w
        local sy = sp.y * h

        -- 估算碰撞球在屏幕上的半径
        -- 用球体顶部点投影计算屏幕半径
        local dist = toTarget:Length()
        if dist < 1 then goto continue end

        -- 使用球体上/下端点投影来计算屏幕半径
        local topPoint = sphereCenter + Vector3(0, sphereRadius, 0)
        local botPoint = sphereCenter - Vector3(0, sphereRadius, 0)
        local spTop = camera:WorldToScreenPoint(topPoint)
        local spBot = camera:WorldToScreenPoint(botPoint)
        local screenRadiusY = math.abs(spTop.y - spBot.y) * h * 0.5

        -- 水平方向
        local rightDir = camNode.worldRotation * Vector3.RIGHT
        local rightPoint = sphereCenter + rightDir * sphereRadius
        local leftPoint = sphereCenter - rightDir * sphereRadius
        local spRight = camera:WorldToScreenPoint(rightPoint)
        local spLeft = camera:WorldToScreenPoint(leftPoint)
        local screenRadiusX = math.abs(spRight.x - spLeft.x) * w * 0.5

        local screenRadius = math.max(screenRadiusX, screenRadiusY)
        if screenRadius < 5 then goto continue end

        -- 绘制碰撞球轮廓（虚线圆圈效果）
        local segments = 32
        local dashOn = true
        for seg = 0, segments - 1 do
            if dashOn then
                local a1 = (seg / segments) * math.pi * 2
                local a2 = ((seg + 1) / segments) * math.pi * 2
                nvgBeginPath(vg)
                nvgMoveTo(vg, sx + math.cos(a1) * screenRadius, sy + math.sin(a1) * screenRadius)
                nvgLineTo(vg, sx + math.cos(a2) * screenRadius, sy + math.sin(a2) * screenRadius)
                nvgStrokeColor(vg, nvgRGBA(0, 255, 100, 180))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end
            dashOn = not dashOn
        end

        -- 中心十字
        local crossSize = 6
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - crossSize, sy)
        nvgLineTo(vg, sx + crossSize, sy)
        nvgMoveTo(vg, sx, sy - crossSize)
        nvgLineTo(vg, sx, sy + crossSize)
        nvgStrokeColor(vg, nvgRGBA(0, 255, 100, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 信息文字
        local phase = enemy.bossPhase or "?"
        local infoText = string.format("R=%.0fm Phase:%s HP:%.0f/%d",
            sphereRadius, phase, enemy.hp or 0, enemy.maxHp or 0)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(0, 255, 100, 220))
        nvgText(vg, sx, sy - screenRadius - 6, infoText)

        -- 距离
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(0, 255, 100, 180))
        nvgText(vg, sx, sy + screenRadius + 4, string.format("%.0fm", dist))

        ::continue::
    end
end

-- ============================================================================
-- NanoVG 主渲染入口
-- ============================================================================

--- 主渲染入口（绑定 NanoVGRender 事件）
---@param eventType string
---@param eventData table
function HUD.Render(eventType, eventData)
    if GS.current ~= GS.PLAYING then return end
    if GS.vg == nil then return end

    local vg = GS.vg
    local dpr = graphics:GetDPR()
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    nvgBeginFrame(vg, w, h, dpr)

    if not GS.exitDialog then
        HUD.DrawPlayerHPBar(w, h)
        HUD.DrawEnergyBar(w, h)
        HUD.DrawBoostIndicator(w, h)
        HUD.DrawAmmoHUD(w, h)
        HUD.DrawTacticalPanel(w, h)
        HUD.DrawInstructions(w)
        HUD.DrawLockOnUI(w, h)
        HUD.DrawOffScreenIndicators(w, h)
        HUD.DrawExitButton(w, h)
        if GS.rebellionState then HUD.DrawRebellionHUD(w, h) end
        -- 调试模式：绘制碰撞球 + BOSS 瞄准信息 + 炮塔条件
        if CONFIG.debugModeEnabled then
            HUD.DrawDebugCollisionSpheres(w, h)
            HUD.DrawDebugBossLockInfo(w, h)
            HUD.DrawDebugTurretInfo(w, h)
        end
    end

    nvgEndFrame(vg)
end

return HUD
