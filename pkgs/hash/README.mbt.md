# Ion Hash (`moonrockz/ion/hash`)

Implements [Ion Hash 1.0](https://amazon-ion.github.io/ion-hash/docs/spec.html)
over SHA-256. A value is serialized to a canonical byte sequence that does not
depend on the encoding or on symbol IDs, and that sequence is hashed. The
official [conformance suite](https://github.com/amazon-ion/ion-hash-test)
checks it byte for byte.

- `ion_hash` returns the 32-octet digest, and `ion_hash_hex` the same digest
  as lowercase hex.
- `ion_hash_with` takes any digest function, as the specification allows; it
  is used for the final digest and for each struct field.

## The same value has the same hash

The hash is the same for text and binary, for any struct field order, and for
any spelling of the same symbol. Anything that changes the Ion value, such as
an annotation or the precision of a decimal, changes the hash.

```mbt check
///|
test "equivalent values hash alike" {
  let text = @text.read_ion("{ name: \"Ion\", version: 1.0 }")
  let reordered = @text.read_ion("{ version: 1.0, name: \"Ion\" }")
  let binary = @binary.read_binary_value(@binary.write_binary_value(text))
  let digest = @hash.ion_hash_hex(text)
  inspect(
    digest,
    content="5c2afe87628c9e9f4b2e7344f9817ae69ed55065368e7beb5fd043fc820a239e",
  )
  assert_eq(@hash.ion_hash_hex(reordered), digest)
  assert_eq(@hash.ion_hash_hex(binary), digest)
  // A symbol ID that names the same text hashes as that text.
  assert_eq(
    @hash.ion_hash_hex(@text.read_ion("$4")),
    @hash.ion_hash_hex(@text.read_ion("name")),
  )
}

///|
test "different values hash differently" {
  let base = @hash.ion_hash_hex(@text.read_ion("1.0"))
  assert_true(@hash.ion_hash_hex(@text.read_ion("1.00")) != base)
  assert_true(@hash.ion_hash_hex(@text.read_ion("unit::1.0")) != base)
  inspect(@hash.ion_hash(@text.read_ion("1.0")).length(), content="32")
}
```

## A custom digest

Passing the identity function returns the canonical serialization itself,
which shows what the digest covers: begin and end markers around a type
descriptor and the value's representation.

```mbt check
///|
test "the canonical serialization" {
  let serialized = @hash.ion_hash_with(@text.read_ion("true"), bytes => bytes)
  let hex = serialized
    .to_array()
    .map(octet => {
      (octet.to_int() + 0x100).to_string(radix=16).view(start_offset=1)
    })
    .join(" ")
  // 0B begins the value, 11 is `true`'s descriptor, and 0E ends the value.
  inspect(hex, content="0b 11 0e")
}
```

A symbol whose text is unknown cannot be hashed, since the hash is defined
over text, so it raises `@ion.IonError`.
