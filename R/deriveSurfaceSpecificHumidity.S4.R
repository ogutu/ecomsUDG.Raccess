#' Compute surface specific humidity in System4 datasets
#' 
#' Performs a basic calculation of specific humidity from sea-level pressure and
#'  surface temperature (for surface pressure calculation) while minimizing the amount
#'  of data simultaneously loaded in memory.
#' 
#' @param gds A java \dQuote{GridDataset}. This is used to load all input java \dQuote{GeoGrid}'s 
#' to derive the target variable.
#' @param grid An input java GeoGrid. This is the grid of the \sQuote{leading var} (\code{leadVar}) previously loaded
#' for subsetting parameter retrieval (see \code{\link{deriveInterface}} for details).
#' @param latLon A list of geolocation parameters, as returned by getLatLonDomainForecast
#' @param memberRangeList A list of ensemble java ranges as returned by getMemberDomain.S4
#' @param runTimePars A list of run time definition parameters, as returned by getRunTimeDomain
#' @param foreTimePars A list of forecast time definition parameters, as returned by getForecastTimeDomain.S4
#' @return A n-dimensional array. Dimensions are labelled by the \dQuote{dimnames} attribute
#' @details The function essentially follows the same approach as \code{\link{makeSubset.S4}}, excepting that
#'  at each time step it loads more than one \dQuote{GeoGrid} in order to apply the equations. 
#' @references \url{http://meteo.unican.es/ecoms-udg/DataServer/ListOfVariables}
#' @author J Bedia \email{joaquin.bedia@@gmail.com}, borrowing MatLab code from S. Herrera. 

deriveSurfaceSpecificHumidity.S4 <- function(gds, grid, latLon, runTimePars, memberRangeList, foreTimePars) {
      message("[", Sys.time(), "] Retrieving data subset ..." )
      # grid = tas (K)
      grid.zs <- gds$findGridByName("zsfc") # surface geopotential (STATIC!) (m^2/s^2)
      grid.mslp <- gds$findGridByName("mslp") # sea level pressure (Pa)
      grid.tdps <- gds$findGridByName("dpt2m") # surface dew point
      gcs <- grid$getCoordinateSystem()
      dimNames <- rev(names(scanVarDimensions(grid))) 
      z <- .jnew("ucar/ma2/Range", 0L, 0L)
      aux.list <- rep(list(bquote()), length(memberRangeList))
      for (i in 1:length(memberRangeList)) {
            ens <- memberRangeList[[i]]
            aux.list1 <- rep(list(bquote()), length(runTimePars$runTimeRanges))
            for (j in 1:length(runTimePars$runTimeRanges)) {
                  rt <- runTimePars$runTimeRanges[[j]]
                  ft <- foreTimePars$ForeTimeRangesList[[j]]
                  aux.list2 <- rep(list(bquote()), length(latLon$llRanges))
                  for (k in 1:length(latLon$llRanges)) {
                        subSet <- grid$makeSubset(rt, ens, ft, z, latLon$llRanges[[k]]$get(0L), latLon$llRanges[[k]]$get(1L))
                        subSet.zs <- grid.zs$makeSubset(z, z, z, z, latLon$llRanges[[k]]$get(0L), latLon$llRanges[[k]]$get(1L))
                        subSet.mslp <- grid.mslp$makeSubset(rt, ens, ft, z, latLon$llRanges[[k]]$get(0L), latLon$llRanges[[k]]$get(1L))
                        subSet.tdps <- grid.tdps$makeSubset(rt, ens, ft, z, latLon$llRanges[[k]]$get(0L), latLon$llRanges[[k]]$get(1L))
                        shapeArray <- rev(subSet$getShape())
                        dimNamesRef <- dimNames              
                        if (latLon$pointXYindex[1] >= 0) {
                              rm.dim <- grep(gcs$getXHorizAxis()$getDimensionsString(), dimNamesRef, fixed = TRUE)
                              shapeArray <- shapeArray[-rm.dim]
                              dimNamesRef <- dimNamesRef[-rm.dim]
                        }
                        if (latLon$pointXYindex[2] >= 0) {
                              rm.dim <- grep(gcs$getYHorizAxis()$getDimensionsString(), dimNamesRef, fixed = TRUE)
                              shapeArray <- shapeArray[-rm.dim]
                              dimNamesRef <- dimNamesRef[-rm.dim]
                        }
                        # tdps2hurs
                        tas <- subSet$readDataSlice(-1L, -1L, -1L, -1L, latLon$pointXYindex[2], latLon$pointXYindex[1])$copyTo1DJavaArray()
                        tdps <- subSet.tdps$readDataSlice(-1L, -1L, -1L, -1L, latLon$pointXYindex[2], latLon$pointXYindex[1])$copyTo1DJavaArray()
                        hurs <- tdps2hurs(tas, tdps)
                        tdps <- NULL
                        # mslp2ps
                        zs.aux <- subSet.zs$readDataSlice(-1L, -1L, -1L, -1L, latLon$pointXYindex[2], latLon$pointXYindex[1])$copyTo1DJavaArray()
                        zs <- rep(zs.aux, length(tas) / length(zs.aux))
                        zs.aux <- NULL
                        mslp <- subSet.mslp$readDataSlice(-1L, -1L, -1L, -1L, latLon$pointXYindex[2], latLon$pointXYindex[1])$copyTo1DJavaArray()
                        ps <- mslp2ps(tas, zs, mslp)
                        # hurs2huss 
                        huss <- hurs2huss(tas, ps, hurs)
                        tas <- NULL
                        ps <- NULL
                        hurs <- NULL
                        aux.list2[[k]] <- array(huss, dim = shapeArray)
                        huss <- NULL
                  }
                  # Sub-routine for daily aggregation from 6h data
                  if (!is.na(foreTimePars$dailyAggr)) {
                        aux.list1[[j]] <- toDD(do.call("abind", c(aux.list2, along = 1)), dimNamesRef, foreTimePars$dailyAggr)
                        dimNamesRef <- attr(aux.list1[[j]], "dimensions")
                  } else {
                        aux.list1[[j]] <- do.call("abind", c(aux.list2, along = 1))
                  }
                  aux.list2 <- NULL
            }
            aux.list[[i]] <- do.call("abind", c(aux.list1, along = grep("^time", dimNamesRef)))
            aux.list1 <- NULL
      }
      mdArray <- do.call("abind", c(aux.list, along = grep(gcs$getEnsembleAxis()$getDimensionsString(), dimNamesRef, fixed = TRUE)))
      aux.list <- NULL
      if (any(dim(mdArray) == 1)) {
            dimNames <- dimNamesRef[-which(dim(mdArray) == 1)]
            mdArray <- drop(mdArray)
      } else {
            dimNames <- dimNamesRef
      }
      dimNames <- gsub("^time.*", "time", dimNames)
      mdArray <- unname(mdArray)
      attr(mdArray, "dimensions") <- dimNames
      return(mdArray)
}
# End