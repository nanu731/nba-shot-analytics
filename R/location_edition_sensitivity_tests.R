# Outcome-free integration tests: invented players only, no production loader.
source("R/location_edition_sensitivity.R")
original_private_inventory<-list.files(LS_CACHE,recursive=TRUE,all.files=TRUE)
passed<-character()
test<-function(name,x){ls_check(x,name);passed<<-c(passed,name)}
rejects<-function(x)inherits(tryCatch(force(x),error=identity),"error")
grid<-ls_grid();cfg<-ls_config(FALSE)
test("27 exact ordered conditions",nrow(grid)==27L&&sum(grid$is_baseline)==1L)
test("configuration parser and explicit seal",identical(cfg$prospective_2026_27_access,FALSE))
test("code parses",all(vapply(LS_CODE,function(p)length(parse(p))>0L,logical(1))))
runner<-paste(readLines(LS_CODE[1]),collapse="\n")
test("no fitting entry point",!any(grepl("INLA::inla\\(|mgcv::|source\\(.*export",readLines(LS_CODE[1]))))
test("no prospective path",!grepl("2026-27",runner,fixed=TRUE))
test("pending lock rejects execution",cfg$pre_result_implementation_commit!="PENDING"||rejects(ls_config(TRUE)))
test("production helpers frozen",identical(ls_hashes(setNames(names(LS_PRODUCTION),names(LS_PRODUCTION))),LS_PRODUCTION))
test("movement interface has no outcomes",!any(grepl("made|miss|outcome",names(formals(ls_player)))))
draws<-matrix(rep(c(.8,.7,.3),4000),3,4000)
baseline<-ls_player(c(450L,100L,450L),c(2,2,2),1:3,draws,grid[14,])
test("invented baseline support",identical(baseline$supported,c(TRUE,TRUE,FALSE)))
test("invented baseline weak order",identical(baseline$source_order,3L))
test("redistribution after cap",max(abs(baseline$allocations$added[,6]-c(.05,.2,0)))<=LS_TOL)
test("full movement cap reached but not limited",baseline$sliders[[6]]$receiving_cap_reached&&
  !baseline$sliders[[6]]$cap_limited&&baseline$sliders[[6]]$full_request_achieved)
test("exact zero request",all(unlist(baseline$sliders[[1]]$season_gain)==0))
test("score convention",abs(baseline$score$point-100*1.13/1.34)<=LS_TOL)
test("fractional movement",abs(target_remove_mass(c(.2,.3,.5),1:2,.25)$removed[2]-.05)<LS_TOL)
test("negative interval retained",ls_summary(c(-2,1,2))$lower_90<0)
test("invalid draw rejected",rejects(ls_player(c(1,1,1),c(2,2,2),1:3,draws+1,grid[14,])))
test("invalid cell duplicate rejected",rejects(ls_player(c(1,1,1),c(2,2,2),c(1,1,2),draws,grid[14,])))
test("wrong draw count rejected",rejects(ls_player(c(1,1,1),c(2,2,2),1:3,draws[,-1],grid[14,])))
overcap<-ls_player(c(600,200,200),c(2,2,2),1:3,matrix(rep(c(.9,.2,.2),4000),3),grid[1,])
test("historical overcap zero additions",all(overcap$allocations$added==0)&&!overcap$availability)
test("unavailable zero request remains null",all(is.na(unlist(overcap$sliders[[1]]$season_gain))))
test("unavailable score null",all(is.na(unlist(overcap$score))))
test("unavailable full zero request trivial",overcap$sliders[[1]]$full_request_achieved)
test("deterministic pure calculation",identical(baseline,
  ls_player(c(450L,100L,450L),c(2,2,2),1:3,draws,grid[14,])))
synthetic<-list(attempts=c(450,100,450),point_value=c(2,2,2),cell_id=1:3,made=c(0,1,0))
flip<-synthetic;flip$made<-1-flip$made
calc<-function(z)ls_player(z$attempts,z$point_value,z$cell_id,draws,grid[14,])
test("outcome independence",identical(calc(synthetic),calc(flip)))
# Independently specified production-shaped fixture, with no real export read.
published<-list(observed_attempts=1000,evidence_status="multiple_destinations",supported_destination_count=2L,
  relocation_available=TRUE,availability_reason="available",eligible_source_share=.45,
  total_supported_destination_capacity=.45,source_cell_count=1L,
  baseline_expected_points_per_attempt=list(mean=1.13,lower_90=1.13,upper_90=1.13),
  score=list(point=100*1.13/1.34,lower_90=100*1.13/1.34,upper_90=100*1.13/1.34),
  heatmap_cells=lapply(c(TRUE,TRUE,FALSE),function(x)list(supported_destination=x)))
published$sliders<-lapply(LS_SHARES,function(s){
  a<-if(s<=(.05/.45*.55))c(s*.45/.55,s*.1/.55)else c(.05,s-.05)
  ep<-1.13+sum(a*c(1.6,1.4))-.6*s
  su<-function(v)list(mean=v,lower_90=v,upper_90=v)
  list(requested_share=s,actual_relocated_share=s,actual_relocated_attempt_equivalents=1000*s,
    relocated_expected_points_per_attempt=su(ep),season_gain=su(1000*(ep-1.13)),gain_per_100=su(100*(ep-1.13)),
    destination_allocation=list(list(cell_id=1L,added_share=a[1],final_share=.45+a[1]),
      list(cell_id=2L,added_share=a[2],final_share=.1+a[2])))})
test("independent baseline fixture",ls_baseline_check(baseline,published))
bad<-published;bad$evidence_status<-"single_destination"
test("baseline exact category failure",rejects(ls_baseline_check(baseline,bad)))
bad<-published;bad$sliders[[6]]$season_gain$mean<-0
test("baseline numerical failure",rejects(ls_baseline_check(baseline,bad)))
bad<-published;bad$sliders[[6]]$destination_allocation[[1]]$cell_id<-3L
test("baseline cell identity failure",rejects(ls_baseline_check(baseline,bad)))
test("null and zero distinguished",rejects(ls_equal(0,NULL)))
test("paired self differences exact zero",{
  r<-ls_records(baseline,baseline,"invented",1L,"A10_E90_C50",TRUE)
  all(r$player_slider$season_gain_delta_mean==0)&&r$player_condition$score_delta==0
})
test("availability transitions",identical(ls_transition(c(TRUE,FALSE,TRUE,FALSE),c(FALSE,TRUE,TRUE,FALSE)),
  c("gained","lost","available_both","unavailable_both")))
test("gain sign inclusive zero",identical(ls_gain_category(c(.1,-1,-1,NA),c(.2,-.1,0,NA)),
  c("positive","negative","includes_zero","unavailable")))
pcs<-pss<-list();idx<-0L
for(id in 1:3) {
  a<-switch(id,c(450,100,450),c(8,12,80),c(60,20,20))
  d<-if(id==3)matrix(rep(c(.9,.2,.2),4000),3)else draws
  b<-ls_player(a,c(2,2,2),1:3,d,grid[14,])
  for(i in 1:27) {
    idx<-idx+1L;r<-ls_player(a,c(2,2,2),1:3,d,grid[i,])
    rr<-ls_records(r,b,"invented",id,grid$condition_id[i],id==1)
    pcs[[idx]]<-rr$player_condition;pss[[idx]]<-rr$player_slider
  }
}
pc<-bind_rows(pcs);ps<-bind_rows(pss)
test("full synthetic coverage",nrow(pc)==81L&&nrow(ps)==486L)
agg<-ls_aggregate(pc,ps,grid)
test("aggregate schema privacy",ls_public_check(agg))
bad<-agg;bad$player_id<-1
test("private column rejected",rejects(ls_public_check(bad)))
test("unavailable paired gain remains null",all(is.na(ps$season_gain_delta_mean[
  ps$player_id==3 & ps$condition_id=="A05_E80_C30"])))
st<-ls_stability(pc,ps,grid);sa<-ls_stability_aggregate(st,pc)
test("27 categorical agreements not majority cutoff",all(st$player_stability$modal_count<=27,na.rm=TRUE))
test("nine contrasts per factor",all(table(interaction(st$factor_contrasts[c("player_id","requested_share","endpoint","factor")],drop=TRUE))==9))
test("factor and stability privacy",ls_public_check(sa$aggregate))
test("exact categorical modal count",all(st$player_stability$modal_count[
  st$player_stability$player_id==1 & st$player_stability$endpoint=="evidence_category"]==27))
test("fixed volume group",all(agg$denominator_n[agg$group=="high_volume" & agg$metric_id=="actual_share"]==1))
test("zero-denominator proportions null",is.na(ls_public_row("invented","all",0,"all","empty",logical(),TRUE)$proportion))
test("empty numeric distribution null",all(is.na(unlist(ls_public_row("invented","all",0,"all","empty",c(NA_real_))[12:16]))))
tmp<-tempfile("location-sensitivity-synthetic-");dir.create(tmp)
ctx<-list(invented=TRUE)
writer<-function(p){ls_write_parquet(agg,file.path(p,"aggregate.parquet"));
  ls_write_parquet(sa$aggregate,file.path(p,"stability.parquet"));
  ls_write_parquet(st$player_stability,file.path(p,"private_stability.parquet"));
  ls_write_parquet(ps,file.path(p,"private_slider.parquet"))}
ls_atomic(file.path(tmp,"first"),writer,ctx);ls_atomic(file.path(tmp,"second"),writer,ctx)
test("two-build bytes including list columns",identical(ls_inventory(file.path(tmp,"first")),ls_inventory(file.path(tmp,"second"))))
test("atomic checkpoint reuse",isTRUE(ls_verify(file.path(tmp,"first"),ctx)$complete))
test("checkpoint context mismatch rejected",rejects(ls_verify(file.path(tmp,"first"),list(wrong=TRUE))))
test("checkpoint overwrite rejected",rejects(ls_atomic(file.path(tmp,"first"),writer,ctx)))
dir.create(file.path(tmp,"partial"))
test("incomplete checkpoint rejected",rejects(ls_verify(file.path(tmp,"partial"),ctx)))
test("exclusive lock first acquisition",dir.create(file.path(tmp,"lock")))
test("exclusive lock second acquisition rejected",!suppressWarnings(dir.create(file.path(tmp,"lock"))))
writeLines("corrupt",file.path(tmp,"second","aggregate.parquet"))
test("changed payload rejected",rejects(ls_verify(file.path(tmp,"second"),ctx)))
test("no real run created",identical(original_private_inventory,list.files(LS_CACHE,recursive=TRUE,all.files=TRUE)))
cat("PASS:",length(passed),"outcome-free structural, synthetic, baseline, privacy and recovery checks.\n")
