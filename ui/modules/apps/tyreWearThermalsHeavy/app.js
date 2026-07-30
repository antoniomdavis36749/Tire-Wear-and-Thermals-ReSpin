angular.module("beamng.apps")
    .directive("tyreWearThermalsHeavy", ["$injector", function ($injector) {
        return {
            template: `
                <div class="tth-panel-container">
                    <style>
                        .tth-panel-container {
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
                        .tth-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 2px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 8px;
                            margin-bottom: 12px;
                        }
                        .tth-title {
                            font-size: 13px;
                            font-weight: bold;
                            letter-spacing: 1.5px;
                            color: #f59e0b;
                        }
                        .tth-grid {
                            display: grid;
                            grid-template-columns: repeat(auto-fit, minmax(290px, 1fr));
                            gap: 14px;
                        }
                        .tth-card {
                            background: rgba(30, 41, 59, 0.6);
                            border: 1px solid rgba(255, 255, 255, 0.04);
                            border-radius: 6px;
                            padding: 12px;
                            box-sizing: border-box;
                        }
                        .tth-card-header {
                            display: flex;
                            justify-content: space-between;
                            align-items: center;
                            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                            padding-bottom: 6px;
                            margin-bottom: 10px;
                        }
                        .tth-wheel-name {
                            font-size: 14px;
                            font-weight: bold;
                            color: #38bdf8;
                        }
                        .tth-compound-tag {
                            font-size: 10px;
                            background: rgba(56, 189, 248, 0.12);
                            border: 1px solid rgba(56, 189, 248, 0.2);
                            padding: 2px 6px;
                            border-radius: 4px;
                            text-transform: uppercase;
                            letter-spacing: 0.5px;
                        }
                        .tth-stat-row {
                            display: flex;
                            justify-content: space-between;
                            margin-bottom: 6px;
                            font-size: 11px;
                        }
                        .tth-label {
                            color: #94a3b8;
                        }
                        .tth-value {
                            font-weight: bold;
                        }
                        /* Segmented Thermal Display */
                        .tth-thermal-strip {
                            display: grid;
                            grid-template-columns: repeat(3, 1fr);
                            gap: 4px;
                            margin: 10px 0;
                            height: 26px;
                        }
                        .tth-thermal-segment {
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 11px;
                            font-weight: bold;
                            border-radius: 3px;
                            text-shadow: 1px 1px 1px rgba(0,0,0,0.85);
                        }
                        /* Progress and Health Bars */
                        .tth-bar-container {
                            width: 100%;
                            background: rgba(255, 255, 255, 0.05);
                            border-radius: 3px;
                            height: 6px;
                            overflow: hidden;
                            margin-top: 3px;
                        }
                        .tth-bar-fill {
                            height: 100%;
                            transition: width 0.1s ease-out;
                        }
                        /* Symmetrical Diagnostics Dashboard */
                        .tth-diagnostics-grid {
                            display: grid;
                            grid-template-columns: 1fr 1fr;
                            gap: 10px;
                            border-top: 1px dashed rgba(255, 255, 255, 0.08);
                            margin-top: 10px;
                            padding-top: 10px;
                        }
                        .tth-diagnostic-item {
                            font-size: 10px;
                        }
                        .tth-diag-label {
                            color: #64748b;
                            display: block;
                            margin-bottom: 3px;
                            font-size: 9px;
                            letter-spacing: 0.5px;
                        }
                    </style>

                    <div class="tth-header">
                        <span class="tth-title">TYRE TELEMETRY (HEAVY / TEST)</span>
                        <span style="font-size: 10px; color: #94a3b8; letter-spacing: 0.5px;">
                            Env {{ envTemp }}°C · Track {{ trackTemp }}°C · Rain {{ rainState }}% · Film {{ waterFilm }}%
                        </span>
                        <span style="font-size: 10px; letter-spacing: 0.5px;">
                            <span style="color: #64748b;">Aero ↓</span>
                            <span style="color: #f59e0b; font-weight: bold;">{{ totalDownforceKN }} kN</span>
                            <span style="color: #64748b; font-size: 9px;">({{ aeroFracPct }}% of load)</span>
                        </span>
                    </div>

                    <div class="tth-grid">
                        <div class="tth-card" ng-repeat="w in wheels">
                            <!-- Wheel Header -->
                            <div class="tth-card-header">
                                <span class="tth-wheel-name">{{ w.name }}</span>
                                <span class="tth-compound-tag">{{ formatProfile(w.profile) }}</span>
                            </div>

                            <!-- Structural Condition -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Tread Condition:</span>
                                <span class="tth-value" ng-style="{'color': getConditionColor(w.condition)}">
                                    {{ w.condition !== undefined ? w.condition.toFixed(1) : '0.0' }}%
                                </span>
                            </div>
                            <div class="tth-bar-container" style="margin-bottom: 10px;">
                                <div class="tth-bar-fill" ng-style="{'width': (w.condition || 0) + '%', 'background-color': getConditionColor(w.condition)}"></div>
                            </div>

                            <!-- Friction Grip Utilization -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Dynamic Grip:</span>
                                <span class="tth-value" ng-style="{'color': getGripColor(w.tyreGrip)}">
                                    {{ ((w.tyreGrip || 0) * 100).toFixed(0) }}%
                                </span>
                            </div>

                            <!-- Pressure setup: cold set vs live vs target hot -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Tire Pressure:</span>
                                <span class="tth-value">
                                    <span ng-style="{'color': getInflationColor(w.pressure, w.targetHotPressure || w.optimalPressure)}">
                                        {{ w.pressure !== undefined ? w.pressure.toFixed(1) : '0.0' }} PSI 
                                    </span>
                                    <span style="font-size: 9px; color: #64748b;">
                                        (Cold: {{ w.coldPressure || w.initialPressure || 0 }} / Hot tgt: {{ w.targetHotPressure || w.optimalPressure || 0 }})
                                    </span>
                                </span>
                            </div>

                            <!-- Zone wear O|M|I -->
                            <div class="tth-stat-row" style="margin-top: 6px;" ng-if="w.zoneCondition">
                                <span class="tth-label">Zone Wear O|M|I:</span>
                                <span class="tth-value" style="font-size: 10px;">
                                    {{ (w.zoneCondition[0]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[1]||0).toFixed(0) }}% |
                                    {{ (w.zoneCondition[2]||0).toFixed(0) }}%
                                </span>
                            </div>

                            <!-- Alignment Parameters -->
                            <div class="tth-stat-row">
                                <span class="tth-label">Camber / Toe:</span>
                                <span class="tth-value" ng-style="{'color': isExcessiveCamber(w.camber) ? '#ffaa44' : '#f1f5f9'}">
                                    {{ w.camber !== undefined ? w.camber.toFixed(2) : '0.00' }}° /
                                    {{ w.toe !== undefined ? w.toe.toFixed(2) : '0.00' }}°
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Temp State / Opt:</span>
                                <span class="tth-value">
                                    <span ng-style="{'color': tempCategoryColor(w.tempCategory)}">{{ w.tempCategory || 'Normal' }}</span>
                                    <span style="color:#64748b;"> · avg {{ (w.avgTemp||0).toFixed(0) }}° / opt {{ (w.working_temp||0).toFixed(0) }}°</span>
                                </span>
                            </div>

                            <!-- SURFACE CONTACT DATA -->
                            <div style="font-size: 10px; color: #f59e0b; margin-top: 10px; letter-spacing: 0.5px;">SURFACE CONTACT</div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Material / Class:</span>
                                <span class="tth-value" style="font-size: 10px;">
                                    {{ w.surfaceName || '—' }} · {{ formatProfile(w.surfaceType) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">μ static / slide:</span>
                                <span class="tth-value">{{ (w.muStatic||0).toFixed(2) }} / {{ (w.muSlide||0).toFixed(2) }}</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Depth / Rough / Flags:</span>
                                <span class="tth-value" style="font-size: 10px;">
                                    {{ (w.contactDepth||0).toFixed(3) }}m · r{{ (w.rough||0).toFixed(2) }}
                                    <span ng-if="w.airborne" style="color:#38bdf8;"> · AIR</span>
                                    <span ng-if="w.underWater" style="color:#38bdf8;"> · H2O</span>
                                </span>
                            </div>

                            <!-- Skin Thermal Distribution (Outer | Middle | Inner) -->
                            <div style="font-size: 10px; color: #94a3b8; margin-top: 10px;">Surface Heat Map (O | M | I):</div>
                            <div class="tth-thermal-strip">
                                <div class="tth-thermal-segment" 
                                     ng-repeat="tempVal in w.surfaceTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ tempVal !== undefined ? tempVal.toFixed(0) : '0' }}°
                                </div>
                            </div>

                            <!-- Carcass L/C/R (shoulders vs center) -->
                            <div style="font-size: 10px; color: #94a3b8; margin-top: 8px;">Carcass Heat Map (O | M | I):</div>
                            <div class="tth-thermal-strip">
                                <div class="tth-thermal-segment" 
                                     ng-repeat="tempVal in w.carcassTemps track by $index"
                                     ng-style="{'background-color': getTempColor(tempVal, w.working_temp), 'color': '#ffffff'}">
                                    {{ tempVal !== undefined ? tempVal.toFixed(0) : '0' }}°
                                </div>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Rim / Brake Soak:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.rimTemp, w.working_temp)}">
                                    {{ (w.rimTemp !== undefined ? w.rimTemp : 0).toFixed(1) }} °C
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Stock Brake (Surf / Core):</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.brakeSurface, 400)}">
                                    {{ (w.brakeSurface !== undefined ? w.brakeSurface : 0).toFixed(0) }} /
                                    {{ (w.brakeCore !== undefined ? w.brakeCore : 0).toFixed(0) }} °C
                                </span>
                            </div>

                            <div class="tth-stat-row">
                                <span class="tth-label">Internal Air Cavity:</span>
                                <span class="tth-value" ng-style="{'color': getTempColor(w.airTemp, w.working_temp)}">
                                    {{ (w.airTemp !== undefined ? w.airTemp : 0).toFixed(1) }} °C
                                </span>
                            </div>

                            <!-- TEST / PHYSICS CHANNELS -->
                            <div style="font-size: 10px; color: #f59e0b; margin-top: 10px; letter-spacing: 0.5px;">TEST CHANNELS</div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Load / Peak F:</span>
                                <span class="tth-value">{{ w.loadN || 0 }} N / {{ w.peakForce || 0 }} N</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Aero Downforce:</span>
                                <span class="tth-value" style="color: #f59e0b;">
                                    {{ (w.aeroLoadN || 0) >= 1000 ? ((w.aeroLoadN || 0) / 1000).toFixed(2) + ' kN' : (w.aeroLoadN || 0) + ' N' }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Grip long / lat:</span>
                                <span class="tth-value">{{ ((w.longGrip||0)*100).toFixed(0) }}% / {{ ((w.latGrip||0)*100).toFixed(0) }}%</span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Slip E / long / side:</span>
                                <span class="tth-value" style="font-size: 10px;">
                                    {{ (w.slipEnergy||0).toFixed(3) }} / {{ (w.longSlip||0).toFixed(3) }} / {{ (w.sideSlip||0).toFixed(3) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Susp z / vel / stress:</span>
                                <span class="tth-value" style="font-size: 10px;">
                                    {{ w.suspCompressionMm || 0 }}mm · {{ (w.suspVel||0).toFixed(2) }}m/s · {{ (w.suspStress||0).toFixed(2) }}
                                </span>
                            </div>
                            <div class="tth-stat-row">
                                <span class="tth-label">Bump / Droop / Rdyn:</span>
                                <span class="tth-value" style="font-size: 10px;">
                                    {{ w.suspBumpMm || 0 }} / {{ w.suspDroopMm || 0 }} mm · {{ (w.dynamicRadius||0).toFixed(3) }}m
                                </span>
                            </div>

                            <!-- Distinct surface modes -->
                            <div class="tth-diagnostics-grid">
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">CLOG</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.clog)}">{{ w.clog || 0 }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.clog || 0) + '%', 'background-color': getDiagnosticColor(w.clog)}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">GRAINING</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.graining)}">{{ w.graining || 0 }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.graining || 0) + '%', 'background-color': getDiagnosticColor(w.graining)}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">BLISTER</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.blistering)}">{{ w.blistering || 0 }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.blistering || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">MARBLES</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.marbles)}">{{ w.marbles || 0 }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.marbles || 0) + '%', 'background-color': getDiagnosticColor(w.marbles)}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">FLATSPOT</span>
                                    <span class="tth-value" ng-style="{'color': getDiagnosticColor(w.flatspot)}">{{ w.flatspot || 0 }}%</span>
                                    <div class="tth-bar-container">
                                        <div class="tth-bar-fill" ng-style="{'width': (w.flatspot || 0) + '%', 'background-color': '#f43f5e'}"></div>
                                    </div>
                                </div>
                                <div class="tth-diagnostic-item">
                                    <span class="tth-diag-label">LEAK / FILM</span>
                                    <span class="tth-value">{{ w.leak || 0 }}% / {{ w.waterFilm || 0 }}%</span>
                                </div>
                            </div>

                            <div style="font-size: 9px; color: #64748b; text-align: right; margin-top: 8px;">
                                Heat Cycles: <span style="color: #f1f5f9; font-weight: bold;">{{ w.cycles || 0 }}</span>
                                &nbsp;|&nbsp; Stint Fade: <span style="color: #f1f5f9; font-weight: bold;">{{ w.stintFade || 0 }}%</span>
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
                } else {
                    console.warn("tyreWearThermalsHeavy: StreamsManager service was not found in this injector context.");
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
                scope.waterFilm = 0;
                scope.totalDownforceKN = "0.00";
                scope.aeroFracPct = 0;

                scope.formatProfile = function (profile) {
                    if (!profile) return '';
                    return profile.replace(/_/g, ' ');
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

                // Specific color progression for physical surface damage states
                scope.getSurfaceDamageColor = function (value) {
                    if (!value || value <= 5) return "#94a3b8"; 
                    if (value <= 25) return "#38bdf8"; // Mild clogging/graining (Blue tint)
                    if (value <= 60) return "#f59e0b"; // Heavy debris or blister threshold (Orange)
                    return "#ef4444";                  // Severe blistering / high blowout warning (Red)
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

                scope.getTuningWarning = function (initialPressure, optimalPressure) {
                    var initialPres = initialPressure || 25;
                    var optPres = optimalPressure || 25;
                    
                    var underLimit = Math.min(optPres * 0.75, optPres - 5);
                    var overLimit = Math.max(optPres * 1.35, optPres + 6);
                    
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
                        // BeamNG streams Lua 1-based arrays as JS 0-based:
                        // [0..2]=skin, [3..5]=carcass, [6]=rim, [7]=air
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
                        scope.waterFilm = dataStream.waterFilm !== undefined ? dataStream.waterFilm : scope.waterFilm;
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