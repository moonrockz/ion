# Ion cookbook

These articles walk through tasks with the `ion` CLI and the MoonBit
library. Run shell commands from the repository root. Library snippets are
MoonBit tests; add the listed imports to your package's `moon.pkg`, then
copy the test into a `*_test.mbt` file and run `moon test`.

| Recipe | What you will accomplish |
| --- | --- |
| [Read, write, and transcode Ion](read-write-and-transcode.md) | Parse a datagram, preserve Ion values through binary, and choose a streaming API |
| [Convert between Ion and JSON](convert-json.md) | Import a JSON document and identify what an Ion export loses |
| [Validate data with Ion Schema](validate-with-ion-schema.md) | Define a record type, validate values, and report paths to bad fields |
| [Model algebraic data types with Ion Schema](algebraic-data-types.md) | Define products, tagged sums, enums, options, and recursive trees |

The [example files](examples/) are ready to run. In particular,
`invalid-shapes.ion` deliberately fails validation so you can see what the
ADT schema rejects. Schemas use the explicit `$ion_schema_2_0` marker to
make their constraint semantics unambiguous.

For individual API details, follow the package guides linked in each
article. For an introduction, read [Ion and the repository](../ion-and-the-repository.md).
