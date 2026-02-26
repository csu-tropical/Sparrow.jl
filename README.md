# Sparrow.jl

**Ship, Plane, and Anchored Radar Research and Operational Workflows**

<!--[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://csu-tropical.github.io/Sparrow.jl/stable/) -->
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://csu-tropical.github.io/Sparrow.jl/dev/)
[![Build Status](https://github.com/csu-tropical/Sparrow.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/csu-tropical/Sparrow.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Sparrow.jl is a flexible, distributed workflow system for processing weather radar data from mobile or fixed platforms. It provides a framework for building custom data processing pipelines with built-in support for radar quality control, analysis, and visualization. Sparrow development is supported by the National Science Foundation (NSF) and National Oceanic and Atmospheric Administration (NOAA) to help improve understanding and forecasting of hazardous weather phenomena such as hurricanes and extreme rainfall. The Sparrow workflow system is designed to process data from the Colorado State University (CSU) Sea-Pol ship-borne radar and NOAA's tail Doppler radar systems aboard the Hurricane Hunter aircraft. Sparrow is part of the LROSE (Lidar Radar Open Software Environment) ecosystem and can also be used for processing data from ground-based fixed or temporarily anchored weather radar systems. The system is built in Julia to provide a high-level interface for defining complex workflows while leveraging the natively fast performance and parallel processing capabilities of the language.

## Features

- **Flexible Workflow System**: Process and analyze radar and other data sources with pre-defined and custom building blocks to build complex workflows
- **Distributed and Real-time Processing**: Built-in support for parallel, real-time processing across multiple computing cores
- **Radar Data Processing**: Specialized tools for quality control and analysis of weather radar data
- **Pre-built Steps**: Ready-to-use workflow steps for common tasks (format conversion, QC, gridding)
- **Extensible Architecture**: Easy to add custom processing steps and workflow types
- **Message System**: Configurable logging with multiple severity levels
- **Integration with HPC**: Support for Slurm and Sun Grid Engine cluster managers

## Installation

Sparrow.jl is not an officially registered package yet, so installation takes a few extra steps to manually install dependencies first. 

### Julia Packages

Most of the Julia packages will be automatically installed when you add Sparrow.jl, but the following need to be manually installed first:

- [Springsteel.jl](https://github.com/csu-tropical/Springsteel.jl) - Semi-spectral grid engine 
- [Daisho.jl](https://github.com/csu-tropical/Daisho.jl) - Data analysis and assimilation software
- [Ronin.jl](https://github.com/csu-tropical/Ronin.jl) - Random forest Optimized Nonmeteorological IdentificatioN radar quality control software

### External Tools (Optional)

Sparrow is part of the [LROSE](https://github.com/NCAR/lrose-core) Lidar Radar Open Software Environment. To use the core Radx tools as part of your workflow, install lrose-core and ensure binaries are in your PATH.

Future support for [PyArt](https://github.com/ARM-DOE/pyart) steps as part of the workflow is planned but is not currently implemented.

### Package Installation

If you just want to use it, install it and the dependencies directly from the GitHub repositories:

```julia
using Pkg
Pkg.add(url="https://github.com/csu-tropical/Springsteel.jl")
Pkg.add(url="https://github.com/csu-tropical/Daisho.jl")
Pkg.add(url="https://github.com/csu-tropical/Ronin.jl")
Pkg.add(url="https://github.com/csu-tropical/Sparrow.jl")
```

This will install the latest version of the code, but any updates to the code will not be reflected in your installation. You can then update the package with `Pkg.update()` which will update all packages in your environment.

If you want to actively develop or modify Sparrow then you can clone the repository code and install in development mode. After cloning, in the REPL, go into Package mode by pressing `]`. You will see the REPL change color and indicate `pkg` mode. You can install the module using `dev /path/to/Sparrow.jl` in `pkg` mode. This will update the module as changes are made to the code. You should see the dependencies being installed, and then the package will be precompiled. After installing, exit Package mode with ctrl-C. 

Test to make sure the precompilation was successful by running `using Sparrow` in the REPL. If everything is successful then you should get no errors and it will just move to a new line.

## Usage

### Basic Example

```julia
using Sparrow

# Define your workflow type
@workflow_type MyRadarWorkflow

# Define workflow steps
@workflow_step QualityControl
@workflow_step Gridding

# Create the workflow
workflow = MyRadarWorkflow(
    base_working_dir = "/tmp/work",
    base_archive_dir = "/data/archive",
    base_data_dir = "/data/raw",
    base_plot_dir = "/data/plots",
    
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("qc", QualityControl, "base_data", false),
        ("grid", Gridding, "qc", true)
    ],
    
    minute_span = 10,
    # Add other parameters as needed
)

# Implement your step
function Sparrow.workflow_step(workflow::MyRadarWorkflow, ::Type{QualityControl},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    msg_info("Running QC on $(input_dir)")
    # Your processing logic here
end
```

Save as `my_workflow.jl` and run:

```bash
sparrow my_workflow.jl --datetime 20260101_120000
```

## Pre-built Workflow Steps

Sparrow includes several ready-to-use workflow steps:

- **Utility**: `PassThroughStep`, `filterByTimeStep`
- **Quality Control**: `RadxConvertStep`, `RoninQCStep`
- **Gridding**: `GridRHIStep`, `GridCompositeStep`, `GridVolumeStep`, `GridLatlonStep`, `GridPPIStep`, `GridQVPStep`

See the [Provided Workflow Steps](https://csu-tropical.github.io/Sparrow.jl/dev/provided_steps/) documentation for complete details.

## Command Line Interface

```bash
sparrow workflow.jl [options]

Options:
  --datetime DATETIME       Process specific time YYYYmmdd_HHMMSS (default: "now")
  --realtime                Process an incoming realtime datastream
  --num_workers N           Number of distributed workers
  --threads N               Number of threads per worker
  -v, --verbose LEVEL       Message verbosity (0-4, default: 2)
  --slurm                   Use Slurm cluster manager
  --sge                     Use Sun Grid Engine
  --paths_file FILE         Override data paths from file
```

## Documentation

📚 **[Full Documentation](https://csu-tropical.github.io/Sparrow.jl/dev/)**

- [Getting Started](https://csu-tropical.github.io/Sparrow.jl/dev/getting_started/) - Installation and first workflow
- [Workflow Guide](https://csu-tropical.github.io/Sparrow.jl/dev/workflow_guide/) - In-depth workflow concepts
- [Provided Workflow Steps](https://csu-tropical.github.io/Sparrow.jl/dev/provided_steps/) - Pre-built steps cookbook
- [Examples](https://csu-tropical.github.io/Sparrow.jl/dev/examples/) - Complete workflow examples
- [API Reference](https://csu-tropical.github.io/Sparrow.jl/dev/api/) - Function documentation

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

See [LICENSE](LICENSE) file for details.

## Citation

If you use Sparrow.jl in your research, please cite:

```bibtex
@software{sparrow_jl,
  author = {Bell, Michael M.},
  title = {Sparrow.jl: Ship, Plane, and Anchored Radar Research and Operational Workflows},
  url = {https://github.com/csu-tropical/Sparrow.jl},
  year = {2026}
}
```

## Acknowledgements
Sparrow.jl development is supported by the NSF awards AGS-2113042, AGS-2331202, and AGS-2348448 and NOAA awards NA23OAR4590408, NA22OAR4590521, and NA25OARX459C023.

## Contact

For questions or issues, please open an issue on GitHub or contact the maintainers.
