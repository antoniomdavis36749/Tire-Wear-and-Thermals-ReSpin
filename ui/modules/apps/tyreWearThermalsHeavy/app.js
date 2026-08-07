angular.module("beamng.apps")
    .directive("tyreWearThermalsHeavy", ["$injector", function ($injector) {
        return {
            template: `
                <div class="tth-panel-container">
                    <style>
                        .tth-panel-container {
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
                            padding: 9px;
                            pointer-events: auto;
                        }
                        .tth-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 2px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 6px;
                            margin-bottom: 9px;
                            gap: 6px;
                            flex-wrap: wrap;
                        }
                        .tth-title {
                            font-size: 11px;
                            font-weight: bold;
                            letter-spacing: 1.2px;
                            color: #f59e0b;
                        }
                        .tth-header-meta {
                            font-size: 9px;
                            color: #94a3b8;
                            letter-spacing: 0.4px;
                        }
                        .tth-grid {
                            display: grid;
                            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
                            gap: 10px;
                        }
                        .tth-card {
                            background: rgba(30, 41, 59, 0.6);
                            border: 1px solid rgba(255, 255, 255, 0.04);
                            border-radius: 5px;
                            padding: 9px;
                            box-sizing: border-box;
                        }
                        .tth-card-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 4px;
                            margin-bottom: 7px;
                        }
                        .tth-wheel-name {
                            font-size: 12px;
                            font-weight: bold;
                            color: #38bdf8;
                        }
                        .tth-compound-tag {
                            font-size: 9px;
                            background: rgba(56, 189, 248, 0.12);
                            border: 1px solid rgba(56, 189, 248, 0.2);
                            padding: 1px 5px;
                            border-radius: 3px;
                            text-transform: uppercase;
                            letter-spacing: 0.4px;
                        }
                        .tth-stat-row {
                            display: flex;
                            justify-content: space-between;
                            margin-bottom: 4px;
                            font-size: 10px;
                        }
                        .tth-label {
                            color: #94a3b8;
                        }
                        .tth-value {
                            font-weight: bold;
                        }
                        .tth-section-label {
                            font-size: 9px;
                            color: #f59e0b;
                            margin-top: 7px;
                            letter-spacing: 0.4px;
                        }
                        .tth-section-label-muted {
                            font-size: 9px;
                            color: #94a3b8;
                            margin-top: 7px;
                            margin-bottom: 1px;
                        }
                        /* Segmented Thermal Display */
                        .tth-thermal-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 3px;
                            margin: 5px 0;
                            height: 21px;
                        }
                        .tth-thermal-segment {
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 10px;
                            font-weight: bold;
                            border-radius: 3px;
                            text-shadow: 1px 1px 1px rgba(0,0,0,0.85);
                        }
                        /* Progress and Health Bars */
                        .tth-bar-container {
                            width: 100%;
                            background: rgba(255, 255, 255, 0.05);
                            border-radius: 3px;
                            height: 5px;
                            overflow: hidden;
                            margin-top: 2px;
                        }
                        .tth-bar-fill {
                            height: 100%;
                        }
                        /* Symmetrical Diagnostics Dashboard */
                        .tth-diagnostics-grid {
                            display: grid;
                            grid-template-columns: 1fr 1fr;
                            gap: 7px;
                            border-top: 1px dashed rgba(255, 255, 255, 0.08);
                            margin-top: 7px;
                            padding-top: 7px;
                        }
                        .tth-diagnostic-item {
                            font-size: 9px;
                        }
                        .tth-diag-label {
                            color: #64748b;
                            display: block;
                            margin-bottom: 2px;
                            font-size: 8px;
                            letter-spacing: 0.4px;
                        }
                        .tth-footer {
                            font-size: 8px;
                            color: #64748b;
                            text-align: right;
                            margin-top: 6px;
                        }
                    </style>

                    <div class="tth-header">
                        <span class="tth-title">TYRE TELEMETRY (PITWALL)</span>
                        <span class="tth-header-meta">
                            Env {{ (envTemp||0).toFixed(2) }}°C · Track {{ (trackTemp||0).toFixed(2) }}°C · Rain {{ (rainState||0).toFixed(2) }}% · Film {{ (waterFilm||0).toFixed(2) }}%
                        </span>
                        <span class="tth-header-meta">
                            <span style="color: #64748b;">Aero ↓</span>
                            <span style="color: #f59e0b; font-weight: bold;">{{ totalDownforceKN }} kN</span>
                            <span style="color: #64748b; font-size: 8px;">({{ (aeroFracPct||0).toFixed(2) }}% of load)</span>
                        </span>
                        <span class="tth-header-meta" style="width: 100%; color: #64748b;">
                            Elev {{ (elevationM||0).toFixed(2) }}m · ToD {{ timeOfDay }} · Cloud {{ (cloudCover||0).toFixed(2) }}% · Wake {{ (packWake||0).toFixed(2) }}% · Δair {{ (packAirDelta||0).toFixed(2) }}°
                            · Stream {{ (streamHz||0).toFixed(0) }} Hz · EnvΔ {{ (envTempRange||0).toFixed(2) }}°
                        </span>
                    </div>

                    <div class="tth-grid">
                        <div class="tth-card" ng-repeat="w in wheels">
                            <!-- Wheel Header -->
                            <div class="tth-card-header">
                                <span class="tth-wheel-name">{{ w.name }}</span>
                                <span style="display: flex; gap: 4px; align-items: center; flex-wrap: wrap; justify-content: flex-end;">
                                    <span class="tth-compound-tag">{{ formatProfile(w.compoundClass || w.profile) }}</span>
                                    <span class="tth-compound-tag" ng-if="w.purpose">{{ formatPurpose(w.purpose) }}</span>
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.profile1 || w.profile2" style="font-size: 8px; margin-top: -3px;">
                                <span class="tth-label">Profiles</span>
                                <span class="tth-value" style="font-size: 8px; color: #94a3b8;">
                                    {{ formatProfile(w.profile1) }} → {{ formatProfile(w.profile2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.classifyReason" style="font-size: 8px; margin-top: -2px;">
                                <span class="tth-label">Classify</span>
                                <span class="tth-value" style="font-size: 8px; color: #64748b;">{{ w.classifyReason }}</span>
                            </div>
                            <div class="tth-stat-row" ng-if="w.dutyMods" style="font-size: 8px; margin-top: -2px;">
                                <span class="tth-label">Duty mods</span>
                                <span class="tth-value" style="font-size: 8px; color: #64748b;">{{ formatDutyMods(w.dutyMods) }}</span>
                            </div>

                            <!-- Structural Condition -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Tread Condition:</span>
                                <span class="tth-value" ng-style="{'color': getConditionColor(w.condition)}">
                                    {{ (w.condition !== undefined ? w.condition : 0).toFixed(2) }}%
                                </span>
                            </div>
                            <div class="tth-bar-container" style="margin-bottom: 7px;">
                                <div class="tth-bar-fill" ng-style="{'width': (w.condition || 0) + '%', 'background-color': getConditionColor(w.condition)}"></div>
                            </div>

                            <!-- Friction Grip Utilization -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Dynamic Grip:</span>
                                <span class="tth-value" ng-style="{'color': getGripColor(w.tyreGrip)}">
                                    {{ ((w.tyreGrip || 0) * 100).toFixed(2) }}%
                                </span>
                            </div>

                            <!-- Pressure setup: cold set vs live vs target hot -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Tire Pressure:</span>
                                <span class="tth-value">
                                    <span ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ (w.pressure !== undefined ? w.pressure : 0).toFixed(2) }} PSI 
                                    </span>
                                    <span class="tth-compound-tag" style="margin-left: 4px;"
                                          ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ pressureBandLabel(w) }}
                                    </span>
                                    <span style="font-size: 8px; color: #64748b;">
                                        (Cold: {{ (w.coldPressure || w.initialPressure || 0).toFixed(2) }} / Hot tgt: {{ (w.targetHotPressure || w.optimalPressure || 0).toFixed(2) }}
                                        · r{{ (w.pressureRatio || 0).toFixed(2) }}
                                        · Lua {{ (w.luaPressure !== undefined ? w.luaPressure : w.pressure || 0).toFixed(1) }}
                                        → Nat {{ (w.nativePressure !== undefined ? w.nativePressure : w.pressure || 0).toFixed(1) }}
                                        <span ng-style="{'color': pressureConvColor(w)}"> Δ{{ pressureDeltaAbs(w) }}</span>)
                                    </span>
                                </span>
                            </div>

                            <!-- Zone wear O|M|I -->
                            <div class="tth-stat-row" style="margin-top: 4px;" ng-if="w.zoneCondition">
                                <span class="tth-label">Zone Wear O|M|I:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ (w.zoneCondition[0]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[1]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[2]||0).toFixed(0) }}%
                                </span>
                            </div>

                            <!-- Alignment Parameters -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Camber / Toe:</span>
                                <span class="tth-value" ng-style="{'color': isExcessiveCamber(w.camber) ? '#ffaa44' : '#f1f5f9'}">
                                    {{ (w.camber !== undefined ? w.camber : 0).toFixed(2) }}° /
                                    {{ (w.toe !== undefined ? w.toe : 0).toFixed(2) }}°
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Temp State / Opt:</span>
                                <span class="tth-value">
                                    <span ng-style="{'color': tempCategoryColor(w.tempCategory)}">{{ w.tempCategory || 'Normal' }}</span>
                                    <span style="color:#64748b;"> · avg {{ (w.avgTemp||0).toFixed(2) }}° / opt {{ (w.working_temp||0).toFixed(2) }}°</span>
                                </span>
                            </div>

                            <!-- SURFACE CONTACT DATA -->
                            <div class="tth-section-label">SURFACE CONTACT</div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Material / Class:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ w.surfaceName || '—' }} · {{ formatProfile(w.surfaceType) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">μ static / slide:</span>
                                <span class="tth-value">{{ (w.muStatic||0).toFixed(2) }} / {{ (w.muSlide||0).toFixed(2) }}</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Depth / Rough / Flags:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ (w.contactDepth||0).toFixed(2) }}m · r{{ (w.rough||0).toFixed(2) }}
                                    <span ng-if="w.airborne" style="color:#38bdf8;"> · AIR</span>
                                    <span ng-if="w.underWater" style="color:#38bdf8;"> · H2O</span>
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Patch / Heat / DepthBoost:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ (w.patchFrac||0).toFixed(3) }} × {{ (w.patchHeatScale||1).toFixed(2) }}
                                    · boost{{ (w.depthHeatBoost||1).toFixed(2) }}
                                    <span style="color:#64748b;">
                                        · Hz{{ (w.hertzArea||0).toFixed(4) }} / defl{{ (w.deflArea||0).toFixed(4) }}
                                        · blend{{ (w.depthBlend||0).toFixed(2) }}
                                    </span>
                                </span>
                            </div>

                            <!-- Skin Thermal Distribution (Outer | Middle | Inner) -->
                            <div class="tth-section-label-muted">Surface Heat Map (O | M | I):</div>
                            <div class="tth-thermal-strip">
                                <div class="tth-thermal-segment" 
                                     ng-repeat="tempVal in w.surfaceTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(2) }}°
                                </div>
                            </div>

                            <!-- Carcass L/C/R (shoulders vs center) -->
                            <div class="tth-section-label-muted" style="margin-top: 5px;">Carcass Heat Map (O | M | I):</div>
                            <div class="tth-thermal-strip">
                                <div class="tth-thermal-segment" 
                                     ng-repeat="tempVal in w.carcassTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ (tempVal !== undefined ? tempVal : 0).toFixed(2) }}°
                                </div>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Rim / Brake Soak:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.rimTemp, w.working_temp)}">
                                    {{ (w.rimTemp !== undefined ? w.rimTemp : 0).toFixed(2) }} °C
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Stock Brake (Surf / Core):</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.brakeSurface, 400)}">
                                    {{ (w.brakeSurface !== undefined ? w.brakeSurface : 0).toFixed(2) }} /
                                    {{ (w.brakeCore !== undefined ? w.brakeCore : 0).toFixed(2) }} °C
                                    <span style="font-size: 8px; color: #64748b;">
                                        · η{{ ((w.brakeThermalEfficiency !== undefined ? w.brakeThermalEfficiency : 1) * 100).toFixed(0) }}%
                                    </span>
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Brake→rim soak:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ ((w.brakeSoakRateCs !== undefined ? w.brakeSoakRateCs : 0) >= 0 ? '+' : '') }}{{ (w.brakeSoakRateCs !== undefined ? w.brakeSoakRateCs : 0).toFixed(2) }} °C/s
                                    · duct air×{{ (w.ductAirCoolFactor !== undefined ? w.ductAirCoolFactor : 1).toFixed(2) }}
                                    / soak×{{ (w.ductSoakCondFactor !== undefined ? w.ductSoakCondFactor : 1.15).toFixed(2) }}
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Internal Air Cavity:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.airTemp, w.working_temp)}">
                                    {{ (w.airTemp !== undefined ? w.airTemp : 0).toFixed(2) }} °C
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Skin−carcass gap:</span>
                                <span class="tth-value" ng-style="{'color': isLargeSkinGap(w.skinCarcassGap) ? '#f59e0b' : '#f1f5f9'}">
                                    {{ (w.skinCarcassGap !== undefined ? w.skinCarcassGap : 0).toFixed(2) }} °C
                                </span>
                            </div>

                            <!-- TEST / PHYSICS CHANNELS -->
                            <div class="tth-section-label">TEST CHANNELS</div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Drive heat gate S/C:</span>
                                <span class="tth-value">
                                    {{ ((w.driveHeatGate||0)*100).toFixed(2) }}% /
                                    {{ ((w.driveHeatGateCarcass||0)*100).toFixed(2) }}%
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Load / Peak F:</span>
                                <span class="tth-value">{{ (w.loadN || 0).toFixed(2) }} N / {{ (w.peakForce || 0).toFixed(2) }} N</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Aero Downforce:</span>
                                <span class="tth-value" style="color: #f59e0b;">
                                    {{ (w.aeroLoadN || 0) >= 1000 ? ((w.aeroLoadN || 0) / 1000).toFixed(2) + ' kN' : (w.aeroLoadN || 0).toFixed(2) + ' N' }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Grip long / lat:</span>
                                <span class="tth-value">{{ ((w.longGrip||0)*100).toFixed(2) }}% / {{ ((w.latGrip||0)*100).toFixed(2) }}%</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Slip E / long / side:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ (w.slipEnergy||0).toFixed(2) }} / {{ (w.longSlip||0).toFixed(2) }} / {{ (w.sideSlip||0).toFixed(2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Susp z / vel / stress:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ (w.suspCompressionMm || 0).toFixed(2) }}mm · {{ (w.suspVel||0).toFixed(2) }}m/s · {{ (w.suspStress||0).toFixed(2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Bump / Droop / Rdyn:</span>
                                <span class="tth-value" style="font-size: 9px;">
                                    {{ (w.suspBumpMm || 0).toFixed(2) }} / {{ (w.suspDroopMm || 0).toFixed(2) }} mm · {{ (w.dynamicRadius||0).toFixed(2) }}m
                                </span>
                            </div>

                            <!-- Distinct surface modes -->
                            <div class="tth-diagnostics-grid">
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">CLOG</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.clog)}">{{ (w.clog || 0).toFixed(0) }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.clog || 0) + '%', 'background-color': getDiagnosticColor(w.clog)}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">GRAINING</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.graining)}">{{ (w.graining || 0).toFixed(0) }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.graining || 0) + '%', 'background-color': getDiagnosticColor(w.graining)}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">BLISTER</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.blistering)}">{{ (w.blistering || 0).toFixed(0) }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.blistering || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">FLATSPOT</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.flatspot)}">{{ (w.flatspot || 0).toFixed(0) }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.flatspot || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">LEAK / FILM</span>
                                    <span class="tth-value">{{ (w.leak || 0).toFixed(0) }}% / {{ (w.waterFilm || 0).toFixed(0) }}%</span>
                                </div>
                            </div>

                            <div class="tth-footer">
                                Heat Cycles: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.cycles || 0).toFixed(0) }}</span>
                                &nbsp;|&nbsp; Stint Fade: <span style="color: #f1f5f9; font-weight: bold;">{{ (w.stintFade || 0).toFixed(0) }}%</span>
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
                } else {
                    console.warn("tyreWearThermalsHeavy: StreamsManager service was not found in this injector context.");
                }

                // Client-side smooth motion: Lua ~30 Hz; RAF lerps display toward targets.
                // Digest is throttled (~20 Hz): full $digest every RAF stalls CEF under Heavy binding load.
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
                    waterFilm: 0,
                    totalDownforceN: 0,
                    aeroFracPct: 0,
                    elevationM: 0,
                    timeOfDay: 0,
                    cloudCover: 0,
                    packWake: 0,
                    packAirDelta: 0,
                    envTempRange: 0
                };
                var WHEEL_LERP_KEYS = [
                    "condition", "tyreGrip", "pressure", "pressureRatio", "camber", "toe", "avgTemp",
                    "working_temp", "rimTemp", "airTemp", "aeroLoadN", "skinCarcassGap",
                    "brakeSurface", "brakeCore", "brakeThermalEfficiency", "brakeSoakRateCs",
                    "ductAirCoolFactor", "ductSoakCondFactor",
                    "driveHeatGate", "driveHeatGateCarcass",
                    "loadN", "peakForce", "longGrip", "latGrip",
                    "slipEnergy", "longSlip", "sideSlip",
                    "suspCompressionMm", "suspVel", "suspStress", "suspBumpMm", "suspDroopMm", "dynamicRadius",
                    "muStatic", "muSlide", "contactDepth", "rough",
                    "patchFrac", "patchHeatScale", "depthHeatBoost", "hertzArea", "deflArea", "depthBlend",
                    "clog", "graining", "blistering", "flatspot", "leak", "waterFilm",
                    "stintFade", "ductPercent", "luaPressure", "nativePressure", "pressureDelta"
                ];

                scope.wheels = [];
                scope.envTemp = 21;
                scope.trackTemp = 21;
                scope.rainState = 0;
                scope.waterFilm = 0;
                scope.totalDownforceKN = "0.00";
                scope.aeroFracPct = 0;
                scope.elevationM = 0;
                scope.timeOfDay = "0.00";
                scope.cloudCover = 0;
                scope.packWake = 0;
                scope.packAirDelta = 0;
                scope.streamHz = 30;
                scope.envTempRange = 0;
                scope._dfN = 0;
                scope._tod = 0;

                scope.formatProfile = function (profile) {
                    if (!profile) return '';
                    return String(profile).replace(/_/g, ' ');
                };

                scope.formatPurpose = function (purpose) {
                    if (!purpose) return '';
                    return String(purpose).replace(/_/g, ' ').replace(/\b\w/g, function (c) {
                        return c.toUpperCase();
                    });
                };

                var DUTY_MOD_LABELS = {
                    fwd_slip_softcap: 'FWD slip soft-cap',
                    street_slip_softcap: 'Street slip soft-cap',
                    sport_plus_slip_softcap: 'Sport+ slip soft-cap',
                    street_high_v_damp: 'High-V street damp',
                    undriven_warmup: 'Undriven warm-up',
                    awd_prop_gate: 'AWD prop gate',
                    brake_tire_soak: 'Brake tire soak',
                    duct_tire_side: 'Duct tire-side',
                    soft_sink_damp: 'Soft-sink damp'
                };

                scope.formatDutyMod = function (id) {
                    if (!id) return '';
                    return DUTY_MOD_LABELS[id] || String(id).replace(/_/g, ' ');
                };

                scope.formatDutyMods = function (dutyMods) {
                    if (!dutyMods) return '';
                    var parts = String(dutyMods).split(',');
                    var labels = [];
                    var i, id;
                    for (i = 0; i < parts.length; i++) {
                        id = parts[i].replace(/^\s+|\s+$/g, '');
                        if (!id) continue;
                        labels.push(scope.formatDutyMod(id));
                    }
                    return labels.join(' · ');
                };

                scope.isLargeSkinGap = function (gap) {
                    return Math.abs(gap || 0) > 15;
                };

                scope.pressureBandLabel = function (w) {
                    var opt = (w && (w.targetHotPressure || w.optimalPressure)) || 25;
                    if (opt <= 0) opt = 25;
                    var pressure = (w && w.pressure) || 0;
                    var ratio = pressure / opt;
                    if (pressure < 5) return "FLAT";
                    if (ratio < 0.70) return "LOW";
                    if (ratio < 0.86) return "UNDER";
                    if (ratio <= 1.04) return "OPT";
                    if (ratio <= 1.32) return "WARM+";
                    if (ratio <= 1.55) return "OVER";
                    return "HIGH";
                };

                // |Lua−Nat| for hot write-back convergence (green when tight, amber while catching up)
                scope.pressureDeltaAbs = function (w) {
                    var d = (w && w.pressureDelta !== undefined)
                        ? w.pressureDelta
                        : ((w && w.luaPressure !== undefined ? w.luaPressure : 0) - (w && w.nativePressure !== undefined ? w.nativePressure : 0));
                    return Math.abs(d || 0).toFixed(1);
                };
                scope.pressureConvColor = function (w) {
                    var d = Math.abs((w && w.pressureDelta !== undefined)
                        ? w.pressureDelta
                        : ((w && w.luaPressure !== undefined ? w.luaPressure : 0) - (w && w.nativePressure !== undefined ? w.nativePressure : 0)));
                    if (d <= 0.2) return "#10b981"; // converged (within ~deadband)
                    if (d <= 1.0) return "#94a3b8"; // closing in
                    return "#f59e0b"; // warm-up lag / write-back catching Nat
                };

                scope.tempCategoryColor = function (cat) {
                    if (cat === 'Cold') return '#38bdf8';
                    if (cat === 'Hot') return '#ef4444';
                    return '#10b981';
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

                scope.getSurfaceDamageColor = function (value) {
                    if (!value || value <= 5) return "#94a3b8";
                    if (value <= 25) return "#38bdf8";
                    if (value <= 60) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getInflationColor = function (pressure, optimalPressure) {
                    if (pressure === undefined) return "#f1f5f9";
                    var opt = optimalPressure || 25;
                    if (opt <= 0) opt = 25;
                    var ratio = pressure / opt;
                    if (pressure < 5) return "#ef4444";
                    if (ratio < 0.70) return "#38bdf8";
                    if (ratio < 0.86) return "#a3e635";
                    if (ratio <= 1.04) return "#10b981";
                    if (ratio <= 1.32) return "#34d399";
                    if (ratio <= 1.55) return "#f59e0b";
                    return "#ef4444";
                };

                scope.getTuningWarning = function (initialPressure, optimalPressure) {
                    var initialPres = initialPressure || 25;
                    var optPres = optimalPressure || 25;
                    var underLimit = Math.min(optPres * 0.86, optPres - 4);
                    var overLimit = Math.max(optPres * 1.32, optPres + 8);
                    if (initialPres < underLimit) {
                        return "UNDERINFLATED";
                    } else if (initialPres > overLimit) {
                        return "OVERINFLATED";
                    }
                    return "";
                };

                scope.getTempColor = function (tempVal, working_temp) {
                    if (tempVal === undefined) return "hsla(240, 80%, 45%, 1)";
                    var r = tempVal / (working_temp || 85);
                    var hue;
                    if (r < 0.75) {
                        var tCold = Math.min(Math.max((r - 0.4) / 0.35, 0), 1);
                        tCold = tCold * tCold * (3 - 2 * tCold);
                        hue = 240 - tCold * 120;
                    } else if (r <= 1.10) {
                        hue = 120;
                    } else {
                        var tHot = Math.min(Math.max((r - 1.10) / 0.30, 0), 1);
                        tHot = tHot * tHot * (3 - 2 * tHot);
                        hue = 120 - tHot * 120;
                    }
                    return "hsla(" + Math.round(hue) + ", 80%, 45%, 1)";
                };

                function lerpNum(cur, tgt, alpha) {
                    if (tgt === undefined || tgt === null) return cur;
                    if (cur === undefined || cur === null) return tgt;
                    var next = cur + (tgt - cur) * alpha;
                    return Math.abs(tgt - next) < LERP_EPS ? tgt : next;
                }

                function isLerpKey(k) {
                    return WHEEL_LERP_KEYS.indexOf(k) !== -1;
                }

                function prepareWheelTemps(w) {
                    var t = w.temp || [];
                    w.surfaceTemps = [t[0] || 0, t[1] || 0, t[2] || 0];
                    w.carcassTemps = [t[3] || 0, t[4] || 0, t[5] || 0];
                    if (w.rimTemp === undefined) w.rimTemp = t[6] || 0;
                    if (w.airTemp === undefined) w.airTemp = t[7] || 0;
                    if (!w.zoneCondition || w.zoneCondition.length !== 3) {
                        var c = w.condition !== undefined ? w.condition : 100;
                        w.zoneCondition = [c, c, c];
                    }
                }

                function copyArr3(src, fallback) {
                    var a = src || fallback || [0, 0, 0];
                    return [a[0] || 0, a[1] || 0, a[2] || 0];
                }

                // Full shallow wheel copy so Heavy keeps every stream field; arrays are cloned.
                function cloneWheel(src) {
                    var dst = {};
                    var k;
                    for (k in src) {
                        if (!Object.prototype.hasOwnProperty.call(src, k)) continue;
                        if (k === "surfaceTemps" || k === "carcassTemps" || k === "zoneCondition" || k === "temp") continue;
                        dst[k] = src[k];
                    }
                    dst.temp = (src.temp && src.temp.slice) ? src.temp.slice() : [];
                    dst.surfaceTemps = copyArr3(src.surfaceTemps);
                    dst.carcassTemps = copyArr3(src.carcassTemps);
                    dst.zoneCondition = copyArr3(src.zoneCondition, [100, 100, 100]);
                    return dst;
                }

                function syncNonLerp(dst, src) {
                    var k;
                    for (k in src) {
                        if (!Object.prototype.hasOwnProperty.call(src, k)) continue;
                        if (isLerpKey(k)) continue;
                        if (k === "surfaceTemps" || k === "carcassTemps" || k === "zoneCondition" || k === "temp") continue;
                        dst[k] = src[k];
                    }
                }

                function setTargetWheel(dst, src) {
                    var k, i;
                    syncNonLerp(dst, src);
                    for (i = 0; i < WHEEL_LERP_KEYS.length; i++) {
                        k = WHEEL_LERP_KEYS[i];
                        dst[k] = src[k] !== undefined && src[k] !== null ? src[k] : 0;
                    }
                    dst.temp = (src.temp && src.temp.slice) ? src.temp.slice() : [];
                    dst.surfaceTemps = copyArr3(src.surfaceTemps);
                    dst.carcassTemps = copyArr3(src.carcassTemps);
                    dst.zoneCondition = copyArr3(src.zoneCondition, [100, 100, 100]);
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
                    scope.timeOfDay = Number(scope._tod || 0).toFixed(2);
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

                    prev = scope.waterFilm;
                    scope.waterFilm = lerpNum(scope.waterFilm, targetMeta.waterFilm, alpha);
                    if (scope.waterFilm !== prev) moved = true;

                    prev = scope._dfN;
                    scope._dfN = lerpNum(scope._dfN || 0, targetMeta.totalDownforceN, alpha);
                    if (scope._dfN !== prev) moved = true;

                    prev = scope.aeroFracPct;
                    scope.aeroFracPct = lerpNum(scope.aeroFracPct, targetMeta.aeroFracPct, alpha);
                    if (scope.aeroFracPct !== prev) moved = true;

                    prev = scope.elevationM;
                    scope.elevationM = lerpNum(scope.elevationM, targetMeta.elevationM, alpha);
                    if (scope.elevationM !== prev) moved = true;

                    prev = scope._tod;
                    scope._tod = lerpNum(scope._tod || 0, targetMeta.timeOfDay, alpha);
                    if (scope._tod !== prev) moved = true;

                    prev = scope.cloudCover;
                    scope.cloudCover = lerpNum(scope.cloudCover, targetMeta.cloudCover, alpha);
                    if (scope.cloudCover !== prev) moved = true;

                    prev = scope.packWake;
                    scope.packWake = lerpNum(scope.packWake, targetMeta.packWake, alpha);
                    if (scope.packWake !== prev) moved = true;

                    prev = scope.packAirDelta;
                    scope.packAirDelta = lerpNum(scope.packAirDelta, targetMeta.packAirDelta, alpha);
                    if (scope.packAirDelta !== prev) moved = true;

                    prev = scope.envTempRange;
                    scope.envTempRange = lerpNum(scope.envTempRange, targetMeta.envTempRange, alpha);
                    if (scope.envTempRange !== prev) moved = true;

                    var n = Math.min(scope.wheels.length, targetWheels.length);
                    for (i = 0; i < n; i++) {
                        d = scope.wheels[i];
                        t = targetWheels[i];
                        syncNonLerp(d, t);
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
                    targetMeta.waterFilm = dataStream.waterFilm !== undefined ? dataStream.waterFilm : targetMeta.waterFilm;
                    targetMeta.totalDownforceN = dataStream.totalDownforceN !== undefined ? dataStream.totalDownforceN : targetMeta.totalDownforceN;
                    targetMeta.aeroFracPct = dataStream.aeroFracPct !== undefined ? dataStream.aeroFracPct : targetMeta.aeroFracPct;
                    targetMeta.elevationM = dataStream.elevationM !== undefined ? dataStream.elevationM : targetMeta.elevationM;
                    targetMeta.timeOfDay = dataStream.timeOfDay !== undefined ? Number(dataStream.timeOfDay) : targetMeta.timeOfDay;
                    targetMeta.cloudCover = dataStream.cloudCover !== undefined ? dataStream.cloudCover : targetMeta.cloudCover;
                    targetMeta.packWake = dataStream.packWake !== undefined ? dataStream.packWake : targetMeta.packWake;
                    targetMeta.packAirDelta = dataStream.packAirDelta !== undefined ? dataStream.packAirDelta : targetMeta.packAirDelta;
                    targetMeta.envTempRange = dataStream.envTempRange !== undefined ? dataStream.envTempRange : targetMeta.envTempRange;

                    if (dataStream.streamHz !== undefined) scope.streamHz = dataStream.streamHz;

                    if (structural) {
                        targetWheels = [];
                        var wheels = [];
                        for (i = 0; i < count; i++) {
                            w = src[i] || {};
                            targetWheels.push(cloneWheel(w));
                            wheels.push(cloneWheel(w));
                        }
                        scope.wheels = wheels;
                        scope.envTemp = targetMeta.envTemp;
                        scope.trackTemp = targetMeta.trackTemp;
                        scope.rainState = targetMeta.rainState;
                        scope.waterFilm = targetMeta.waterFilm;
                        scope._dfN = targetMeta.totalDownforceN;
                        scope.aeroFracPct = targetMeta.aeroFracPct;
                        scope.elevationM = targetMeta.elevationM;
                        scope._tod = targetMeta.timeOfDay;
                        scope.cloudCover = targetMeta.cloudCover;
                        scope.packWake = targetMeta.packWake;
                        scope.packAirDelta = targetMeta.packAirDelta;
                        scope.envTempRange = targetMeta.envTempRange;
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
