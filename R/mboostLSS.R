###
# Generic implementation for multiple component LSS-models

### (glm/gam/m/black)boostLSS functions

mboostLSS <- function(formula, data = list(), families = GaussianLSS(),
                      control = boost_control(), weights = NULL, 
                      method = c("cycling", "inner", "outer"), ...){
  
    cl <- match.call()
    if(is.null(cl$families))
        cl$families <- families
    method <- match.arg(method)

    fit <- mboostLSS_fit(formula = formula, data = data, families = families,
                         control = control, weights = weights, ...,
                         fun = mboost, funchar = "mboost", call = cl,
                         method = method)
    return(fit)
}

glmboostLSS <- function(formula, data = list(), families = GaussianLSS(),
                        control = boost_control(), weights = NULL, 
                        method = c("cycling", "inner", "outer"), ...){
  
    cl <- match.call()
    if(is.null(cl$families))
        cl$families <- families
    method <- match.arg(method)

    fit <- mboostLSS_fit(formula = formula, data = data, families = families,
                         control = control, weights = weights, ...,
                         fun = glmboost, funchar = "glmboost", call = cl,
                         method = method)
  
    return(fit)
}

gamboostLSS <- function(formula, data = list(), families = GaussianLSS(),
                        control = boost_control(), weights = NULL, 
                        method = c("cycling", "inner", "outer"), ...){
    
    cl <- match.call()
    if(is.null(cl$families))
        cl$families <- families
    method <- match.arg(method)

    fit <- mboostLSS_fit(formula = formula, data = data, families = families,
                         control = control, weights = weights, ...,
                         fun = gamboost, funchar = "gamboost", call = cl,
                         method = method)
    
    return(fit)
}

blackboostLSS <- function(formula, data = list(), families = GaussianLSS(),
                          control = boost_control(), weights = NULL, 
                          method = c("cycling", "inner", "outer"), ...){
    cl <- match.call()
    if(is.null(cl$families))
        cl$families <- families
    method <- match.arg(method)

    fit <- mboostLSS_fit(formula = formula, data = data, families = families,
                         control = control, weights = weights, ...,
                         fun = blackboost, funchar = "blackboost", call = cl,
                         method = method)
    return(fit)
}


### work horse for fitting (glm/gam/m/black)boostLSS models
mboostLSS_fit <- function(formula, data = list(), families = GaussianLSS(),
                          control = boost_control(), weights = NULL,
                          fun = mboost, funchar = "mboost", call = NULL,
                          method, ...){
  
    if(method == "cycling")
      iBoost_cycling <- function(niter) {
    
    start <- sapply(fit, mstop)
    mvals <- vector("list", length(niter))
    for (j in 1:length(niter)){
      mvals[[j]] <- rep(start[j] + niter[j], max(niter))
      if (niter[j] > 0)
        mvals[[j]][1:niter[j]] <- (start[j] + 1):(start[j] + niter[j])
    }
    
    ENV <- lapply(mods, function(j) environment(fit[[j]]$subset))
    
    for (i in 1:max(niter)){
      for (j in mods){
        ## update value of nuisance parameters
        ## use response(fitted()) as this is much quicker than fitted(, type = response)
        for (k in mods[-j])
          assign(names(fit)[k], families[[k]]@response(fitted(fit[[k]])),
                 environment(get("ngradient", environment(fit[[j]]$subset))))
        ## update value of u, i.e. compute ngradient with new nuisance parameters
        
        ENV[[j]][["u"]] <- ENV[[j]][["ngradient"]](ENV[[j]][["y"]], ENV[[j]][["fit"]],
                                                   ENV[[j]][["weights"]])
        # same as:
        # evalq(u <- ngradient(y, fit, weights), environment(fit[[j]]$subset))
        
        ## update j-th component to "m-th" boosting step
        fit[[j]][mvals[[j]][i]]
      }
      if (trace){
        firstRun <- firstRun
        ## which is the current risk? rev() needed to get the last
        ## list element with maximum length
        whichRisk <- names(which.max(rev(lapply(lapply(fit, function(x) x$risk()), length))))
        do_trace(current = max(sapply(mvals, function(x) x[i])),
                 mstart = ifelse(firstRun, 0, max(start)),
                 mstop = ifelse(firstRun, max(niter) + 1, max(niter)),
                 risk = fit[[whichRisk]]$risk())
      }
    }
    return(TRUE)
  }
    if(method == "outer")
      iBoost_outer <- function(niter){
    
    #this is the case for boosting from the beginning
    if(is.null(attr(fit, "combined_risk")) | niter == 0){
      combined_risk <- vapply(fit, risk, numeric(1))
    }
    
    best <- which(names(fit) == tail(names(combined_risk), 1))
    
    
    
    ENV <- lapply(mods, function(j) environment(fit[[j]]$subset))
    
    for (i in seq_len(niter)){
      
      ## update value of nuisance parameters
      ## use response(fitted()) as this is much quicker than fitted(, type = response)
      for( k in mods[-best]){
        assign(names(fit)[best], families[[best]]@response(fitted(fit[[best]])),
               environment(get("ngradient", environment(fit[[k]]$subset))))
        
        #evalq(u <- ngradient(y, fit, weights), ENV[[k]])
        ENV[[k]][["u"]] <- ENV[[k]][["ngradient"]](ENV[[k]][["y"]],
                                                   ENV[[k]][["fit"]],
                                                   ENV[[k]][["weights"]])
      }
      
      if (funchar == "glmboost") {
        lik_risks <- list()
        coefs <- list()
        
        for(i in mods){
          coefs[[i]] <- evalq(environment(get("fit1"))[["est"]](u)/
                                environment(get("fit1"))[["sxtx"]], envir = ENV[[i]])
          
          all_fitted <- sweep(environment(ENV[[i]][["fit1"]])[["X"]], 2, 
                              coefs[[i]] ,`*`)
          
          lik_risks[[i]] <- sapply(1:ncol(all_fitted), function(j) 
            ENV[[i]][["triskfct"]](ENV[[i]][["y"]], 
                                   ENV[[i]][["fit"]] + nu[i] * all_fitted[,j]))
        }
        
        #do a mboost step per hand
        best <- which.min(vapply(lik_risks, min, 
                                 FUN.VALUE = numeric(1), ...))
        
        ENV[[best]]$all_fitted <- all_fitted
        ENV[[best]]$lik_risks <- lik_risks
        ENV[[best]]$best <- best
        ENV[[best]]$coefs <- coefs
        
        evalq({
          xs <- which.min(lik_risks[[best]])
          basses <- list(model = c(coef = coefs[[best]][xs],
                                   xselect = xs,
                                   p = length(coefs[[best]])),
                         fitted = function() {
                           return(coefs[[best]][xs] * environment(get("fit1"))[["X"]][, xs, drop = FALSE])
                         })
          class(basses) <- c("bm_cwlin", "bm_lin", "bm")
          fit <- fit + nu * basses$fitted()
          u <- get("ngradient")(get("y"), fit, weights)
          mrisk[(mstop + 1)] <- get("triskfct")(get("y"), fit)
          ens[[(mstop + 1)]] <- basses
          xselect[(mstop + 1)] <- xs
          nuisance[[(mstop +1)]] <- family@nuisance()
          mstop <- mstop + 1}, 
          envir <- ENV[[best]])
      }
      
      #all other baselearner
      else{
        risks <- list()
        for( i in mods){
          risks[[i]] <- evalq({
            ss_new <- lapply(get("blfit", envir = environment(get("basefit"))), 
                             function(x) x(u))
            sapply(ss_new, function(x) get("riskfct")(get("y"), fit + nu * x$fitted(), weights))
          }, envir = ENV[[i]])
        }
        
        best <- which.min(vapply(risks, min, 
                                 FUN.VALUE = numeric(1)))
        
        evalq({
          ss <- lapply(get("blfit", envir = environment(get("basefit"))), 
                       function(x) x(u))
          xselect[mstop + 1] <- which.min(sapply(ss, function(x) 
            get("riskfct")(get("y"), fit + nu * x$fitted(), weights)))
          fit <- fit + nu * ss[[tail(xselect, 1)]]$fitted()
          u <- get("ngradient")(get("y"), fit, weights)
          mrisk[(mstop + 1)] <- get("triskfct")(get("y"), fit)
          ens[[(mstop + 1)]] <- ss[[tail(xselect, 1)]]
          nuisance[[(mstop + 1)]] <- family@nuisance()
          mstop <- mstop + 1}, 
          envir = ENV[[best]])
        
      }
      
      combined_risk[(length(combined_risk) + 1)] <- tail(risk(fit[[best]]), 1)
      names(combined_risk)[length(combined_risk)] <- names(fit)[best]
      
      if (trace){
        do_trace(current = length(combined_risk[combined_risk != 0]),
                 mstart = ifelse(firstRun, length(fit) + 1, 
                                 length(combined_risk[combined_risk != 0])),
                 mstop = ifelse(firstRun, niter - length(fit), niter),
                 risk = combined_risk[combined_risk != 0])
      }
    }
    combined_risk  <<- combined_risk
    return(TRUE)
  }
    if(method == "inner" )
      iBoost_inner <- function(niter){
    
    
    #this is the case for boosting from the beginning
    if(is.null(attr(fit, "combined_risk")) | niter == 0){
      combined_risk <- vapply(fit, risk, numeric(1))
    }
    
    best <- which(names(fit) == tail(names(combined_risk), 1))
    
    
    
    ENV <- lapply(mods, function(j) environment(fit[[j]]$subset))
    
    for (i in seq_len(niter)){
      
      ## update value of nuisance parameters
      ## use response(fitted()) as this is much quicker than fitted(, type = response)
      for( k in mods[-best]){
        assign(names(fit)[best], families[[best]]@response(fitted(fit[[best]])),
               environment(get("ngradient", environment(fit[[k]]$subset))))
      }
      
      risks <- numeric(length(fit))
      for(b  in 1:length(fit)){
        st <- mstop(fit[[b]])
        fit[[b]][st + 1]
        #risks[b] <- evalq({riskfct(y, fit, weights)}, envir = ENV[[b]])
        risks[b] <- ENV[[b]][["riskfct"]](ENV[[b]][["y"]], 
                                          ENV[[b]][["fit"]],
                                          ENV[[b]][["weights"]])
        fit[[b]][st]
        
        ## fit[[b]][st] is not enough to reduce the model back to beginning, so
        ## so all these values have to be reduced, so that they are calculated 
        ## correctly the next time
        evalq({xselect <- xselect[1:mstop];
        mrisk <- mrisk[1:mstop];
        ens <- ens[1:mstop];
        nuisance <- nuisance[1:mstop]},
        environment(fit[[b]]$subset))
      }
      
      
      
      best <- which.min(risks)
      
      ## update value of u, i.e. compute ngradient with new nuisance parameters
      ENV[[best]][["u"]] <- ENV[[best]][["ngradient"]](ENV[[best]][["y"]], 
                                                       ENV[[best]][["fit"]],
                                                       ENV[[best]][["weights"]])
      
      # same as:
      # evalq(u <- ngradient(y, fit, weights), environment(fit[[j]]$subset))
      
      
      ## update selected component by 1
      fit[[best]][mstop(fit[[best]]) + 1]
    
    
    combined_risk[(length(combined_risk) + 1)] <- tail(risk(fit[[best]]), 1)
    names(combined_risk)[length(combined_risk)] <- names(fit)[best]
    
    if (trace){
      do_trace(current = length(combined_risk[combined_risk != 0]),
               mstart = ifelse(firstRun, length(fit) + 1, 
                               length(combined_risk[combined_risk != 0])),
               mstop = ifelse(firstRun, niter - length(fit), niter),
               risk = combined_risk[combined_risk != 0])
    }
    combined_risk  <<- combined_risk
    }
    return(TRUE)
  }

    if (length(families) == 0)
        stop(sQuote("families"), " not specified")

    if ("offset" %in% names(list(...)))
        stop("Do not use argument ", sQuote("offset"),
             ". Please specify offsets via families")
    ### Use mu in "families" to specify offset in mu-family etc.

    if (is.list(formula)){
        if (!all(names(formula) %in% names(families)) ||
            length(unique(names(formula))) != length(names(families)))
            stop(sQuote("formula"), " can be either a formula or a named list",
                 " of formulas with same names as ",  sQuote("families"), ".")
        ynames <- sapply(formula, function(fm) as.character(fm[[2]]))
        if (length(unique(ynames)) > 1)
            warning("responses differ for the components")
        response <- lapply(formula, function(fm)
                           eval(as.expression(fm[[2]]), envir = data,
                                enclos = environment(fm)))
        #response <- eval(as.expression(formula[[1]][[2]]), envir = data,
        #                 enclos = environment(formula[[1]]))
    } else {
        response <- eval(as.expression(formula[[2]]), envir = data,
                         enclos = environment(formula))
        tmp <- vector("list", length = length(families))
        names(tmp) <- names(families)
        for (i in 1:length(tmp))
            tmp[[i]] <- formula
        formula <- tmp
    }

    mstop <- mstoparg <- control$mstop
    control$mstop <- 1
    if (method == "cycling") {
        mstop <- check(mstop, "mstop", names(families))
    } else {
        #check mstop for inner and outer loss fitting methods
        if (length(mstop) != 1 | mstop %% 1 != 0 | mstop < length(families))
            stop(sQuote("mstop"), " has to be an integer larger than ", 
                 length(families))
    }

    nu <- control$nu
    nu <- check(nu, "nu", names(families))

    if (is.list(control$risk) || is.list(control$center) || is.list(control$trace))
        stop(sQuote("risk"),", ", sQuote("center"), " and ", sQuote("trace") ,
             " cannot be lists in ", sQuote("boost_control"))

    trace <- control$trace
    control$trace <- FALSE

    w <- weights
    if (is.null(weights)){
        if (!is.list(response)) {
            weights <- rep.int(1, NROW(response))
        } else {
            weights <- rep.int(1, NROW(response[[1]]))
        }
    }
    weights <- rescale_weights(weights)

    fit <- vector("list", length = length(families))
    names(fit) <- names(families)

    mods <- 1:length(fit)

    offset <- vector("list", length = length(mods))
    names(offset) <- names(families)
    for (j in mods){
        if (!is.list(response)) {
            response <- check_y_family(response, families[[j]])
            offset[[j]] <- families[[j]]@offset(y = response, w = weights)
        } else {
            response[[j]] <- check_y_family(response[[j]], families[[j]])
            offset[[j]] <- families[[j]]@offset(y = response[[j]], w = weights)
        }
        for (k in mods){
            for (l in mods){
                if (!is.null(offset[[l]]))
                    assign(names(offset)[l], families[[l]]@response(offset[[l]]),
                           environment(families[[k]]@ngradient))
            }
        }
    }
    for (j in mods){
        ## update value of nuisance parameters in families
        for (k in mods[-j]){
            if (!is.null(fit[[k]]))
                assign(names(fit)[k], fitted(fit[[k]], type = "response"),
                       environment(families[[j]]@ngradient))
        }
        ## use appropriate nu for the model
        control$nu <- nu[[j]]
        ## <FIXME> Do we need to recompute ngradient?
        fit[[j]] <- do.call(fun, list(formula[[names(families)[[j]]]],
                                      data = data, family = families[[j]],
                                      control=control, weights = w,
                                      ...))
    }
    if (trace)
        do_trace(current = 1, mstart = 0,
                 mstop = max(mstop),
                 risk = fit[[length(fit)]]$risk())

    #select the correct fitting method    
    if (method == "cycling") {
      if (any(mstop > 1)){
        firstRun <- TRUE
        ## actually go for initial mstop iterations!
        tmp <- iBoost_cycling(mstop - 1)
      }
    }

    else {
      if (mstop >= length(fit)){
        firstRun <- TRUE
        combined_risk <- NULL
        tmp <- ifelse(method == "inner", 
                      iBoost_inner(mstop - length(fit)),
                      iBoost_outer(mstop - length(fit)))
      }
    }

    firstRun <- FALSE

    class(fit) <- c(paste(funchar, "LSS", sep=""), "mboostLSS")
    if(method != "cycling"){
      class(fit) <- c("nc_mboostLSS", class(fit))
    }

    ### update to a new number of boosting iterations mstop
    ### i <= mstop means less iterations than current
    ### i >  mstop needs additional computations
    ### updates take place in THIS ENVIRONMENT,
    ### some models are CHANGED!
    if(method == "cycling") {
      attr(fit, "subset") <- function(i) {

        i <- check(i, "mstop", names(families))

        msf <- mstop(fit)
        niter <- i - msf
        if (all(niter == 0)) {
            ## make nothing happen with the model
            minStart <- max(msf)
        } else {
            minStart <- min(msf[niter != 0], i[niter != 0])
        }

        ## check if minStart bigger than mstop of parameters that are not touched
        #if (length(msf[niter == 0]) > 0 && minStart < min(msf[niter == 0]))
           #minStart <- min(msf[niter == 0])

        ## reduce models first (when necessary)
        if (any(msf > minStart)){
            cf <- class(fit)
            class(fit) <- "list" ## needed to use [] operator for lists

            #cat("processed parameters: ", paste(names(fit[msf > minStart]),
            #                                    collapse = ", "), "\n")

            lapply(fit[msf > minStart],
                   function(obj) obj$subset(minStart))

            ## remove additional boosting iterations from environments
            lapply(fit[msf > minStart], function(obj){
                   evalq({xselect <- xselect[1:mstop];
                          mrisk <- mrisk[1:mstop];
                          ens <- ens[1:mstop];
                          nuisance <- nuisance[1:mstop]},
                         environment(obj$subset))
               })

            class(fit) <- cf
            if (trace)
                cat("Model first reduced to mstop = ", minStart, ".\n",
                    "Now continue ...\n", sep ="")
        }

        ## now increase models (when necessary)
        if (any(i > minStart)){
            ## set negative values to 0
            ## (only applicable if some parameters do not need to be touched
            inc <- ifelse(i - minStart > 0, i - minStart, 0)
            tmp <- iBoost_cycling(inc)
        }
        
        mstop <<- i
      }
    } 
    else {
      attr(fit, "subset") <- function(i) {
        if(i < length(fit)){
          warning(paste("Minimal number of iterations:", length(fit), 
                        "(at least one iteration for each distribution parameter)"))
          i <- length(fit)
        }
        msf <- sum(mstop(fit))
        niter <- i - msf
        
        ## check if minStart bigger than mstop of parameters that are not touched
        #if (length(msf[niter == 0]) > 0 && minStart < min(msf[niter == 0]))
        #minStart <- min(msf[niter == 0])
        
        ## reduce models first (when necessary)
        if (niter < 0 ){
          cf <- class(fit)
          class(fit) <- "list" ## needed to use [] operator for lists
          
          #cat("processed parameters: ", paste(names(fit[msf > minStart]),
          #                                    collapse = ", "), "\n")
          
          #reduce the combined risk values
          combined_risk <<- attr(fit, "combined_risk")()[1:i]
          new_stop_value <- table(names(attr(fit, "combined_risk")()))
          
          
          for(o in names(new_stop_value)){
            fit[[o]]$subset(new_stop_value[o])
          }
          
          ## remove additional boosting iterations from environments
          lapply(fit, function(obj){
            evalq({xselect <- xselect[1:mstop];
            mrisk <- mrisk[1:mstop];
            ens <- ens[1:mstop];
            nuisance <- nuisance[1:mstop]},
            environment(obj$subset))
          })
          
          #update ALL nuisance parameters to last update
          ENV <- lapply(mods, function(j) environment(fit[[j]]$subset))
          for(j in names(new_stop_value)){
            for( k in setdiff(names(new_stop_value), j)){
              assign(k, families[[k]]@response(fitted(fit[[k]])),
                     environment(get("ngradient", environment(fit[[j]]$subset))))
            }
          }
          
          for(k in mods){
            evalq(u <- get("ngradient")(get("y"), fit, weights), ENV[[k]])
          }
          
          
          class(fit) <- cf
        }
        
        ## now increase models (when necessary)
        else if (niter > 0){
          if (method == "inner") {
            tmp <- iBoost_inner(niter)
          }
          else {
            tmp <- iBoost_outer(niter)
          }

          
        }
        
        mstop <<- i
      }
    }

    ## make call in submodels nicer:
    cl <- call
    cl[[1]] <- as.name(gsub("LSS", "", cl[[1]]))
    names(cl)[names(cl) == "families"] <- "family"
    for (i in 1:length(fit)) {
        fit[[i]]$call <- cl
        ## <FIXME> This is not really nice
        fit[[i]]$call$family <- families[[i]]
    }

    attr(fit, "(weights)") <- weights  ## attach weights used for fitting

    ## update to new weights; just a fresh start
    attr(fit, "update") <- function(weights = NULL, oobweights = NULL,
                                    risk = NULL, trace = NULL, mstop = NULL) {
        if (is.null(mstop)) {
            control$mstop <- mstoparg
        } else {
            control$mstop <- mstop
        }
        if (!is.null(risk))
            control$risk <- risk
        if (!is.null(trace))
            control$trace <- trace
        ## re-use user specified offset only
        ## (since it depends on weights otherwise)
        ## this is achieved via a re-evaluation of the families argument
        mboostLSS_fit(formula = formula, data = data,
                      families = eval(call[["families"]]), weights = weights,
                      control = control, fun = fun, funchar = funchar,
                      call = call, oobweights = oobweights,
                      method = method)
    }
    attr(fit, "control") <- control
    attr(fit, "call") <- call
    attr(fit, "data") <- data
    attr(fit, "families") <- families
    if(method != "cycling")
      attr(fit, "combined_risk") <- function() combined_risk
    
    return(fit)
}