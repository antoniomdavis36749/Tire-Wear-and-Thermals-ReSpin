angular.module("beamng.apps")
    .directive("tyreWearThermalsMedium", ["$injector", function ($injector) {
        return {
            template: `
                <div class="ttm-panel-container">
                    <style>
                        .ttm-panel-container {
                            width: 100%;
                            height: 100%;
                            background: rgba(18, 22, 28, 0.90);
                            border: 1px solid rgba(255, 255, 255, 0.08);
                            border-radius: 6px;
                            box-sizing: border-box;
                            font-family: "Lucida Console", Monaco, monospace;
                            color: #f1f5f9;
                            overflow: auto;
                            padding: 12px;
                        }
                        .ttm-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 2px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 8px;
                            margin-bottom: 12px;
                            gap: 8px;
                            flex-wrap: wrap;
                        }
                        .ttm-title {
                            font-size: 13px;
                            font-weight: bold;
                            letter-spacing: 1.5px;
                            color: #38bdf8;
                        }
                        .ttm-header-meta {
                            font-size: 10px;
                            color: #94a3b8;
                            letter-spacing: 0.5px;
                        }
                        .ttm-grid {
                            display: grid;
                            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
                            gap: 12px;
                        }
                        .ttm-card {
                            background: rgba(30, 41, 59, 0.6);
                            border: 1px solid rgba(255, 255, 255, 0.04);
                            border-radius: 6px;
                            padding: 12px;
                            box-sizing: border-box;
                        }
                        .ttm-card-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 6px;
                            margin-bottom: 10px;
                        }
                        .ttm-wheel-name {
                            font-size: 14px;
                            font-weight: bold;
                            color: #38bdf8;
                        }
                        .ttm-compound-tag {
                            font-size: 10px;
                            background: rgba(56, 189, 248, 0.12);
                            border: 1px solid rgba(56, 189, 248, 0.2);
                            padding: 2px 6px;
                            border-radius: 4px;
                            text-transform: uppercase;
                            letter-spacing: 0.5px;
                        }
                        .ttm-stat-row {
                            display: flex;
                            justify-content: space-between;
                            margin-bottom: 6px;
                            font-size: 11px;
                        }
                        .ttm-label { color: #94a3b8; }
                        .ttm-value { font-weight: bold; }
                        .ttm-section-label {
                            font-size: 10px;
                            color: #94a3b8;
                            margin-top: 8px;
                            margin-bottom: 2px;
                        }
                        .ttm-thermal-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 4px;
                            margin: 6px 0 8px;
                            height: 24px;
                        }
                        .ttm-thermal-segment {
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 11px;
                            font-weight: bold;
                            border-radius: 3px;
                            text-shadow: 1px 1px 1px rgba(0,0,0,0.85);
                        }
                        .ttm-bar-container {
                            width: 100%;
                            background: rgba(255, 255, 255, 0.05);
                            border-radius: 3px;
                            height: 6px;
                            overflow: hidden;
                            margin-top: 3px;
                        }
                        .ttm-bar-fill {
                            height: 100%;
                            transition: width 0.1s ease-out;
                        }
                        .ttm-diagnostics-grid {
                            display: grid;
                            grid-template-columns: 1fr 1fr;
                            gap: 10px;
                            border-top: 1px dashed rgba(255, 255, 255, 0.08);
                            margin-top: 10px;
                            padding-top: 10px;
                        }
                        .ttm-diagnostic-item { font-size: 10px; }
                        .ttm-diag-label {
                            color: #64748b;
                            display: block;
                            margin-bottom: 3px;
                            font-size: 9px;
                            letter-spacing: 0.5px;
                        }
                        .ttm-footer {
                            font-size: 9px;
                            color: #64748b;
                            text-align: right;
                            margin-top: 8px;
                        }
                    </style>

                    <div class="ttm-header">
                        <span class="ttm-title">TYRE TELEMETRY (MEDIUM)</span>
                        <span class="ttm-header-meta">
                            Env {{ envTemp }}°C · Track {{ trackTemp }}°C · Rain {{ rainState }}%
                        </span>
                        <span class="ttm-header-meta">
                            <span style="color: #64748b;">Aero ↓</span>
                            <span style="color: #f59e0b; font-weight: bold;"> {{ totalDownforceKN }} kN</span>
                            <span style="color: #475569; font-size: 9px;"> ({{ aeroFracPct }}%)</span>
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
                                    {{ w.condition !== undefined ? w.condition.toFixed(1) : '0.0' }}%
                                </span>
                            </div>
                            <div class="ttm-bar-container" style="margin-bottom: 8px;">
                                <div class="ttm-bar-fill" ng-style="{'width': (w.condition || 0) + '%', 'background-color': getConditionColor(w.condition)}"></div>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Dynamic Grip:</span>
                                <span class="ttm-value" ng-style="{'color': getGripColor(w.tyreGrip)}">
                                    {{ ((w.tyreGrip || 0) * 100).toFixed(0) }}%
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Tire Pressure:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ w.pressure !== undefined ? w.pressure.toFixed(1) : '0.0' }} PSI
                                    </span>
                                    <span style="font-size: 9px; color: #64748b;">
                                        (Cold {{ w.coldPressure || w.initialPressure || 0 }} / Hot {{ w.targetHotPressure || w.optimalPressure || 0 }})
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
                                    {{ w.camber !== undefined ? w.camber.toFixed(2) : '0.00' }}° /
                                    {{ w.toe !== undefined ? w.toe.toFixed(2) : '0.00' }}°
                                </span>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Temp State / Opt:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': tempCategoryColor(w.tempCategory)}">{{ w.tempCategory || 'Normal' }}</span>
                                    <span style="color:#64748b;"> · avg {{ (w.avgTemp||0).toFixed(0) }}° / opt {{ (w.working_temp||0).toFixed(0) }}°</span>
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
                                    {{ (w.aeroLoadN || 0) >= 1000 ? ((w.aeroLoadN || 0) / 1000).toFixed(2) + ' kN' : (w.aeroLoadN || 0) + ' N' }}
                                </span>
                            </div>

                            <div class="ttm-section-label">Surface Heat Map (O | M | I):</div>
                            <div class="ttm-thermal-strip">
                                <div class="ttm-thermal-segment"
                                     ng-repeat="tempVal in w.surfaceTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ tempVal !== undefined ? tempVal.toFixed(0) : '0' }}°
                                </div>
                            </div>

                            <div class="ttm-section-label">Carcass Heat Map (O | M | I):</div>
                            <div class="ttm-thermal-strip">
                                <div class="ttm-thermal-segment"
                                     ng-repeat="tempVal in w.carcassTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ tempVal !== undefined ? tempVal.toFixed(0) : '0' }}°
                                </div>
                            </div>

                            <div class="ttm-stat-row">
                                <span class="ttm-label">Rim / Air:</span>
                                <span class="ttm-value">
                                    <span ng-style="{'color': getTempColor(w.rimTemp, w.working_temp)}">{{ (w.rimTemp || 0).toFixed(0) }}°</span>
                                    /
                                    <span ng-style="{'color': getTempColor(w.airTemp, w.working_temp)}">{{ (w.airTemp || 0).toFixed(0) }}°</span>
                                </span>
                            </div>

                            <div class="ttm-diagnostics-grid">
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">CLOG</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.clog)}">{{ w.clog || 0 }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.clog || 0) + '%', 'background-color': getDiagnosticColor(w.clog)}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">GRAINING</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.graining)}">{{ w.graining || 0 }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.graining || 0) + '%', 'background-color': getDiagnosticColor(w.graining)}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">BLISTER</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.blistering)}">{{ w.blistering || 0 }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.blistering || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">MARBLES</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.marbles)}">{{ w.marbles || 0 }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.marbles || 0) + '%', 'background-color': getDiagnosticColor(w.marbles)}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">FLATSPOT</span>
                                    <span class="ttm-value" ng-style="{'color': getDiagnosticColor(w.flatspot)}">{{ w.flatspot || 0 }}%</span>
                                    <div class="ttm-bar-container">
                                        <div class="ttm-bar-fill" ng-style="{'width': (w.flatspot || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="ttm-diagnostic-item">
                                    <span class="ttm-diag-label">LEAK / FILM</span>
                                    <span class="ttm-value">{{ w.leak || 0 }}% / {{ w.waterFilm || 0 }}%</span>
                                </div>
                            </div>

                            <div class="ttm-footer">
                                Cycles: <span style="color: #f1f5f9; font-weight: bold;">{{ w.cycles || 0 }}</span>
                                &nbsp;|&nbsp; Stint: <span style="color: #f1f5f9; font-weight: bold;">{{ w.stintFade || 0 }}%</span>
                                &nbsp;|&nbsp; Duct: <span style="color: #f1f5f9; font-weight: bold;">{{ w.ductPercent || 1 }}%</span>
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

                scope.$on("$destroy", function () {
                    if (StreamsManager) {
                        StreamsManager.remove(streamsList);
                    }
                });

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

                function processData(dataStream) {
                    if (!dataStream || !dataStream.data) return;

                    angular.forEach(dataStream.data, function (w) {
                        var t = w.temp || [];
                        w.surfaceTemps = [t[0] || 0, t[1] || 0, t[2] || 0];
                        w.carcassTemps = [t[3] || 0, t[4] || 0, t[5] || 0];
                        if (w.rimTemp === undefined) w.rimTemp = t[6] || 0;
                        if (w.airTemp === undefined) w.airTemp = t[7] || 0;
                    });

                    scope.$evalAsync(function () {
                        scope.wheels = dataStream.data;
                        scope.envTemp = dataStream.envTemp !== undefined ? dataStream.envTemp : scope.envTemp;
                        scope.trackTemp = dataStream.trackTemp !== undefined ? dataStream.trackTemp : scope.trackTemp;
                        scope.rainState = dataStream.rainState !== undefined ? dataStream.rainState : scope.rainState;
                        scope.totalDownforceKN = dataStream.totalDownforceN !== undefined
                            ? (dataStream.totalDownforceN / 1000).toFixed(2)
                            : scope.totalDownforceKN;
                        scope.aeroFracPct = dataStream.aeroFracPct !== undefined ? dataStream.aeroFracPct : scope.aeroFracPct;
                    });
                }

                scope.$on("TyreWearThermals", function (event, dataStream) {
                    processData(dataStream);
                });

                scope.$on("streamsUpdate", function (event, streams) {
                    if (streams && streams.TyreWearThermals) {
                        processData(streams.TyreWearThermals);
                    }
                });
            }
        };
    }]);
