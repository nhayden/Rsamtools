setMethod(isOpen, "BamFile",
    function(con, rw="")
{
    if (!missing(rw) && rw != "read")
        stop("'rw' must be 'read'")
    .Call(.bamfile_isopen, .extptr(con))
})

setMethod(isIncomplete, "BamFile",
    function(con)
{
    .Call(.bamfile_isincomplete, .extptr(con))
})

.check_qname_arg <- function(arg, name)
{
    if (is.na(arg) || arg == "")
        return(NA_character_)
    if (length(arg) == 0L || !is(arg, "character"))
        stop(name, " must be a single character")
    if (nchar(arg) > 1L)
        stop("'nchar(", name, ")' must be < 1")

    arg
}

.BamFile_guessIndex <-
    function(files)
{
    index <- rep(NA_character_, length(files))
    
    idx <- sprintf("%s.bai", files)
    exists <- file.exists(idx)
    index[exists] <- idx[exists]

    idx <- sub("bam$", "bai", files)
    exists <- is.na(index) & files != idx & file.exists(idx)
    index[exists] <- idx

    idx <- sub("BAM$", "BAI", files)
    exists <- is.na(index) & files != idx & file.exists(idx)
    index[exists] <- idx

    index
}

BamFile <-
    function(file, index=file, ..., yieldSize=NA_integer_, 
             obeyQname=FALSE, asMates=FALSE, 
             qnamePrefixEnd=NA, qnameSuffixStart=NA)
{
    if (missing(file) || !isSingleString(file))
        stop("'file' must be character(1) and not NA")
    file <- .normalizePath(file)
    if (!asMates) {
        if (!is.na(qnamePrefixEnd) || !is.na(qnameSuffixStart))
            warning(paste0("when 'asMates' is FALSE 'qnamePrefixEnd' ",
                    "and 'qnameSuffixStart' are ignored"))
    }
    if (missing(index)) {
        index <- .BamFile_guessIndex(file)
        if (is.na(index))
            index <- character()
    }
    if (!(isSingleString(index) || 0L == length(index))) {
        txt <- "'index', when present, must be character(0) or character(1)
            with nchar(index) > 0 and not NA"
        stop(paste(strwrap(txt), collapse="\n  "))
    }
    index <- .normalizePath(index)
    qnamePrefixEnd <- .check_qname_arg(qnamePrefixEnd, "qnamePrefixEnd")
    qnameSuffixStart <- .check_qname_arg(qnameSuffixStart, "qnameSuffixStart")
    .RsamtoolsFile(.BamFile, path=file, index=index, yieldSize=yieldSize,
                   obeyQname=obeyQname, asMates=asMates, 
                   qnamePrefixEnd=qnamePrefixEnd, 
                   qnameSuffixStart=qnameSuffixStart, ...)
}

open.BamFile <-
    function(con, ...)
{
    tryCatch({
        .io_check_exists(path(con))
        index <- sub("\\.bai$", "", index(con))
        con$.extptr <- .Call(.bamfile_open, path(con), index, "rb")
    }, error=function(err) {
        stop("failed to open BamFile: ", conditionMessage(err))
    })
    invisible(con)
}

close.BamFile <-
    function(con, ...)
{
    if (!isOpen(con))
        stop("isOpen(<BamFile>) is not 'TRUE'")
    con$.extptr <- .Call(.bamfile_close, .extptr(con))
    invisible(con)
}

## scanBam, filterBam, countBam

setMethod(scanBamHeader, "BamFile",
          function(files, ..., what=c("targets", "text"))
{
    if (!isOpen(files)) {
        open(files)
        on.exit(close(files))
    }
    .Call(.read_bamfile_header, .extptr(files), c("targets", "text") %in% what)
})

setMethod(seqinfo, "BamFile",
          function(x)
{
    h <- scanBamHeader(x, what="targets")[["targets"]]
    Seqinfo(names(h), unname(h))
})

setMethod(obeyQname, "BamFile",
    function(object, ...)
{
    object$obeyQname
})

setReplaceMethod("obeyQname", "BamFile", 
    function(object, ..., value)
{
    if (1L != length(value))
        stop("'value' must be length 1")
    object$obeyQname <- value
    object
})

setMethod(asMates, "BamFile",
    function(object, ...)
{
    object$asMates
})

setReplaceMethod("asMates", "BamFile", 
    function(object, ..., value)
{
    if (!isTRUEorFALSE(value))
        stop("'value' must be TRUE or FALSE")
    object$asMates <- value
    object
})

.checkPrefixSuffix <- function(object, value, name)
{
    if (!is(value, "character"))
        stop("'value' must be a single character")
    if (length(value))
        if (nchar(value) > 1L)
            stop("nchar(value) must be <= 1")
    if (!asMates(object))
        warning(paste0("when 'asMates' is TRUE '", name, "' is ignored"))
}

setMethod(qnamePrefixEnd, "BamFile",
    function(object, ...)
{
    object$qnamePrefixEnd
})

setReplaceMethod("qnamePrefixEnd", "BamFile", 
    function(object, ..., value)
{
    .checkPrefixSuffix(object, value, "qnamePrefixEnd")
    object$qnamePrefixEnd <- value
    object
})

setMethod(qnameSuffixStart, "BamFile",
    function(object, ...)
{
    object$qnameSuffixStart
})

setReplaceMethod("qnameSuffixStart", "BamFile", 
    function(object, ..., value)
{
    .checkPrefixSuffix(object, value, "qnameSuffixStart")
    object$qnameSuffixStart <- value
    object
})

setMethod(scanBam, "BamFile",
          function(file, index=file, ...,
                   param=ScanBamParam(what=scanBamWhat()))
{
    if (!isOpen(file)) {
        open(file)
        on.exit(close(file))
    }
    if (obeyQname(file) && asMates(file))
        warning("'obeyQname=TRUE' ignored when 'asMates=TRUE'")
    if (!missing(index))
        warning("'index' ignored for scanBam,BamFile-method")
    if (!is(param, "ScanBamParam")) {
        msg <- sprintf("'%s' must be a '%s'; was '%s'",
                       "param", "ScanBamParam", class(param))
        stop(msg)
    }
    if (0L == length(bamWhat(param)) && 0L == length(bamTag(param))) {
        txt <- "no BAM fields selected for input (neither 'bamWhat(param)'
                nor 'bamTag(param)' defined)"
        warning(paste(strwrap(txt), collapse="\n  "))
    }
    if (!asMates(file))
        bamWhat(param) <- setdiff(bamWhat(param), c("groupid", "mate_status")) 
    reverseComplement <- bamReverseComplement(param)
    if (is.na(qnamePrefix <- qnamePrefixEnd(file)))
        qnamePrefix <- ""
    if (is.na(qnameSuffix <- qnameSuffixStart(file)))
        qnameSuffix <- ""
    tmpl <- .scanBam_template(file, param)
    x <- .io_bam(.scan_bamfile, file, reverseComplement,
                 yieldSize(file), tmpl, obeyQname(file), 
                 asMates(file), qnamePrefix, qnameSuffix, 
                 param=param)
    .scanBam_postprocess(x, param)
})

setMethod(countBam, "BamFile",
          function (file, index=file, ..., param = ScanBamParam())
{
    if (!isOpen(file)) {
        open(file)
        on.exit(close(file))
    }
    if (!missing(index))
        warning("'index' ignored for countBam,BamFile-method")
    x <- .io_bam(.count_bamfile, file, param=param)
    .countBam_postprocess(x, file, param)
})

### NOTE: Not exported but used in the GenomicAlignments package!
### 'bamfile' must be a BamFile object. Returns a named list with 1 element
### per loaded column.
.load_bamcols_from_scanBam_res <- function(res, param, with.which_label=FALSE)
{
    if (!isTRUEorFALSE(with.which_label))
        stop("'with.which_label' must be TRUE or FALSE")
    which_label <- names(res)
    names(res) <- NULL
    ## Compute the "which_label" col.
    ans3 <- list()
    if (with.which_label) {
        if (is.null(which_label)) {
            warning("'which_label' is ignored when 'param' is missing or ",
                    "doesn't have a 'which' component")
        } else {
            ## We want unique labels.
            if (anyDuplicated(which_label))
                which_label <- paste0(which_label, ".", seq_along(which_label))
            ## Currently scanBam() should always output a 'res' of length != 0
            ## but we test anyway just in case one day this changes.
            if (length(res) == 0L) {
                run_lens <- integer(0)
            } else {
                run_lens <- sapply(res, function(x) length(x[[1L]]))
            }
            which_label <- Rle(factor(which_label, levels=which_label),
                               run_lens)
            ans3 <- list(which_label=which_label)
        }
    }
    ## Extract the "what" cols.
    ans1 <- lapply(setNames(bamWhat(param), bamWhat(param)),
                   function(nm) {
                       tmp <- lapply(res, "[[", nm)
                       S4Vectors:::quick_unlist(tmp)
                   })

    ## Extract the "tag" cols.
    ans2 <- lapply(setNames(bamTag(param), bamTag(param)),
                   function(nm) {
                       tmp <- lapply(res,
                                     function(res_elt) {
                                         tag <- res_elt[["tag"]]
                                         tag_elt <- tag[[nm]]
                                         ## Fill empty tag with NAs.
                                         if (is.null(tag_elt)) {
                                             count <- length(res_elt[["rname"]])
                                             tag_elt <- rep.int(NA, count)
                                         }
                                         tag_elt
                                     })
                       S4Vectors:::quick_unlist(tmp)
                   })
    ## Put all the cols together and return them.
    c(ans1, ans2, ans3)
}

.filterBam_FilterRules <-
    function(file, destination, filter, param)
{
    which <- unlist(bamWhich(param))
    nRange <- length(which)
    if (nRange)                         # yield by range
        iRange <- 1L

    yieldSize <- yieldSize(file)
    if (is.na(yieldSize))
        yieldSize <- 1000000L

    tmpl <- .scanBam_template(file, param)
    reverseComplement <- bamReverseComplement(param)
    if (is.na(qnamePrefix <- qnamePrefixEnd(file)))
        qnamePrefix <- ""
    if (is.na(qnameSuffix <- qnameSuffixStart(file)))
        qnameSuffix <- ""

    dest <- .Call(.bamfile_open, destination, path(file), "wb")
    on.exit(.Call(.bamfile_close, dest))

    n_tot <- 0L
    repeat {
        buf <- .io_bam(.prefilter_bamfile, file, param=param,
                       yieldSize, obeyQname(file), asMates(file),
                       qnamePrefix, qnameSuffix)
        if (0L == .Call(.bambuffer_length, buf))
            break

        ans <- .io_bam(.bambuffer_parse, file, param=param, buf,
                       reverseComplement, tmpl)
        ans <- DataFrame(.load_bamcols_from_scanBam_res(ans, param))
        ans <- eval(filter, ans)
        n_tot <- n_tot + .Call(.bambuffer_write, buf, dest, ans)
    }

    destination
}

setMethod(filterBam, "BamFile",
          function (file, destination, index=file, ...,
                    filter=FilterRules(),
                    indexDestination=TRUE,
                    param=ScanBamParam(what=scanBamWhat()))
{
    if (!isOpen(file)) {
        open(file)
        on.exit(close(file))
    }
    if (missing(destination))
        stop(sprintf("'%s' missing with no default", "destination"))
    if (!is(param, "ScanBamParam"))
        stop(sprintf("'%s' must be a '%s'; was '%s'",
                     "param", "ScanBamParam", class(param)))
    param <- .filterBam_preprocess(file, param)
    destination <- .normalizePath(destination)

    if (length(filter))
        .filterBam_FilterRules(file, param=param, destination, filter)
    else
        .io_bam(.filter_bamfile, file, param=param, destination, "wb")

    if (indexDestination) {
        if (asMates(file)) {
            ## FIXME: filtering by mates requires expensive re-sort!
            fl <- tempfile()
            file.rename(destination, fl)
            sortBam(fl, destination)
            file.rename(paste0(destination, ".bam"), destination)
        }
        indexBam(destination)
    }
    destination
})

setMethod(indexBam, "BamFile", function(files, ...) {
    indexBam(path(files), ...)
})

setMethod(sortBam, "BamFile",
    function(file, destination, ..., byQname=FALSE, maxMemory=512)
{
    sortBam(path(file), destination, ...,
                byQname=byQname, maxMemory=maxMemory)
})


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### "quickBamFlagSummary" methods.
###

setMethod(quickBamFlagSummary, "BamFile",
    function(file, ..., param=ScanBamParam(), main.groups.only=FALSE)
{
    what0 <- c("qname", "flag")
    if (length(bamWhat(param)) != 0L)
        warning("bamWhat component of supplied 'param' was ignored")
    bamWhat(param) <- what0

    res <- scanBam(file, param=param)
    res0 <- res[[1L]]
    if (length(res) != 1L) {
        res0[["qname"]] <- do.call(c, lapply(res, "[[", "qname"))
        res0[["flag"]] <- do.call(c, lapply(res, "[[", "flag"))
    } 

    quickBamFlagSummary(res0, param=param, main.groups.only=main.groups.only)
})

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### "show" methods
###

setMethod(show, "BamFile", function(object) {
    callNextMethod()
    cat("obeyQname:", obeyQname(object), "\n")
    cat("asMates:", asMates(object), "\n")
    cat("qnamePrefixEnd:", qnamePrefixEnd(object), "\n")
    cat("qnameSuffixStart:", qnameSuffixStart(object), "\n")
})
