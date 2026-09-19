# Example paths file for `--paths_file`.
#
# A paths file lets the same workflow file run unmodified on different
# machines: keep the workflow's processing parameters in version control, and
# keep each machine's actual directories in a paths file like this one, which
# is not checked in.
#
# Usage:
#   sparrow my_workflow.jl --paths_file path_parameters_example.jl --datetime 20240101
#
# Only the five variables below are recognized; each one that is defined here
# overrides the matching value in the workflow file, and any left undefined is
# untouched. Any other variable defined in this file (see `qc_base` below) is
# ignored.

base_data_dir = "/path/to/radar/data"
base_working_dir = "/path/to/working"
base_archive_dir = "/path/to/archive"
base_plot_dir = "/path/to/plots"

# Optional: override date_subdir from the workflow file too.
# date_subdir = false

# Extra variables like this one are ignored by Sparrow; they are only useful
# if your own workflow file reads them back out explicitly.
qc_base = "/path/to/qc_data"
