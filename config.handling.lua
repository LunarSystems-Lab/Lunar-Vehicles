-- lunar-vehicles — handling multipliers (server script, not streamed to clients)
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Edit this file on the server. Values are clamped and sealed before the
-- client apply loop may use them.

Config.Handling = Config.Handling or {}

Config.Handling.globalAdd = {
    fSuspensionRaise = 0.038,
}

Config.Handling.global = {
    fInitialDriveForce = 0.90,
    fDriveInertia = 1.42,
    fInitialDragCoeff = 1.08,
    fSteeringLock = 1.16,
    fTractionCurveMax = 0.78,
    fTractionCurveMin = 0.71,
    fTractionCurveLateral = 0.86,
    fTractionSpringDeltaMax = 0.84,
    fLowSpeedTractionLossMult = 1.28,
    fTractionLossMult = 1.18,
    fTractionBiasFront = 1.03,
    fCamberStiffnesss = 0.90,
    fSuspensionForce = 0.56,
    fSuspensionCompDamp = 0.58,
    fSuspensionReboundDamp = 0.50,
    fSuspensionUpperLimit = 1.32,
    fSuspensionLowerLimit = 1.24,
    fAntiRollBarForce = 0.40,
    fRollCentreHeightFront = 0.88,
    fRollCentreHeightRear = 0.90,
    fBrakeForce = 0.94,
    fHandBrakeForce = 1.14,
    fCollisionDamageMult = 4.6,
    fWeaponDamageMult = 1.0,
    fDeformationDamageMult = 3.8,
    fEngineDamageMult = 4.2,
}

Config.Handling.kits = {
    engine = {
        D = { fInitialDriveForce = 1.00 },
        C = { fInitialDriveForce = 1.03 },
        B = { fInitialDriveForce = 1.07 },
        A = { fInitialDriveForce = 1.11 },
        S = { fInitialDriveForce = 1.16 },
        X = { fInitialDriveForce = 1.22 },
    },
    brakes = {
        E = { fBrakeForce = 1.00 },
        D = { fBrakeForce = 1.04 },
        C = { fBrakeForce = 1.08 },
        B = { fBrakeForce = 1.12 },
        A = { fBrakeForce = 1.16 },
        S = { fBrakeForce = 1.22 },
    },
    susp = {
        ['1'] = { fSuspensionForce = 1.04, fAntiRollBarForce = 1.04 },
        ['2'] = { fSuspensionForce = 1.08, fAntiRollBarForce = 1.08 },
        ['3'] = { fSuspensionForce = 1.12, fAntiRollBarForce = 1.12 },
        ['4'] = { fSuspensionForce = 1.16, fAntiRollBarForce = 1.16 },
    },
    trans = {
        D = { fClutchChangeRateScaleUpShift = 1.0, fClutchChangeRateScaleDownShift = 1.0 },
        C = { fClutchChangeRateScaleUpShift = 1.1, fClutchChangeRateScaleDownShift = 1.1 },
        B = { fClutchChangeRateScaleUpShift = 1.2, fClutchChangeRateScaleDownShift = 1.2 },
        A = { fClutchChangeRateScaleUpShift = 1.28, fClutchChangeRateScaleDownShift = 1.28 },
        S = { fClutchChangeRateScaleUpShift = 1.35, fClutchChangeRateScaleDownShift = 1.35 },
        X = { fClutchChangeRateScaleUpShift = 1.42, fClutchChangeRateScaleDownShift = 1.42 },
    },
}

Config.Handling.damage = {
    engineBelow = 500.0,
    engineForceMult = 0.22,
    bodyBelow = 600.0,
    tractionMult = 0.62,
    panelLimpTraction = 0.78,
    panelLimpSteer = 0.84,
    oilCriticalForce = 0.45,
}
