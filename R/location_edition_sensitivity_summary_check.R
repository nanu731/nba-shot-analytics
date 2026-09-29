# Explicit verification-only mode: cached condition tables, never models/draws.
source("R/location_edition_sensitivity.R")
args<-commandArgs(trailingOnly=TRUE)
ls_check(length(args)==1L && args[1]%in%ls_config(FALSE)$seasons,"one authorized summary season")
season<-args[1];cfg<-ls_config(FALSE);grid<-ls_grid()
setTimeLimit(elapsed=600,transient=FALSE)
ctx<-readRDS(file.path(LS_CACHE,"authorization.rds"))$context
root<-file.path(LS_CACHE,"build_one",season)
pc<-ps<-list()
for(i in seq_len(nrow(grid))) {
  p<-file.path(root,grid$condition_id[i]);ls_verify(p,ctx)
  pc[[i]]<-read_parquet(file.path(p,"player_condition.parquet"))
  ps[[i]]<-read_parquet(file.path(p,"player_slider.parquet"))
}
pc<-bind_rows(pc);ps<-bind_rows(ps)
expected<-file.path(root,"summary");ls_verify(expected,ctx)
# Leave every temporary verification output intact in the existing private namespace.
out<-tempfile(paste0("summary-equivalence-",season,"-"),file.path(LS_CACHE,"operations"))
ls_check(dir.create(out),"isolated verification directory")
start<-proc.time();st<-ls_stability(pc,ps,grid);agg<-ls_aggregate(pc,ps,grid)
stab<-ls_stability_aggregate(st,pc)
tables<-list(player_stability=st$player_stability,factor_contrasts=st$factor_contrasts,
  factor_profiles=stab$factor_profiles,attribution=stab$attribution,
  aggregate_summary=agg,stability_summary=stab$aggregate)
for(n in names(tables)) {
  path<-file.path(out,paste0(n,".parquet"));ref<-file.path(expected,paste0(n,".parquet"))
  ls_write_parquet(tables[[n]],path)
  # identical includes types, attributes, row/key ordering, values and null positions.
  ls_check(identical(read_parquet(path),read_parquet(ref)),paste(n,"exact object equality"))
  ls_check(identical(ls_hash(path),ls_hash(ref)),paste(n,"registered byte equality"))
}
elapsed<-unclass(proc.time()-start)
saveRDS(list(season=season,complete=TRUE,reporting_sha256=ls_hash(
  "R/location_edition_sensitivity_reporting.R"),reference=expected,
  hashes=ls_inventory(out),elapsed=elapsed),file.path(out,"verification.rds"))
cat("PASS",season,"six tables: exact schemas/types/keys/order/values/nulls/bytes; seconds",
  elapsed["elapsed"],"private verification",out,"\n")
