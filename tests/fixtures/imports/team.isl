$ion_schema_2_0

// A schema that imports a type from `common/people.isl`, whose id is a path
// relative to this file's directory.
schema_header::{
  imports: [{ id: "common/people.isl", type: person }],
}

type::{
  name: team,
  fields: {
    lead: { type: person, occurs: required },
    members: { type: list, element: person },
  },
}

schema_footer::{}
