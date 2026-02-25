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

### Common Parameters

Most gridding steps require these workflow parameters:

- `qc_moment_dict`: Dictionary mapping moment names (e.g., "DBZ" → "reflectivity")
- `grid_type_dict`: Dictionary specifying interpolation method per moment (`:linear`, `:weighted`, `:nearest`)
- `beam_inflation`: Beam width inflation factor (typically 1.0-2.0)
- `missing_key`: Value for missing/invalid data (typically -9999.0)
- `valid_key`: Minimum valid data value (typically -32.0 for DBZ)

---

### GridRHIStep

**Module:** `grid.jl`

**Purpose:** Grid RHI (Range-Height Indicator) scans to a regular range-height grid.

**Use Cases:**
- Processing vertically-pointing or RHI scans
- Creating cross-sections
- Studying vertical structure

**Parameters Required:**
- Common gridding parameters (above)
- `rmin`: Minimum range (m)
- `rincr`: Range increment (m)
- `rdim`: Number of range bins
- `rhi_zmin`: Minimum height (m)
- `rhi_zincr`: Height increment (m)
- `rhi_zdim`: Number of height bins
- `rhi_power_threshold`: Power threshold for valid data

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("qc", MyQCStep, "base_data", false),
        ("grid_rhi", GridRHIStep, "qc", true),
    ],
    qc_moment_dict = Dict("DBZ" => "reflectivity", "VEL" => "velocity"),
    grid_type_dict = Dict("reflectivity" => :linear, "velocity" => :weighted),
    rmin = 0.0,
    rincr = 100.0,
    rdim = 200,
    rhi_zmin = 0.0,
    rhi_zincr = 100.0,
    rhi_zdim = 150,
    beam_inflation = 1.5,
    rhi_power_threshold = -10.0,
    missing_key = -9999.0,
    valid_key = -32.0,
)
```

**Output:**
- Files named: `gridded_rhi_YYYYmmdd_HHMM_AA.A.nc` (AA.A = azimuth angle)
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
- Common gridding parameters
- `long_xmin`: Minimum X coordinate (m, radar-relative)
- `long_xincr`: X increment (m)
- `long_xdim`: Number of X bins
- `long_ymin`: Minimum Y coordinate (m)
- `long_yincr`: Y increment (m)
- `long_ydim`: Number of Y bins

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_composite", GridCompositeStep, "qc", true),
    ],
    # Common params...
    long_xmin = -50000.0,
    long_xincr = 500.0,
    long_xdim = 200,
    long_ymin = -50000.0,
    long_yincr = 500.0,
    long_ydim = 200,
)
```

**Output:**
- Files named: `gridded_composite_YYYYmmdd_HHMM.nc`
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
- Common gridding parameters
- `vol_xmin`, `vol_xincr`, `vol_xdim`: X-axis parameters (m)
- `vol_ymin`, `vol_yincr`, `vol_ydim`: Y-axis parameters (m)
- `zmin`, `zincr`, `zdim`: Z-axis (height) parameters (m)
- `ppi_power_threshold`: Power threshold for PPI scans

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_volume", GridVolumeStep, "qc", true),
    ],
    # Common params...
    vol_xmin = -40000.0,
    vol_xincr = 500.0,
    vol_xdim = 160,
    vol_ymin = -40000.0,
    vol_yincr = 500.0,
    vol_ydim = 160,
    zmin = 0.0,
    zincr = 250.0,
    zdim = 60,
    ppi_power_threshold = -10.0,
)
```

**Output:**
- Files named: `gridded_volume_YYYYmmdd_HHMM.nc`
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
- Common gridding parameters
- `latmin`: Minimum latitude (degrees)
- `latdim`: Number of latitude bins
- `lonmin`: Minimum longitude (degrees)
- `londim`: Number of longitude bins
- `degincr`: Degree increment (both lat and lon)
- `zmin`, `zincr`, `zdim`: Height parameters (m)
- `ppi_power_threshold`: Power threshold

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_latlon", GridLatlonStep, "qc", true),
    ],
    # Common params...
    latmin = 25.0,
    latdim = 100,
    lonmin = -80.0,
    londim = 100,
    degincr = 0.01,  # ~1 km
    zmin = 0.0,
    zincr = 250.0,
    zdim = 60,
    ppi_power_threshold = -10.0,
)
```

**Output:**
- Files named: `gridded_latlon_YYYYmmdd_HHMM.nc`
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
- Common gridding parameters
- `long_xmin`, `long_xincr`, `long_xdim`: X-axis parameters (m)
- `long_ymin`, `long_yincr`, `long_ydim`: Y-axis parameters (m)
- `ppi_power_threshold`: Power threshold
- `max_ppi_angle`: Maximum elevation angle to grid (degrees)

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_ppi", GridPPIStep, "qc", true),
    ],
    # Common params...
    long_xmin = -50000.0,
    long_xincr = 500.0,
    long_xdim = 200,
    long_ymin = -50000.0,
    long_yincr = 500.0,
    long_ydim = 200,
    max_ppi_angle = 10.0,  # Only grid sweeps <= 10 degrees
    ppi_power_threshold = -10.0,
)
```

**Output:**
- Files named: `gridded_ppi_YYYYmmdd_HHMM_EE.E.nc` (EE.E = elevation angle)
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
- Common gridding parameters
- `zmin`, `zincr`, `zdim`: Height parameters (m)
- `qvp_power_threshold`: Power threshold
- `min_qvp_angle`: Minimum elevation angle for QVP (degrees, typically 70-90°)

**Example:**
```julia
workflow = MyWorkflow(
    steps = [
        ("grid_qvp", GridQVPStep, "qc", true),
    ],
    # Common params...
    zmin = 0.0,
    zincr = 100.0,
    zdim = 150,
    min_qvp_angle = 75.0,  # Only use scans >= 75 degrees
    qvp_power_threshold = -15.0,
)
```

**Output:**
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
    
    # Time parameters
    minute_span = 10,
    reverse = false,
    
    # Workflow steps
    steps = [
        ("convert", RadxConvertStep, "base_data", false),
        ("ronin_qc", RoninQCStep, "convert", false),
        ("grid_volume", GridVolumeStep, "ronin_qc", true),
        ("grid_ppi", GridPPIStep, "ronin_qc", true),
    ],
    
    # Moment configuration
    qc_moment_dict = Dict(
        "DBZ" => "reflectivity",
        "VEL" => "velocity",
        "WIDTH" => "spectrum_width"
    ),
    grid_type_dict = Dict(
        "reflectivity" => :linear,
        "velocity" => :weighted,
        "spectrum_width" => :weighted
    ),
    
    # Ronin QC
    ronin_config = "/data/models/ronin_seapol.jld2",
    
    # Volume grid parameters
    vol_xmin = -40000.0,
    vol_xincr = 500.0,
    vol_xdim = 160,
    vol_ymin = -40000.0,
    vol_yincr = 500.0,
    vol_ydim = 160,
    zmin = 0.0,
    zincr = 250.0,
    zdim = 60,
    
    # PPI grid parameters
    long_xmin = -50000.0,
    long_xincr = 500.0,
    long_xdim = 200,
    long_ymin = -50000.0,
    long_yincr = 500.0,
    long_ydim = 200,
    max_ppi_angle = 5.0,
    
    # Common gridding parameters
    beam_inflation = 1.5,
    ppi_power_threshold = -10.0,
    missing_key = -9999.0,
    valid_key = -32.0,
    
    message_level = 2
)
```

Run with:
```bash
julia sparrow radar_processing.jl --datetime 20240115_120000 --num_workers 4
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