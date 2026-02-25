# Sparrow.jl Testing Guide

## Running Tests

### Quick Tests

Run the basic test suite:

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

### Manual Testing

For faster iteration during development, you can run tests directly:

```bash
# Run all tests
julia --project=test test/runtests.jl

# Run specific test file
julia --project=test test/test_workflow.jl
```

## Test Structure

```
test/
├── runtests.jl           # Main test runner
├── test_messaging.jl     # Messaging system tests
├── test_workflow.jl      # Workflow type and step tests
├── test_utility.jl       # Utility function tests
├── test_io.jl           # I/O operation tests
└── README.md            # This file
```

## Writing New Tests

### Testing Workflow Types

```julia
using Test
using Sparrow

@testset "My Workflow Tests" begin
    # Create a test workflow type
    @workflow_type MyTestWorkflow
    
    # Create an instance
    wf = MyTestWorkflow(
        param1="value1",
        param2=42,
        enabled=true
    )
    
    # Test parameter access
    @test wf["param1"] == "value1"
    @test wf["param2"] == 42
    
    # Test parameter modification
    wf["new_param"] = "added"
    @test wf["new_param"] == "added"
end
```

### Testing Workflow Steps

```julia
@testset "Custom Step Tests" begin
    @workflow_type TestWorkflow
    @workflow_step CustomStep
    
    # Track if step was called
    called = false
    
    # Define step implementation
    function Sparrow.workflow_step(wf::TestWorkflow, ::Type{CustomStep},
                                   input_dir::String, output_dir::String;
                                   kwargs...)
        called = true
    end
    
    # Create workflow and call step
    wf = TestWorkflow()
    Sparrow.workflow_step(wf, CustomStep, "/in", "/out")
    
    @test called == true
end
```

### Testing Message System

```julia
@testset "Message Level Tests" begin
    # Set message level
    Sparrow.set_message_level(Sparrow.MSG_DEBUG)
    @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_DEBUG
    
    # Test that messages don't crash
    @test_nowarn Sparrow.msg_info("Test message")
    @test_nowarn Sparrow.msg_debug("Debug message")
    
    # Test that errors throw
    @test_throws Exception Sparrow.msg_error("Error message")
end
```

### Testing I/O Functions

```julia
@testset "File Operations" begin
    # Use temporary directory for testing
    mktempdir() do tmpdir
        # Create test file
        test_file = joinpath(tmpdir, "test.txt")
        write(test_file, "test content")
        
        @test isfile(test_file)
        @test read(test_file, String) == "test content"
        
        # Test file operations
        dest_file = joinpath(tmpdir, "copy.txt")
        cp(test_file, dest_file)
        @test isfile(dest_file)
    end
    # tmpdir is automatically cleaned up
end
```

## Test Coverage

Key areas to test:

- ✅ Workflow type creation and instantiation
- ✅ Dict-like parameter access (getindex, setindex)
- ✅ Workflow step type creation
- ✅ Workflow step dispatch
- ✅ Message system and filtering
- ✅ Utility functions (get_param, get_scan_start, etc.)
- ✅ I/O operations (file reading, directory creation, symlinks)
- 🚧 Integration tests with real data
- 🚧 Worker distribution tests
- 🚧 Full workflow execution tests

## Testing Best Practices

### 1. Use Temporary Directories

Always use `mktempdir()` for file I/O tests to avoid polluting the filesystem:

```julia
mktempdir() do tmpdir
    # Your test code here
    test_file = joinpath(tmpdir, "test.nc")
    # ...
end  # Automatically cleaned up
```

### 2. Test Edge Cases

```julia
@testset "Edge Cases" begin
    wf = TestWorkflow()
    
    # Test missing key
    @test_throws ErrorException wf["nonexistent"]
    
    # Test empty parameters
    empty_wf = TestWorkflow()
    @test length(empty_wf) == 0
end
```

### 3. Isolate Tests

Each test should be independent and not rely on state from other tests:

```julia
@testset "Independent Test" begin
    # Set up fresh state
    wf = TestWorkflow(param="value")
    
    # Test
    @test wf["param"] == "value"
    
    # No cleanup needed - let it go out of scope
end
```

### 4. Use Descriptive Test Names

```julia
@testset "Workflow Parameters" begin
    @testset "Parameter Storage" begin
        # ...
    end
    
    @testset "Parameter Modification" begin
        # ...
    end
    
    @testset "Mixed Type Parameters" begin
        # ...
    end
end
```

## Continuous Integration

Tests are automatically run on:
- Pull requests
- Commits to main branch
- Release tags

## Troubleshooting

### Tests Timeout

If tests timeout, it's likely due to:
1. Heavy dependencies loading (Makie, etc.)
2. Worker processes being created
3. External commands (RadxConvert, etc.)

**Solution:** Mock external dependencies or skip integration tests in CI.

### Tests Fail Locally

1. Check that all dependencies are installed:
   ```bash
   julia --project -e 'using Pkg; Pkg.instantiate()'
   ```

2. Ensure you're using the correct Julia version (1.10+)

3. Check if external tools are available (RadxConvert, RadxPrint, etc.)

### Worker Tests Fail

Worker-based tests require:
- Multiple CPU cores available
- Distributed package properly loaded
- No port conflicts

## Adding New Tests

1. Create a new test file in `test/` directory
2. Add test file to `test/runtests.jl`:
   ```julia
   @testset "My New Tests" begin
       include("test_mynew.jl")
   end
   ```
3. Run tests to verify
4. Commit both the test file and updated `runtests.jl`

## Performance Testing

For performance-critical code, use `@benchmark`:

```julia
using BenchmarkTools

@testset "Performance" begin
    wf = TestWorkflow(large_data=rand(1000))
    
    # Benchmark parameter access
    b = @benchmark $wf["large_data"]
    @test median(b.times) < 1_000  # Less than 1μs
end
```

## Integration Testing

For full workflow tests with real data:

```bash
# Set up test data directory
export SPARROW_TEST_DATA=/path/to/test/data

# Run integration tests
julia --project test/integration_tests.jl
```

## Contributing Tests

When contributing:
1. Write tests for new features
2. Ensure existing tests still pass
3. Add documentation for complex test scenarios
4. Keep tests fast and focused
5. Use meaningful assertion messages

Example:
```julia
@test wf["param"] == expected "Parameter 'param' should equal $expected"
```

## Questions?

For questions about testing, please:
- Open an issue on GitHub
- Check existing test files for examples
- Consult Julia's Test.jl documentation