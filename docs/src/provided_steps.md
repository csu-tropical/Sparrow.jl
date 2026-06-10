# Provided Workflow Steps

Sparrow.jl includes several pre-built workflow steps that handle common radar data processing tasks. These steps are ready to use in your workflows and serve as examples for creating custom steps.

## Utility Steps

### PassThroughStep

**Module:** `utility.jl`

**Purpose:** Copy all files from input directory to output directory without modification.

**Use Cases:**
- Testing workflows
- Creating checkpoints in multi-step workflows
- Archiving intermediate results

**Parameters Required:** None

**Example:**
```julia
@workflow_step PassThroughStep  # Already defined, just use it

workflow = MyWorkflow(
    steps = [
        ("copy_raw", PassThroughStep, "base_data", true),
        # ... other steps
    ],
    # ... other params
)

# No custom implementation needed - step is already defined
```

**Behavior:**
- Copies all files from input directory to output directory
- Follows symlinks
- Processes all files regardless of time window
- Useful for creating a snapshot of data at a particular workflow stage

---

### filterByTimeStep

**Module:** `utility.jl`

**Purpose:** Filter and copy only files that fall within the specified time window.

**Use Cases:**
- Filtering data by time before expensive processing
- Selecting specific time ranges from a larger dataset
- Time-based quality control

**Parameters Required:** None (uses `start_time` and `stop_time` from workflow)

**Example:**
```julia
@workflow_step filterByTimeStep  # Already defined

workflow = MyWorkflow(
    steps = [
        ("filter", filterByTimeStep, "base_data", false),
        ("process", MyProcessingStep, "filter", true),
    ],
    # ... other params
)
```

**Behavior:**
- Parses filename to extract scan start time
- Only copies files where `start_time <= scan_start < stop_time`
- Supports CfRadial, Sigmet, and RAW file naming conventions

---

## Quality Control Steps

### RadxConvertStep

**Module:** `qc.jl`

**Purpose:** Convert radar data files to CfRadial format using RadxConvert.

**Use Cases:**
- Converting from Sigmet, UF, or other formats to CfRadial
- Standardizing data format across different radar systems
- Preparing data for downstream processing

**Parameters Required:**
- `process_all` (optional): If `true`, process all files regardless of time window

**External Dependencies:**
- `RadxConvert` command-line tool (from LROSE toolkit)

**Example:**
```julia
@workflow_step RadxConvertStep  # Already defined

workflow = MyWorkflow(
    steps = [
        ("convert", RadxConvertStep, "base_data", false),
        ("qc", MyQCStep, "convert", true),
    ],
    process_all = false,  # Only process files in time window
    # ... other params
)
```

**Behavior:**
- Runs `RadxConvert -sort_rays_by_time -const_ngates` on each input file
- Sorts rays by time for consistent ordering
- Forces constant number of gates for uniform dimensions
- Skips files outside time window (unless `process_all = true`)
- Handles multiple file formats automatically

**Output:**
- CfRadial NetCDF files with standardized structure

---

### RoninQCStep

**Module:** `qc.jl`

**Purpose:** Apply machine learning-based quality control using Ronin.jl.

**Use Cases:**
- Automated clutter removal
- Artifact detection and removal
- ML-based quality control filtering

**Parameters Required:**
- `ronin_config`: Path to Ronin configuration file (JLD2 format)

**External Dependencies:**
- Ronin.jl package and trained models

**Example:**
```julia
@workflow_step RoninQCStep  # Already defined

workflow = MyWorkflow(
    steps = [
        ("convert", RadxConvertStep, "base_data", false),
        ("ronin_qc", RoninQCStep, "convert", true),
    ],
    ronin_config = "/path/to/ronin_config.jld2",
    # ... other params
)
```

**Behavior:**
- Loads Ronin configuration and trained models
- Copies input file to output directory
- Applies composite QC to the file in-place
- Modifies radar moments based on ML predictions

**Output:**
- Quality-controlled CfRadial files with artifacts removed

---

## Gridding Steps

All gridding steps use the Daisho.jl package for radar coordinate transformations and interpolation.

### Configuration via Daisho TOML

Grid geometry, the fields to grid, interpolation methods, and gridding weights are all configured in a Daisho TOML file referenced by the `daisho_config` workflow parameter:

```julia
workflow = MyWorkflow(
    steps = [
        ("grid_volume", GridVolumeStep, "qc", true),
    ],
    daisho_config = "/path/to/daisho.toml",
)
```

Generate a template with `using Daisho; print_config("daisho.toml")` and edit it for your radar. The relevant sections are:

- `[fields]` — the moments to grid, their interpolation type (`linear_interp`, `weighted_interp`, `nearest_interp`), and the special tags `define_detection` (field whose presence proves a detectable echo) and `define_scanned` (field whose presence proves the gate was scanned)
- `[io]` — fill value and undetect value for the output files
- `[gridding]` — power threshold and region-of-influence weighting options
- `[grid.cartesian]` — x/y/z extents used by volume, composite, PPI, and QVP grids
- `[grid.rhi]` — range/height extents for RHI grids
- `[grid.latlon]` — lat/lon extents for geographic grids
- `[grid.metadata]` — CF global attributes written to every gridded output

The TOML is validated when the workflow starts, and a grid step that needs a missing section raises an error naming the operation and the section. Legacy per-workflow grid parameters from older versions (`vol_xmin`, `beam_inflation`, `qc_moment_dict`, `grid_type_dict`, `missing_key`, `valid_key`, power thresholds, etc.) are ignored with a warning.

Output files are named by the scan start time with second precision, so scans within the same minute do not overwrite each other.

---

### GridRHIStep

**Module:** `grid.jl`

**Purpose:** Grid RHI (Range-Height Indicator) scans to a regular range-height grid. Each sweep in a file is gridded as a separate product.

**Use Cases:**
- Processing vertically-pointing or RHI scans
- Creating cross-sections
- Studying vertical structure

**Parameters Required:**
- `daisho_config` with `[grid.rhi]` configured

**Output:**
- Files named: `gridded_rhi_YYYYmmdd_HHMMSS_AA.A.nc` (AA.A = fixed angle)
- Regular 2D grid in range and height coordinates

---

### GridCompositeStep

**Module:** `grid.jl`

**Purpose:** Create a composite (CAPPI-like) grid from volumetric radar scans.

**Use Cases:**
- Creating plan-view displays
- Analyzing horizontal structure
- Maximum/composite reflectivity products

**Parameters Required:**
- `daisho_config` with `[grid.cartesian]` configured (the z-axis settings are ignored)

**Output:**
- Files named: `gridded_composite_YYYYmmdd_HHMMSS.nc`
- 2D horizontal composite grid

---

### GridVolumeStep

**Module:** `grid.jl`

**Purpose:** Grid volumetric radar data to a 3D Cartesian grid.

**Use Cases:**
- Creating 3D analysis-ready datasets
- Volume rendering
- 3D structure analysis

**Parameters Required:**
- `daisho_config` with `[grid.cartesian]` configured

**Output:**
- Files named: `gridded_volume_YYYYmmdd_HHMMSS.nc`
- 3D Cartesian grid (X, Y, Z)

---

### GridLatlonStep

**Module:** `grid.jl`

**Purpose:** Grid volumetric radar data to a geographic (lat/lon) coordinate system.

**Use Cases:**
- Overlaying radar data on maps
- Multi-radar merging in geographic coordinates
- GIS integration

**Parameters Required:**
- `daisho_config` with `[grid.latlon]` configured

**Output:**
- Files named: `gridded_latlon_YYYYmmdd_HHMMSS.nc`
- 3D grid in latitude, longitude, height coordinates

---

### GridPPIStep

**Module:** `grid.jl`

**Purpose:** Grid individual PPI (Plan Position Indicator) sweeps separately.

**Use Cases:**
- Analyzing individual elevation angles
- Creating elevation-specific products
- Studying elevation-dependent phenomena

**Parameters Required:**
- `daisho_config` with `[grid.cartesian]` configured (the z-axis settings are ignored)
- `max_ppi_angle`: Maximum elevation angle to grid (degrees)

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_ppi", GridPPIStep, "qc", true),
    ],
    daisho_config = "/path/to/daisho.toml",
    max_ppi_angle = 10.0,  # Only grid sweeps <= 10 degrees
)
```

**Output:**
- Files named: `gridded_ppi_YYYYmmdd_HHMMSS_EE.E.nc` (EE.E = elevation angle)
- One file per PPI sweep
- 2D horizontal grids

---

### GridQVPStep

**Module:** `grid.jl`

**Purpose:** Generate Quasi-Vertical Profile (QVP) by averaging near-vertical scans.

**Use Cases:**
- Profiling atmospheric structure
- Time-height displays
- Microphysical retrievals

**Parameters Required:**
- `daisho_config` with `[grid.cartesian]` configured (the z-axis settings define the column)
- `min_qvp_angle`: Minimum elevation angle for QVP (degrees, typically 70-90°)

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_qvp", GridQVPStep, "qc", true),
    ],
    daisho_config = "/path/to/daisho.toml",
    min_qvp_angle = 75.0,  # Only use scans >= 75 degrees
)
```

**Output:**
- Files named: `gridded_qvp_YYYYmmdd_HHMMSS_EE.E.nc`
- Vertical profiles averaged azimuthally
- Useful for precipitation microphysics studies

---

## Helper Functions

### get_scan_start

**Module:** `utility.jl`

**Purpose:** Extract scan start time from radar filename.

**Supported Formats:**
1. **CfRadial**: `cfrad.YYYYmmdd_HHMMSS.*`
2. **Sigmet**: `SEAYYYYmmdd_HHMMSS*`
3. **RAW**: Uses `RadxPrint` to extract metadata

**Usage:**
```julia
scan_time = get_scan_start("/path/to/cfrad.20240101_120000.nc")
# Returns: DateTime(2024, 1, 1, 12, 0, 0)
```

**Note:** For RAW files, requires `RadxPrint` command-line tool.

---

## Complete Workflow Example

Here's a complete workflow using several provided steps:

```julia
using Sparrow

@workflow_type RadarProcessingWorkflow

workflow = RadarProcessingWorkflow(
    # Directories
    base_working_dir = "/tmp/radar_processing",
    base_archive_dir = "/data/archive",
    base_data_dir = "/data/raw/radar",
    base_plot_dir = "/data/plots",
    
    # Time parameters: seconds, or a string with a unit code ("20S", "5M", "10H", "1D")
    span_seconds = "10M",
    reverse = false,
    
    # Workflow steps
    steps = [
        ("convert", RadxConvertStep, "base_data", false),
        ("ronin_qc", RoninQCStep, "convert", false),
        ("grid_volume", GridVolumeStep, "ronin_qc", true),
        ("grid_ppi", GridPPIStep, "ronin_qc", true),
    ],
    
    # Ronin QC
    ronin_config = "/data/models/ronin_seapol.jld2",
    
    # Daisho TOML with [fields], [io], [gridding], and [grid.cartesian] configured
    daisho_config = "/data/config/daisho.toml",
    
    # PPI sweep selection
    max_ppi_angle = 5.0,
    
    message_level = 2
)
```

Run with:
```bash
sparrow radar_processing.jl --datetime 20240115_120000 --num_workers 4
```

---

## Tips for Using Provided Steps

1. **Check Parameters**: Each step expects specific workflow parameters. Missing parameters will cause errors.

2. **Archive Strategy**: Set the `archive` flag (`true`/`false`) appropriately:
   - `false` for intermediate steps that can be regenerated
   - `true` for final products you want to keep

3. **Input Chaining**: Each step's input directory should match a previous step's name or "base_data":
   ```julia
   ("step1", Step1Type, "base_data", false),
   ("step2", Step2Type, "step1", false),      # Uses step1's output
   ("step3", Step3Type, "step2", true),       # Uses step2's output
   ```

4. **External Tools**: Steps using `RadxConvert` or `RadxPrint` require LROSE toolkit installed and in PATH.

5. **Performance**: Gridding steps are computationally intensive. Use multiple workers for large datasets.

6. **Customize**: These steps serve as templates. Copy and modify them for your specific needs.

---

## See Also

- [Workflow Guide](workflow_guide.md) - How to create custom workflow steps
- [Examples](examples.md) - Complete workflow examples
- [API Reference](api.md) - Core Sparrow functions