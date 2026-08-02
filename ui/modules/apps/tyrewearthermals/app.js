angular.module("beamng.apps")
    .directive("tyreWearThermals", ["$injector", function ($injector) {
        return {
            template: '<canvas class="twt-simple-canvas" width="220" height="220" style="width:100%;height:100%;display:block;box-sizing:border-box;"></canvas>',
            replace: true,
            restrict: "EA",
            link: function (scope, element, attrs) {
                var StreamsManager = window.StreamsManager || ($injector.has("StreamsManager") ? $injector.get("StreamsManager") : null);
                var streamsList = ["TyreWearThermals"];
                
                if (StreamsManager) {
                    StreamsManager.add(streamsList);
                }

                scope.$on("$destroy", function () {
                    stopRaf();
                    document.removeEventListener("visibilitychange", onVisibilityChange);
                    if (StreamsManager) {
                        StreamsManager.remove(streamsList);
                    }
                });

                var c = element[0];
                var ctx = c.getContext("2d");

                // Client-side smooth motion: Lua stays ~30 Hz; RAF lerps display toward targets.
                var LERP_K = 12;
                var LERP_EPS = 0.05;
                var rafId = null;
                var lastRafTs = 0;
                var rafRunning = false;
                var targetWheels = [];
                var displayWheels = [];
                var needsRedraw = false;

                function fitCanvas(width, height) {
                    var w = Math.max(1, Math.floor(width || c.clientWidth || 220));
                    var h = Math.max(1, Math.floor(height || c.clientHeight || 220));
                    if (c.width !== w || c.height !== h) {
                        c.width = w;
                        c.height = h;
                        needsRedraw = true;
                    }
                }

                scope.$on('app:resized', function (event, data) {
                    fitCanvas(data && data.width, data && data.height);
                    if (displayWheels.length) {
                        renderDisplay();
                    }
                });

                function lerpNum(cur, tgt, alpha) {
                    if (tgt === undefined || tgt === null) return cur;
                    if (cur === undefined || cur === null) return tgt;
                    var next = cur + (tgt - cur) * alpha;
                    return Math.abs(tgt - next) < LERP_EPS ? tgt : next;
                }

                function copyTemps(src) {
                    var t = src || [];
                    var out = [];
                    for (var i = 0; i < 8; i++) {
                        out[i] = t[i] || 0;
                    }
                    return out;
                }

                function makeWheelState(src) {
                    return {
                        name: src.name || "unknown",
                        temp: copyTemps(src.temp),
                        working_temp: src.working_temp,
                        condition: src.condition !== undefined ? src.condition : 100,
                        camber: src.camber || 0,
                        pressure: src.pressure !== undefined ? src.pressure : 25,
                        initialPressure: src.initialPressure || 25,
                        surfaceDamage: src.surfaceDamage || 0,
                        flatspot: src.flatspot || 0
                    };
                }

                function snapWheel(dst, src) {
                    dst.name = src.name || "unknown";
                    dst.working_temp = src.working_temp;
                    dst.initialPressure = src.initialPressure || 25;
                    dst.condition = src.condition !== undefined ? src.condition : 100;
                    dst.camber = src.camber || 0;
                    dst.pressure = src.pressure !== undefined ? src.pressure : 25;
                    dst.surfaceDamage = src.surfaceDamage || 0;
                    dst.flatspot = src.flatspot || 0;
                    dst.temp = copyTemps(src.temp);
                }

                function stopRaf() {
                    if (rafId !== null) {
                        cancelAnimationFrame(rafId);
                        rafId = null;
                    }
                    rafRunning = false;
                    lastRafTs = 0;
                }

                function isAppVisible() {
                    if (document.hidden) return false;
                    if (!c) return false;
                    return !!(c.offsetWidth || c.offsetHeight || c.getClientRects().length);
                }

                function startRaf() {
                    if (rafRunning || !isAppVisible()) return;
                    rafRunning = true;
                    lastRafTs = 0;
                    rafId = requestAnimationFrame(rafTick);
                }

                function lerpWheels(alpha) {
                    var moved = false;
                    var n = Math.min(targetWheels.length, displayWheels.length);
                    for (var i = 0; i < n; i++) {
                        var d = displayWheels[i];
                        var t = targetWheels[i];
                        var prev;

                        prev = d.condition;
                        d.condition = lerpNum(d.condition, t.condition, alpha);
                        if (d.condition !== prev) moved = true;

                        prev = d.camber;
                        d.camber = lerpNum(d.camber, t.camber, alpha);
                        if (d.camber !== prev) moved = true;

                        prev = d.pressure;
                        d.pressure = lerpNum(d.pressure, t.pressure, alpha);
                        if (d.pressure !== prev) moved = true;

                        prev = d.surfaceDamage;
                        d.surfaceDamage = lerpNum(d.surfaceDamage, t.surfaceDamage, alpha);
                        if (d.surfaceDamage !== prev) moved = true;

                        prev = d.flatspot;
                        d.flatspot = lerpNum(d.flatspot, t.flatspot, alpha);
                        if (d.flatspot !== prev) moved = true;

                        for (var ti = 0; ti < 8; ti++) {
                            prev = d.temp[ti];
                            d.temp[ti] = lerpNum(d.temp[ti], t.temp[ti], alpha);
                            if (d.temp[ti] !== prev) moved = true;
                        }

                        // Non-visual / discrete: keep in sync without lerp
                        d.name = t.name;
                        d.working_temp = t.working_temp;
                        d.initialPressure = t.initialPressure;
                    }
                    return moved;
                }

                function rafTick(ts) {
                    if (!rafRunning) return;
                    if (!isAppVisible()) {
                        stopRaf();
                        return;
                    }
                    var dt = lastRafTs ? Math.min(0.05, (ts - lastRafTs) / 1000) : (1 / 60);
                    lastRafTs = ts;
                    var alpha = Math.min(1, LERP_K * dt);
                    var moved = lerpWheels(alpha);
                    if (moved || needsRedraw) {
                        needsRedraw = false;
                        renderDisplay();
                    }
                    if (moved) {
                        rafId = requestAnimationFrame(rafTick);
                    } else {
                        stopRaf();
                    }
                }

                function onVisibilityChange() {
                    if (!isAppVisible()) {
                        stopRaf();
                    } else if (targetWheels.length) {
                        startRaf();
                    }
                }
                document.addEventListener("visibilitychange", onVisibilityChange);

                // Standard border-radius drawing utility
                function roundRect(ctx, x, y, width, height, radius, fill, stroke) {
                    if (radius === undefined) radius = 5;
                    if (fill === undefined) fill = false;
                    if (stroke === undefined) stroke = true;

                    if (typeof radius === 'number') {
                        radius = { tl: radius, tr: radius, br: radius, bl: radius };
                    } else {
                        radius = angular.extend({ tl: 0, tr: 0, br: 0, bl: 0 }, radius);
                    }
                    ctx.beginPath();
                    ctx.moveTo(x + radius.tl, y);
                    ctx.lineTo(x + width - radius.tr, y);
                    ctx.quadraticCurveTo(x + width, y, x + width, y + radius.tr);
                    ctx.lineTo(x + width, y + height - radius.br);
                    ctx.quadraticCurveTo(x + width, y + height, x + width - radius.br, y + height);
                    ctx.lineTo(x + radius.bl, y + height);
                    ctx.quadraticCurveTo(x, y + height, x, y + height - radius.bl);
                    ctx.lineTo(x, y + radius.tl);
                    ctx.quadraticCurveTo(x, y, x + radius.tl, y);
                    ctx.closePath();
                    if (fill) {
                        ctx.fill();
                    }
                    if (stroke) {
                        ctx.stroke();
                    }
                }

                // Resolves HSL thermal gradient with smoothstep transitions
                function getTempColor(tempVal, working_temp) {
                    var r = tempVal / (working_temp || 85);
                    var hue;
                    
                    if (r < 0.75) {
                        // Cold to Optimal transition: Blue (240) to Green (120)
                        var t = Math.min(Math.max((r - 0.4) / 0.35, 0), 1);
                        t = t * t * (3 - 2 * t);
                        hue = 240 + t * (120 - 240);
                    } else if (r <= 1.15) {
                        // Optimal zone (Green)
                        hue = 120;
                    } else {
                        // Overheated transition: Green to Red (120 to 0)
                        var t = Math.min(1.0, (r - 1.15) / 0.35);
                        t = t * t * (3 - 2 * t);
                        hue = 120 - t * 120;
                    }
                    
                    return "hsla(" + Math.round(hue) + ",85%,52%,1)";
                }

                function drawWheelData(d, tyreNumber, wheelCount) {
                    var name = d.name || "unknown";
                    var temps = d.temp;
                    var working_temp = d.working_temp;
                    var condition = d.condition;
                    var camber = d.camber;
                    var pressure = d.pressure;
                    var initialPressure = d.initialPressure;
                    var surfaceDamage = d.surfaceDamage; 
                    var flatspot = d.flatspot;

                    if (!temps || temps.length === 0) {
                        temps = [0, 0, 0, 0, 0, 0, 0, 0];
                    }

                    if (condition === undefined) condition = 100;
                    camber = camber || 0;

                    ctx.textAlign = 'center';

                    // Robust horizontal coordinate (Left/Right Side detection)
                    var right = (tyreNumber % 2 === 1) ? 1 : 0;
                    var nameUpper = name.toUpperCase();
                    var testStr = nameUpper;
                    
                    if (nameUpper.length > 1 && (nameUpper[0] === 'F' || nameUpper[0] === 'R')) {
                        testStr = nameUpper.substring(1);
                    }
                    
                    if (testStr.indexOf("R") !== -1) {
                        right = 1;
                    } else if (testStr.indexOf("L") !== -1) {
                        right = 0;
                    }

                    // Robust dynamic axle coordinate assignment (Row detection)
                    var back = 0;
                    if (nameUpper.indexOf("F") === 0) {
                        back = 0;
                    } else if (nameUpper.indexOf("R") === 0) {
                        var axleNumMatch = nameUpper.match(/\d+/);
                        if (axleNumMatch) {
                            back = parseInt(axleNumMatch[0], 10);
                        } else {
                            back = 1;
                        }
                    } else {
                        back = Math.floor(tyreNumber / 2);
                    }

                    var axleCount = Math.max(2, Math.ceil(wheelCount / 2));
                    var pad = Math.max(6, Math.min(c.width, c.height) * 0.035);
                    var gapX = Math.max(8, c.width * 0.04);
                    var gapY = Math.max(10, c.height * 0.045);
                    var colW = (c.width - pad * 2 - gapX) / 2;
                    var rowH = (c.height - pad * 2 - gapY * (axleCount - 1)) / axleCount;

                    var x = pad + right * (colW + gapX);
                    var y = pad + back * (rowH + gapY);
                    var cx = x + colW * 0.5;

                    // Reserve vertical bands inside the cell so text/triangles never collide
                    var headerH = Math.max(12, rowH * 0.16);
                    var footerH = Math.max(12, rowH * 0.16);
                    var camberGap = Math.max(5, rowH * 0.05);
                    var treadY = y + headerH + camberGap;
                    var treadH = Math.max(18, rowH - headerH - footerH - camberGap * 2);
                    var treadW = colW;

                    // 1. Header Text: Wheel Name & Condition (e.g., FL | 98%)
                    ctx.fillStyle = "#ffffff";
                    var headerSize = Math.max(Math.min(colW / 12.0, 10.0), 7.0);
                    ctx.font = 'bold ' + headerSize + 'pt "Lucida Console", Monaco, monospace';
                    var headerText = name.toUpperCase() + " | " + Number(condition).toFixed(2) + "%";
                    ctx.fillText(headerText, cx, y + headerH * 0.72);

                    // 2. Draw Tyre Tread Rings
                    var segGap = 2;
                    var sectionWidth = (treadW - segGap * 2) / 3.0;
                    for (var i = 0; i < 3; i++) {
                        var tempVal = temps[i] || 0;
                        var sectionColor = getTempColor(tempVal, working_temp);

                        var crad = Math.min(5.0, sectionWidth * 0.25);
                        var radius = { tl: 0, tr: 0, br: 0, bl: 0 };
                        if (i === 0) {
                            radius = { tl: crad, tr: 0, br: 0, bl: crad };
                        } else if (i === 2) {
                            radius = { tl: 0, tr: crad, br: crad, bl: 0 };
                        }

                        var sectionXOffset = (sectionWidth + segGap) * i;
                        
                        // Draw empty background representing tread loss
                        ctx.fillStyle = "rgba(15, 23, 42, 0.65)";
                        ctx.beginPath();
                        ctx.rect(x + sectionXOffset, treadY, sectionWidth, treadH);
                        ctx.fill();

                        // Fill color representing remaining tread
                        if (condition > 1) {
                            var ft = 1.0 - (condition / 100);
                            ctx.fillStyle = sectionColor;
                            ctx.beginPath();
                            ctx.rect(x + sectionXOffset, treadY + treadH * ft, sectionWidth, treadH - treadH * ft);
                            ctx.fill();
                        }
                        
                        ctx.lineWidth = "2";
                        ctx.strokeStyle = "rgba(0,0,0,1)";
                        roundRect(ctx, x + sectionXOffset, treadY, sectionWidth, treadH, radius, false, true);

                        // Overlay Temperature centered vertically inside the block
                        ctx.fillStyle = "#ffffff";
                        var font_size = Math.max(Math.min(colW / 16.0 * 2.6, 11.0), 7.0);
                        ctx.font = 'bold ' + font_size + 'pt "Lucida Console", Monaco, monospace';
                        ctx.fillText(Number(tempVal).toFixed(2), x + sectionXOffset + (sectionWidth / 2), treadY + treadH / 2 + (font_size / 2.2));
                    }

                    // 3. Draw Camber Triangle Indicators (bound-clamped within the tread width)
                    var triX = x + treadW * 0.5 + treadW * (camber * 0.2 * 0.5);
                    var safetyMargin = Math.max(5, sectionWidth * 0.15);
                    triX = Math.max(x + safetyMargin, Math.min(x + treadW - safetyMargin, triX));

                    ctx.fillStyle = "rgba(239, 68, 68, 0.9)";
                    ctx.beginPath();
                    ctx.moveTo(triX, treadY - 1);
                    ctx.lineTo(triX - 4, treadY - 6);
                    ctx.lineTo(triX + 4, treadY - 6);
                    ctx.fill();

                    ctx.beginPath();
                    ctx.moveTo(triX, treadY + treadH + 1);
                    ctx.lineTo(triX - 4, treadY + treadH + 6);
                    ctx.lineTo(triX + 4, treadY + treadH + 6);
                    ctx.fill();

                    // 4. Footer Text: Pressure with Context-Aware Highlight
                    var pres = (pressure !== undefined) ? pressure : 25;
                    var initPres = initialPressure || 25;
                    var isLow = (pres < initPres * 0.8) || (pres < 10);
                    var isHigh = (pres > initPres * 1.3);
                    
                    ctx.fillStyle = isLow ? "#38bdf8" : (isHigh ? "#ef4444" : "#e2e8f0");
                    var infoFontSize = Math.max(Math.min(colW / 18.0 * 2.4, 10.0), 6.5);
                    ctx.font = 'bold ' + infoFontSize + 'pt "Lucida Console", Monaco, monospace';
                    
                    // Show a warning indicator if flat spots or surface damage are severe
                    var warningTag = "";
                    if ((surfaceDamage && surfaceDamage > 25) || (flatspot && flatspot > 25) || (condition < 35)) {
                        warningTag = "⚠ ";
                        ctx.fillStyle = "#ffaa44";
                    }

                    var footerText = warningTag + Number(pres).toFixed(2) + " PSI";
                    ctx.fillText(footerText, cx, y + rowH - footerH * 0.25);
                }

                function renderDisplay() {
                    ctx.setTransform(1, 0, 0, 1, 0, 0);
                    ctx.clearRect(0, 0, c.width, c.height);
                    ctx.textAlign = 'center';

                    var wheelCount = displayWheels.length;
                    for (var i = 0; i < wheelCount; i++) {
                        var d = displayWheels[i];
                        if (d) {
                            drawWheelData(d, i, wheelCount);
                        }
                    }
                }

                function ingestStream(dataStream) {
                    if (!dataStream || !dataStream.data) return;

                    var src = dataStream.data;
                    var count = src.length;
                    var structural = (targetWheels.length !== count);

                    if (structural) {
                        targetWheels = [];
                        displayWheels = [];
                        for (var i = 0; i < count; i++) {
                            var state = makeWheelState(src[i] || {});
                            targetWheels.push(state);
                            displayWheels.push(makeWheelState(src[i] || {}));
                        }
                        needsRedraw = true;
                        renderDisplay();
                    } else {
                        for (var j = 0; j < count; j++) {
                            snapWheel(targetWheels[j], src[j] || {});
                        }
                    }
                    startRaf();
                }

                scope.$on("TyreWearThermals", function (event, dataStream) {
                    ingestStream(dataStream);
                });

                scope.$on("streamsUpdate", function (event, streams) {
                    if (streams && streams.TyreWearThermals) {
                        ingestStream(streams.TyreWearThermals);
                    }
                });
            }
        };
    }]);