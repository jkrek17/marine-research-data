# marine-research-data
Bulk model and truth fields for the marine research kit (GitHub Releases as storage)

## Layout

Model fields for the marine research kit (`rk/` in jkrek17/marine-research). They are stored as GitHub Release assets, not in git.

- **Release** per basin and month, tag `fields-{basin}-{YYYYMM}`, e.g. `fields-natl-202511`. Basins: `natl`, `npac`.
- **Asset** per basin-cycle, `{basin}_{YYYYMMDDHH}.zip`: a `ZIP_STORED` zip (the npz files are already compressed) holding that cycle's files, flat, as `{name}.npz`:
  - `{gfs,ifs,aifs}_fFFF.npz`: `u`, `v` (float16, m/s), `msl` (float32, hPa)
  - `{gefs,ens,aifs-ens}_fFFF.npz`: `mean_u`, `mean_v`, `spd_mean`, `spd_std`, `p34`, `p48`, `p64`, `msl_mean`, `msl_std`, `n`
  - other names added by studies, e.g. `gfs_low_f024.npz`; steps beyond f120 and 06/18 UTC steps (`f030`, `f054`, ...) use the same pattern
- **Read URL** (public, no auth): `https://github.com/jkrek17/marine-research-data/releases/download/{tag}/{asset}`

### Truth

The kit's truth files (`rk.truth`, `rk.store.truth_*`) live in releases too, as plain npz assets, one per valid time or day:

| Kind | Release tag | Asset | Contents |
|---|---|---|---|
| analysis | `truth-analysis-{basin}-{YYYYMM}` | `{YYYYMMDDHH}.npz` | GFS and IFS step-0 u, v, MSLP, mean speed, open-water mask |
| obs | `truth-obs-{basin}-{YYYYMM}` | `{YYYYMMDDHH}.npz` | ship and buoy winds rebuilt from the GDAS marine csv |
| airsea | `truth-airsea-{basin}-{YYYYMM}` | `{YYYYMMDDHH}.npz` | GFS 2 m air and skin temperature |
| ascat | `truth-ascat-{YYYYMM}` | `{YYYYMMDD}.npz` | RSS ASCAT cells of the UTC day, both basins |
| smap | `truth-smap-{YYYYMM}` | `{YYYYMMDD}.npz` | RSS SMAP L3 daily cells (`final` 1 FINAL, 0 NRT), both basins |
| gridsat | `truth-gridsat-{basin}-{YYYYMM}` | `{YYYYMMDDHH}.npz` | GridSat-B1 11 um IR brightness temperature over the basin box with margins (`rk.satellite.box`), int16, 00/06/12/18 UTC |
| airmass | `truth-airmass-{basin}-{YYYYMM}` | `{YYYYMMDDHH}.npz` | GOES ABI bands 8, 10, 12, 13 (air-mass RGB inputs) over the basin box with margins (`rk.satellite.airmass_box`), int16, 00/06/12/18 UTC |

The month is the month of the valid time or day. A release holds at most about 124 assets (4 valid times a day). Read URL: `https://github.com/jkrek17/marine-research-data/releases/download/{tag}/{asset}`. The OPC hurricane-force low fixes (hf-low CSVs) are not here: `rk.truth.hf_archive` reads them from the hf-low repo over HTTPS.

### Lab inputs

Release `lab-assets` holds the fixed inputs of the wxmap.pro lab job (`rk.store.lab_asset(name)` in the kit), one npz per name, replaced in place when rebuilt:

| Asset | Contents |
|---|---|
| `twins_library.npz` | Storm Twins library: 32,288 ERA5 pipeline A fixes (a proxy), Oct-Apr 2014-15..2021-22, 15 pattern components and gust class each |
| `twins_clim0012.npz` | WeatherBench2 1990-2019 climatology of z500, MSLP, u250, v250 at 00 and 12 UTC on the 1.5 degree grid (float16) |
| `twins_pca.npz` | the frozen scaler, mask and 15-component PCA (hf-low `storm_patch_analogs/gfs/results/frozen_pca_full.npz`) |

### Reading

Normally through the kit: `rk.store.load_det / load_ens / load` check the local cache (`RK_CACHE`, default `~/.cache/marine-research`), then download and unpack the cycle's zip. By hand:

```python
import io, urllib.request, zipfile, numpy as np
url = "https://github.com/jkrek17/marine-research-data/releases/download/fields-natl-202511/natl_2025111212.zip"
z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(url).read()))
d = np.load(io.BytesIO(z.read("gfs_f024.npz")))
u, v, msl = d["u"], d["v"], d["msl"]
```

### Writing

Never by hand and never to `main`. Two routes, both through `tools/publish_store.py` in marine-research, which merges each file with what is already published (so nothing another thread published is dropped):

1. A session pushes a branch `upload/<utc-timestamp>-<n>` holding `incoming/{basin}/{YYYYMMDDHH}.zip` (fields) and `incoming/truth/{kind}/[{basin}/]{stem}.npz` (truth). `.github/workflows/publish.yml` uploads them with `scripts/upload_incoming.sh` and deletes the branch.
2. The scheduled jobs write the same layout to a folder (`publish_store.py --direct`) and call `scripts/upload_incoming.sh` themselves, with the job's `GITHUB_TOKEN`.

`scripts/upload_incoming.sh <folder>` is the one upload step: it creates a missing release, then uploads each file with `--clobber`. `.gitignore` blocks `*.npz` on main.

### Scheduled jobs

All three clone jkrek17/marine-research without a token (it has to be public). `fill.yml` and `truth.yml` share the concurrency group `ecmwf-pull`, so only one heavy pull runs at a time; `scores.yml` only reads the store and has its own group.

- `fill.yml`, 10:15 and 22:15 UTC (and on demand: start, end, models, steps): GFS, GEFS, IFS, AIFS, ENS, AIFS ENS for the 00 and 12 UTC cycles of the last 14 days, steps 24-120, the 06/18 UTC-valid steps (30, 54, 78, 102, 126) and day 5-7 steps for gfs/ifs/aifs (36, 60, 84, 108, 132, 144, 156, 168). Already published cycles are not fetched again. An ensemble step is stored only with all its members, and cycles younger than 8 h are not tried, so a cycle whose ENS is still being posted is filled by the next run.
- `truth.yml`, 04:00 UTC (and on demand): analyses, air-sea, obs, ASCAT and SMAP for days 3 to 16 back.
- `scores.yml`, Mondays 06:00 UTC (and on demand: start, end as YYYYMMDD, kit_ref): the standing scores, see below.

Limits to stay under: 2 GB per asset, 1000 assets per release. A cycle is about 10-15 MB, a fields release about 60 assets, a truth release at most about 124.

### Standing scores

`scores.yml` runs `tools/run_presets.py` of the kit (every `studies/*/preset.py`, which re-score a finished study's frozen method) on the newest 8 ISO weeks, ending at the most recent Sunday at least 3 days back (ASCAT lags about 2 days). Reads come from the releases above; nothing in them is changed. The history is built up, not recomputed: before publishing, the job downloads the published `standing_scores.csv` (a 404 means the first run; any other failure stops the job), drops its rows for the (study, week) pairs it has just scored, appends the new rows and sorts by study, week, basin, method, metric. `drift_flags.csv` and `preset_status.csv` come from the latest run only. A manual run with `start` and `end` (YYYYMMDD) does the same merge, so the history from 2025-11-01 can be filled in chunks of a few months; `kit_ref` picks the kit branch or tag. Limit 120 minutes; two runs never overlap. If a preset fails, the CSVs that were written are still published (the failed study keeps its older rows) and the job then fails.

The results are the assets of one release, tag `scores`, replaced on every run:

| Asset | Content |
|---|---|
| [`standing_scores.csv`](https://github.com/jkrek17/marine-research-data/releases/download/scores/standing_scores.csv) | all presets' rows: `study, week, basin, method, metric, value, n, truth` (one row per ISO week x basin x method x metric) |
| [`drift_flags.csv`](https://github.com/jkrek17/marine-research-data/releases/download/scores/drift_flags.csv) | newest 4 weeks against the study's original interval: `ok`, `drift` or `insufficient` |
| [`preset_status.csv`](https://github.com/jkrek17/marine-research-data/releases/download/scores/preset_status.csv) | per study: `ok` or `failed`, exit code, last error lines |
| [`scores_meta.json`](https://github.com/jkrek17/marine-research-data/releases/download/scores/scores_meta.json) | generated time (UTC), kit commit, date range, `weeks_scored` (ISO weeks of the new rows), per-preset status |

URL pattern: `https://github.com/jkrek17/marine-research-data/releases/download/scores/{asset}`. Inputs a preset cannot get from the store are reported in `preset_status.csv` and left out of the scores; they are not filled in.
