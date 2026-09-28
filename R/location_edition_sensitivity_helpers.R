# Pure calculations for location_sensitivity_v0.1.0. No data/model loader.
source("R/spatial_targeted_relocation_helpers.R")
LS_ID <- "location_sensitivity_v0.1.0"
LS_SHARES <- c(0, .05, .10, .15, .20, .25)
LS_TOL <- 1e-12
ls_check <- function(ok, label) {
  if (!isTRUE(ok)) stop("SENSITIVITY CHECK FAILED: ", label, call. = FALSE)
}
ls_grid <- function(path = "config/location_edition_sensitivity_grid_v0_1.csv") {
  g <- read.csv(path, stringsAsFactors = FALSE)
  e <- expand.grid(min_destination_attempts = c(5L,10L,20L),
                   min_posterior_evidence = c(.8,.9,.95),
                   max_final_destination_share = c(.3,.5,.7))
  e <- e[order(e[[1]],e[[2]],e[[3]]), ]
  ls_check(identical(names(g), c("condition_id",names(e),"is_baseline")) &&
    nrow(g) == 27L && !anyNA(g) && !anyDuplicated(g$condition_id) &&
    isTRUE(all.equal(unname(as.matrix(g[2:4])),unname(as.matrix(e)),tolerance=0)) &&
    identical(g$condition_id, sprintf("A%02d_E%02d_C%02d",g[[2]],
      as.integer(round(g[[3]]*100)),as.integer(round(g[[4]]*100)))) &&
    identical(which(g$is_baseline),14L), "ordered frozen grid")
  g
}
ls_equal <- function(actual, expected, label = "baseline") {
  if (is.null(expected)) expected <- NA_real_
  if (is.list(actual)) {
    ls_check(is.list(expected) && identical(names(actual),names(expected)) &&
               length(actual)==length(expected),paste(label,"list schema"))
    for (i in seq_along(actual)) ls_equal(actual[[i]],expected[[i]],paste(label,i))
  } else if (is.numeric(actual)) {
    ls_check(length(actual)==length(expected) &&
      identical(is.na(actual),is.na(expected)),paste(label,"numeric/null shape"))
    keep <- !is.na(actual)
    ls_check(all(is.finite(actual[keep])) && all(is.finite(expected[keep])) &&
      all(abs(actual[keep]-expected[keep])<=LS_TOL),paste(label,"numeric value"))
  } else ls_check(identical(actual,expected),paste(label,"exact value"))
  invisible(TRUE)
}
ls_summary <- function(x) {
  if (is.null(x)) return(list(mean=NA_real_,lower_90=NA_real_,upper_90=NA_real_))
  ls_check(length(x)>0 && all(is.finite(x)),"finite summary draws")
  z <- target_summary(x)
  ls_check(z$lower_90<=z$upper_90,"ordered interval")
  z
}
ls_transition <- function(a,b) {
  ifelse(a & b,"available_both",ifelse(a,"gained",ifelse(b,"lost","unavailable_both")))
}
ls_gain_category <- function(lo,hi) {
  ifelse(is.na(lo),"unavailable",ifelse(lo>0,"positive",ifelse(hi<0,"negative","includes_zero")))
}
ls_player <- function(attempts, point_value, cell_id, draws, condition) {
  # Make/miss labels cannot enter this interface. Empty-cell values are zero.
  ls_check(length(attempts)==length(cell_id) && !anyDuplicated(cell_id) &&
    identical(order(cell_id),seq_along(cell_id)) && all(attempts>=0) &&
    all(attempts==as.integer(attempts)) && sum(attempts)>0 &&
    length(point_value)==length(attempts) && nrow(draws)==length(attempts) &&
    ncol(draws)==4000L && all(is.finite(draws)) && all(draws>=0 & draws<=1),
    "player input dimensions and probabilities")
  observed <- attempts>0
  ls_check(all(point_value[observed]>=2 & point_value[observed]<=3) &&
    all(point_value[!observed]==0),"fixed effective point values")
  n <- sum(attempts); f <- attempts/n
  b <- colSums(draws*f*point_value)
  ls_check(all(b>0),"positive baseline EPPA")
  ep <- rowMeans(draws)*point_value
  prob <- rep(NA_real_,length(attempts))
  prob[observed] <- rowMeans(sweep(draws[observed,,drop=FALSE]*
    point_value[observed],2L,b,`>`))
  supported <- observed & attempts>=condition$min_destination_attempts &
    !is.na(prob) & prob>=condition$min_posterior_evidence
  source <- target_source_order(attempts,ep,mean(b),cell_id)
  ls_check(!any(supported[source]),"source/support overlap")
  w <- sum(f[source]); cap <- condition$max_final_destination_share
  d <- sum(pmax(0,cap-f[supported])); k <- sum(supported)
  available <- k>0 && w>LS_TOL && d>LS_TOL
  reason <- if(k==0) "no_supported_destinations" else if(d<=LS_TOL)
    "no_positive_supported_capacity" else if(w<=LS_TOL)
    "no_eligible_weak_source_mass" else "available"
  removed <- added <- matrix(0,length(attempts),length(LS_SHARES))
  relocated <- matrix(NA_real_,4000L,length(LS_SHARES))
  sliders <- vector("list",length(LS_SHARES))
  for (j in seq_along(LS_SHARES)) {
    request <- LS_SHARES[j]
    a <- target_capped_allocation(f,supported,request,w,cap)
    actual <- if(available) a$actual else 0
    if(available) {
      r <- target_remove_mass(f,source,actual)
      removed[,j] <- r$removed; added[,j] <- a$added
    }
    q <- f-removed[,j]+added[,j]; receiver <- added[,j]>LS_TOL
    ls_check(abs(sum(q)-1)<=LS_TOL && all(q>=-LS_TOL) &&
      abs(sum(q)*n-n)<=LS_TOL*max(1,n,abs(sum(q)*n)) &&
      abs(sum(removed[,j])-actual)<=LS_TOL && abs(sum(added[,j])-actual)<=LS_TOL &&
      actual<=min(request,w,d)+LS_TOL,"mass, attempts and movement limits")
    ls_check(all(added[!supported,j]==0) && all(added[f>=cap,j]==0) &&
      all(q[receiver]<=cap+LS_TOL),"support and receiving cap")
    if(available) {
      expected_removed <- pmin(f[source],pmax(0,actual-c(0,head(cumsum(f[source]),-1))))
      ls_check(all(abs(removed[source,j]-expected_removed)<=LS_TOL),
               "weakest-first fractional source boundary")
      uncapped <- supported & (a$capacity-a$added)>LS_TOL
      ratios <- a$added[uncapped]/f[uncapped]
      ls_check(length(ratios)<2L || diff(range(ratios))<=LS_TOL,
               "proportional uncapped redistribution")
      relocated[,j] <- if(request==0) b else colSums(draws*q*point_value)
      ls_check(all(is.finite(relocated[,j]) & relocated[,j]>0),"positive relocated EPPA")
    }
    rr <- if(available) relocated[,j] else NULL
    gain <- if(available) rr-b else NULL
    shares <- sort(q[receiver],decreasing=TRUE)
    sliders[[j]] <- list(requested_share=request,actual_share=actual,
      moved_attempt_equivalents=actual*n,cap_limited=a$cap_limited,
      receiving_cap_reached=any(abs(q[receiver]-cap)<=LS_TOL),
      receiving_count=as.integer(sum(receiver)),receiving_final_shares_sorted=shares,
      receiving_share_min=if(length(shares))min(shares)else NA_real_,
      receiving_share_median=if(length(shares))median(shares)else NA_real_,
      receiving_share_max=if(length(shares))max(shares)else NA_real_,
      relocated_eppa=ls_summary(rr),season_gain=ls_summary(if(available)n*gain else NULL),
      gain_per_100=ls_summary(if(available)100*gain else NULL),
      full_request_achieved=abs(actual-request)<=LS_TOL)
  }
  ls_check(all(apply(removed,1,diff)>=-LS_TOL) &&
    all(apply(added,1,diff)>=-LS_TOL),"nested cellwise movement")
  score_draws <- if(available)pmin(100,pmax(0,100*b/relocated[,6]))else NULL
  score <- if(available)target_score(b,relocated[,6])else
    list(point=NA_real_,lower_90=NA_real_,upper_90=NA_real_)
  if(available) {
    ls_check(all(diff(colMeans(relocated)-mean(b))>=-LS_TOL),"nondecreasing mean gain")
    ls_check(identical(relocated[,1]-b,rep(0,4000L)),"exact zero-request gain")
    ls_check(all(unlist(score)>=0 & unlist(score)<=100) &&
      score$lower_90<=score$upper_90,"bounded score and interval")
  }
  list(attempts=n,evidence_status=target_evidence_status(k),supported_count=as.integer(k),
    availability=available,availability_reason=reason,weak_source_capacity=w,
    destination_capacity=d,score=score,sliders=sliders,supported=supported,
    support_probability=prob,source_order=source,baseline=ls_summary(b),
    baseline_draws=b,relocated_draws=relocated,score_draws=score_draws,
    allocations=list(cell_id=cell_id,baseline=f,removed=removed,added=added,
                     final=f-removed+added))
}
ls_baseline_check <- function(result, published) {
  scalar <- c(attempts="observed_attempts",evidence_status="evidence_status",
    supported_count="supported_destination_count",availability="relocation_available",
    availability_reason="availability_reason",weak_source_capacity="eligible_source_share",
    destination_capacity="total_supported_destination_capacity",score="score",
    baseline="baseline_expected_points_per_attempt")
  for(n in names(scalar)) ls_equal(result[[n]],published[[scalar[[n]]]],n)
  ls_equal(length(result$source_order),published$source_cell_count,"source count")
  ls_check(identical(vapply(published$heatmap_cells,`[[`,logical(1),"supported_destination"),
    result$supported),"baseline supported cells")
  ls_check(length(published$sliders)==6L,"baseline slider count")
  for(j in 1:6) {
    s <- result$sliders[[j]]; p <- published$sliders[[j]]
    fields <- c(requested_share="requested_share",actual_share="actual_relocated_share",
      moved_attempt_equivalents="actual_relocated_attempt_equivalents",
      relocated_eppa="relocated_expected_points_per_attempt",season_gain="season_gain",
      gain_per_100="gain_per_100")
    for(n in names(fields)) ls_equal(s[[n]],p[[fields[[n]]]],paste("slider",j,n))
    rows <- if(result$availability)which(result$supported)else integer()
    a <- unname(lapply(rows,function(i)list(cell_id=as.integer(result$allocations$cell_id[i]),
      added_share=result$allocations$added[i,j],final_share=result$allocations$final[i,j])))
    ls_equal(a,p$destination_allocation,paste("baseline allocation",j))
  }
  invisible(TRUE)
}
ls_flat_summary <- function(x,prefix) setNames(x,paste0(prefix,"_",names(x)))
ls_records <- function(r,b,season,player_id,condition_id,high_volume) {
  paired <- r$availability && b$availability
  sc <- if(paired) r$score$point-b$score$point else NA_real_
  si <- if(paired)target_quantile(r$score_draws-b$score_draws,c(.05,.95))else c(NA_real_,NA_real_)
  pc <- data.frame(season,player_id,condition_id,attempts=r$attempts,
    evidence_status=r$evidence_status,supported_count=r$supported_count,
    availability=r$availability,availability_reason=r$availability_reason,
    weak_source_capacity=r$weak_source_capacity,destination_capacity=r$destination_capacity,
    high_volume,score=r$score$point,score_lower_90=r$score$lower_90,score_upper_90=r$score$upper_90,
    baseline_evidence_status=b$evidence_status,evidence_category_changed=r$evidence_status!=b$evidence_status,
    availability_transition=ls_transition(r$availability,b$availability),
    score_delta=sc,score_delta_lower_90=si[1],score_delta_upper_90=si[2])
  ps <- lapply(1:6,function(j) {
    s <- r$sliders[[j]]; bs <- b$sliders[[j]]
    delta <- if(paired)(r$relocated_draws[,j]-r$baseline_draws)-
      (b$relocated_draws[,j]-b$baseline_draws)else NULL
    row <- c(list(season=season,player_id=player_id,condition_id=condition_id),
      s[!names(s)%in%c("receiving_final_shares_sorted","relocated_eppa","season_gain","gain_per_100")],
      ls_flat_summary(s$relocated_eppa,"relocated_eppa"),
      ls_flat_summary(s$season_gain,"season_gain"),ls_flat_summary(s$gain_per_100,"gain_per_100"),
      list(actual_share_delta=s$actual_share-bs$actual_share,
           moved_attempt_equivalents_delta=s$moved_attempt_equivalents-bs$moved_attempt_equivalents),
      ls_flat_summary(ls_summary(if(paired)r$attempts*delta else NULL),"season_gain_delta"),
      ls_flat_summary(ls_summary(if(paired)100*delta else NULL),"gain_per_100_delta"))
    row <- as.data.frame(row,stringsAsFactors=FALSE)
    row$receiving_final_shares_sorted <- list(s$receiving_final_shares_sorted)
    row
  })
  list(player_condition=pc,player_slider=dplyr::bind_rows(ps))
}
