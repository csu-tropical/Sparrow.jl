using Sparrow.NCDatasets
using Dates

"""
    generate_test_cfradial(filepath; start_time, instrument_name, scan_name, nrays, ngates, nsweeps)

Generate a minimal valid CfRadial-1.4 NetCDF file for testing.
Based on the structure of real SEA-POL CfRadial files produced by RadxConvert.

The generated file contains all required CfRadial variables and global attributes
so that RadxPrint can read it and extract metadata (startTimeSecs, etc.).
Moment data arrays are filled with zeros.
"""
function generate_test_cfradial(filepath::String;
        start_time::DateTime = DateTime(2024, 9, 3, 12, 0, 8),
        end_time::DateTime = DateTime(2024, 9, 3, 12, 6, 13),
        instrument_name::String = "SEAPOL",
        scan_name::String = "PICCOLO_VOL1",
        nrays::Int = 10,
        ngates::Int = 20,
        nsweeps::Int = 1,
        latitude::Float64 = 8.4866,
        longitude::Float64 = -30.8300,
        altitude::Float64 = 14.0)

    start_str = Dates.format(start_time, dateformat"yyyy-mm-ddTHH:MM:SSZ")
    end_str = Dates.format(end_time, dateformat"yyyy-mm-ddTHH:MM:SSZ")

    NCDataset(filepath, "c") do ds
        # Global attributes (CfRadial-1.4 required)
        ds.attrib["Conventions"] = "CF-1.7"
        ds.attrib["Sub_conventions"] = "CF-Radial instrument_parameters radar_parameters radar_calibration"
        ds.attrib["version"] = "CF-Radial-1.4"
        ds.attrib["title"] = "Test CfRadial"
        ds.attrib["institution"] = "Test"
        ds.attrib["references"] = ""
        ds.attrib["source"] = "generate_test_cfradial.jl"
        ds.attrib["history"] = ""
        ds.attrib["comment"] = "Synthetic test data"
        ds.attrib["original_format"] = "CFRADIAL"
        ds.attrib["driver"] = "NCDatasets.jl"
        ds.attrib["created"] = Dates.format(now(), dateformat"yyyy/mm/dd HH:MM:SS")
        ds.attrib["start_datetime"] = start_str
        ds.attrib["time_coverage_start"] = start_str
        ds.attrib["start_time"] = Dates.format(start_time, dateformat"yyyy-mm-dd HH:MM:SS.sss")
        ds.attrib["end_datetime"] = end_str
        ds.attrib["time_coverage_end"] = end_str
        ds.attrib["end_time"] = Dates.format(end_time, dateformat"yyyy-mm-dd HH:MM:SS.sss")
        ds.attrib["instrument_name"] = instrument_name
        ds.attrib["site_name"] = instrument_name
        ds.attrib["scan_name"] = scan_name
        ds.attrib["scan_id"] = Int32(0)
        ds.attrib["platform_is_mobile"] = "false"
        ds.attrib["n_gates_vary"] = "false"
        ds.attrib["ray_times_increase"] = "true"

        # Dimensions
        defDim(ds, "time", nrays)
        defDim(ds, "range", ngates)
        defDim(ds, "sweep", nsweeps)
        defDim(ds, "string_length_8", 8)
        defDim(ds, "string_length_32", 32)
        defDim(ds, "frequency", 1)

        # volume_number
        vn = defVar(ds, "volume_number", Int32, ())
        vn.attrib["long_name"] = "data_volume_index_number"
        vn[:] = Int32(0)

        # platform_type
        pt = defVar(ds, "platform_type", Char, ("string_length_32",))
        pt.attrib["long_name"] = "platform_type"
        pt.attrib["options"] = "fixed, vehicle, ship, aircraft_fore, aircraft_aft, aircraft_tail, aircraft_belly, aircraft_roof, aircraft_nose, satellite_orbit, satellite_geo"
        _write_string!(pt, "fixed", 32)

        # primary_axis
        pa = defVar(ds, "primary_axis", Char, ("string_length_32",))
        pa.attrib["long_name"] = "primary_axis_of_rotation"
        _write_string!(pa, "axis_z", 32)

        # instrument_type
        it = defVar(ds, "instrument_type", Char, ("string_length_32",))
        it.attrib["long_name"] = "type_of_instrument"
        it.attrib["options"] = "radar, lidar"
        _write_string!(it, "radar", 32)

        # time_coverage_start/end as char arrays
        tcs = defVar(ds, "time_coverage_start", Char, ("string_length_32",))
        tcs.attrib["long_name"] = "data_volume_start_time_utc"
        _write_string!(tcs, start_str, 32)

        tce = defVar(ds, "time_coverage_end", Char, ("string_length_32",))
        tce.attrib["long_name"] = "data_volume_end_time_utc"
        _write_string!(tce, end_str, 32)

        # frequency
        freq = defVar(ds, "frequency", Float32, ("frequency",))
        freq.attrib["long_name"] = "radiation_frequency"
        freq.attrib["units"] = "s-1"
        freq[:] = [Float32(5.625e9)]

        # time variable
        tv = defVar(ds, "time", Float64, ("time",),
            attrib = Dict(
                "standard_name" => "time",
                "long_name" => "time_in_seconds_since_volume_start",
                "calendar" => "gregorian",
                "units" => "seconds since $start_str",
                "comment" => "times are relative to the volume start_time"
            ))
        time_offsets = range(0.0, stop=Float64(Dates.value(end_time - start_time) / 1000), length=nrays)
        tv[:] = collect(time_offsets)

        # range variable
        rv = defVar(ds, "range", Float32, ("range",),
            attrib = Dict(
                "long_name" => "range_to_center_of_measurement_volume",
                "standard_name" => "projection_range_coordinate",
                "units" => "meters",
                "axis" => "radial_range_coordinate",
                "spacing_is_constant" => "true",
                "meters_to_center_of_first_gate" => 400.0,
                "meters_between_gates" => 100.0
            ))
        rv[:] = Float32.(range(400, step=100, length=ngates))

        # ray geometry variables
        az = defVar(ds, "azimuth", Float32, ("time",),
            attrib = Dict(
                "standard_name" => "ray_azimuth_angle",
                "long_name" => "azimuth_angle_from_true_north",
                "units" => "degrees"
            ))
        az[:] = Float32.(range(0, stop=360*(1-1/nrays), length=nrays))

        el = defVar(ds, "elevation", Float32, ("time",),
            attrib = Dict(
                "standard_name" => "ray_elevation_angle",
                "long_name" => "elevation_angle_from_horizontal_plane",
                "units" => "degrees",
                "positive" => "up"
            ))
        el[:] = fill(Float32(0.5), nrays)

        # ray_start_range and ray_gate_spacing
        rsr = defVar(ds, "ray_start_range", Float32, ("time",),
            attrib = Dict("long_name" => "start_range_for_ray", "units" => "meters"))
        rsr[:] = fill(Float32(400.0), nrays)

        rgs = defVar(ds, "ray_gate_spacing", Float32, ("time",),
            attrib = Dict("long_name" => "gate_spacing_for_ray", "units" => "meters"))
        rgs[:] = fill(Float32(100.0), nrays)

        # Geolocation
        lat = defVar(ds, "latitude", Float64, ("time",),
            attrib = Dict("long_name" => "latitude", "standard_name" => "latitude",
                          "units" => "degrees_north"))
        lat[:] = fill(latitude, nrays)

        lon = defVar(ds, "longitude", Float64, ("time",),
            attrib = Dict("long_name" => "longitude", "standard_name" => "longitude",
                          "units" => "degrees_east"))
        lon[:] = fill(longitude, nrays)

        alt = defVar(ds, "altitude", Float64, ("time",),
            attrib = Dict("long_name" => "altitude", "standard_name" => "altitude",
                          "units" => "meters"))
        alt[:] = fill(altitude, nrays)

        # Sweep metadata
        sn = defVar(ds, "sweep_number", Int32, ("sweep",),
            attrib = Dict("long_name" => "sweep_index_number_0_based"))
        sn[:] = Int32.(0:nsweeps-1)

        rays_per_sweep = nrays ÷ nsweeps
        sri = defVar(ds, "sweep_start_ray_index", Int32, ("sweep",),
            attrib = Dict("long_name" => "index_of_first_ray_in_sweep"))
        sri[:] = Int32.([i * rays_per_sweep for i in 0:nsweeps-1])

        eri = defVar(ds, "sweep_end_ray_index", Int32, ("sweep",),
            attrib = Dict("long_name" => "index_of_last_ray_in_sweep"))
        eri[:] = Int32.([(i+1) * rays_per_sweep - 1 for i in 0:nsweeps-1])

        fa = defVar(ds, "fixed_angle", Float32, ("sweep",),
            attrib = Dict("long_name" => "ray_target_fixed_angle", "units" => "degrees"))
        fa[:] = Float32.(range(0.5, step=1.0, length=nsweeps))

        sm = defVar(ds, "sweep_mode", Char, ("string_length_32", "sweep"),
            attrib = Dict("long_name" => "scan_mode_for_sweep"))
        for i in 1:nsweeps
            _write_string_col!(sm, "azimuth_surveillance", 32, i)
        end

        # Pulse/PRT metadata
        pw = defVar(ds, "pulse_width", Float32, ("time",),
            attrib = Dict("long_name" => "transmitter_pulse_width", "units" => "seconds"))
        pw[:] = fill(Float32(1.0e-6), nrays)

        prt = defVar(ds, "prt", Float32, ("time",),
            attrib = Dict("long_name" => "pulse_repetition_time", "units" => "seconds"))
        prt[:] = fill(Float32(1.0e-3), nrays)

        nyq = defVar(ds, "nyquist_velocity", Float32, ("time",),
            attrib = Dict("long_name" => "unambiguous_doppler_velocity", "units" => "meters per second"))
        nyq[:] = fill(Float32(26.0), nrays)

        ant = defVar(ds, "antenna_transition", Int8, ("time",),
            attrib = Dict("long_name" => "antenna_is_in_transition_between_sweeps"))
        ant[:] = fill(Int8(0), nrays)

        ns = defVar(ds, "n_samples", Int32, ("time",),
            attrib = Dict("long_name" => "number_of_samples_used_to_compute_moments"))
        ns[:] = fill(Int32(64), nrays)

        # Moment data field (DBZ only - minimal)
        dbz = defVar(ds, "DBZ", Float32, ("range", "time"),
            attrib = Dict(
                "long_name" => "reflectivity",
                "standard_name" => "equivalent_reflectivity_factor",
                "units" => "dBZ",
                "_FillValue" => Float32(-9999.0)
            ))
        dbz[:,:] = zeros(Float32, ngates, nrays)
    end
end

"""Helper to write a string into a fixed-length Char variable."""
function _write_string!(var, str::String, len::Int)
    chars = fill('\0', len)
    for (i, c) in enumerate(str)
        i > len && break
        chars[i] = c
    end
    var[:] = chars
end

"""Helper to write a string into a column of a 2D Char variable."""
function _write_string_col!(var, str::String, len::Int, col::Int)
    chars = fill('\0', len)
    for (i, c) in enumerate(str)
        i > len && break
        chars[i] = c
    end
    var[:, col] = chars
end
