# XipFax for Ruby

Send faxes from your code with [XipFax](https://xipfax.com): quote a fax, add your PDFs, send them to a
number or a government office, and follow each fax until it's delivered. The SDK is generated from
the API's own document, so its methods and types are the API's. It needs Ruby 2.7 or later, and
sends its requests with Faraday.

## Install

```sh
gem install xipfax-sdk
```

Or, in your Gemfile, `gem 'xipfax-sdk'`.

## Make an API key

Sign in to the [developer console](https://developer.xipfax.com/console/), open API keys and make a
key. You see it whole just once, so copy it then. Every key is live: what it sends is real.

Keep the key on your server. A key in a web page or an app is anyone's.

## Use it

```ruby
require 'xipfax-sdk'

client = XipFax::Client.new(ENV.fetch('XIPFAX_API_KEY', ''))

begin
  quote = client.quote.get_quote(3)
rescue XipFax::ApiError => e
  raise unless e.refusal

  abort "#{e.refusal.error.code}: #{e.refusal.error.message}"
end
puts "#{quote.price_shown}: #{quote.terms}"
```

The client's APIs are the [API reference](https://developer.xipfax.com/docs/api/)'s sections:
`quote`, `draft`, `faxes`, `plan`, `offices` and `webhook_endpoints`. Each method takes what the
request needs as its arguments, and what it may carry as its options, by name,
`list_offices(search: 'Form 2848', place: 'OH', limit: 3)`, and answers the API's answer as its
model. Where the API refuses, it raises
an `XipFax::ApiError`, whose `code` is the HTTP status and whose `refusal` is the API's error
object, an `XipFax::ApiErrorBody`, whose error's `code` is the one to branch on. A request that
never reached XipFax raises an `XipFax::ApiError` whose `refusal` is nil. Each method has a
`…_with_http_info` form too, which answers the model with the status and the headers.

`XipFax::Client.new(api_key, base_url: …)` takes another address than `https://api.xipfax.com`, and
yields the client's settings, a `XipFax::Configuration`, before its first request: its `timeout`,
in seconds, 60 unless you set it, and its Faraday connection, which `configure_faraday_connection`
gives what you'd give any other.

```ruby
client = XipFax::Client.new(api_key) { |config| config.timeout = 30 }
```

## The quickstart

[`examples/quickstart.rb`](examples/quickstart.rb) takes the steps of
[XipFax's quickstart](https://developer.xipfax.com/docs/guides/quickstart/) through the SDK. Run it
from a clone of this repository, after `bundle install`:

```sh
XIPFAX_API_KEY=xipfax_key_live_… bundle exec ruby examples/quickstart.rb
```

That takes the free steps alone: what a fax costs, and the offices that take Form 2848 from Ohio,
with their fax numbers.

To send a fax too, name a fax number of yours and a public https link to a PDF:

```sh
XIPFAX_TO='+1 202 555 0143' XIPFAX_PDF_URL=https://example.com/letter.pdf \
  XIPFAX_API_KEY=xipfax_key_live_… bundle exec ruby examples/quickstart.rb
```

**That step sends a real fax, and it's charged.** Its pages count on your plan, or where you have no
plan its price is held on the card you saved, and taken once it's delivered. A fax that fails costs
nothing. The quickstart says so before it sends, and sends only once you type `send`. Then it
follows the fax until it's delivered, and gives the link to its confirmation.

## Methods

| Method                                                                               | Request                                        | What it does                                                                         |
| ------------------------------------------------------------------------------------ | ---------------------------------------------- | ------------------------------------------------------------------------------------ |
| `quote.get_quote(pages)`                                                             | `GET /quote`                                   | The price of a fax of so many pages, sent without a plan.                            |
| `draft.get_draft`                                                                    | `GET /draft`                                   | Your draft, the fax you prepare, its documents in the order it sends them.           |
| `draft.add_document(idempotency_key, new_document)`                                  | `POST /draft/documents`                        | Adds a PDF to the draft, by a link XipFax fetches or by an upload.                   |
| `draft.complete_document(idempotency_key, document_id)`                              | `POST /draft/documents/{document_id}/complete` | Reads an uploaded PDF back, its pages counted.                                       |
| `draft.remove_document(document_id)`                                                 | `DELETE /draft/documents/{document_id}`        | Takes a document out of the draft.                                                   |
| `draft.send_draft(idempotency_key, send_draft)`                                      | `POST /draft/send`                             | Sends the draft to a number or an office.                                            |
| `faxes.list_faxes(opts)`                                                             | `GET /faxes`                                   | The faxes you sent and received, newest first, a page at a time.                     |
| `faxes.get_fax(fax_id)`                                                              | `GET /faxes/{fax_id}`                          | A fax, where it stands now.                                                          |
| `faxes.get_confirmation(fax_id)`                                                     | `GET /faxes/{fax_id}/confirmation`             | A delivered fax's confirmation, by a link that reads it for a few minutes.           |
| `plan.get_plan`                                                                      | `GET /plan`                                    | Your plan, or none.                                                                  |
| `offices.list_offices(opts)`                                                         | `GET /offices`                                 | The government offices XipFax gives the fax numbers of.                              |
| `webhook_endpoints.register_webhook_endpoint(idempotency_key, new_webhook_endpoint)` | `POST /webhook-endpoints`                      | Registers an endpoint of your server for every event, its signing secret shown once. |
| `webhook_endpoints.remove_webhook_endpoint(endpoint_id)`                             | `DELETE /webhook-endpoints/{endpoint_id}`      | Takes an endpoint away: no event goes to it from then on.                            |

### Upload a PDF from your disk

Give its size, send its bytes to the link the answer gives, then complete it:

```ruby
require 'faraday'

pdf = File.binread('letter.pdf')
added = client.draft.add_document(add_key, XipFax::NewDocument.new(name: 'letter.pdf', size_bytes: pdf.bytesize))
upload = added.upload or raise 'No link to upload to: the document is ready or removed.'
# A connection of its own: the link carries its own signature, and your key goes to XipFax alone.
response = Faraday.put(upload.url, pdf, upload.headers)
raise "The upload failed: #{response.status}" unless response.success?

client.draft.complete_document(complete_key, added.document.id)
```

`add_key` and `complete_key` are keys of your own, one for each request, as the next section says.

## Retries and `Idempotency-Key`

`add_document`, `complete_document`, `send_draft` and `register_webhook_endpoint` take an
`Idempotency-Key` of your own, such as `SecureRandom.uuid`, which you keep with the request. Sent
again with the same key within 24 hours, the request is answered as it was the first time rather
than done twice, so a retry after a timeout can't send a fax twice. The SDK makes up no key itself:
one it made would be new on each try, and protect nothing.

The answer to a request sent again keeps none of its signed links, nor an endpoint's secret: a
document's `url` and an endpoint's `secret` come back nil. `upload` is signed again instead while
its document is still uploading: asked for again with its key, `add_document` gives a fresh link to
send the bytes to, and nil once the document is ready or removed. An endpoint whose first answer you
lost has no secret to check its deliveries by: remove it with `remove_webhook_endpoint`, and
register it again with a new key.

## Webhooks

`register_webhook_endpoint` registers an endpoint of your server, which every event goes to from
then on: when a fax you sent is delivered or fails for good, and when a fax sent to your number
arrives. Its answer shows the endpoint's signing secret once, so keep it then.
`remove_webhook_endpoint` takes an endpoint away, as revoking the key that registered it does. Both
take an API key, not an app's token.

Check each delivery's `webhook-signature` with that secret, against its body exactly as it came,
before you trust it. [XipFax's webhooks guide](https://developer.xipfax.com/docs/guides/webhooks/)
shows how. Its body is then a `XipFax::FaxEvent`, which
`XipFax::FaxEvent.build_from_hash(JSON.parse(body))` reads.

## Versions

Each request names the version of the API the SDK was generated from, `XipFax::API_VERSION`, in its
`Xip-Version` header, so each answer keeps the shape the SDK's models describe. Within that version,
an answer may gain a member, and a set of values a new value: the SDK reads both, and leaves a member
it doesn't know out of the model it answers.

## Where the SDK comes from

`openapi.json` is the API's document, as [api.xipfax.com](https://api.xipfax.com/openapi.json) gives
it, and `scripts/generate.sh` makes the SDK from it with
[openapi-generator](https://openapi-generator.tech) 7.17.0's Ruby generator and
`openapi-generator.yaml`. It first writes the document the SDK is generated from, by
`scripts/sdk-document.jq`, which sets aside what the SDK sends itself or doesn't offer: the
document's security, since `XipFax::Client` sends your key on every request, and an app's token is
not the SDK's; the per-request `Xip-Version`, since `XipFax::Client` names the version on every
request; and the webhooks, which are XipFax's requests to your server, their bodies typed as
`XipFax::FaxEvent`. Nothing the generator writes is edited by hand: `lib/xipfax-sdk/client.rb` is
the hand-written part, and the script writes `lib/xipfax-sdk/api_version.rb` and the two lines it
adds to the entry. To update the SDK, copy the new document over `openapi.json`, run
`scripts/generate.sh`, and commit what changes. `scripts/gates.sh` checks that the SDK is what the
document generates, that every file reads, that the gem builds and that every file loads;
`scripts/test.sh` runs the specs. Both run Ruby in Docker, by `scripts/docker.sh`, on what
`scripts/fetch.sh` fetched.

## Help

Write to [help@xipfax.com](mailto:help@xipfax.com).

## License

[MIT](LICENSE).
