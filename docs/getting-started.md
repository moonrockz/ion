# Getting started

`moonrockz/ion` reads and writes [Amazon Ion](https://amazon-ion.github.io/ion-docs/)
1.0 from the command line and from MoonBit. [Install](installation.md) the
library, `moonx`, or the `ion` binary before the steps below. The commands
read stdin.

## Print a value

```ion
order::{
  id: 7,
  status: shipped,
  total: 19.990,
}
```

`order::` is an annotation. `shipped` is a symbol, and `"shipped"` would be
a string. `19.990` is an exact decimal. A file may contain several top-level
values in a row; it does not need a surrounding list.

The first command is shown for a POSIX shell and for PowerShell, and in
each shell for both ways to run the tool. `moonx moonrockz/ion` runs the
published module. `ion` is the release binary. Later examples use `moonx`.
When `ion` is on your `PATH`, drop the `moonx moonrockz/ion` prefix and keep
the rest of the command.

POSIX shell:

```sh
printf '%s\n' 'order::{id: 7, status: shipped, total: 19.990}' |
  moonx moonrockz/ion print --pretty
```

```sh
printf '%s\n' 'order::{id: 7, status: shipped, total: 19.990}' |
  ion print --pretty
```

PowerShell. A single-quoted string is the text to pipe:

```powershell
'order::{id: 7, status: shipped, total: 19.990}' |
  moonx moonrockz/ion print --pretty
```

```powershell
'order::{id: 7, status: shipped, total: 19.990}' |
  ion print --pretty
```

Omitting the input file reads stdin. `-` names stdin explicitly. Pass a
path when the input is a file.

## Call the library

```sh
moon add moonrockz/ion
```

```moonbit
import {
  "moonrockz/ion/text" @text,
}
```

```moonbit
let value = @text.read_ion("order::{id: 7, status: shipped, total: 19.990}")
println(@text.write_ion(value))
```

`read_ion` reads one value. `read_ion_datagram` reads every top-level value.
Both raise `IonError` when the text is not Ion.

## Next

| Task | Guide |
| --- | --- |
| Move between Ion text and binary | [Read, write, and transcode Ion](cookbook/read-write-and-transcode.md) |
| Import or export JSON | [Convert between Ion and JSON](cookbook/convert-json.md) |
| Check records | [Validate data with Ion Schema](cookbook/validate-with-ion-schema.md) |
| Encode variants | [Model algebraic data types with Ion Schema](cookbook/algebraic-data-types.md) |

[Ion and the repository](ion-and-the-repository.md) covers the data model
and the package map. The [CLI reference](../pkgs/README.md) lists every
command.
