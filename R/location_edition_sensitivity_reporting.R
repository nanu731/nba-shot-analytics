# Registered private records and identifier-free aggregate summaries.
LS_PUBLIC_COLUMNS <- c("protocol_id","season","condition_id","requested_share","group",
  "metric_id","denominator_n","available_n","missing_n","count","proportion",
  "minimum","q25","median","q75","maximum")
ls_public_row <- function(season,condition_id,request,group,metric,x,logical_metric=FALSE) {
  n <- length(x); valid <- !is.na(x); m <- sum(valid)
  q <- rep(NA_real_,5)
  if(m && !logical_metric) q <- as.numeric(quantile(x[valid],c(0,.25,.5,.75,1),type=7))
  data.frame(protocol_id=LS_ID,season,condition_id,requested_share=request,group,metric_id=metric,
    denominator_n=as.integer(n),available_n=as.integer(m),missing_n=as.integer(n-m),
    count=if(logical_metric)as.integer(sum(x[valid]))else NA_integer_,
    proportion=if(logical_metric && n>0)sum(x[valid])/n else NA_real_,
    minimum=q[1],q25=q[2],median=q[3],q75=q[4],maximum=q[5])
}
ls_public_check <- function(x) {
  ls_check(identical(names(x),LS_PUBLIC_COLUMNS),"aggregate privacy allowlist")
  ls_check(!anyNA(x[c("protocol_id","season","condition_id","requested_share","group","metric_id",
    "denominator_n","available_n","missing_n")]) &&
    !anyDuplicated(x[1:6]),"aggregate keys complete and unique")
  ls_check(all(vapply(x[vapply(x,is.numeric,logical(1))],function(y)
    all(is.na(y)|is.finite(y)),logical(1))),"aggregate finite values")
  text <- unlist(x[vapply(x,is.character,logical(1))],use.names=FALSE)
  ls_check(!any(grepl("/Users/|data/cache|PLAYER_ID|GAME_ID|2026-27",text)),"aggregate private values")
  invisible(TRUE)
}
ls_join <- function(pc,ps) {
  dplyr::left_join(ps,pc,by=c("season","player_id","condition_id")) |>
    dplyr::mutate(score_interval_width=score_upper_90-score_lower_90,
      season_gain_interval_width=season_gain_upper_90-season_gain_lower_90,
      gain_per_100_interval_width=gain_per_100_upper_90-gain_per_100_lower_90,
      relocated_eppa_interval_width=relocated_eppa_upper_90-relocated_eppa_lower_90,
      gain_interval_category=ls_gain_category(gain_per_100_lower_90,gain_per_100_upper_90))
}
ls_aggregate <- function(pc,ps,grid) {
  x <- ls_join(pc,ps); result <- list(); i <- 0L
  for(id in grid$condition_id) for(request in LS_SHARES) {
    z <- x[x$condition_id==id & x$requested_share==request,,drop=FALSE]
    for(group in c("all","high_volume","single_destination","multiple_destinations")) {
      y <- switch(group,all=z,high_volume=z[z$high_volume,,drop=FALSE],
        z[z$evidence_status==group,,drop=FALSE])
      add <- function(metric,values,bool=FALSE) {
        i <<- i+1L; result[[i]] <<- ls_public_row(unique(x$season),id,request,group,metric,values,bool)
      }
      for(status in c("insufficient_evidence","single_destination","multiple_destinations"))
        add(paste0("evidence_",status),y$evidence_status==status,TRUE)
      for(reason in c("no_supported_destinations","no_positive_supported_capacity",
                      "no_eligible_weak_source_mass","available"))
        add(paste0("reason_",reason),y$availability_reason==reason,TRUE)
      for(tr in c("gained","lost","available_both","unavailable_both"))
        add(paste0("transition_",tr),y$availability_transition==tr,TRUE)
      for(a in c("insufficient_evidence","single_destination","multiple_destinations"))
        for(b in c("insufficient_evidence","single_destination","multiple_destinations"))
          add(paste0("evidence_transition_",a,"_to_",b),
            y$baseline_evidence_status==a & y$evidence_status==b,TRUE)
      for(n in c("availability","full_request_achieved","cap_limited","receiving_cap_reached"))
        add(n,y[[n]],TRUE)
      add("full_request_achieved_among_available",y$full_request_achieved[y$availability],TRUE)
      for(n in c("supported_count","weak_source_capacity","destination_capacity","actual_share",
        "moved_attempt_equivalents","receiving_count","receiving_share_max","actual_share_delta",
        "moved_attempt_equivalents_delta","relocated_eppa_mean","season_gain_mean","gain_per_100_mean",
        "relocated_eppa_interval_width","season_gain_interval_width","gain_per_100_interval_width",
        "season_gain_delta_mean","season_gain_delta_lower_90","season_gain_delta_upper_90",
        "gain_per_100_delta_mean","gain_per_100_delta_lower_90","gain_per_100_delta_upper_90")) add(n,y[[n]])
      if(request==.25) for(n in c("score","score_lower_90","score_upper_90","score_interval_width",
        "score_delta","score_delta_lower_90","score_delta_upper_90")) add(n,y[[n]])
      for(n in c("invalid","impossible","failed","unexecuted"))add(paste0(n,"_cases"),rep(FALSE,nrow(y)),TRUE)
    }
  }
  out <- dplyr::bind_rows(result); ls_public_check(out); out
}
ls_endpoints <- function(z,request) {
  result <- list(
    evidence_category=as.character(z$evidence_status),
    estimate_availability=ifelse(z$availability,"available","unavailable"),
    full_request_achieved=ifelse(z$full_request_achieved,"achieved","not_achieved"),
    gain_interval_interpretation=z$gain_interval_category,
    actual_share=z$actual_share,moved_attempt_equivalents=z$moved_attempt_equivalents,
    season_gain=z$season_gain_mean,gain_per_100=z$gain_per_100_mean,
    season_gain_interval_width=z$season_gain_interval_width,
    gain_per_100_interval_width=z$gain_per_100_interval_width,
    relocated_eppa=z$relocated_eppa_mean,
    relocated_eppa_interval_width=z$relocated_eppa_interval_width)
  if(request==.25) result <- c(result,list(score=z$score,score_interval_width=z$score_interval_width))
  result
}
ls_stability <- function(pc,ps,grid) {
  x <- ls_join(pc,ps); rows <- contrasts <- list(); ri <- ci <- 0L
  baseline <- which(grid$is_baseline)
  factors <- names(grid)[2:4]
  for(id in unique(x$player_id)) for(request in LS_SHARES) {
    z <- x[x$player_id==id & x$requested_share==request,,drop=FALSE]
    z <- z[match(grid$condition_id,z$condition_id),,drop=FALSE]
    ls_check(nrow(z)==27L && !anyNA(z$condition_id),"full stability grid")
    mixed <- length(unique(z$availability))>1 || length(unique(z$gain_interval_category))>1
    endpoints <- ls_endpoints(z,request)
    for(endpoint in names(endpoints)) {
      values <- endpoints[[endpoint]]; categorical <- is.character(values)
      valid <- !is.na(values); v <- values[valid]; count <- length(v)
      mode_categories <- character(); mode_count <- NA_integer_; agreement <- NA_integer_
      same <- FALSE
      if(categorical) {
        tab <- table(v); mode_count <- as.integer(max(tab)); mode_categories <- sort(names(tab)[tab==max(tab)])
        agreement <- as.integer(sum(v==values[baseline])); same <- length(unique(v))==1
      }
      delta <- if(!categorical && !is.na(values[baseline]))values-values[baseline]else rep(NA_real_,27)
      q <- if(!categorical && count) c(min(v),median(v),max(v))else rep(NA_real_,3)
      d <- delta[!is.na(delta)]; dq <- if(length(d))c(min(d),median(d),max(d))else rep(NA_real_,3)
      ri <- ri+1L
      row <- data.frame(season=z$season[1],player_id=id,requested_share=request,endpoint,
        baseline_value=as.character(values[baseline]),modal_count=mode_count,
        baseline_agreement_count=agreement,valid_condition_count=as.integer(count),
        unavailable_condition_count=as.integer(if(categorical)sum(values=="unavailable")else sum(!valid)),
        all_27_agree=same,value_min=q[1],value_median=q[2],value_max=q[3],
        paired_baseline_delta_min=dq[1],paired_baseline_delta_median=dq[2],paired_baseline_delta_max=dq[3],
        availability_or_sign_mixed=mixed)
      row$modal_categories <- list(mode_categories); rows[[ri]] <- row
      for(factor in factors) {
        other <- setdiff(factors,factor)
        low <- which(grid[[factor]]==min(grid[[factor]]))
        for(l in low) {
          h <- which(grid[[factor]]==max(grid[[factor]]) &
            grid[[other[1]]]==grid[[other[1]]][l] & grid[[other[2]]]==grid[[other[2]]][l])
          ls_check(length(h)==1L,"unique matched factor pair")
          pa <- valid[l] && valid[h]
          ci <- ci+1L
          contrasts[[ci]] <- data.frame(season=z$season[1],player_id=id,requested_share=request,endpoint,factor,
            fixed_other_levels=paste(other[1],grid[[other[1]]][l],other[2],grid[[other[2]]][l],sep="="),
            low_condition_id=grid$condition_id[l],high_condition_id=grid$condition_id[h],paired_available=pa,
            category_changed=if(categorical)values[l]!=values[h]else FALSE,
            availability_transition=ls_transition(z$availability[h],z$availability[l]),
            signed_difference=if(pa && !categorical)values[h]-values[l]else NA_real_,categorical=categorical)
        }
      }
    }
  }
  list(player_stability=dplyr::bind_rows(rows),factor_contrasts=dplyr::bind_rows(contrasts))
}
ls_stability_aggregate <- function(st,pc) {
  s <- dplyr::left_join(st$player_stability,pc[pc$condition_id=="A10_E90_C50",
    c("season","player_id","high_volume")],by=c("season","player_id"))
  out <- list(); i <- 0L
  for(request in LS_SHARES) for(endpoint in unique(s$endpoint))for(group in c("all","high_volume")) {
    y <- s[s$requested_share==request & s$endpoint==endpoint &
      (group=="all"|s$high_volume),,drop=FALSE]
    if(!nrow(y))next
    for(n in c("modal_count","baseline_agreement_count","valid_condition_count","unavailable_condition_count",
      "value_min","value_median","value_max","paired_baseline_delta_min",
      "paired_baseline_delta_median","paired_baseline_delta_max","all_27_agree","availability_or_sign_mixed")) {
      if(n%in%c("modal_count","baseline_agreement_count","all_27_agree") && all(is.na(y$modal_count)))next
      i <- i+1L; out[[i]] <- ls_public_row(y$season[1],"ALL_GRID",request,group,
        paste(endpoint,n,sep="__"),y[[n]],is.logical(y[[n]]))
    }
    # Exact categorical agreement counts, including all tied modes and uniform unavailability.
    if(any(!is.na(y$modal_count))) {
      categories <- sort(unique(unlist(y$modal_categories)))
      for(cat in categories) {
        i<-i+1L; out[[i]]<-ls_public_row(y$season[1],"ALL_GRID",request,group,
          paste(endpoint,"mode_includes",cat,sep="__"),vapply(y$modal_categories,function(v)cat%in%v,logical(1)),TRUE)
      }
      for(k in 0:27)for(field in c("modal_count","baseline_agreement_count")) {
        i<-i+1L;out[[i]]<-ls_public_row(y$season[1],"ALL_GRID",request,group,
          paste(endpoint,field,k,sep="__"),y[[field]]==k,TRUE)
      }
    }
  }
  f <- st$factor_contrasts
  profiles <- f |>
    dplyr::summarise(paired_count=sum(paired_available),changed_pairs=sum(category_changed),
      mean_absolute_difference=if(all(is.na(signed_difference)))NA_real_ else mean(abs(signed_difference),na.rm=TRUE),
      categorical=dplyr::first(categorical),.by=c(season,player_id,requested_share,endpoint,factor))
  labels <- profiles |>
    dplyr::summarise(attribution={
      v <- if(dplyr::first(categorical))changed_pairs else mean_absolute_difference
      if(any(paired_count!=9L)||anyNA(v))"insufficient_paired_coverage" else
        if(sum(v==max(v))!=1L)"tied_or_mixed" else factor[which.max(v)]
    },.by=c(season,player_id,requested_share,endpoint))
  # Each matched pair remains visible to expose interactions, rather than only marginal labels.
  for(request in LS_SHARES) for(endpoint in unique(f$endpoint)) {
    p <- profiles[profiles$requested_share==request & profiles$endpoint==endpoint,,drop=FALSE]
    if(!nrow(p))next
    for(factor in unique(p$factor)) {
      y <- p[p$factor==factor,,drop=FALSE]
      for(n in c("paired_count","changed_pairs","mean_absolute_difference")) {
        i<-i+1L;out[[i]]<-ls_public_row(y$season[1],"ALL_GRID",request,"all",
          paste(endpoint,factor,n,sep="__"),y[[n]])
      }
      pairs <- f[f$requested_share==request & f$endpoint==endpoint & f$factor==factor,,drop=FALSE]
      for(levels in unique(pairs$fixed_other_levels)) {
        y<-pairs[pairs$fixed_other_levels==levels,,drop=FALSE]
        for(n in c("signed_difference","paired_available","category_changed")) {
          i<-i+1L;out[[i]]<-ls_public_row(y$season[1],"ALL_GRID",request,"all",
            paste(endpoint,factor,levels,n,sep="__"),y[[n]],is.logical(y[[n]]))
        }
        for(tr in c("gained","lost","available_both","unavailable_both")) {
          i<-i+1L;out[[i]]<-ls_public_row(y$season[1],"ALL_GRID",request,"all",
            paste(endpoint,factor,levels,tr,sep="__"),y$availability_transition==tr,TRUE)
        }
      }
    }
    y<-labels[labels$requested_share==request & labels$endpoint==endpoint,,drop=FALSE]
    for(label in c(unique(profiles$factor),"tied_or_mixed","insufficient_paired_coverage")) {
      i<-i+1L;out[[i]]<-ls_public_row(y$season[1],"ALL_GRID",request,"all",
        paste(endpoint,"attribution",label,sep="__"),y$attribution==label,TRUE)
    }
  }
  result<-dplyr::bind_rows(out);ls_public_check(result)
  list(aggregate=result,factor_profiles=profiles,attribution=labels)
}
