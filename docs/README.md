# Using Ion and this repository

`moonrockz/ion` is a MoonBit library for Amazon Ion 1.0. The `ion` command
line tool uses the same readers, writers, and validators as library callers.

Start with [Ion and the repository](ion-and-the-repository.md) for the data
model, package map, and setup. Go to the [cookbook](cookbook/README.md) when
you have a task to accomplish.

| Task | Guide |
| --- | --- |
| Read Ion and move between text and binary | [Read, write, and transcode Ion](cookbook/read-write-and-transcode.md) |
| Import JSON or export Ion to JSON | [Convert between Ion and JSON](cookbook/convert-json.md) |
| Check records and report validation errors | [Validate data with Ion Schema](cookbook/validate-with-ion-schema.md) |
| Encode records, variants, and recursive data | [Model algebraic data types with Ion Schema](cookbook/algebraic-data-types.md) |

The package READMEs contain executable MoonBit examples and more detailed
API guidance. Their links are in the [package map](ion-and-the-repository.md#choose-a-package).
The cookbook's [example files](cookbook/examples/) run from a checkout,
and its library examples and schemas have blackbox tests in `pkgs/`.

For the format's authoritative definitions, see the
[Ion specification](https://amazon-ion.github.io/ion-docs/docs/spec.html) and
[Ion Schema 2.0 specification](https://amazon-ion.github.io/ion-schema/docs/isl-2-0/spec.html).
