# Outcome-free equivalence against the immutable original implementation.
source("R/location_edition_sensitivity_tests.R")
old <- new.env(parent=globalenv())
eval(parse(text=ls_git(c("show",paste0(
  "52bc0b45d4809a96e743c12976bdf728fe478ac6:",
  "R/location_edition_sensitivity_reporting.R")))),envir=old)
test("exact original reporting objects",identical(st,old$ls_stability(pc,ps,grid)))
test("empty reporting identity",identical(ls_stability(pc[0,],ps[0,],grid),
  old$ls_stability(pc[0,],ps[0,],grid)))
test("no retained one-row tables",!grepl("data.frame\\(|bind_rows\\(rows|contrasts\\[\\[ci\\]\\]",
  paste(deparse(body(ls_stability)),collapse="\n")))
test("fixed-size column construction",grepl("length.out = nc",paste(deparse(body(ls_stability)),collapse="\n")))
for(name in names(st)) {
  legacy<-old$ls_stability(pc,ps,grid)[[name]]
  a<-file.path(tmp,paste0(name,"-original.parquet"))
  b<-file.path(tmp,paste0(name,"-corrected.parquet"))
  ls_write_parquet(legacy,a);ls_write_parquet(st[[name]],b)
  test(paste(name,"exact serialization"),identical(ls_hash(a),ls_hash(b)))
}
test("all other reporting functions unchanged",all(vapply(setdiff(ls(old),"ls_stability"),
  function(n) {a<-get(n,old);b<-get(n,globalenv())
    if(is.function(a)) identical(body(a),body(b)) else identical(a,b)},logical(1))))
test("immutable original checkpoint code hashes",identical(unname(ls_original_code_hashes(
  cfg$pre_result_implementation_commit)),c(
  "232c452b55431924132dac6014c9a91056b4a23ee12920322d863e2ddab44508",
  "f40e7b4b741777c70f1267548f63ac6ecefb4b355edb354b68ddbcf589173d2a",
  "1f0ca4eb8fbe557d7159a1850fa226eddb8d3833eb6263a408439717603fe3d0",
  "b6055c21237b7d0d28ef2b043ef47757fe24cfbaba280747e9367b37c7354c4d")))
lock<-fromJSON(LS_REPORTING_LOCK)
test("separate original calculation anchor",identical(lock$original_calculation_commit,
  "52bc0b45d4809a96e743c12976bdf728fe478ac6"))
test("pending correction cannot execute",lock$reporting_correction_commit!="PENDING" ||
  rejects(ls_reporting_lock()))
test("one corrected resume guard present",grepl("one corrected resume only",runner,fixed=TRUE))
cat("PASS:",length(passed),"combined execution and reporting regression checks.\n")
