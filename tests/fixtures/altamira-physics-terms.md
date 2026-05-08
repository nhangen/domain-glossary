# Altamira Physics Terms Fixture

### Smooth phase boundaries

**Domain:** Altamira
**Citation:** `smooth_phase_boundaries` in `mtf-builder:scripts/pipeline/dtw_pipeline/combine_phases.py`
**Last verified:** 2026-05-08
**Aliases:** phase-boundary smoothing

The production phase-join repair path that stitches adjacent trajectory phases
while preserving continuity metrics at the join.

### Kinematics anchor

**Domain:** Altamira
**Citation:** `estimate_boundary_kinematics` in `mtf-builder:scripts/pipeline/core/stitching_methods.py`
**Last verified:** 2026-05-08
**Aliases:** endpoint kinematics, boundary derivatives

The position, velocity, and acceleration estimate used to constrain a boundary
bridge at a specific phase-join index.

### DTW threshold artifact

**Domain:** Altamira
**Citation:** `load_threshold_artifact` in `mtf-builder:scripts/pipeline/core/adapters.py`
**Last verified:** 2026-05-08
**Aliases:** calibration artifact, trust threshold artifact

The parsed and hashed per-class calibration file that allows DTW and MCMC
validation records to emit calibrated trust decisions instead of staying in
`not_calibrated` mode.
