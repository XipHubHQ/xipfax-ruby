# The document the SDK is generated from: the API's own, openapi.json, with what the SDK doesn't
# offer and what XipFax sends on every request set aside, an answer's values read as the API may
# widen them, and one form openapi-generator 7.17.0 renders wrong put in a form it renders right.
# scripts/generate.sh runs it. None of it changes what a request or an answer is. A document it
# can't read as it expects stops the generation, naming what it found, so that a change to the API
# is looked at before the SDK is made from it.

# A nullable member, as the document writes one: `anyOf` of a schema, a $ref or a type, and null.
def nullable_shape:
  type == "array"
  and length == 2
  and (map(select(. == {"type": "null"})) | length) == 1
  and (map(select(. != {"type": "null"}))[0] | type == "object" and (has("$ref") or (has("type") and .type != "null")));

# Each operation of the document, by its path and its method.
def operations(f): .paths |= map_values(map_values(if type == "object" then f else . end));

# The SDK offers the API key alone, as the TypeScript SDK does, and XipFax sends it on every request
# as the bearer token. So the document's security is set aside, the app token's scheme with it.
if (.components.securitySchemes | keys) != ["apiKey", "appToken"]
  or .components.securitySchemes.apiKey.type != "http"
  or .components.securitySchemes.apiKey.scheme != "bearer"
then
  error("openapi.json's security schemes aren't apiKey, a bearer token, and appToken: see what the SDK should offer before generating it")
else . end
| del(.components.securitySchemes, .security)
| operations(del(.security))

# XipFax names the version the SDK is generated from in every request's Xip-Version, as the
# TypeScript SDK does, and the document takes that version alone. So the parameter is set aside: a
# call's own would send the header a second time.
| .info.version as $version
| if (.components.parameters.XipVersion | .name != "Xip-Version" or .in != "header" or (.required // false) or .schema.enum != [$version]) then
    error("openapi.json's Xip-Version isn't an optional header taking \($version) alone: see how the SDK should offer a choice of versions before generating it")
  else . end
| operations(if has("parameters") then .parameters |= map(select(. != {"$ref": "#/components/parameters/XipVersion"})) else . end)
| del(.components.parameters.XipVersion)
| if [.. | objects | select(.name? == "Xip-Version" or ."$ref"? == "#/components/parameters/XipVersion")] != [] then
    error("openapi.json names Xip-Version somewhere other than its parameter XipVersion: see how the SDK should send it before generating it")
  else . end

# The webhooks are XipFax's requests to your server, which the SDK doesn't make. The body they carry
# stays typed, as the schema FaxEvent.
| del(.webhooks)

# An answer's set of values may gain one within its version, which the SDK reads rather than refuses,
# as the document's Additions rule asks: each enum under the schemas is set aside, and its value is
# read as the string it is, the schema's description still naming the values the version gives. The
# schemas only answers use are the ones set aside: so the step refuses a request body that isn't
# JSON by a reference to one of the schemas, a schema a request body names that holds an enum or a
# reference of its own, and an enum on anything but a string. A request's parameters keep theirs.
| . as $document
| [.paths[][] | objects | select(has("requestBody")) | .requestBody] as $bodies
| if [$bodies[] | select(
      (.content | type) != "object"
      or (.content | keys) != ["application/json"]
      or (.content["application/json"].schema | type) != "object"
      or (.content["application/json"].schema | keys) != ["$ref"]
      or (.content["application/json"].schema."$ref" | type) != "string"
      or (.content["application/json"].schema."$ref" | startswith("#/components/schemas/") | not)
      or ($document.components.schemas[.content["application/json"].schema."$ref" | ltrimstr("#/components/schemas/")] | type) != "object"
    )] != [] then
    error("a request body in openapi.json isn't JSON by a reference to one of its schemas: see how the SDK should read its values before generating it")
  else . end
| if [$bodies[] | .content["application/json"].schema."$ref" | ltrimstr("#/components/schemas/") | $document.components.schemas[.] | .. | objects | select((.enum? | type == "array") or has("$ref"))] != [] then
    error("a schema a request body names holds an enum or a reference: see how the SDK should read an answer's values apart from a request's before generating it")
  else . end
| if [.components.schemas | .. | objects | select(.enum? | type == "array") | select(.type != "string")] != [] then
    error("an enum under openapi.json's schemas isn't on a string: see how the SDK should read it before generating it")
  else . end
| .components.schemas |= walk(if type == "object" and (.enum? | type == "array") then del(.enum) else . end)

# An answer's object may gain a member within its version, which the SDK carries through rather than
# drops, as the same rule asks. openapi-generator 7.17.0 reads a schema that doesn't say whether it
# takes members it doesn't name as one that takes none, and gives its model no place for them, so
# each object of the answers that doesn't say says it does, as OpenAPI reads it. With those marks,
# the generator gives a request body's model a place for them too where its schema says it takes
# none, and none where its schema doesn't say: so a request body's schema doesn't say, and its model
# sends the members it names alone, as the API takes them. A request body that takes others, or an
# object the step can't find by its type, stops it.
| [$bodies[] | .content["application/json"].schema."$ref" | ltrimstr("#/components/schemas/")] as $requests
| if [.components.schemas[$requests[]] | .additionalProperties | select(. != false and . != null)] != [] then
    error("a schema a request body names takes members it doesn't name: see how the SDK should send them before generating it")
  else . end
| if [.components.schemas | .. | objects | select(.type? | type == "array" and index("object") != null)] != [] then
    error("an object under openapi.json's schemas takes its type as a list: see how the SDK should carry an answer's new members before generating it")
  else . end
| .components.schemas |= with_entries(
    if .key | IN($requests[]) then
      .value |= del(.additionalProperties)
    else
      .value |= walk(
        if type == "object" and .type? == "object" and (has("additionalProperties") | not) then
          . + {additionalProperties: true}
        else . end
      )
    end
  )

# The generator drops the description of a nullable member and keeps the description of the schema
# inside it, so the description moves in.
| walk(
    if type == "object" and has("anyOf") then
      if (.anyOf | nullable_shape | not) then
        error("openapi.json has an anyOf that isn't a schema or null, which scripts/sdk-document.jq doesn't read: \(.anyOf | tojson)")
      elif has("description") and (.anyOf | map(select(has("description"))) | length) > 0 then
        error("openapi.json describes a nullable member both outside and inside its anyOf: \(.description)")
      elif has("description") then
        .description as $description
        | .anyOf |= map(if . == {"type": "null"} then . else . + {description: $description} end)
        | del(.description)
      else . end
    else . end
  )

# Each generated file's header carries the document's description: its first paragraph alone keeps
# it to what the API is, so that a new entry in the document's changelog changes no generated file.
| .info.description |= (split("\n\n") | .[0])
