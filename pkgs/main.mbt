// The `ion` command-line tool. The commands live in `moonrockz/ion/cli`; this
// executable runs them with the process's arguments and standard streams.

///|
async fn main {
  let args = @env.args()
  let status = @cli.run(
    args[1:].to_owned(),
    @stdio.stdin,
    @stdio.stdout,
    @stdio.stderr,
  )
  if status != 0 {
    @sys.exit(status)
  }
}
