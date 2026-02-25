#!/bin/bash
# Convenience script to run Sparrow tests

set -e

echo "🧪 Sparrow.jl Test Runner"
echo "=========================="
echo ""

# Parse arguments
RUN_INTEGRATION=false
GENERATE_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --integration|-i)
            RUN_INTEGRATION=true
            shift
            ;;
        --generate-data|-g)
            GENERATE_DATA=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./run_tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -i, --integration     Run integration tests"
            echo "  -g, --generate-data   Generate test data first"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_tests.sh                    # Run basic tests only"
            echo "  ./run_tests.sh -i                 # Run with integration tests"
            echo "  ./run_tests.sh -g -i              # Generate data and run all tests"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Generate test data if requested
if [ "$GENERATE_DATA" = true ]; then
    echo "📊 Generating test data..."
    julia test/fixtures/generate_test_data.jl
    echo ""
fi

# Run tests
if [ "$RUN_INTEGRATION" = true ]; then
    echo "🔧 Running all tests (including integration)..."
    SPARROW_RUN_INTEGRATION_TESTS=1 julia --project -e 'using Pkg; Pkg.test()'
else
    echo "⚡ Running basic unit tests..."
    julia --project -e 'using Pkg; Pkg.test()'
fi

echo ""
echo "✅ Tests complete!"
