# Test Fixtures for Sparrow.jl

This directory contains test fixtures and utilities for integration testing.

## Directory Structure

```
fixtures/
├── data/                       # Test data files (generated)
│   ├── cfrad.*.nc             # CfRadial-style test files
│   └── seapol/                # SEAPOL-style test files
├── minimal_workflow.jl        # Minimal workflow for testing
├── generate_test_data.jl      # Script to generate test data
└── README.md                  # This file
```

## Generating Test Data

Before running integration tests, you need to generate test data files:

```bash
# Generate test data
julia test/fixtures/generate_test_data.jl
```

This creates:
- 5 CfRadial-style test files in `fixtures/data/`
- 3 SEAPOL-style test files in `fixtures/data/seapol/`

The files are simple text files with radar-like filenames for testing purposes. They are NOT actual NetCDF files to keep the test suite lightweight.

## Test Workflows

### minimal_workflow.jl

A minimal workflow configuration for integration testing. It includes:
- `MinimalTestWorkflow` type
- `CopyStep` that copies files between directories
- Uses temporary directories for I/O
- Debug-level logging

Usage in tests:
```julia
# Include the workflow
include("fixtures/minimal_workflow.jl")

# The 'workflow' variable is now available
@test workflow isa Sparrow.SparrowWorkflow
```

## Using Fixtures in Tests

### Loading Test Data

```julia
# Get path to test data
test_data_dir = joinpath(@__DIR__, "fixtures", "data")

# List test files
test_files = readdir(test_data_dir)
```

### Using Test Workflows

```julia
# Include a test workflow
workflow_file = joinpath(@__DIR__, "fixtures", "minimal_workflow.jl")
include(workflow_file)

# Access the workflow
@test @isdefined workflow
```

### Creating Temporary Test Environments

```julia
# Use mktempdir for isolated testing
mktempdir() do tmpdir
    # Set up test environment
    input_dir = joinpath(tmpdir, "input")
    output_dir = joinpath(tmpdir, "output")
    mkpath(input_dir)
    
    # Copy test data
    test_file = joinpath(@__DIR__, "fixtures", "data", "cfrad.20240816_080000.000_to_20240816_080500.000_TEST_SUR.nc")
    cp(test_file, joinpath(input_dir, basename(test_file)))
    
    # Run your test
    # ...
end  # tmpdir automatically cleaned up
```

## Test Data Format

### CfRadial-style Files

Filename format:
```
cfrad.YYYYmmdd_HHMMSS.000_to_YYYYmmdd_HHMMSS.000_RADAR_SCANTYPE.nc
```

Example:
```
cfrad.20240816_080000.000_to_20240816_080500.000_TEST_SUR.nc
```

These files contain simple text content (not actual NetCDF) for lightweight testing.

### SEAPOL-style Files

Filename format:
```
SEAYYYYmmdd_HHMMSS
```

Example:
```
SEA20240816_080000
```

## Cleaning Up Test Data

To remove generated test data:

```julia
include("fixtures/generate_test_data.jl")
cleanup_test_data(joinpath(@__DIR__, "data"))
```

Or manually:
```bash
rm -rf test/fixtures/data/*
```

## Adding New Fixtures

### Adding a New Test Workflow

1. Create a new workflow file: `test/fixtures/my_test_workflow.jl`
2. Define workflow type, steps, and implementations
3. Use in tests:
   ```julia
   include("fixtures/my_test_workflow.jl")
   ```

### Adding New Test Data Generators

1. Edit `generate_test_data.jl`
2. Add new function:
   ```julia
   function generate_my_data(data_dir::String)
       # Generate your test data
   end
   ```
3. Call from main section if appropriate

## Best Practices

1. **Keep test data small** - Use minimal files for faster tests
2. **Use temporary directories** - Avoid polluting the filesystem
3. **Clean up after tests** - Use `mktempdir()` for automatic cleanup
4. **Document data format** - Explain what your test data represents
5. **Version control** - Don't commit generated test data, only generators
6. **Isolation** - Each test should be independent

## Environment Variables

- `SPARROW_RUN_INTEGRATION_TESTS=1` - Enable integration tests
- `SPARROW_TEST_DATA=/path/to/data` - Override test data location (optional)

## Running Integration Tests

```bash
# Generate test data first
julia test/fixtures/generate_test_data.jl

# Run integration tests
SPARROW_RUN_INTEGRATION_TESTS=1 julia --project -e 'using Pkg; Pkg.test()'
```

## Notes

- Test data files are in `.gitignore` to avoid bloating the repository
- Regenerate test data after major changes to filename formats
- Integration tests are optional and skipped by default
- For real-world testing with actual NetCDF files, use a separate test data repository