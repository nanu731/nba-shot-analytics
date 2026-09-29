# Pure M3 representation and guards. No file reads or model fits on sourcing.
M3_VERSION <- "context_m3_protocol_v0.1.0"
M3_SEASONS <- c("2021-22", "2022-23", "2023-24", "2024-25", "2025-26")
M3_FIELDS <- c("season", "player_id", "point_value", "finish_family", "creation_family",
  "period", "minutes_remaining", "seconds_remaining", "shooter_home_away",
  "score_margin_before", "pre_shot_score_verified", "score_sequence_agrees", "linkage_status")
M3_KEYS <- c("player_id_factor", "point_value_factor", "finish_family", "creation_family",
  "period_group", "period_minutes_remaining", "home_away", "score_margin_tens", "score_margin_missing")
m3_assert <- function(ok, message) { if (!isTRUE(ok)) stop(message, call. = FALSE); invisible(TRUE) }
m3_formula <- function() stats::as.formula(paste(
  "cbind(makes, misses) ~ point_value_factor + finish_family + creation_family +",
  "s(player_id_factor, bs = 're') + period_group + period_minutes_remaining +",
  "home_away + score_margin_tens + score_margin_missing"))
m3_fixed_formula <- function() ~ point_value_factor + finish_family + creation_family +
  period_group + period_minutes_remaining + home_away + score_margin_tens + score_margin_missing
m3_seal <- function(seasons) {
  m3_assert(length(seasons) > 0L && !anyNA(seasons) && all(seasons %in% M3_SEASONS),
    "Unregistered/prospective season: access forbidden")
}
m3_prepare <- function(x, player_levels = sort(unique(as.character(x$player_id)))) {
  m3_assert(identical(names(x), M3_FIELDS), "M3 predictor column allowlist changed")
  m3_seal(unique(x$season))
  m3_assert(nrow(x) > 0 && !anyNA(x[c("player_id", "point_value", "finish_family", "creation_family",
    "period", "minutes_remaining", "seconds_remaining", "pre_shot_score_verified", "linkage_status")]), "Missing required predictor")
  lev <- context_factor_levels()
  m3_assert(all(x$point_value %in% c(2L,3L)) && all(x$finish_family %in% lev$finish_family) &&
    all(x$creation_family %in% lev$creation_family), "Taxonomy/point level changed")
  integers <- function(v) all(is.finite(v) & v == floor(v))
  m3_assert(all(vapply(x[c("period","minutes_remaining","seconds_remaining")], integers, logical(1))) &&
    all(x$period >= 1 & x$period <= 10) && all(x$minutes_remaining >= 0) &&
    all(x$seconds_remaining >= 0 & x$seconds_remaining <= 59), "Invalid period clock")
  seconds <- 60 * x$minutes_remaining + x$seconds_remaining
  m3_assert(all(seconds <= ifelse(x$period <= 4,720,300)), "Period-specific clock boundary failed")
  missing <- is.na(x$score_margin_before)
  m3_assert(is.logical(x$pre_shot_score_verified) && identical(!missing, x$pre_shot_score_verified), "Unverified/exposed score margin")
  m3_assert(integers(x$score_margin_before[!missing]) &&
    all(x$score_sequence_agrees[!missing] %in% TRUE), "Score sequence verification failed")
  known_side <- !is.na(x$shooter_home_away)
  m3_assert(all(x$shooter_home_away[known_side] %in% c("home","away")) &&
    all(x$linkage_status[known_side | !missing] == "unique_exact"), "Unverified home/away or score join")
  data.frame(
    player_id_factor=factor(as.character(x$player_id),levels=player_levels),
    point_value_factor=factor(ifelse(x$point_value==2,"two","three"),levels=lev$point_value_factor),
    finish_family=factor(x$finish_family,levels=lev$finish_family),
    creation_family=factor(x$creation_family,levels=lev$creation_family),
    period_group=factor(ifelse(x$period<=4,as.character(x$period),"OT"),levels=c("1","2","3","4","OT")),
    period_minutes_remaining=seconds/60,
    home_away=factor(ifelse(known_side,x$shooter_home_away,"unknown"),levels=c("home","away","unknown")),
    score_margin_tens=ifelse(missing,0,x$score_margin_before)/10,
    score_margin_missing=as.integer(missing))
}
m3_support <- function(prepared, training_range = NULL, training = TRUE) {
  m3_assert(identical(names(prepared), M3_KEYS), "Prepared feature matrix changed")
  m3_assert(!anyNA(prepared[setdiff(M3_KEYS,"player_id_factor")]), "Missing prepared predictor")
  if (training) {
    m3_assert(!anyNA(prepared$player_id_factor), "Missing training player")
    for (field in c("point_value_factor","finish_family","creation_family","period_group","home_away"))
      m3_assert(all(table(prepared[[field]]) > 0), paste("Unsupported training factor",field))
    for (field in c("period_minutes_remaining","score_margin_tens","score_margin_missing"))
      m3_assert(length(unique(prepared[[field]])) > 1L, paste("Constant predictor",field))
    # Twenty fixed columns only. Accumulate a Gram matrix in bounded chunks.
    gram <- matrix(0,20,20)
    for (start in seq.int(1,nrow(prepared),by=10000L)) {
      matrix_part <- model.matrix(m3_fixed_formula(), prepared[start:min(start+9999L,nrow(prepared)),])
      m3_assert(ncol(matrix_part)==20L && all(is.finite(matrix_part)), "Fixed design dimensions/values failed")
      gram <- gram + crossprod(matrix_part)
    }
    m3_assert(qr(gram,tol=1e-10)$rank==20L, "Fixed design not identifiable; no automatic form change")
  }
  observed <- prepared$score_margin_tens[prepared$score_margin_missing==0L]
  if (!is.null(training_range)) m3_assert(length(observed)>0 &&
    all(observed>=training_range[1] & observed<=training_range[2]), "Score margin extrapolation blocked")
  invisible(range(observed))
}
m3_group <- function(prepared, outcome = NULL) {
  m3_assert(!anyNA(prepared) && identical(names(prepared),M3_KEYS), "Invalid grouping predictors")
  if (is.null(outcome)) return(dplyr::distinct(prepared))
  context_assert_binary(outcome)
  m3_assert(length(outcome)==nrow(prepared), "Outcome alignment failed")
  prepared$field_goal_made <- outcome
  prepared |>
    dplyr::group_by(dplyr::across(dplyr::all_of(M3_KEYS)),.drop=TRUE) |>
    dplyr::summarise(makes=sum(field_goal_made),attempts=dplyr::n(),misses=attempts-makes,.groups="drop") |>
    dplyr::arrange(dplyr::across(dplyr::all_of(M3_KEYS)))
}
m3_predict <- function(fit, predictors, predict_function = stats::predict) {
  players <- levels(fit$model$player_id_factor)
  prepared <- m3_prepare(predictors,players)
  m3_support(prepared,range(fit$model$score_margin_tens[fit$model$score_margin_missing==0]),FALSE)
  known <- !is.na(prepared$player_id_factor)
  p <- rep(NA_real_,nrow(prepared))
  if(any(known)) p[known] <- plogis(predict_function(fit,newdata=prepared[known,,drop=FALSE],type="link"))
  if(any(!known)) {
    unseen <- prepared[!known,,drop=FALSE]
    unseen$player_id_factor <- factor(rep("__UNSEEN_PLAYER__",nrow(unseen)),levels=c(players,"__UNSEEN_PLAYER__"))
    p[!known] <- plogis(suppressWarnings(predict_function(fit,newdata=unseen,type="link",
      exclude="s(player_id_factor)",newdata.guaranteed=TRUE)))
  }
  m3_assert(all(is.finite(p)) && all(p>0 & p<1), "Invalid M3 probabilities")
  list(probability=p,expected_points=context_expected_points(p,predictors$point_value),known_player=known)
}
m3_complete_case <- function(predictors) !is.na(predictors$shooter_home_away) &
  predictors$pre_shot_score_verified & !is.na(predictors$score_margin_before)
m3_bootstrap <- function(data, replicates=2000L, seed=20260914L) {
  m3_assert("probability_m3" %in% names(data) && !"probability_m2" %in% names(data), "Candidate naming conflict")
  names(data)[names(data)=="probability_m3"] <- "probability_m2"
  result <- context_m2_paired_game_bootstrap(data,replicates,seed)
  names(result) <- sub("m2", "m3", names(result),fixed=TRUE)
  result
}
m3_select <- function(...) {
  result <- context_m2_evaluation_select(...)
  result[] <- gsub("M2","M3",result,fixed=TRUE)
  result
}
