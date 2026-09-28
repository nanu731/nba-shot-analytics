# Isolated runner. Sourcing defines functions only; execution requires explicit mode.
suppressPackageStartupMessages({library(arrow);library(dplyr);library(jsonlite)})
source("R/location_edition_sensitivity_helpers.R")
source("R/location_edition_sensitivity_reporting.R")
LS_CACHE <- "data/cache/location_edition_sensitivity_v0_1"
LS_OUTPUT <- "data/processed/location_edition_sensitivity_v0_1"
LS_CONFIG <- "config/location_edition_sensitivity_execution_v0_1.json"
LS_GRID <- "config/location_edition_sensitivity_grid_v0_1.csv"
LS_PREREG <- "docs/LOCATION_EDITION_SENSITIVITY_PREREGISTRATION.md"
LS_CODE <- c("R/location_edition_sensitivity.R","R/location_edition_sensitivity_helpers.R",
  "R/location_edition_sensitivity_reporting.R","R/location_edition_sensitivity_tests.R")
LS_PRODUCTION <- c(
  "R/spatial_targeted_relocation_helpers.R"="bc23d4738fa19c15c0571754698ef2456c175f1e8d74ccab1d9030f1a6198aa7",
  "R/spatial_targeted_capped_website_export.R"="bc4b761d0dad35ebc5584a2b773020591c17caa93d569ea8db61f26042f1c113",
  "R/spatial_multiseason_website_export.R"="99edeb6622b18f57fecd83143cb44c4fed4fe67b23a7b05ece90676a96c7e211")
ls_hash <- function(path) {
  ls_check(file.exists(path),paste("missing hash input",path))
  x<-system2("shasum",c("-a","256",shQuote(path)),stdout=TRUE)
  ls_check(length(x)==1L && is.null(attr(x,"status")),"SHA-256 command")
  strsplit(x,"[[:space:]]+")[[1]][1]
}
ls_hashes <- function(paths) setNames(vapply(paths,ls_hash,character(1)),names(paths))
ls_git <- function(args) {
  x<-system2("git",args,stdout=TRUE,stderr=TRUE)
  ls_check(is.null(attr(x,"status")),paste("git",paste(args,collapse=" ")));x
}
ls_config <- function(locked=FALSE) {
  x<-fromJSON(LS_CONFIG)
  ls_check(identical(x$protocol_id,LS_ID) &&
    identical(x$preregistration_commit,"e8cc2704b59a99862204276945a83982dec956e3") &&
    identical(x$seasons,c("2025-26","2024-25","2023-24","2022-23","2021-22")) &&
    identical(x$player_counts,c(318L,304L,281L,292L,312L)) &&
    identical(x$shot_counts,c(194987L,194526L,192608L,192897L,193577L)) &&
    x$posterior_draws==4000L && x$posterior_seed==20260902L &&
    identical(x$requested_shares,LS_SHARES) && x$cells_per_player==156L &&
    x$tolerance==LS_TOL && identical(x$baseline_condition,"A10_E90_C50") &&
    identical(x$prospective_2026_27_access,FALSE) && x$model_refits==0L,
    "frozen execution configuration")
  ls_grid()
  ls_check(identical(ls_hashes(setNames(names(LS_PRODUCTION),names(LS_PRODUCTION))),LS_PRODUCTION),
    "production code hashes")
  for(p in c(LS_GRID,LS_PREREG)) ls_check(length(ls_git(c("diff","--name-only",
    x$preregistration_commit,"--",p)))==0L,"preregistration bytes unchanged")
  if(locked) {
    sha<-x$pre_result_implementation_commit
    ls_check(grepl("^[a-f0-9]{40}$",sha),"pushed implementation lock missing")
    ls_git(c("merge-base","--is-ancestor",sha,"HEAD"))
    ls_check(length(ls_git(c("diff","--name-only",sha,"--",LS_CODE)))==0L,
      "implementation changed after freeze")
    original<-fromJSON(paste(ls_git(c("show",paste0(sha,":",LS_CONFIG))),collapse="\n"))
    original$pre_result_implementation_commit<-sha
    ls_check(identical(original,x),"only registered hash changed in lock commit")
  }
  x
}
ls_synced <- function() {
  head<-ls_git(c("rev-parse","HEAD"));up<-ls_git(c("rev-parse","@{upstream}"))
  branch<-ls_git(c("branch","--show-current"))
  ls_check(identical(branch,"codex/location-edition-sensitivity-preregistration") &&
    identical(head,up) && length(ls_git(c("status","--porcelain","--untracked-files=no")))==0L,
    "clean pushed feature branch")
  remote<-ls_git(c("ls-remote","origin",paste0("refs/heads/",branch)))
  ls_check(length(remote)==1L && identical(strsplit(remote,"[[:space:]]+")[[1]][1],head),
    "GitHub commit differs")
  head
}
ls_inventory <- function(root) {
  files<-sort(list.files(root,recursive=TRUE,all.files=TRUE,no..=TRUE))
  files<-files[!file.info(file.path(root,files))$isdir]
  setNames(vapply(file.path(root,files),ls_hash,character(1)),files)
}
ls_atomic <- function(path,writer,context) {
  ls_check(!file.exists(path),paste("refusing overwrite",path))
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  stage<-tempfile(paste0(basename(path),".partial-"),dirname(path))
  ls_check(dir.create(stage),"atomic staging creation")
  writer(stage)
  h<-ls_inventory(stage)
  ls_check(length(h)>0 && !"complete.rds"%in%names(h),"atomic payload inventory")
  saveRDS(list(complete=TRUE,context=context,hashes=h),file.path(stage,"complete.rds"),compress=FALSE,version=3)
  writeLines(ls_hash(file.path(stage,"complete.rds")),file.path(stage,"complete.sha256"))
  ls_check(file.rename(stage,path),"atomic publication rename")
  ls_verify(path,context)
}
ls_verify <- function(path,context=NULL) {
  marker<-file.path(path,"complete.rds");seal<-file.path(path,"complete.sha256")
  ls_check(file.exists(marker)&&file.exists(seal),"incomplete atomic checkpoint")
  ls_check(identical(ls_hash(marker),readLines(seal,warn=FALSE)),"completion marker hash")
  m<-readRDS(marker)
  ls_check(isTRUE(m$complete) && (is.null(context)||identical(m$context,context)),"checkpoint context")
  h<-ls_inventory(path);h<-h[!names(h)%in%c("complete.rds","complete.sha256")]
  ls_check(identical(m$hashes,h),"atomic payload hashes")
  m
}
ls_write_parquet <- function(x,path) write_parquet(x,path,compression="snappy",version="2.6")
ls_note <- function(stage,details=list()) {
  dir.create(file.path(LS_CACHE,"operations"),recursive=TRUE,showWarnings=FALSE)
  rss<-suppressWarnings(as.numeric(system2("ps",c("-o","rss=","-p",Sys.getpid()),stdout=TRUE)))*1024
  disk<-system2("df",c("-k","."),stdout=TRUE)
  record<-c(list(stage=stage,utc=format(Sys.time(),tz="UTC",usetz=TRUE),pid=Sys.getpid(),
    proc_time=unclass(proc.time()),sampled_rss_bytes=rss,disk_snapshot=disk),details)
  saveRDS(record,tempfile("event-",file.path(LS_CACHE,"operations"),fileext=".rds"))
  cat(format(Sys.time(),tz="UTC",usetz=TRUE),stage,"\n");flush.console()
}
ls_sources <- function(config) {
  all<-list()
  for(i in seq_along(config$seasons)) {
    season<-config$seasons[i]
    root<-file.path("data/cache",if(season=="2025-26")"spatial_car_production"else
      "spatial_car_multiseason",paste0("season=",season))
    completion<-file.path(root,"production_complete_checkpoint.rds")
    ls_check(identical(ls_hash(completion),config$completion_sha256[i]),"production completion anchor")
    m<-readRDS(completion)
    ls_check(isTRUE(m$complete)&&all(m$checks$passed)&&identical(m$season,season)&&
      m$player_count==config$player_counts[i]&&m$shot_count==config$shot_counts[i]&&
      m$lattice_rows==156L*m$player_count,"production completion checks")
    fields<-c(input="input_sha256",configuration="configuration_sha256",fit="fit_sha256",
      surface="surface_sha256",uncertainty="uncertainty_sha256",hyperparameter="hyperparameter_sha256",
      model_checkpoint="model_checkpoint_sha256")
    paths<-setNames(file.path(root,c("production_input.rds","production_configuration.rds",
      "car_production_fit.rds","player_probability_surfaces.parquet","player_uncertainty_summary.parquet",
      "hyperparameter_summary.parquet","model_checkpoint.rds")),names(fields))
    paths<-c(paths,raw=file.path("data/raw/shots",paste0("season=",season),"shots.parquet"))
    expected<-c(setNames(vapply(fields,function(f)m[[f]],character(1)),names(fields)),raw=config$raw_sha256[i])
    hashes<-ls_hashes(paths)
    ls_check(identical(hashes,expected),paste(season,"full production payload hashes"))
    cfg<-readRDS(paths["configuration"])
    ls_check(identical(cfg,m$configuration)&&cfg$posterior_draws==4000L&&cfg$posterior_seed==20260902L&&
      cfg$grid_width==40L&&cfg$cells_per_player==156L,"production configuration identity")
    versions<-vapply(names(cfg$package_versions),function(p)if(p=="R")as.character(getRversion())else
      as.character(packageVersion(p)),character(1))
    ls_check(identical(versions,cfg$package_versions),"frozen runtime package versions")
    all[[season]]<-list(paths=paths,hashes=hashes,completion_sha256=config$completion_sha256[i],
      player_count=m$player_count,shot_count=m$shot_count,versions=versions)
  }
  v4<-"export/spatial-shot-selection/v4"
  ls_check(identical(ls_hash(file.path(v4,"manifest.json")),
    "685aa02b5003cb292fbe0926b242a351200f0cd785a169c31942f8518ac03242"),"v4 manifest anchor")
  manifest<-fromJSON(file.path(v4,"manifest.json"),simplifyVector=FALSE)
  for(p in manifest$payload_files)ls_check(identical(ls_hash(file.path(v4,p$path)),p$sha256),"v4 baseline payload")
  all
}
ls_prepare <- function(src,season) {
  input<-readRDS(src$paths["input"])
  ls_check(isTRUE(input$complete)&&identical(input$season,season)&&input$player_count==src$player_count&&
    input$shot_count==src$shot_count&&input$lattice_rows==156L*src$player_count,"input counts")
  lattice<-input$lattice |> arrange(PLAYER_ID,cell_id)
  ls_check(!anyDuplicated(lattice[c("PLAYER_ID","cell_id")]) &&
    identical(sort(unique(lattice$PLAYER_ID)),sort(input$player_ids)) &&
    all(vapply(split(lattice$cell_id,lattice$PLAYER_ID),function(x)identical(x,1:156),logical(1))) &&
    sum(lattice$attempts)==src$shot_count,"full frozen lattice keys")
  raw<-open_dataset(src$paths["raw"]) |>
    filter(PLAYER_ID %in% input$player_ids,LOC_Y<=397.5) |>
    select(PLAYER_ID,LOC_X,LOC_Y,SHOT_TYPE,SHOT_MADE_FLAG,GAME_ID) |>collect()|>as_tibble()
  ls_check(nrow(raw)==src$shot_count&&all(raw$SHOT_TYPE%in%c("2PT Field Goal","3PT Field Goal"))&&
    all(raw$SHOT_MADE_FLAG%in%c(0L,1L))&&is.character(raw$GAME_ID),"authorized raw values")
  eligible<-raw |>summarise(attempts=n(),games=n_distinct(GAME_ID),.by=PLAYER_ID)
  ls_check(all(eligible$attempts>=250 & eligible$games>=20),"original eligibility")
  cells<-target_assign_cells(raw)|>summarise(n=n(),m=sum(SHOT_MADE_FLAG),
    point_value=2+mean(SHOT_TYPE=="3PT Field Goal"),.by=c(PLAYER_ID,cell_id))
  lattice<-left_join(lattice,cells,by=c("PLAYER_ID","cell_id"))
  observed<-lattice$attempts>0
  ls_check(all(lattice$attempts[observed]==lattice$n[observed])&&
    all(lattice$makes[observed]==lattice$m[observed]),"raw/production count identity")
  lattice$point_value[!observed]<-0
  volume<-lattice |>summarise(attempts=sum(attempts),.by=PLAYER_ID)|>arrange(desc(attempts),PLAYER_ID)
  high<-head(volume$PLAYER_ID,ceiling(nrow(volume)/4))
  list(lattice=lattice,player_ids=input$player_ids,high_volume=high)
}
ls_draws <- function(src,prepared,season,context) {
  root<-file.path(LS_CACHE,"draws",season)
  if(dir.exists(root)) {ls_verify(root,context);return(root)}
  started<-file.path(LS_CACHE,paste0("draw-recovery-started-",season,".rds"))
  ls_check(!file.exists(started),"unfinished draw recovery: separate decision required")
  saveRDS(list(season=season,context=context,pid=Sys.getpid(),started=Sys.time()),started)
  ls_note(paste("recovering_draws",season))
  fit<-readRDS(src$paths["fit"])
  ls_check(isTRUE(fit$ok)&&identical(as.numeric(fit$mode$mode.status),0),"saved CAR fit status")
  RNGkind("Mersenne-Twister","Inversion","Rejection");set.seed(20260902L)
  warnings<-character()
  samples<-withCallingHandlers(INLA::inla.posterior.sample(n=4000L,result=fit,
    selection=list(Predictor=prepared$lattice$predictor_index),seed=20260902L,
    num.threads=1L,parallel.configs=FALSE,add.names=FALSE),warning=function(w){
      warnings<<-c(warnings,conditionMessage(w))
    })
  labels<-rownames(samples[[1]]$latent)
  indices<-suppressWarnings(as.integer(sub("^Predictor:","",labels)))
  expected<-prepared$lattice$predictor_index
  ls_check(!is.null(labels)&&!anyNA(indices)&&!anyDuplicated(indices)&&setequal(indices,expected),
    "posterior predictor selection")
  draws<-vapply(samples,function(s)as.numeric(s$latent),numeric(length(expected)))
  draws<-plogis(draws[match(expected,indices),,drop=FALSE]);rm(samples,fit);gc()
  surface<-read_parquet(src$paths["surface"])|>arrange(PLAYER_ID,cell_id)
  ls_check(identical(as.integer(dim(draws)),c(as.integer(nrow(prepared$lattice)),4000L))&&
    all(is.finite(draws))&&all(draws>=0 & draws<=1)&&
    identical(surface$PLAYER_ID,prepared$lattice$PLAYER_ID)&&
    identical(surface$cell_id,prepared$lattice$cell_id)&&
    max(abs(rowMeans(draws)-surface$draw_mean_probability))<=LS_TOL,"registered draw reproduction")
  ls_atomic(root,function(p) {
    saveRDS(draws,file.path(p,"draws.rds"),compress=FALSE,version=3)
    saveRDS(prepared,file.path(p,"input.rds"),compress=FALSE,version=3)
  },context)
  ls_note(paste("draws_complete",season),list(bytes=file.info(file.path(root,"draws.rds"))$size,
    posterior_warnings=warnings,maximum_draw_mean_difference=max(abs(rowMeans(draws)-surface$draw_mean_probability))))
  root
}
ls_baseline <- function(prepared,draws,season,condition) {
  result<-list()
  ids<-sort(prepared$player_ids)
  for(id in ids) {
    ii<-which(prepared$lattice$PLAYER_ID==id);z<-prepared$lattice[ii,]
    r<-ls_player(z$attempts,z$point_value,z$cell_id,draws[ii,,drop=FALSE],condition)
    p<-fromJSON(file.path("export/spatial-shot-selection/v4/seasons",season,"players",paste0(id,".json")),
      simplifyVector=FALSE)
    ls_check(identical(p$player_id,as.character(id))&&identical(p$season,season),"baseline exact identity")
    ls_equal(as.numeric(z$attempts),as.numeric(vapply(p$heatmap_cells,`[[`,integer(1),"observed_attempts")),"baseline cell attempts")
    ls_check(identical(z$cell_id,vapply(p$heatmap_cells,`[[`,integer(1),"cell_id")),"baseline exact cell order")
    for(k in which(z$attempts>0))ls_equal(z$point_value[k],p$heatmap_cells[[k]]$effective_point_value,
      "baseline effective shot value")
    ls_baseline_check(r,p)
    result[[as.character(id)]]<-r
  }
  result
}
ls_condition <- function(prepared,draws,baseline,season,condition) {
  pcs<-pss<-allocations<-list();ids<-sort(prepared$player_ids)
  for(j in seq_along(ids)) {
    id<-ids[j];ii<-which(prepared$lattice$PLAYER_ID==id);z<-prepared$lattice[ii,]
    b<-baseline[[as.character(id)]]
    r<-if(condition$is_baseline)b else ls_player(z$attempts,z$point_value,z$cell_id,draws[ii,,drop=FALSE],condition)
    records<-ls_records(r,b,season,id,condition$condition_id,id%in%prepared$high_volume)
    pcs[[j]]<-records$player_condition;pss[[j]]<-records$player_slider
    allocations[[as.character(id)]]<-list(supported=r$supported,allocation=r$allocations)
  }
  list(player_condition=bind_rows(pcs),player_slider=bind_rows(pss),allocations=allocations)
}
ls_build_season <- function(prepared,draws,baseline,season,grid,root,context) {
  pcs<-pss<-list();support<-list()
  for(i in seq_len(nrow(grid))) {
    id<-grid$condition_id[i];path<-file.path(root,season,id)
    if(!dir.exists(path)) {
      ls_note(paste("condition",basename(root),season,id))
      result<-ls_condition(prepared,draws,baseline,season,grid[i,])
      ls_atomic(path,function(p) {
        ls_write_parquet(result$player_condition,file.path(p,"player_condition.parquet"))
        ls_write_parquet(result$player_slider,file.path(p,"player_slider.parquet"))
        saveRDS(result$allocations,file.path(p,"allocations.rds"),compress=FALSE,version=3)
      },context)
    }
    ls_verify(path,context)
    pcs[[i]]<-read_parquet(file.path(path,"player_condition.parquet"))
    pss[[i]]<-read_parquet(file.path(path,"player_slider.parquet"))
    a<-readRDS(file.path(path,"allocations.rds"))
    support[[i]]<-unlist(lapply(a,`[[`,"supported"),use.names=FALSE)
  }
  for(i in 1:27)for(j in 1:27) {
    if(grid$min_destination_attempts[i]>=grid$min_destination_attempts[j] &&
       grid$min_posterior_evidence[i]>=grid$min_posterior_evidence[j])
      ls_check(!any(support[[i]] & !support[[j]]),"nested support independent of cap")
  }
  pc<-bind_rows(pcs);ps<-bind_rows(pss)
  ls_check(nrow(pc)==length(prepared$player_ids)*27L&&nrow(ps)==nrow(pc)*6L&&
    !anyDuplicated(pc[c("season","player_id","condition_id")])&&
    !anyDuplicated(ps[c("season","player_id","condition_id","requested_share")])&&
    all(pc$high_volume==pc$player_id%in%prepared$high_volume),"complete private coverage and volume membership")
  final<-file.path(root,season,"summary")
  if(!dir.exists(final)) {
    st<-ls_stability(pc,ps,grid);agg<-ls_aggregate(pc,ps,grid)
    stab<-ls_stability_aggregate(st,pc)
    ls_atomic(final,function(p) {
    ls_write_parquet(st$player_stability,file.path(p,"player_stability.parquet"))
    ls_write_parquet(st$factor_contrasts,file.path(p,"factor_contrasts.parquet"))
    ls_write_parquet(stab$factor_profiles,file.path(p,"factor_profiles.parquet"))
    ls_write_parquet(stab$attribution,file.path(p,"attribution.parquet"))
    ls_write_parquet(agg,file.path(p,"aggregate_summary.parquet"))
    ls_write_parquet(stab$aggregate,file.path(p,"stability_summary.parquet"))
    },context)
  }
  ls_verify(final,context)
  final
}
ls_execute <- function(mode) {
  ls_check(mode%in%c("audit","authorize","run","verify"),"explicit runner mode")
  cfg<-ls_config(mode!="audit");grid<-ls_grid()
  if(mode=="audit") {cat("Outcome-free configuration/code audit passed. No source/model access.\n");return(invisible(TRUE))}
  head<-ls_synced()
  context<-list(protocol_id=LS_ID,implementation_commit=cfg$pre_result_implementation_commit,
    configuration_sha256=ls_hash(LS_CONFIG),grid_sha256=ls_hash(LS_GRID),preregistration_sha256=ls_hash(LS_PREREG),
    code_sha256=ls_hashes(setNames(LS_CODE,LS_CODE)))
  auth_path<-file.path(LS_CACHE,"authorization.rds")
  if(mode=="authorize") {
    ls_check(!file.exists(auth_path),"preserve existing authorization")
    dir.create(LS_CACHE,recursive=TRUE,showWarnings=FALSE)
    saveRDS(list(context=context,execution_commit=head,authorized_seasons=cfg$seasons,
      user_authorization="d6d76981-c3dd-4b7a-8286-b3a815613ffa",allow_refit=FALSE,
      authorized_at_utc=format(Sys.time(),tz="UTC",usetz=TRUE)),auth_path)
    return(invisible(TRUE))
  }
  ls_check(file.exists(auth_path),"private authorization required")
  auth<-readRDS(auth_path)
  ls_check(identical(auth$context,context)&&identical(auth$authorized_seasons,cfg$seasons)&&
    identical(auth$allow_refit,FALSE),"authorization identity")
  if(mode=="verify") {
    ls_verify(file.path(LS_CACHE,"published"),context)
    for(s in cfg$seasons) {
      root<-file.path(LS_CACHE,"published",s)
      for(name in c("aggregate_summary.parquet","stability_summary.parquet"))
        ls_public_check(read_parquet(file.path(root,name)))
    }
    h<-ls_inventory(file.path(LS_CACHE,"published"));h<-h[grepl("\\.parquet$",names(h))]
    ls_check(identical(ls_inventory(LS_OUTPUT),h),"public/private aggregate identity")
    cat("Verified complete aggregate result; no model, draw, or raw outcome loaded.\n");return(invisible(TRUE))
  }
  if(dir.exists(file.path(LS_CACHE,"published")))stop("Completed result exists; use verify, not run.")
  ls_check(!length(list.files(LS_CACHE,pattern="^failure-")),"preserved failure needs separate authorization")
  lock<-file.path(LS_CACHE,"run.lock")
  if(dir.exists(lock)) {
    owner<-readRDS(file.path(lock,"owner.rds"))
    alive<-system2("ps",c("-p",owner$pid,"-o","pid="),stdout=TRUE,stderr=FALSE)
    ls_check(!length(alive),"existing sensitivity process remains active")
    ls_check(file.rename(lock,tempfile("recovered-lock-",LS_CACHE)),"preserve stale lock")
  }
  ls_check(dir.create(lock),"exclusive study lock")
  saveRDS(list(pid=Sys.getpid(),context=context,started=Sys.time()),file.path(lock,"owner.rds"))
  tryCatch({
    ls_note("source_verification")
    protected<-ls_inventory("export/spatial-shot-selection")
    sources<-ls_sources(cfg)
    saveRDS(list(context=context,sources=sources,protected=protected),
      tempfile("source-audit-",LS_CACHE,fileext=".rds"))
    for(season in cfg$seasons) {
      src<-sources[[season]];prepared<-ls_prepare(src,season)
      draw_root<-ls_draws(src,prepared,season,context)
      base_path<-file.path(LS_CACHE,"baseline",season)
      if(!dir.exists(base_path)) {
        ls_note(paste("baseline",season))
        draws<-readRDS(file.path(draw_root,"draws.rds"))
        b<-ls_baseline(prepared,draws,season,grid[grid$is_baseline,])
        ls_atomic(base_path,function(p)saveRDS(b,file.path(p,"baseline.rds"),compress=FALSE,version=3),context)
        rm(draws,b);gc()
      }
      ls_verify(base_path,context)
    }
    ls_note("all_five_baselines_passed")
    for(build in c("build_one","build_two"))for(season in cfg$seasons) {
      root<-file.path(LS_CACHE,"draws",season);ls_verify(root,context)
      prepared<-readRDS(file.path(root,"input.rds"));draws<-readRDS(file.path(root,"draws.rds"))
      bp<-file.path(LS_CACHE,"baseline",season);ls_verify(bp,context)
      baseline<-readRDS(file.path(bp,"baseline.rds"))
      ls_build_season(prepared,draws,baseline,season,grid,file.path(LS_CACHE,build),context)
      rm(prepared,draws,baseline);gc()
    }
    h1<-ls_inventory(file.path(LS_CACHE,"build_one"));h2<-ls_inventory(file.path(LS_CACHE,"build_two"))
    ls_check(identical(h1,h2),"two clean builds byte identity")
    ls_check(identical(protected,ls_inventory("export/spatial-shot-selection")),"production exports unchanged")
    # Rehash full model/source payloads, without loading a model again.
    ls_check(identical(sources,ls_sources(cfg)),"production sources unchanged after study")
    ls_synced()
    pub<-file.path(LS_CACHE,"published")
    ls_atomic(pub,function(p) {
      for(season in cfg$seasons) {
        dir.create(file.path(p,season))
        for(name in c("aggregate_summary.parquet","stability_summary.parquet")) {
          src<-file.path(LS_CACHE,"build_one",season,"summary",name)
          ls_public_check(read_parquet(src))
          ls_check(file.copy(src,file.path(p,season,name),overwrite=FALSE),"aggregate copy")
        }
      }
      provenance<-bind_rows(lapply(cfg$seasons,function(s)data.frame(protocol_id=LS_ID,season=s,
        artifact=names(sources[[s]]$hashes),sha256=unname(sources[[s]]$hashes))))
      ls_write_parquet(provenance,file.path(p,"source_hashes.parquet"))
      ls_write_parquet(data.frame(protocol_id=LS_ID,pre_result_commit=cfg$pre_result_implementation_commit,
        execution_commit=head,baseline_verified=TRUE,byte_identical_builds=TRUE,
        seasons=5L,player_seasons=1507L,conditions=27L,shares=6L,
        player_condition_rows=40689L,player_slider_rows=244134L,model_refits=0L,
        prospective_access=FALSE),file.path(p,"study_audit.parquet"))
    },context)
    ls_check(!dir.exists(LS_OUTPUT),"preserve prior aggregate outputs")
    output_stage<-tempfile("aggregate-publication-",LS_CACHE)
    ls_check(dir.create(output_stage),"aggregate publication staging")
    # Only Parquet aggregate payloads leave private storage; manifests stay private.
    files<-names(ls_inventory(pub));files<-files[grepl("\\.parquet$",files)]
    for(f in files) {
      dir.create(dirname(file.path(output_stage,f)),recursive=TRUE,showWarnings=FALSE)
      ls_check(file.copy(file.path(pub,f),file.path(output_stage,f),overwrite=FALSE),"public aggregate copy")
    }
    ls_check(identical(ls_inventory(output_stage),ls_inventory(pub)[files]),"staged public payload hashes")
    ls_check(file.rename(output_stage,LS_OUTPUT),"atomic aggregate directory publication")
    ls_note("complete",list(private_bytes=sum(file.info(list.files(LS_CACHE,recursive=TRUE,full.names=TRUE))$size,na.rm=TRUE)))
    ls_check(file.rename(lock,file.path(LS_CACHE,"completed.lock")),"preserve completed lock")
  },error=function(e) {
    ls_note("failure",list(message=conditionMessage(e)))
    saveRDS(list(context=context,error=conditionMessage(e),time=Sys.time()),
      tempfile("failure-",LS_CACHE,fileext=".rds"))
    stop(e)
  })
}
if(sys.nframe()==0L) {
  args<-commandArgs(trailingOnly=TRUE)
  ls_check(length(args)==1L,"one explicit mode required")
  ls_execute(args[1])
}
