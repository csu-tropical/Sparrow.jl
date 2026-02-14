# QC helper functions and workflow steps

function seapol_level_one()

   # Get the sigmet data from the SEA-POL server
   sigmet_raw = temp_dir * "/sigmet_raw/" * date
   if time == "now"
       link_latest_sigmet_data(date, sigmet_raw)
   else
       link_sigmet_data(date, time, sigmet_raw)
   end

   # Convert the Sigmet files to CfRadial
   println("Converting Sigmet data to CfRadial...")
   sigmet_files = readdir(sigmet_raw; join=true)
   filter!(!isdir,sigmet_files)

   cfrad_raw = temp_dir * "/cfrad_raw"
   for file in sigmet_files
       scan_name = String(readchomp(pipeline(`RadxPrint -f $file`, `grep scanName`)))
       outdir = cfrad_raw
       if contains(scan_name, "VOL") || contains(scan_name, "SUR")
           outdir = outdir * "/sur"
       else
           outdir = outdir * "/rhi"
       end

       # Need to sort and force the number of gates to get time, range dimension instead of n_points
       run(`RadxConvert -sort_rays_by_time -outdir $outdir -const_ngates -f $file`)
   end
end
