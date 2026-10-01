# Ion cookbook

These articles walk through tasks with the published CLI and the MoonBit
library. [Install](../installation.md) `moonx` or the `ion` binary first.
[Getting started](../getting-started.md) prints one value.

Each article's first shell command is shown for a POSIX shell and for
PowerShell. In each shell it appears twice: `moonx moonrockz/ion` runs the
published module, and `ion` is the release binary. Later commands use
`moonx`. When `ion` is on your `PATH`, drop the `moonx moonrockz/ion` prefix
and keep the rest of the command.

Omit the input file to read stdin. A POSIX shell uses `printf`. PowerShell
pipes a single-quoted string, and several strings separated by commas become
one value per line. Command Prompt runs the same commands when the input is
a file path. `-` names stdin explicitly. `validate` still takes its schema
as a file path. PowerShell rewrites bytes when `>` redirects a native
command, so an example that writes Ion binary uses `cmd /c` for that
redirect. The [example files](examples/) hold the same values. In
particular, `invalid-shapes.ion` collects values the algebraic-data-type
schema rejects. Schemas use the `$ion_schema_2_0` marker so their constraint
semantics are explicit.

Library snippets are MoonBit tests. Add the listed imports to your
package's `moon.pkg`, copy the test into a `*_test.mbt` file, and run
`moon test`.

| Recipe | What you will accomplish |
| --- | --- |
| [Read, write, and transcode Ion](read-write-and-transcode.md) | Parse a datagram, preserve Ion values through binary, and choose a streaming API |
| [Convert between Ion and JSON](convert-json.md) | Import a JSON document and identify what an Ion export loses |
| [Validate data with Ion Schema](validate-with-ion-schema.md) | Define a record type, validate values, and report paths to bad fields |
| [Model algebraic data types with Ion Schema](algebraic-data-types.md) | Define products, tagged sums, enums, options, and recursive trees |

For individual API details, follow the package guides linked in each
article. For the data model and package map, read
[Ion and the repository](../ion-and-the-repository.md).
