#!/usr/bin/env Rscript
# Outcome-free audit by default. Only separately authorized fit mode reads training responses.
suppressPackageStartupMessages({library(arrow);library(dplyr);library(readr);library(mgcv)})
options(contrasts=c("contr.treatment","contr.poly"))
for (file in c("context_edition_m0_m1_protocol.R","context_edition_m2_protocol.R",
  "context_edition_preflight_helpers.R","context_edition_first_validation_helpers.R",
  "context_edition_m2_evaluation_helpers.R","context_edition_m3_protocol.R")) source(file.path("R",file))

m3_config_path <- "config/context_edition_m3_v0_1.csv"
m3_private <- "data/cache/context_edition_m3"
m3_public <- "data/processed/context_edition_m3_preregistration_v0_1"
m3_canonical <- "data/cache/context_edition_canonical/context_field_goal_v0.1.2__2021-22_to_2025-26"
m3_hash <- context_sha256_file
m3_write <- context_write_csv_stable
m3_config <- function() {
  x <- read.csv(m3_config_path,colClasses="character",check.names=FALSE)
  m3_assert(!anyDuplicated(x$key) && identical(names(x),c("key","value")),"Configuration schema failed")
  values <- setNames(x$value,x$key)
  expected <- c(protocol_version=M3_VERSION,audit_result_commit="ce042f3760162dabb74a6b06ef6bb94a2da07da7",
    inherited_windows="config/context_edition_m2_evaluation_windows_v0_1.csv",primary_difference_sign="M3_minus_M1",
    probability_clip="1e-15",bootstrap_replicates="2000",bootstrap_seed="20260914",material_calibration_margin="0.005",
    minimum_subgroup_shots="200",minimum_season_wins="2",tie_or_failed_gate_action="retain_M1",
    period_levels="1;2;3;4;OT",home_away_levels="home;away;unknown",period_time_divisor="60",score_margin_divisor="10",
    missing_score_fill="0",score_margin_missing_indicator="TRUE",complete_case_diagnostic="same_saved_predictions_no_extra_fit",
    PMM="do_not_advance_failed_or_unavailable_joins",fit_engine="mgcv::gam",fit_method="REML",optimizer="outer;newton",
    discrete="FALSE",select="FALSE",gamma="1",worker_count="1",fit_seed="20260914",execution_authorization_required="TRUE",
    validation_execution_enabled="FALSE",validation_2023_24_outcomes_accessed="FALSE",validation_2024_25_outcomes_accessed="FALSE",
    validation_2025_26_outcomes_accessed="FALSE",prospective_2026_27_access_allowed="FALSE",model_fits_performed="0",
    performance_comparison_created="FALSE",public_shot_rows="FALSE")
  m3_assert(setequal(names(values),c(names(expected),"pre_result_implementation_commit")) &&
    identical(unname(values[names(expected)]),unname(expected)),"Frozen M3 configuration changed")
  m3_assert(values[["pre_result_implementation_commit"]]=="PENDING" ||
    grepl("^[0-9a-f]{40}$",values[["pre_result_implementation_commit"]]),"Invalid pre-result commit")
  values
}
m3_environment <- function() {
  expected <- c(mgcv="1.9.4",Matrix="1.7.5",arrow="25.0.0",dplyr="1.2.1",tidyr="1.3.2",readr="2.2.0")
  actual <- vapply(names(expected),function(p)as.character(packageVersion(p)),character(1))
  m3_assert(identical(actual,expected) && getRversion()=="4.6.0","Frozen package environment changed")
  actual
}
m3_dependencies <- function() {
  manifest <- read.csv("config/context_edition_m3_dependencies_v0_1.csv",colClasses="character")
  m3_assert(identical(names(manifest),c("file","sha256")) && !anyDuplicated(manifest$file),"Dependency manifest schema failed")
  for(i in seq_len(nrow(manifest))) context_m2_evaluation_verify_hash(manifest$file[i],manifest$sha256[i],m3_hash)
  invisible(manifest)
}
m3_windows <- function() {
  windows <- read.csv("config/context_edition_m2_evaluation_windows_v0_1.csv",stringsAsFactors=FALSE,na.strings=NULL)
  context_m2_evaluation_validate_windows(windows)
  windows
}
m3_source_manifest <- function() {
  path <- file.path(m3_canonical,"completion_manifest.csv")
  context_m2_evaluation_verify_hash(path,"5f8e294903701a3fb99511f060b1da269823c63fb350cda9a1fc15ca8cea20dc",m3_hash)
  read.csv(path,stringsAsFactors=FALSE)
}
m3_read <- function(seasons,training_response=FALSE,authorized_training=NULL) {
  m3_seal(seasons) # Before constructing any path.
  if(training_response) m3_assert(identical(seasons,authorized_training) &&
    all(seasons %in% c("2021-22","2022-23","2023-24","2024-25")),"Training-response access not authorized")
  manifest <- m3_source_manifest()
  fields <- c(M3_FIELDS,if(training_response) "field_goal_made")
  bind_rows(lapply(seasons,function(season){
    relative <- paste0("season=",season,"/canonical_shots.parquet")
    row <- manifest[manifest$artifact==relative,,drop=FALSE]
    path <- file.path(m3_canonical,relative)
    m3_assert(nrow(row)==1L && isTRUE(row$atomic_complete) && isTRUE(row$checks_passed),"Invalid partition manifest")
    context_m2_evaluation_verify_hash(path,row$sha256,m3_hash)
    x <- arrow::read_parquet(path,col_select=all_of(fields),as_data_frame=TRUE)
    m3_assert(identical(names(x),fields) && nrow(x)==row$rows && identical(unique(x$season),season),"Partition schema/rows failed")
    x
  }))
}
m3_verify_m1 <- function(row) {
  context_m2_evaluation_verify_hash(row$m1_fit_source,row$m1_fit_sha256,m3_hash)
  root <- dirname(row$m1_fit_source)
  m <- read.csv(file.path(root,"completion_manifest.csv"),stringsAsFactors=FALSE)
  context_preflight_verify_manifest(m,root,m3_hash)
  m3_assert(sum(m$artifact==basename(row$m1_fit_source))==1L &&
    m$sha256[m$artifact==basename(row$m1_fit_source)]==row$m1_fit_sha256,"M1 manifest mismatch")
  # No model loading is necessary in an outcome-free dimensions audit.
  invisible(TRUE)
}
m3_audit <- function(publish=FALSE) {
  m3_config();m3_environment();m3_dependencies()
  windows <- m3_windows()
  m3_assert(!dir.exists(file.path(m3_private,"access")),"Unexpected M3 outcome-access record")
  results <- lapply(seq_len(nrow(windows)),function(i){
    row <- windows[i,];m3_verify_m1(row)
    seasons <- strsplit(row$training_seasons,";",fixed=TRUE)[[1]]
    x <- m3_read(seasons);prepared <- m3_prepare(x)
    training_range <- m3_support(prepared)
    validation <- m3_read(row$validation_season)
    m3_support(m3_prepare(validation,levels(prepared$player_id_factor)),training_range,FALSE)
    grouped <- nrow(m3_group(prepared))
    players <- nlevels(prepared$player_id_factor);coefs <- players+20L
    m3_assert(nrow(x)==row$training_shots && players==row$training_players,"Frozen training population mismatch")
    dense <- grouped*coefs*8
    data.frame(comparison_id=row$comparison_id,training_seasons=row$training_seasons,
      validation_season=row$validation_season,training_shots=nrow(x),training_players=players,
      grouped_rows=grouped,coefficients=coefs,fixed_columns=20L,smoothing_parameters=1L,
      complete_case_training_rows=sum(m3_complete_case(x)),complete_case_validation_rows=sum(m3_complete_case(validation)),
      validation_predictor_rows=nrow(validation),dense_matrix_bytes=dense,
      estimated_working_bytes=4*dense+1024^3,
      estimated_wall_minutes_low=c(60,90,180)[i],estimated_wall_minutes_high=c(480,720,1440)[i],
      estimates_not_benchmarks=TRUE,predictor_checks_passed=TRUE,
      fits=0L,outcomes_accessed=FALSE,prospective_accessed=FALSE)
  })
  results <- bind_rows(results)
  if(publish) {
    m3_assert(!dir.exists(m3_public),"Dimensions bundle already exists; do not overwrite")
    stage <- paste0(m3_public,".partial-",Sys.getpid())
    m3_assert(!dir.exists(stage),"Partial dimensions bundle exists")
    dir.create(stage,recursive=TRUE)
    m3_write(results,file.path(stage,"predictor_dimensions.csv"))
    m3_write(data.frame(artifact="predictor_dimensions.csv",sha256=m3_hash(file.path(stage,"predictor_dimensions.csv")),
      atomic_complete=TRUE,checks_passed=TRUE),file.path(stage,"completion_manifest.csv"))
    context_preflight_atomic_publish(stage,m3_public)
  }
  results
}
m3_pushed_lock <- function(config) {
  hash <- config[["pre_result_implementation_commit"]]
  m3_assert(grepl("^[0-9a-f]{40}$",hash),"Pre-result lock required")
  git <- function(args) context_git_value(normalizePath("."),args)
  m3_assert(git(c("branch","--show-current"))=="codex/context-edition-m3-preregistration","Wrong execution branch")
  m3_assert(git(c("rev-parse","HEAD"))==git(c("rev-parse","@{upstream}")),"Unpushed execution code")
  remote <- system2("git",c("ls-remote","origin","refs/heads/codex/context-edition-m3-preregistration"),stdout=TRUE)
  m3_assert(length(remote)==1L && strsplit(remote,"\t")[[1]][1]==git(c("rev-parse","HEAD")),"GitHub revision mismatch")
  m3_assert(system2("git",c("merge-base","--is-ancestor",hash,"HEAD"))==0L &&
    system2("git",c("diff","--quiet"))==0L && system2("git",c("diff","--cached","--quiet"))==0L,"Dirty or non-ancestor execution")
  # Lock must name this implementation, not merely any historical commit.
  frozen <- c("R/context_edition_m3_runner.R","R/context_edition_m3_protocol.R",
    "R/context_edition_m3_tests.R","docs/CONTEXT_EDITION_M3_PREREGISTRATION.md",
    "config/context_edition_m3_dependencies_v0_1.csv",m3_public)
  m3_assert(system2("git",c("diff","--quiet",hash,"HEAD","--",frozen))==0L,"Implementation changed since pre-result commit")
  invisible(hash)
}
m3_bundle_verify <- function(root,config_hash=NULL,window=NULL) {
  manifest <- read.csv(file.path(root,"completion_manifest.csv"),stringsAsFactors=FALSE)
  m3_assert(setequal(list.files(root),c("fit.rds","metadata.rds","checks.csv","completion_manifest.csv")) &&
    identical(sort(manifest$artifact),sort(c("fit.rds","metadata.rds","checks.csv"))),"Unexpected fit bundle inventory")
  context_preflight_verify_manifest(manifest,root,m3_hash)
  meta <- readRDS(file.path(root,"metadata.rds"))
  if(!is.null(config_hash)) m3_assert(meta$config_sha256==config_hash,"Checkpoint configuration mismatch")
  m3_assert(meta$fits==1L && !meta$validation_outcomes_accessed && !meta$prospective_accessed,"Invalid fit/access accounting")
  if(!is.null(window)) m3_assert(meta$comparison_id==window$comparison_id &&
    meta$training_seasons==window$training_seasons && meta$training_partition_sha256s==window$training_partition_sha256s &&
    meta$shots==window$training_shots && meta$players==window$training_players &&
    meta$coefficients==window$training_players+20L,"Checkpoint input/window mismatch")
  invisible(meta)
}
m3_check_fit <- function(fit,counts,predictors,expected_coefficients) {
  formula_text <- function(f) gsub("[[:space:]]+","",paste(deparse(f),collapse=""))
  m3_assert(inherits(fit,"gam") && isTRUE(fit$converged) && identical(fit$outer.info$conv,"full convergence") &&
    formula_text(formula(fit))==formula_text(m3_formula()) && length(coef(fit))==expected_coefficients &&
    all(is.finite(coef(fit))) && all(is.finite(fit$Vp)) && all(is.finite(fit$edf)) &&
    length(fit$sp)==1L && all(is.finite(fit$sp)) && all(fit$sp>0) &&
    all(is.finite(fit$outer.info$grad)),"M3 fit/convergence failed; no refit permitted")
  m3_assert(fit$family$family=="binomial" && fit$family$link=="logit" && fit$method=="REML" &&
    length(fit$smooth)==1L && inherits(fit$smooth[[1]],"random.effect"),"Frozen likelihood/engine structure failed")
  for(field in c("point_value_factor","finish_family","creation_family","period_group","home_away"))
    m3_assert(identical(levels(fit$model[[field]]),levels(counts[[field]])),paste("Fit factor changed",field))
  m3_assert(max(abs(fit$Vp-t(fit$Vp)))<1e-8 && min(eigen(fit$Vp,symmetric=TRUE,only.values=TRUE)$values)>=-1e-8,
    "Covariance symmetry/PSD failed")
  m3_assert(nrow(fit$model)==nrow(counts) && sum(fit$model[["cbind(makes, misses)"]])==nrow(predictors),"Fitted population changed")
  first <- m3_predict(fit,predictors);second <- m3_predict(fit,predictors)
  m3_assert(identical(first,second),"Prediction determinism failed")
  m3_assert(identical(first$expected_points,first$probability*predictors$point_value),"Expected points failed")
  data.frame(check=c("formula_dimensions","convergence","finite_coefficients_covariance_edf_sp_gradient",
    "covariance_psd","training_population","probability_bounds","expected_points","deterministic_predictions"),passed=TRUE)
}
m3_fit <- function(id) {
  config <- m3_config();versions <- m3_environment();m3_dependencies();m3_pushed_lock(config)
  windows <- m3_windows();row <- windows[windows$comparison_id==id,,drop=FALSE]
  m3_assert(nrow(row)==1L,"Unregistered comparison")
  authorization <- file.path(m3_private,"authorizations",paste0(id,".csv"))
  context_m2_evaluation_verify_authorization(authorization,id,config[["pre_result_implementation_commit"]])
  auth <- read.csv(authorization,stringsAsFactors=FALSE)
  m3_assert(identical(auth$action,"fit") && identical(auth$model_id,"M3"),"Fit-only M3 authorization required")
  m3_verify_m1(row)
  final <- file.path(m3_private,"fits",id)
  if(dir.exists(final)) { m3_bundle_verify(final,m3_hash(m3_config_path),row);message("Verified completed M3 checkpoint; zero refits");return(invisible(NULL)) }
  attempt <- file.path(m3_private,"attempts",id)
  dir.create(dirname(attempt),recursive=TRUE,showWarnings=FALSE)
  m3_assert(dir.create(attempt,showWarnings=FALSE),"Existing attempt/lock: preserve evidence; manual recovery required")
  m3_write(data.frame(pid=Sys.getpid(),started_utc=format(Sys.time(),tz="UTC"),stage="preflight",
    pre_result_commit=config[["pre_result_implementation_commit"]]),file.path(attempt,"pid.csv"))
  started <- Sys.time();cpu_started <- proc.time()
  tryCatch({
    seasons <- strsplit(row$training_seasons,";",fixed=TRUE)[[1]]
    predictors <- m3_read(seasons);prepared <- m3_prepare(predictors)
    training_range <- m3_support(prepared)
    m3_support(m3_prepare(m3_read(row$validation_season),levels(prepared$player_id_factor)),training_range,FALSE)
    context_preflight_verify_manifest(read.csv(file.path(m3_public,"completion_manifest.csv")),m3_public,m3_hash)
    dims <- read.csv(file.path(m3_public,"predictor_dimensions.csv"));dim <- dims[dims$comparison_id==id,]
    m3_assert(nrow(dim)==1L && nrow(m3_group(prepared))==dim$grouped_rows &&
      nrow(prepared)==row$training_shots && nlevels(prepared$player_id_factor)==row$training_players,"Dimensions changed")
    physical_memory <- suppressWarnings(as.numeric(system2("sysctl",c("-n","hw.memsize"),stdout=TRUE)))
    m3_assert(length(physical_memory)==1L && is.finite(physical_memory) &&
      dim$estimated_working_bytes+3*1024^3<=physical_memory,
      "Conservative memory estimate leaves less than 3 GiB headroom; no fit attempted")
    m3_assert(context_available_disk_bytes(".")>=10*1024^3,"Less than 10 GiB free disk; no fit attempted")
    training <- m3_read(seasons,TRUE,seasons)
    m3_assert(identical(training[M3_FIELDS],predictors),"Training predictor alignment failed")
    counts <- m3_group(prepared,training$field_goal_made)
    m3_assert(nrow(counts)==dim$grouped_rows && sum(counts$attempts)==row$training_shots,"Grouped counts failed")
    m3_write(data.frame(stage="fit_started",timestamp=format(Sys.time(),tz="UTC")),file.path(attempt,"fit_started.csv"))
    RNGkind("Mersenne-Twister","Inversion","Rejection");set.seed(20260914L)
    warnings <- character();fit_started <- Sys.time();fit_cpu <- proc.time()
    fit <- withCallingHandlers(mgcv::gam(m3_formula(),family=binomial(link="logit"),data=counts,
      method="REML",optimizer=c("outer","newton"),control=mgcv::gam.control(),select=FALSE,gamma=1,
      na.action=na.fail,drop.unused.levels=FALSE,discrete=FALSE),warning=function(w){
        warnings <<- c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
    fit_seconds <- as.numeric(difftime(Sys.time(),fit_started,units="secs"));fit_cpu <- proc.time()-fit_cpu
    saveRDS(fit,file.path(attempt,"fit.rds"),compress="xz") # Private partial evidence, NOT a completion checkpoint.
    m3_write(data.frame(warning=warnings),file.path(attempt,"warnings.csv"))
    m3_assert(length(warnings)==0L,"Fit warnings: stop without refitting")
    checks <- m3_check_fit(fit,counts,predictors,dim$coefficients)
    stage <- file.path(attempt,"publish.partial");dir.create(stage)
    m3_assert(file.copy(file.path(attempt,"fit.rds"),file.path(stage,"fit.rds"),overwrite=FALSE),"Could not preserve fit")
    metadata <- list(protocol=M3_VERSION,comparison_id=id,training_seasons=row$training_seasons,
      training_partition_sha256s=row$training_partition_sha256s,config_sha256=m3_hash(m3_config_path),
      implementation_commit=config[["pre_result_implementation_commit"]],fits=1L,
      validation_outcomes_accessed=FALSE,prospective_accessed=FALSE,shots=nrow(training),grouped_rows=nrow(counts),
      players=nlevels(prepared$player_id_factor),coefficients=length(coef(fit)),versions=versions,
      fit_seconds=fit_seconds,fit_cpu=fit_cpu,total_seconds=as.numeric(difftime(Sys.time(),started,units="secs")),
      total_cpu=proc.time()-cpu_started,rss_sample_bytes=context_current_rss_bytes(),
      disk_available_bytes=context_available_disk_bytes("."),object_bytes=as.numeric(object.size(fit)),
      serialized_bytes=file.info(file.path(stage,"fit.rds"))$size,warnings=warnings,sp=fit$sp,
      edf=sum(fit$edf),max_abs_gradient=max(abs(fit$outer.info$grad)))
    saveRDS(metadata,file.path(stage,"metadata.rds"));m3_write(checks,file.path(stage,"checks.csv"))
    files <- c("fit.rds","metadata.rds","checks.csv")
    m3_write(data.frame(artifact=files,sha256=vapply(file.path(stage,files),m3_hash,character(1)),
      atomic_complete=TRUE,checks_passed=TRUE),file.path(stage,"completion_manifest.csv"))
    m3_bundle_verify(stage,m3_hash(m3_config_path),row)
    dir.create(dirname(final),recursive=TRUE,showWarnings=FALSE);context_preflight_atomic_publish(stage,final)
    message("One M3 training fit published; validation outcomes remain sealed")
  },error=function(e){m3_write(data.frame(error=conditionMessage(e),timestamp=format(Sys.time(),tz="UTC")),
    file.path(attempt,"failure.csv"));stop(e)})
}
m3_main <- function(args=commandArgs(trailingOnly=TRUE)) {
  mode <- if(length(args))args[1] else "audit"
  m3_assert(mode %in% c("audit","publish-audit","fit","verify"),"No validation/evaluation mode is authorized or implemented")
  if(mode %in% c("audit","publish-audit")) {print(m3_audit(mode=="publish-audit"));return(invisible(NULL))}
  m3_assert(length(args)==2L && args[2] %in% paste0("development_",1:3),"Registered window required")
  if(mode=="fit")m3_fit(args[2]) else {
    m3_config();m3_dependencies();m3_environment()
    windows <- m3_windows()
    m3_bundle_verify(file.path(m3_private,"fits",args[2]),m3_hash(m3_config_path),windows[windows$comparison_id==args[2],])
    message("Private checkpoint hashes verified without outcomes or refitting")
  }
}
if(sys.nframe()==0L)m3_main()
