angular.module("beamng.apps")
    .directive("tyreWearThermalsMedium", ["$injector", function ($injector) {
        return {
            template: `
                <div class="ttm-panel-container">
                    <style>
                        .ttm-panel-container {
                            width: 100%;
                            height: 100%;
                            max-height: 100%;
                            min-height: 0;
                            background: rgba(18, 22, 28, 0.90);
                            border: 1px solid rgba(255, 255, 255, 0.08);
                            border-radius: 6px;
                            box-sizing: border-box;
                            font-family: "Lucida Console", Monaco, monospace;
                            color: #f1f5f9;
                            overflow-x: hidden;
                            overflow-y: auto;
                            -webkit-overflow-scrolling: touch;
                            padding: 8px;
                            pointer-events: auto;
                        }
                        .ttm-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 2px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 5px;
                            margin-bottom: 8px;
                            gap: 6px;
                            flex-wrap: wrap;
                        }
                        .ttm-title {
                            font-size: 12px;
                            font-weight: bold;
                            letter-spacing: 1.2px;
                            color: #38bdf8;
                        }
                        .ttm-header-meta {
                            font-size: 9px;
                            color: #94a3b8;
                            letter-spacing: 0.4px;
                        }
                        .ttm-grid {
                            display: grid;
                            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
                            gap: 8px;
                        }
                        .ttm-card {
                            background: rgba(30, 41, 59, 0.6);
                            border: 1px solid rgba(255, 255, 255, 0.04);
                            border-radius: 5px;
                            padding: 8px;
                            box-sizing: border-box;
                        }
                        .ttm-card-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 4px;
                            margin-bottom: 6px;
                        }
                        .ttm-wheel-name {
                            font-size: 12px;
                            font-weight: bold;
                            color: #38bdf8;
                        }
                        .ttm-compound-tag {
                            font-size: 9px;
                            background: rgba(56, 189, 248, 0.12);
                            border: 1px solid rgba(56, 189, 248, 0.2);
                            padding: 1px 5px;
                            border-radius: 3px;
                            text-transform: uppercase;
                            letter-spacing: 0.4px;
                        }
                        .ttm-stat-row {
                            display: flex;
                            justify-content: space-between;
                            margin-bottom: 3px;
                            font-size: 10px;
                        }
                        .ttm-label { color: #94a3b8; }
                        .ttm-value { font-weight: bold; }
                        .ttm-section-label {
                            font-size: 9px;
                            color: #94a3b8;
                            margin-top: 5px;
                            margin-bottom: 1px;
                        }
                        .ttm-thermal-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 3px;
                            margin: 3px 0 5px;
                            height: 20px;
                        }
                        .ttm-thermal-segment {
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 10px;
                            font-weight: bold;
                            border-radius: 3px;
                            text-shadow: 1px 1px 1px rgba(0,0,0,0.85);
                        }
                        .ttm-bar-container {
                            width: 100%;
                            background: rgba(255, 255, 255, 0.05);
                            border-radius: 3px;
                            height: 5px;
                            overflow: hidden;
                            margin-top: 2px;
                        }
                        .ttm-bar-fill {
                            height: 100%;
                        }
                        .ttm-diagnostics-grid {
                            display: grid;
                            grid-template-columns: 1fr 1fr;
                            gap: 6px;
                            border-top: 1px dashed rgba(255, 255, 255, 0.08);
                            margin-top: 6px;
                            padding-top: 6px;
                        }
                        .ttm-diagnostic-item { font-size: 9px; }
                        .ttm-diag-label {
                            color: #64748b;
                            display: block;
                            margin-bottom: 2px;
                            font-size: 8px;
                            letter-spacing: 0.4px;
                        }
                        .ttm-footer {
                            font-size: 8px;
                            color: #64748b;
                            text-align: right;
                            margin-top: 5px;
                        }
                    </style>

                    <div class="ttm-header">
                        <span class="ttm-title">TYRE TELEMETRY (MEDIUM)</span>
                        <span class="ttm-header-meta">
                            Env {{ (envTemp||0).toFixed(2) }}°C · Track {{ (trackTemp||0).toFixed(2) }}°C · Rain {{ (rainState||0).toFixed(2) }}%
                        </span>
                        <span class="ttm-header-meta">
                            <span style="color: #64748b;">Aero ↓</span>
                            <span style="color: #f59e0b; font-weight: bold;"> {{ totalDownforceKN }} kN</span>
                            <span style="color: #475569; font-size: 9px;"> ({{ (aeroFracPct||0).toFixed(2) }}%)</span>
                        </span>
                    </div>

                    <div class="ttm-grid">
                        <div class="ttm-card" ng-repeat="w in wheels">
                            <div class="ttm-card-header">
                                <span class="ttm-wheel-name">{{ w.name }}</span>
                                <span class="ttm-compound-tag">{{ formatProfile(w.profile) }}</span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Tread Condition:</span>
                                <span class="ttm-value" ng-style="{'color': getConditionColor(w.condition)}">
                                    {{ (w.condition !== undefined ? w.condition : 0).toFixed(2) }}%
                                </span>
                            </div>
                            <div class="ttm-bar-container" style="margin-bottom: 5px;">
                                <div class="ttm-bar-fill" ng-style="{'width': (w.condition || 0) + '%', 'background-color': getConditionColor(w.condition)}"></div>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Dynamic Grip:</span>
                                <span class="ttm-value" ng-style="{'color': getGripColor(w.tyreGrip)}">
                                    {{ ((w.tyreGrip || 0) * 100).toFixed(2) }}%
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Tire Pressure:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ (w.pressure !== undefined ? w.pressure : 0).toFixed(2) }} PSI
                                    </span>
                                    <span style="font-size: 9px; color: #64748b;">
                                        (Cold {{ (w.coldPressure || w.initialPressure || 0).toFixed(2) }} / Hot {{ (w.targetHotPressure || w.optimalPressure || 0).toFixed(2) }})
                                    </span>
                                </span>
                            </div>

                            <div class="ttm-stat-row" ng-if="w.zoneCondition">
                                <span class="ttm-label">Zone Wear O|M|I:</span>
                                <span class="ttm-value" style="font-size: 10px;">
                                    {{ (w.zoneCondition[0]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[1]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[2]||0).toFixed(0) }}%
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Camber / Toe:</span>
                                <span class="ttm-value" ng-style="{'color': isExcessiveCamber(w.camber) ? '#ffaa44' : '#f1f5f9'}">
                                    {{ (w.camber !== undefined ? w.camber : 0).toFixed(2) }}° /
                                    {{ (w.toe !== undefined ? w.toe : 0).toFixed(2) }}°
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Temp State / Opt:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': tempCategoryColor(w.tempCategory)}">{{ w.tempCategory || 'Normal' }}</span>
                                    <span style="color:#64748b;"> · avg {{ (w.avgTemp||0).toFixed(2) }}° / opt {{ (w.working_temp||0).toFixed(2) }}°</span>
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Surface:</span>
                                <span class="ttm-value" style="font-size: 10px;">
                                    {{ w.surfaceName || '—' }} · {{ formatProfile(w.surfaceType) }}
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Aero Load:</span>
                                <span class="ttm-value" style="color: #f59e0b;">
                                    {{ (w.aeroLoadN || 0) >= 1000 ? ((w.aeroLoadN || 0) / 1000).toFixed(2) + ' kN' : (w.aeroLoadN || 0).toFixed(2) + ' N' }}
                                </span>
                            </div>

                            <div class="ttm-section-label">Surface Heat Map (O | M | I):</div>
                            <div class="ttm-thermal-strip">
                                <div class="ttm-thermal-segment"
                                     ng-repeat="tempVal in w.surfaceTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(2) }}°
                                </div>
                            </div>

                            <div class="ttm-section-label">Carcass Heat Map (O | M | I):</div>
                            <div class="ttm-thermal-strip">
                                <div class="ttm-thermal-segment"
                                     ng-repeat="tempVal in w.carcassTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(2) }}°
                                </div>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Rim / Air:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': getTempColor(w.rimTemp, w.working_temp)}">{{ (w.rimTemp || 0).toFixed(2) }}°</span>
                                    /
                                    <span ng-style="{'color': getTempColor(w.airTemp, w.working_temp)}">{{ (w.airTemp || 0).toFixed(2) }}°</span>
                                </span>
                            </div>

                            <div class="ttm-diagnostics-grid">
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">CLOG</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.clog)}">{{ (w.clog || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.clog || 0) + '%', 'background-color': getDiagnosticColor(w.clog)}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">GRAINING</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.graining)}">{{ (w.graining || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.graining || 0) + '%', 'background-color': getDiagnosticColor(w.graining)}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">BLISTER</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.blistering)}">{{ (w.blistering || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.blistering || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">MARBLES</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.marbles)}">{{ (w.marbles || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.marbles || 0) + '%', 'background-color': getDiagnosticColor(w.marbles)}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">FLATSPOT</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.flatspot)}">{{ (w.flatspot || 0).toFixed(0) }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.flatspot || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">LEAK / FILM</span>
                                    <span class="ttm-value">{{ (w.leak || 0).toFixed(0) }}% / {{ (w.waterFilm || 0).toFixed(0) }}%</span>
                                </div>
                            </div>

                            <div class="ttm-footer">
                                Cycles: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.cycles || 0).toFixed(0) }}</span>
                                &nbsp;|&nbsp; Stint: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.stintFade || 0).toFixed(0) }}%</span>
                                &nbsp;|&nbsp; Duct: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.ductPercent || 1).toFixed(0) }}%</span>
                            </div>
                        </div>
                    </div>
                </div>
            `,
            replace: true,
            restrict: "EA",
            link: function (scope, element, attrs) {
                var StreamsManager = window.StreamsManager || ($injector.has("StreamsManager") ? $injector.get("StreamsManager") : null);
                var streamsList = ["TyreWearThermals"];

                if (StreamsManager) {
                    StreamsManager.add(streamsList);
                }

                // Client-side smooth motion: Lua ~30 Hz; RAF lerps display toward targets.
                // Digest is throttled (~20 Hz): full $digest every RAF stalls CEF under Heavy/Medium binding load.
                var LERP_K = 12;
                var LERP_EPS = 0.05;
                var DIGEST_INTERVAL_MS = 50; // ~20 Hz Angular updates; RAF still lerps at display rate
                var rafId = null;
                var lastRafTs = 0;
                var lastDigestTs = 0;
                var rafRunning = false;
                var targetWheels = [];
                var targetMeta = {
                    envTemp: 21,
                    trackTemp: 21,
                    rainState: 0,
                    totalDownforceN: 0,
                    aeroFracPct: 0
                };
                var WHEEL_LERP_KEYS = [
                    "condition", "tyreGrip", "pressure", "camber", "toe", "avgTemp",
                    "working_temp", "rimTemp", "airTemp", "aeroLoadN",
                    "clog", "graining", "blistering", "marbles", "flatspot", "leak", "waterFilm",
                    "stintFade", "ductPercent"
                ];

                scope.wheels = [];
                scope.envTemp = 21;
                scope.trackTemp = 21;
                scope.rainState = 0;
                scope.totalDownforceKN = "0.00";
                scope.aeroFracPct = 0;

                scope.formatProfile = function (profile) {
                    if (!profile) return "";
                    return String(profile).replace(/_/g, " ");
                };

                scope.tempCategoryColor = function (cat) {
                    if (cat === "Cold") return "#38bdf8";
                    if (cat === "Hot") return "#ef4444";
                    return "#10b981";
                };

                scope.isExcessiveCamber = function (camber) {
                    return Math.abs(camber || 0) > 3.0;
                };

                scope.getConditionColor = function (condition) {
                    if (condition === undefined) return "#10b981";
                    var ratio = condition / 100;
                    if (ratio > 0.7) return "#10b981";
                    if (ratio > 0.4) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getGripColor = function (grip) {
                    if (grip === undefined) return "#f1f5f9";
                    if (grip >= 0.95) return "#10b981";
                    if (grip >= 0.85) return "#a3e635";
                    if (grip >= 0.70) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getDiagnosticColor = function (value) {
                    if (!value || value <= 5) return "#94a3b8";
                    if (value <= 25) return "#a3e635";
                    if (value <= 60) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getInflationColor = function (pressure, optimalPressure) {
                    if (pressure === undefined) return "#f1f5f9";
                    var opt = optimalPressure || 25;
                    if (opt <= 0) opt = 25;
                    var ratio = pressure / opt;
                    if (pressure < 5) return "#ef4444";
                    if (ratio < 0.75) return "#38bdf8";
                    if (ratio < 0.90) return "#a3e635";
                    if (ratio <= 1.25) return "#10b981";
                    if (ratio <= 1.40) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getTempColor = function (tempVal, working_temp) {
                    if (tempVal === undefined) return "hsla(240, 80%, 45%, 1)";
                    var r = tempVal / (working_temp || 85);
                    var hue;
                    if (r < 0.75) {
                        var t = Math.min(Math.max((r - 0.4) / 0.35, 0), 1);
                        t = t * t * (3 - 2 * t);
                        hue = 240 - t * 120;
                    } else if (r <= 1.10) {
                        hue = 120;
                    } else {
                        var t = Math.min(Math.max((r - 1.10) / 0.30, 0), 1);
                        t = t * t * (3 - 2 * t);
                        hue = 120 - t * 120;
                    }
                    return "hsla(" + Math.round(hue) + ", 80%, 45%, 1)";
                };

                function lerpNum(cur, tgt, alpha) {
                    if (tgt === undefined || tgt === null) return cur;
                    if (cur === undefined || cur === null) return tgt;
                    var next = cur + (tgt - cur) * alpha;
                    return Math.abs(tgt - next) < LERP_EPS ? tgt : next;
                }

                function ensureArr3(dst, a, b, c) {
                    if (!dst || dst.length !== 3) return [a || 0, b || 0, c || 0];
                    dst[0] = a || 0;
                    dst[1] = b || 0;
                    dst[2] = c || 0;
                    return dst;
                }

                function prepareWheelTemps(w) {
                    var t = w.temp || [];
                    w.surfaceTemps = ensureArr3(w.surfaceTemps, t[0], t[1], t[2]);
                    w.carcassTemps = ensureArr3(w.carcassTemps, t[3], t[4], t[5]);
                    if (w.rimTemp === undefined) w.rimTemp = t[6] || 0;
                    if (w.airTemp === undefined) w.airTemp = t[7] || 0;
                    if (!w.zoneCondition || w.zoneCondition.length !== 3) {
                        w.zoneCondition = [
                            (w.zoneCondition && w.zoneCondition[0]) || w.condition || 100,
                            (w.zoneCondition && w.zoneCondition[1]) || w.condition || 100,
                            (w.zoneCondition && w.zoneCondition[2]) || w.condition || 100
                        ];
                    }
                }

                function copyStaticWheel(dst, src) {
                    dst.name = src.name;
                    dst.profile = src.profile;
                    dst.tempCategory = src.tempCategory;
                    dst.surfaceName = src.surfaceName;
                    dst.surfaceType = src.surfaceType;
                    dst.coldPressure = src.coldPressure;
                    dst.initialPressure = src.initialPressure;
                    dst.targetHotPressure = src.targetHotPressure;
                    dst.optimalPressure = src.optimalPressure;
                    dst.cycles = src.cycles;
                }

                function snapLerpArrays(dst, src) {
                    var st = src.surfaceTemps || [0, 0, 0];
                    var ct = src.carcassTemps || [0, 0, 0];
                    var zc = src.zoneCondition || [100, 100, 100];
                    dst.surfaceTemps = [st[0] || 0, st[1] || 0, st[2] || 0];
                    dst.carcassTemps = [ct[0] || 0, ct[1] || 0, ct[2] || 0];
                    dst.zoneCondition = [zc[0] || 0, zc[1] || 0, zc[2] || 0];
                }

                function snapLerpScalars(dst, src) {
                    for (var i = 0; i < WHEEL_LERP_KEYS.length; i++) {
                        var k = WHEEL_LERP_KEYS[i];
                        dst[k] = src[k] !== undefined && src[k] !== null ? src[k] : 0;
                    }
                }

                function makeDisplayWheel(src) {
                    var dst = {};
                    copyStaticWheel(dst, src);
                    snapLerpScalars(dst, src);
                    snapLerpArrays(dst, src);
                    return dst;
                }

                function setTargetWheel(dst, src) {
                    copyStaticWheel(dst, src);
                    snapLerpScalars(dst, src);
                    snapLerpArrays(dst, src);
                }

                function isAppVisible() {
                    if (document.hidden) return false;
                    var el = element[0];
                    if (!el) return false;
                    // Detached / display:none apps have no layout box — skip RAF work.
                    return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
                }

                function stopRaf() {
                    if (rafId !== null) {
                        cancelAnimationFrame(rafId);
                        rafId = null;
                    }
                    rafRunning = false;
                    lastRafTs = 0;
                }

                function startRaf() {
                    if (rafRunning || !isAppVisible()) return;
                    rafRunning = true;
                    lastRafTs = 0;
                    lastDigestTs = 0;
                    rafId = requestAnimationFrame(rafTick);
                }

                function applyDisplayMeta() {
                    scope.totalDownforceKN = ((scope._dfN || 0) / 1000).toFixed(2);
                }

                function lerpDisplay(alpha) {
                    var moved = false;
                    var i, j, k, prev, d, t;

                    prev = scope.envTemp;
                    scope.envTemp = lerpNum(scope.envTemp, targetMeta.envTemp, alpha);
                    if (scope.envTemp !== prev) moved = true;

                    prev = scope.trackTemp;
                    scope.trackTemp = lerpNum(scope.trackTemp, targetMeta.trackTemp, alpha);
                    if (scope.trackTemp !== prev) moved = true;

                    prev = scope.rainState;
                    scope.rainState = lerpNum(scope.rainState, targetMeta.rainState, alpha);
                    if (scope.rainState !== prev) moved = true;

                    prev = scope._dfN;
                    scope._dfN = lerpNum(scope._dfN || 0, targetMeta.totalDownforceN, alpha);
                    if (scope._dfN !== prev) moved = true;

                    prev = scope.aeroFracPct;
                    scope.aeroFracPct = lerpNum(scope.aeroFracPct, targetMeta.aeroFracPct, alpha);
                    if (scope.aeroFracPct !== prev) moved = true;

                    var n = Math.min(scope.wheels.length, targetWheels.length);
                    for (i = 0; i < n; i++) {
                        d = scope.wheels[i];
                        t = targetWheels[i];
                        copyStaticWheel(d, t);
                        for (j = 0; j < WHEEL_LERP_KEYS.length; j++) {
                            k = WHEEL_LERP_KEYS[j];
                            prev = d[k];
                            d[k] = lerpNum(d[k], t[k], alpha);
                            if (d[k] !== prev) moved = true;
                        }
                        for (j = 0; j < 3; j++) {
                            prev = d.surfaceTemps[j];
                            d.surfaceTemps[j] = lerpNum(d.surfaceTemps[j], t.surfaceTemps[j], alpha);
                            if (d.surfaceTemps[j] !== prev) moved = true;

                            prev = d.carcassTemps[j];
                            d.carcassTemps[j] = lerpNum(d.carcassTemps[j], t.carcassTemps[j], alpha);
                            if (d.carcassTemps[j] !== prev) moved = true;

                            prev = d.zoneCondition[j];
                            d.zoneCondition[j] = lerpNum(d.zoneCondition[j], t.zoneCondition[j], alpha);
                            if (d.zoneCondition[j] !== prev) moved = true;
                        }
                    }
                    applyDisplayMeta();
                    return moved;
                }

                function digestDisplay() {
                    if (scope.$$phase) return;
                    scope.$digest();
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
                    var moved = lerpDisplay(alpha);
                    // Throttle digests: RAF keeps lerping the model; Angular rebinds at ~20 Hz.
                    if (!moved || !lastDigestTs || (ts - lastDigestTs) >= DIGEST_INTERVAL_MS) {
                        lastDigestTs = ts;
                        digestDisplay();
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

                function ingestStream(dataStream) {
                    if (!dataStream || !dataStream.data) return;

                    var src = dataStream.data;
                    var count = src.length;
                    var structural = (scope.wheels.length !== count);
                    var i, w;

                    for (i = 0; i < count; i++) {
                        prepareWheelTemps(src[i]);
                    }

                    targetMeta.envTemp = dataStream.envTemp !== undefined ? dataStream.envTemp : targetMeta.envTemp;
                    targetMeta.trackTemp = dataStream.trackTemp !== undefined ? dataStream.trackTemp : targetMeta.trackTemp;
                    targetMeta.rainState = dataStream.rainState !== undefined ? dataStream.rainState : targetMeta.rainState;
                    targetMeta.totalDownforceN = dataStream.totalDownforceN !== undefined ? dataStream.totalDownforceN : targetMeta.totalDownforceN;
                    targetMeta.aeroFracPct = dataStream.aeroFracPct !== undefined ? dataStream.aeroFracPct : targetMeta.aeroFracPct;

                    if (structural) {
                        targetWheels = [];
                        var wheels = [];
                        for (i = 0; i < count; i++) {
                            w = src[i] || {};
                            var tgt = {};
                            setTargetWheel(tgt, w);
                            targetWheels.push(tgt);
                            wheels.push(makeDisplayWheel(w));
                        }
                        scope.wheels = wheels;
                        scope.envTemp = targetMeta.envTemp;
                        scope.trackTemp = targetMeta.trackTemp;
                        scope.rainState = targetMeta.rainState;
                        scope._dfN = targetMeta.totalDownforceN;
                        scope.aeroFracPct = targetMeta.aeroFracPct;
                        applyDisplayMeta();
                        if (!scope.$$phase) {
                            scope.$evalAsync(angular.noop);
                        }
                    } else {
                        for (i = 0; i < count; i++) {
                            setTargetWheel(targetWheels[i], src[i] || {});
                        }
                    }
                    startRaf();
                }

                scope.$on("$destroy", function () {
                    stopRaf();
                    document.removeEventListener("visibilitychange", onVisibilityChange);
                    if (StreamsManager) {
                        StreamsManager.remove(streamsList);
                    }
                });

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
