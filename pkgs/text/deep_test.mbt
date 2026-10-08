// The text walkers handle values nested far deeper than the reader accepts.
// See pkgs/ion/deep_test.mbt for the approach.

///|
let deep : Int = 100_000

///|
/// Pretty text has one indent per level on each line, so its size grows with
/// the square of the depth. 3,000 levels is past the depth where a recursive
/// writer overflows a cold js or wasm-gc engine (about 1,000).
let pretty_deep : Int = 3_000

///|
let shapes : Array[@testkit.DeepShape] = [
  List,
  Sexp,
  Struct,
  AnnotatedList,
  Mixed,
]

///|
/// The opening and closing text of one nesting level.
fn level_text(shape : @testkit.DeepShape) -> (String, String) {
  match shape {
    Sexp => ("(", ")")
    Struct => ("{", "}")
    AnnotatedList => ("name::[", "]")
    List | Mixed => ("[", "]")
  }
}

///|
/// The compact text of `@testkit.deep_value(shape, depth)`, built with loops.
fn deep_text(shape : @testkit.DeepShape, depth : Int) -> String {
  let out = StringBuilder()
  for level in 0..<depth {
    if level > 0 && shape.at(level - 1) == Struct {
      out.write_string("name: ")
    }
    out.write_string(level_text(shape.at(level)).0)
  }
  if depth > 0 && shape.at(depth - 1) == Struct {
    out.write_string("name: ")
  }
  out.write_string("1")
  for level = depth - 1; level >= 0; level = level - 1 {
    out.write_string(level_text(shape.at(level)).1)
  }
  out.to_string()
}

///|
/// The pretty text of `@testkit.deep_value(shape, depth)`, built with loops.
fn deep_pretty_text(shape : @testkit.DeepShape, depth : Int) -> String {
  let out = StringBuilder()
  for level in 0..<depth {
    if level > 0 {
      out.write_string("\n")
      out.write_string("  ".repeat(level))
      if shape.at(level - 1) == Struct {
        out.write_string("name: ")
      }
    }
    out.write_string(level_text(shape.at(level)).0)
  }
  out.write_string("\n")
  out.write_string("  ".repeat(depth))
  if shape.at(depth - 1) == Struct {
    out.write_string("name: ")
  }
  out.write_string("1")
  for level = depth - 1; level >= 0; level = level - 1 {
    out.write_string("\n")
    out.write_string("  ".repeat(level))
    out.write_string(level_text(shape.at(level)).1)
  }
  out.to_string()
}

///|
test "deep_text spells shallow values as the writer does" {
  for shape in shapes {
    let value = @testkit.deep_value(shape, 4)
    assert_eq(deep_text(shape, 4), @text.write_ion(value))
    assert_eq(deep_pretty_text(shape, 4), @text.write_ion_pretty(value))
  }
}

///|
#skip("ion-dql.5: write_value recurses once per level")
test "write_ion writes values 100,000 levels deep" {
  for shape in shapes {
    let text = @text.write_ion(@testkit.deep_value(shape, deep))
    if text != deep_text(shape, deep) {
      fail("compact text differs")
    }
  }
}

///|
#skip("ion-dql.5: write_value recurses once per level")
test "write_ion_pretty writes values 3,000 levels deep" {
  for shape in shapes {
    let text = @text.write_ion_pretty(@testkit.deep_value(shape, pretty_deep))
    if text != deep_pretty_text(shape, pretty_deep) {
      fail("pretty text differs")
    }
  }
}

///|
#skip("ion-dql.5: emit_value recurses once per level")
test "IonReader emits the events of values 100,000 levels deep" {
  for shape in shapes {
    let events = @text.IonReader::from_value(@testkit.deep_value(shape, deep)).remaining()
    let mut depth = 0
    let mut deepest = 0
    let mut scalars = 0
    for event in events {
      match event {
        ListStart | SexpStart | StructStart => {
          depth += 1
          deepest = if depth > deepest { depth } else { deepest }
        }
        ListEnd | SexpEnd | StructEnd => depth -= 1
        Scalar(_) => scalars += 1
        _ => ()
      }
    }
    assert_eq((deepest, depth, scalars), (deep, 0, 1))
  }
}

///|
/// Tracks the container depth of the events it receives.
struct DepthCounter {
  mut depth : Int
  mut deepest : Int
  mut scalars : Int
}

///|
fn DepthCounter::enter(self : DepthCounter) -> Unit {
  self.depth += 1
  if self.depth > self.deepest {
    self.deepest = self.depth
  }
}

///|
impl @text.IonHandler for DepthCounter with fn on_list_start(self) {
  self.enter()
}

///|
impl @text.IonHandler for DepthCounter with fn on_sexp_start(self) {
  self.enter()
}

///|
impl @text.IonHandler for DepthCounter with fn on_struct_start(self) {
  self.enter()
}

///|
impl @text.IonHandler for DepthCounter with fn on_list_end(self) {
  self.depth -= 1
}

///|
impl @text.IonHandler for DepthCounter with fn on_sexp_end(self) {
  self.depth -= 1
}

///|
impl @text.IonHandler for DepthCounter with fn on_struct_end(self) {
  self.depth -= 1
}

///|
impl @text.IonHandler for DepthCounter with fn on_scalar(self, _value) {
  self.scalars += 1
}

///|
#skip("ion-dql.5: dispatch_value recurses once per level")
test "dispatch_value pushes the events of values 100,000 levels deep" {
  for shape in shapes {
    let counter : DepthCounter = { depth: 0, deepest: 0, scalars: 0, }
    @text.dispatch_value(@testkit.deep_value(shape, deep), counter)
    assert_eq((counter.deepest, counter.depth, counter.scalars), (deep, 0, 1))
  }
}
