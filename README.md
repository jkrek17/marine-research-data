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

Never by hand and never to `main`. `tools/publish_store.py` in marine-research merges a cycle's new files with the published asset (so nothing another thread published is dropped), commits `incoming/{basin}/{YYYYMMDDHH}.zip` to a branch `upload/<utc-timestamp>-<n>` and pushes it. `.github/workflows/publish.yml` creates the release if it is missing, uploads each zip with `--clobber`, and deletes the branch. `.gitignore` blocks `*.npz` on main.

Limits to stay under: 2 GB per asset, 1000 assets per release. A cycle is about 10-15 MB, a release about 60 assets.
