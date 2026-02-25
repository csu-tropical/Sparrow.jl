# Integration Testing Guide

## Overview

Integration tests verify that Sparrow workflows execute correctly end-to-end, including:
- Loading workflow files
- Executing multiple workflow steps in sequence
- File I/O operations
- Parameter passing between steps
- Error handling

## Quick Start

```bash
# 1. Generate test data
julia test/fixtures/generate_test_data.jl

# 2. Run integration tests
julia --project -e 'using Test, Sparrow; include("test/test_integration.jl")'

# Or use the convenience script
./run_tests.sh --generate-data --integration
```

## What Gets Tested

### ✅ Workflow File Loading
Tests that workflow files can be included and create valid workflow objects.

### ✅ Multi-Step Workflows
Simulates a 3-step workflow with data flowing from step to step.

### ✅ File Processing
Tests reading files from input directories and writing to output directories.

### ✅ Parameter Usage
Verifies that workflow parameters are accessible within step functions.

### ✅ Error Handling
Tests that steps properly handle missing directories and invalid inputs.

## Test Data

Test data files are generated with realistic radar-like filenames but contain simple text content (not actual NetCDF) to keep tests lightweight and fast.

### CfRadial Files
```
cfrad.20240816_080000.000_to_20240816_080500.000_TEST_SUR.nc
```

### SEAPOL Files
```
SEA20240816_080000
```

## Using Test_workflow.jl

To test with the actual `Test_workflow.jl`:

```julia
@testset "Real Workflow Test" begin
    # Set up test environment
    mktempdir() do tmpdir
        # Create test data directory structure
        test_data_dir = joinpath(tmpdir, "20240816")
        mkpath(test_data_dir)
        
        # Copy test data
        fixtures_dir = joinpath(@__DIR__, "fixtures", "data")
        for file in readdir(fixtures_dir)
            src = joinpath(fixtures_dir, file)
            dst = joinpath(test_data_dir, file)
            cp(src, dst)
        end
        
        # Modify Test_workflow.jl to use tmpdir
        # Then include and run it
    end
end
```

## Writing New Integration Tests

```julia
@testset "My Integration Test" begin
    @workflow_type MyTestWorkflow
    @workflow_step MyStep
    
    function Sparrow.workflow_step(wf::MyTestWorkflow, ::Type{MyStep},
                                   input_dir, output_dir; kwargs...)
        # Your step implementation
    end
    
    mktempdir() do tmpdir
        # Set up test environment
        # Execute workflow
        # Verify results
    end
end
```

## Advantages of Integration Tests

1. **End-to-End Validation** - Tests real workflow execution paths
2. **Catch Integration Issues** - Finds problems that unit tests miss
3. **Documentation** - Shows how workflows should be structured
4. **Confidence** - Proves the system works as a whole

## Running Selectively

```bash
# Skip integration tests (default)
julia --project -e 'using Pkg; Pkg.test()'

# Run integration tests
SPARROW_RUN_INTEGRATION_TESTS=1 julia --project -e 'using Pkg; Pkg.test()'
```

## CI/CD Considerations

For continuous integration:
- Generate test data in CI pipeline
- Use `SPARROW_RUN_INTEGRATION_TESTS=1`
- Set appropriate timeouts (integration tests take longer)
- Consider caching generated test data

## Troubleshooting

**Tests timeout**: Integration tests load the full module. Increase timeout or run directly.

**Test data missing**: Run `julia test/fixtures/generate_test_data.jl` first.

**File permissions**: Ensure test directories are writable.

**Path issues**: Use `joinpath()` for cross-platform compatibility.
