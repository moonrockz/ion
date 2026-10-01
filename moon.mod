// The moonrockz/ion module: a MoonBit implementation of the Amazon Ion data
// format (text and binary encodings) and the Ion Schema Language.
//
// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "moonrockz/ion"

version = "0.3.0"

readme = "README.md"

repository = "https://github.com/moonrockz/ion"

license = "Apache-2.0"

keywords = [ "ion", "serialization", "aws", "schema" ]

description = "A MoonBit implementation of the Amazon Ion data format and Ion Schema."

// Packages live under pkgs/ so the module root stays free of package sources.

source = "pkgs"

import {
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.4",
}
