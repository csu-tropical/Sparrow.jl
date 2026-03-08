# Main driver for Sparrow workflows

function parse_arguments(args)
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--datetime"
            help = "Process a specific time YYYYmmdd_HHMMSS"
            arg_type = String
            default = "now"
        "--realtime"
            help = "Process an incoming realtime datastream"
            action = :store_true
        "--force_reprocess"
            help = "Force reprocessing of previously processed data"
            action = :store_true
        "--log_prefix"
            help = "Log file prefix"
            arg_type = String
            default = "default"
        "--threads"
            help = "Number of threads"
            arg_type = Int
            default = 1
        "--num_workers"
            help = "Number of worker processes"
            arg_type = Int
            default = 1
        "--sge"
            help = "Run on Sun Grid Engine"
            action = :store_true
        "--email"
            help = "Email address for SGE"
            arg_type = String
            default = "none"
        "--slurm"
            help = "Run on Slurm"
            action = :store_true
        "--paths_file"
            help = "File overriding data paths"
            arg_type = String
            default = "none"
        "--verbose", "-v"
            help = "Verbosity level (0=errors only, 1=warnings, 2=info, 3=debug, 4=trace)"
            arg_type = Int
            default = 2
        "workflow"
            help = "Name of workflow file"
            arg_type = String
            required = true
    end
    return parse_args(args, s)
end

function setup_workers(parsed_args)
    num_workers = parsed_args["num_workers"]
    email_address = parsed_args["email"]
    email_flags = email_address != "none" ? "eas" : "n"

    if parsed_args["sge"]
        msg_info("Initializing Sparrow on SGE with $(num_workers) workers and $(Threads.nthreads()) threads")
        ClusterManagers.addprocs_sge(num_workers;
            qsub_flags=`-q all.q -pe mpi $(num_threads) -m $(email_flags) -M $(email_address)`)
    elseif parsed_args["slurm"]
        msg_info("Initializing Sparrow on Slurm with $(num_workers) workers and $(Threads.nthreads()) threads")
        addprocs(SlurmClusterManager.SlurmManager())
    else
        msg_info("Initializing Sparrow locally with $(num_workers) workers and $(Threads.nthreads()) threads")
        addprocs(num_workers)
    end

    # Load Sparrow on all workers
    @eval @everywhere using Sparrow

    # Load plot extension on workers if available on the main process.
    # Must eval in Main on each worker — using from within Sparrow's module
    # context fails because CairoMakie is a weakdep, not a dep.
    if Base.get_extension(Sparrow, :SparrowPlotExt) !== nothing
        @everywhere Main.eval(:(using CairoMakie, GeoMakie, ColorSchemes, Images))
        msg_info("Plot extension loaded on all workers")
    end
end
