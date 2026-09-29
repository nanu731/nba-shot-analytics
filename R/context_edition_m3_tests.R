#!/usr/bin/env Rscript
# Synthetic values only. No canonical read, real model load, fit, or validation access.
source("R/context_edition_m3_runner.R")
checks <- data.frame(check=character(),passed=logical())
check <- function(name,code) {force(code);checks[nrow(checks)+1L,] <<- list(name,TRUE)}
reject <- function(code) stopifnot(inherits(try(force(code),silent=TRUE),"try-error"))
lev <- context_factor_levels()
g <- expand.grid(point_value=c(2L,3L),finish_family=lev$finish_family,creation_family=lev$creation_family,
  period=c(1L,2L,3L,4L,5L),side=c("home","away",NA_character_),margin=c(-10L,0L,10L),clock=c(0L,120L),
  stringsAsFactors=FALSE)
x <- data.frame(season="2021-22",player_id=rep(c("synthetic_a","synthetic_b"),length.out=nrow(g)),
  point_value=g$point_value,finish_family=g$finish_family,creation_family=g$creation_family,
  period=g$period,minutes_remaining=g$clock%/%60,seconds_remaining=g$clock%%60,
  shooter_home_away=g$side,score_margin_before=g$margin,
  pre_shot_score_verified=TRUE,score_sequence_agrees=TRUE,
  linkage_status=ifelse(is.na(g$side),"unmatched_event","unique_exact"))
missing <- is.na(g$side) | seq_len(nrow(g))%%17L==0L
x$score_margin_before[missing] <- NA_integer_;x$pre_shot_score_verified[missing] <- FALSE
x$score_sequence_agrees[missing] <- NA
p <- m3_prepare(x)
check("configuration_and_package_versions",{m3_config();m3_environment();m3_dependencies()})
check("exact_M1_preservation",stopifnot(identical(deparse(context_model_formulas()$M1),deparse(context_m2_formulas()$M1))))
check("exact_M3_terms",stopifnot(setequal(all.vars(m3_formula()),c("makes","misses",M3_KEYS)) && length(M3_KEYS)==9L))
check("three_frozen_windows",{w<-m3_windows();stopifnot(identical(w$validation_season,M3_SEASONS[3:5]))})
check("no_prospective_access",{reject(m3_read("2026-27"));reject(m3_seal(c("2021-22","2026-27")))})
check("no_validation_execution_mode",{reject(m3_main(c("evaluate","development_1")));reject(m3_main("finalize"))})
check("training_read_requires_exact_authorized_window",{reject(m3_read("2023-24",TRUE));reject(m3_read("2025-26",TRUE,"2025-26"))})
check("exact_feature_allowlist",{bad<-x;bad$field_goal_made<-0L;reject(m3_prepare(bad))})
check("blocked_distance_context_text",{for(field in c("shot_distance_feet","x","defender","shot_clock","raw_pbp_description")){bad<-x;bad[[field]]<-0;reject(m3_prepare(bad))}})
check("factor_levels_and_unknown_taxonomy",{stopifnot(identical(levels(p$creation_family),lev$creation_family),"other_or_unknown" %in% p$creation_family)})
check("invalid_taxonomy_stops",{bad<-x;bad$finish_family[1]<-"invented";reject(m3_prepare(bad))})
check("unknown_is_explicit",stopifnot(all(as.character(p$home_away[is.na(x$shooter_home_away)])=="unknown")))
check("neutral_fill_not_tied_score",{stopifnot(all(p$score_margin_tens[missing]==0),all(p$score_margin_missing[missing]==1),all(p$score_margin_missing[!missing]==0))})
check("unverified_margin_rejected",{bad<-x;bad$pre_shot_score_verified[1]<-FALSE;bad$score_margin_before[1]<-2L;reject(m3_prepare(bad))})
check("missing_verified_margin_rejected",{bad<-x;bad$pre_shot_score_verified[1]<-TRUE;bad$score_margin_before[1]<-NA;reject(m3_prepare(bad))})
check("sequence_disagreement_rejected",{bad<-x;bad$score_sequence_agrees[1]<-FALSE;reject(m3_prepare(bad))})
check("unverified_side_rejected",{bad<-x;bad$linkage_status[1]<-"unmatched_event";reject(m3_prepare(bad))})
check("factor_unknown_typo_rejected",{bad<-x;bad$shooter_home_away[1]<-"neutral";reject(m3_prepare(bad))})
check("regulation_boundary",{bad<-x;bad$minutes_remaining[1]<-12L;bad$seconds_remaining[1]<-0L;m3_prepare(bad);bad$seconds_remaining[1]<-1L;reject(m3_prepare(bad))})
check("OT_boundary",{bad<-x;bad$period[1]<-5L;bad$minutes_remaining[1]<-5L;bad$seconds_remaining[1]<-0L;m3_prepare(bad);bad$seconds_remaining[1]<-1L;reject(m3_prepare(bad))})
check("invalid_clock_and_period",{bad<-x;bad$seconds_remaining[1]<-60L;reject(m3_prepare(bad));bad<-x;bad$period[1]<-11L;reject(m3_prepare(bad))})
check("nonfinite_predictors",{bad<-x;bad$minutes_remaining[1]<-Inf;reject(m3_prepare(bad))})
check("full_rank_fixed_design",m3_support(p))
check("rank_failure_stops",{bad<-p;bad$score_margin_missing<-as.integer(bad$home_away=="unknown");reject(m3_support(bad))})
check("nonconstant_numeric_guard",{bad<-p;bad$period_minutes_remaining<-0;reject(m3_support(bad))})
check("range_extrapolation_guard",reject(m3_support(p,c(-0.5,0.5),FALSE)))
check("grouping_has_all_context_fields",{stopifnot(identical(names(m3_group(p)),M3_KEYS));y<-rep(c(0L,1L),length.out=nrow(p));z<-m3_group(p,y);stopifnot(sum(z$attempts)==length(y),sum(z$makes)==sum(y),sum(z$misses)==sum(1-y))})
check("grouping_likelihood_equivalence",{y<-rep(c(0L,1L),length.out=nrow(p));z<-m3_group(p,y);a<-sum(y*log(.4)+(1-y)*log(.6));b<-sum(z$makes*log(.4)+z$misses*log(.6));stopifnot(abs(a-b)<1e-9)})
check("outcome_alignment_rejected",reject(m3_group(p,0L)))
check("complete_case_definition",stopifnot(identical(m3_complete_case(x),!is.na(x$shooter_home_away)&!missing)))
check("deterministic_preparation_and_grouping",{stopifnot(identical(p,m3_prepare(x)),identical(m3_group(p),m3_group(p)))})
check("known_and_unseen_player_prediction",{
  fake<-list(model=p);test<-x[1:2,];test$player_id[2]<-"new_player"
  calls<-list();mock<-function(object,newdata,type,exclude=NULL,newdata.guaranteed=FALSE){
    calls[[length(calls)+1L]]<<-list(exclude=exclude,type=type,guaranteed=newdata.guaranteed)
    rep(0,nrow(newdata))}
  a<-m3_predict(fake,test,mock);b<-m3_predict(fake,test,mock)
  stopifnot(identical(a,b),identical(a$known_player,c(TRUE,FALSE)),identical(a$probability,c(.5,.5)),
    identical(a$expected_points,test$point_value*.5),is.null(calls[[1]]$exclude),calls[[2]]$exclude=="s(player_id_factor)",calls[[2]]$guaranteed)
})
check("invalid_prediction_rejected",{fake<-list(model=p);reject(m3_predict(fake,x[1:2,],function(...)rep(Inf,2)))})
check("bootstrap_exact_M2_reuse_and_determinism",{
  b<-data.frame(comparison_id=rep(c("development_1","development_2","development_3"),each=8),
    game_id=rep(rep(c("synthetic_game_a","synthetic_game_b"),each=4),3),outcome=rep(c(0L,1L),12),
    probability_m1=rep(c(.3,.6),12),probability_m3=rep(c(.35,.65),12))
  r<-m3_bootstrap(b,20);r2<-m3_bootstrap(b,20);names(b)[5]<-"probability_m2"
  old<-context_m2_paired_game_bootstrap(b,20);names(old)<-sub("m2","m3",names(old),fixed=TRUE)
  stopifnot(identical(r,r2),identical(r,old))
})
check("all_selection_gates",{
  choose<-function(candidate=.64,se=.001,bias=0,ece=0,seasons=c(.64,.64,.64))
    m3_select(.65,candidate,se,bias,ece,c(.65,.65,.65),seasons)[["model"]]
  stopifnot(choose()=="M3",choose(.65)=="M1",choose(se=.02)=="M1",choose(bias=.006)=="M1",
    choose(ece=.006)=="M1",choose(seasons=c(.64,.66,.66))=="M1",choose(ece=.005)=="M3")
})
check("recovery_action_inherits_frozen_rules",{
  f<-context_m2_evaluation_recovery_action
  stopifnot(f(TRUE,FALSE,FALSE)=="verify_completed_result",f(FALSE,TRUE,TRUE)=="resume_from_predictions",
    f(FALSE,TRUE,FALSE)=="stop_for_manual_recovery",f(FALSE,FALSE,TRUE)=="reject_orphan_checkpoint")
})
check("atomic_no_overwrite_and_hash_rejection",{
  root<-tempfile("m3-synthetic-");dir.create(root);a<-file.path(root,"stage");b<-file.path(root,"final");dir.create(a)
  writeLines("synthetic",file.path(a,"test.txt"));hash<-m3_hash(file.path(a,"test.txt"));context_preflight_atomic_publish(a,b)
  context_m2_evaluation_verify_hash(file.path(b,"test.txt"),hash,m3_hash)
  reject(context_m2_evaluation_verify_hash(file.path(b,"test.txt"),paste(rep("0",64),collapse=""),m3_hash))
  dir.create(a);reject(context_preflight_atomic_publish(a,b)) # Preserve temp evidence; no deletion.
})
check("authorization_absence_stops",reject(context_m2_evaluation_verify_authorization(tempfile(),"development_1",paste(rep("a",40),collapse=""))))
check("runner_default_audit_and_no_top_level_fit",{
  source_text<-readLines("R/context_edition_m3_runner.R")
  stopifnot(any(grepl('else "audit"',source_text,fixed=TRUE)),sum(grepl('mgcv::gam(',source_text,fixed=TRUE))==1L,
    any(grepl('if(sys.nframe()==0L)m3_main()',source_text,fixed=TRUE)))
})
check("privacy_and_seals",{
  conf<-m3_config();stopifnot(all(conf[grepl("access",names(conf)) & names(conf)!="execution_authorization_required"]=="FALSE"))
  stopifnot(!any(c("source_game_id","source_event_id","field_goal_made","raw_pbp_description")%in%M3_FIELDS))
})
check("parsing",{for(file in c("R/context_edition_m3_protocol.R","R/context_edition_m3_runner.R","R/context_edition_m3_tests.R"))invisible(parse(file))})
check("exclusive_attempt_directory",{
  root<-tempfile("m3-lock-synthetic-");stopifnot(dir.create(root),!dir.create(root,showWarnings=FALSE))
})
check("completed_checkpoint_recovery_without_fit",{
  root<-tempfile("m3-checkpoint-synthetic-");dir.create(root)
  saveRDS(list(synthetic=TRUE),file.path(root,"fit.rds"))
  meta<-list(config_sha256="synthetic",fits=1L,validation_outcomes_accessed=FALSE,prospective_accessed=FALSE,
    comparison_id="development_1",training_seasons="2021-22;2022-23",training_partition_sha256s="synthetic",
    shots=2L,players=1L,coefficients=21L)
  saveRDS(meta,file.path(root,"metadata.rds"));write.csv(data.frame(check="synthetic",passed=TRUE),file.path(root,"checks.csv"),row.names=FALSE)
  files<-c("fit.rds","metadata.rds","checks.csv")
  write.csv(data.frame(artifact=files,sha256=vapply(file.path(root,files),m3_hash,character(1)),
    atomic_complete=TRUE,checks_passed=TRUE),file.path(root,"completion_manifest.csv"),row.names=FALSE)
  w<-data.frame(comparison_id="development_1",training_seasons=meta$training_seasons,
    training_partition_sha256s="synthetic",training_shots=2L,training_players=1L)
  stopifnot(identical(m3_bundle_verify(root,"synthetic",w),meta));reject(m3_bundle_verify(root,"wrong",w))
  w$training_shots<-3L;reject(m3_bundle_verify(root,"synthetic",w))
  writeLines("corruption",file.path(root,"fit.rds"));reject(m3_bundle_verify(root,"synthetic"))
})
check("pre_result_commit_shape_and_no_schema_extension",{
  hash<-m3_config()[["pre_result_implementation_commit"]]
  if(hash!="PENDING") {
    stopifnot(system2("git",c("cat-file","-e",paste0(hash,"^{commit}")))==0L)
    for(file in c("R/context_edition_m3_runner.R","R/context_edition_m3_protocol.R","R/context_edition_m3_tests.R"))
      stopifnot(system2("git",c("diff","--quiet",hash,"--",file))==0L)
  }
})
check("published_dimension_privacy_and_integrity",{
  if(dir.exists(m3_public)) {
    context_preflight_verify_manifest(read.csv(file.path(m3_public,"completion_manifest.csv")),m3_public,m3_hash)
    d<-read.csv(file.path(m3_public,"predictor_dimensions.csv"))
    stopifnot(nrow(d)==3L,all(d$fits==0L),!any(d$outcomes_accessed),!any(d$prospective_accessed),
      all(d$coefficients==d$training_players+20L),!any(grepl("player_id|game_id|event_id|outcome$|prediction",names(d))))
  }
})
cat(nrow(checks),"M3 structural/synthetic checks passed; no canonical rows, models or real outcomes loaded\n")
