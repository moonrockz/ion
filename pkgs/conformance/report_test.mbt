// Machine-readable corpus results for the CI summary. Emit before asserting
// success so a failed suite still reports its counts and exclusions.

///|
fn report_conformance(
  suite : String,
  total : Int,
  passed : Int,
  skipped? : Int = 0,
  known_failures? : Int = 0,
  not_applicable? : Int = 0,
  unexpected? : Int = 0,
  stale? : Int = 0,
  files? : Int = 0,
  out_of_scope? : Int = 0,
  details? : Array[String] = [],
) -> Unit {
  let result = Json::object(
    Map([
      ("suite", Json::string(suite)),
      ("total", Json::number(total.to_double())),
      ("passed", Json::number(passed.to_double())),
      ("skipped", Json::number(skipped.to_double())),
      ("known_failures", Json::number(known_failures.to_double())),
      ("not_applicable", Json::number(not_applicable.to_double())),
      ("unexpected", Json::number(unexpected.to_double())),
      ("stale", Json::number(stale.to_double())),
      ("files", Json::number(files.to_double())),
      ("out_of_scope", Json::number(out_of_scope.to_double())),
      ("details", Json::array(details.map(Json::string))),
    ]),
  )
  println("CONFORMANCE " + result.stringify())
}
