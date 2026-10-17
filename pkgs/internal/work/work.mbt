///|
/// A synchronous executor for compiler-generated continuations.
/// Each executor owns one active computation. It performs no I/O.
/// This package supports the library's private recursive operations.
#doc(hidden)
pub struct Runner {
  priv mut continue_ : (() -> Unit)?
  priv mut until_pause : Int32
}

///|
/// Create an executor with no suspended work.
#doc(hidden)
pub fn Runner::Runner() -> Runner {
  { continue_: None, until_pause: 0, }
}

///|
async fn suspend(
  register : ((Unit) -> Unit) -> Unit,
) -> Unit noraise + nocancel = "%async.suspend"

///|
fn enter(body : async () -> Unit noraise + nocancel) -> Unit = "%async.run"

///|
/// Request a scheduling point. A bounded batch of requests shares one
/// executor iteration. Call before descent and on return, including errors.
#doc(hidden)
pub async fn Runner::pause(self : Runner) -> Unit noraise + nocancel {
  if self.until_pause > 0 {
    self.until_pause -= 1
    return
  }
  self.until_pause = 15
  suspend(continue_ => self.continue_ = Some(() => continue_(())))
}

///|
/// Run a computation to completion before returning to the caller.
/// All suspension points must use this executor's `pause` method.
/// Do not start another computation on the same executor while this runs.
#doc(hidden)
pub fn[A, E : Error] Runner::run(
  self : Runner,
  body : async () -> A raise E + nocancel,
) -> A raise E {
  let result : Result[A, E] = self.run_total(() => {
    Ok(body()) catch {
      error => Err(error)
    }
  })
  match result {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
/// Run a computation that cannot raise an error.
/// All suspension points must use this executor's `pause` method.
///
/// ```mbt check
/// test {
///   let runner = @work.Runner()
///   let result = runner.run_total(() => {
///     runner.pause()
///     7
///   })
///   assert_eq(result, 7)
/// }
/// ```
#doc(hidden)
pub fn[A] Runner::run_total(
  self : Runner,
  body : async () -> A noraise + nocancel,
) -> A {
  let result : Ref[A?] = { val: None, }
  enter(() => result.val = Some(body()))
  for outcome = result.val {
    match outcome {
      Some(value) => return value
      None => {
        guard self.continue_ is Some(continue_) else {
          abort("executor suspended outside Runner::pause")
        }
        self.continue_ = None
        continue_()
        continue result.val
      }
    }
  }
}

///|
/// Internal switching threshold for bounded recursive value-processing fast
/// paths. This never limits which nesting depths a reader accepts.
#doc(hidden)
pub const SHALLOW_DEPTH : Int32 = 128
