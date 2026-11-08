# frozen_string_literal: true

require_relative 'test_helper'

# Each of the SDK's methods sends the request the API's document asks for: its method and path on the
# document's server, the key as a bearer token, the version, and every parameter and body as the
# document's schemas take them. Each request a call sends is read against the document itself, as
# each answer the stand-in gives is. Each event the document posts is read by the SDK as a FaxEvent,
# which the document takes as the SDK writes it.
class ContractTest < Minitest::Test
  API_KEY = 'xipfax_key_live_example'

  # The API's document, as the repository holds it.
  def self.document
    @document ||= XipFaxSpecs::Document.load(File.expand_path('../openapi.json', __dir__))
  end

  def document
    self.class.document
  end

  # One call of each operation, by its operation id, with arguments the document takes.
  CALLS = {
    'getQuote' => ->(client) { client.quote.get_quote(3) },
    'getDraft' => ->(client) { client.draft.get_draft },
    'addDocument' => lambda do |client|
      client.draft.add_document(
        'add-letter-1', XipFax::NewDocument.new(name: 'letter.pdf', url: 'https://example.com/letter.pdf')
      )
    end,
    'completeDocument' => ->(client) { client.draft.complete_document('complete-letter-1', 'doc_1') },
    'removeDocument' => ->(client) { client.draft.remove_document('doc_1') },
    'sendDraft' => lambda do |client|
      client.draft.send_draft(
        'send-letter-1', XipFax::SendDraft.new(fax_number: '+1 202 555 0143', document_ids: ['doc_1'])
      )
    end,
    'listFaxes' => ->(client) { client.faxes.list_faxes(limit: 20, starting_after: 'fax_0', direction: 'sent') },
    'getFax' => ->(client) { client.faxes.get_fax('fax_1') },
    'getConfirmation' => ->(client) { client.faxes.get_confirmation('fax_1') },
    'getPlan' => ->(client) { client.plan.get_plan },
    'listOffices' => lambda do |client|
      client.offices.list_offices(search: 'Form 2848', place: 'OH', limit: 5, starting_after: 'office_0')
    end,
    'registerWebhookEndpoint' => lambda do |client|
      client.webhook_endpoints.register_webhook_endpoint(
        'register-endpoint-1', XipFax::NewWebhookEndpoint.new(url: 'https://example.com/xipfax/events')
      )
    end,
    'removeWebhookEndpoint' => ->(client) { client.webhook_endpoints.remove_webhook_endpoint('endpoint_1') }
  }.freeze

  # What the stand-in answers each operation's success with, by its operation id: none for the two
  # that answer 204.
  ANSWERS = {
    'getQuote' => XipFaxSpecs::Answers::QUOTE,
    'getDraft' => '{"id":"fax_1","documents":[]}',
    'addDocument' => %({"document":#{XipFaxSpecs::Answers.document('doc_1', 'letter.pdf')},"upload":null}),
    'completeDocument' => XipFaxSpecs::Answers.document('doc_1', 'letter.pdf'),
    'sendDraft' => %({"fax":#{XipFaxSpecs::Answers.fax('status' => 'sending', 'step' => 'queued', 'finished_at' => nil)},) +
                   '"paid_by":"plan","confirm_url":null}',
    'listFaxes' => %({"data":[#{XipFaxSpecs::Answers.fax}],"has_more":false,"next_cursor":null}),
    'getFax' => XipFaxSpecs::Answers.fax,
    'getConfirmation' => '{"url":"https://example.com/confirmation.pdf"}',
    'getPlan' => XipFaxSpecs::Answers::NO_PLAN,
    'listOffices' => %({"data":[#{XipFaxSpecs::Answers::OFFICE}],"has_more":false,"next_cursor":null}),
    'registerWebhookEndpoint' => '{"id":"endpoint_1","url":"https://example.com/xipfax/events",' \
                                 '"created_at":"2026-11-07T02:00:00Z","secret":"whsec_c3RhbmQtaW4="}'
  }.freeze

  def test_the_sdk_has_a_call_for_every_operation_the_document_names_and_no_other
    assert_equal document.operations.map(&:id).sort, CALLS.keys.sort
  end

  def test_the_sdk_names_the_version_the_document_is_the_one_xip_version_takes
    assert_equal document.version, XipFax::API_VERSION
    document.operations.each do |operation|
      assert_equal [], document.version_refused(operation, XipFax::API_VERSION), operation.id
    end
  end

  # One spec for each operation the document names, so that one the SDK has no call of fails by its
  # name.
  document.operations.each do |operation|
    define_method("test_#{operation.id}_sends_its_request_as_the_document_asks") do
      call = CALLS[operation.id]
      refute_nil call, "no call of #{operation.id}"
      answer = ANSWERS.fetch(operation.id, '')
      stand_in = XipFaxSpecs::StandIn.same(operation.success, answer)

      call.call(stand_in.client(API_KEY))

      assert_equal 1, stand_in.requests.size, "#{operation.id} sent other than one request"
      request = stand_in.requests[0]
      assert_equal ["Bearer #{API_KEY}"], request.header('Authorization')
      assert_equal [operation.id, []], document.read_request(request, XipFax::API_VERSION),
                   "#{request.verb} #{request.url} reads otherwise"
      assert_equal [], document.read_answer(request, operation.success, answer), "the stand-in's answer is refused"
    end
  end

  def test_each_event_the_document_posts_is_a_fax_event_it_takes
    # The fax each event tells of, by the event's type: one for each type the document posts.
    faxes = {
      'fax.delivered' => XipFaxSpecs::Answers.fax('price' => { 'amount_minor' => 100, 'currency' => 'USD' }),
      'fax.failed' => XipFaxSpecs::Answers.fax('status' => 'failed', 'failure' => 'busy'),
      'fax.received' => XipFaxSpecs::Answers.fax(
        'id' => 'fax_2', 'direction' => 'received', 'status' => 'received', 'from_number' => '+12025550111',
        'to_number' => '+12025550100', 'pages' => 3, 'finished_at' => nil, 'time_zone' => nil
      )
    }
    assert_equal document.webhooks.keys.sort, faxes.keys.sort, 'the document posts other events than the spec types'

    faxes.each do |name, fax|
      data = XipFax::Fax.build_from_hash(JSON.parse(fax))
      assert_instance_of XipFax::Fax, data, "#{name}: the SDK doesn't read its fax"
      event = XipFax::FaxEvent.new(
        id: 'event_1', type: name, api_version: XipFax::API_VERSION, created_at: '2026-11-07T02:03:00Z', data: data
      )
      body = JSON.generate(event.to_hash)

      assert_equal [], document.check(document.webhooks[name], JSON.parse(body), name),
                   "#{name} as the SDK writes it is refused"
      # As the README reads an event: its body as JSON.parse gives it, its names text.
      read = XipFax::FaxEvent.build_from_hash(JSON.parse(body))
      assert_instance_of XipFax::FaxEvent, read, "#{name}: the SDK doesn't read back the event it wrote"
      assert_equal data.id, read.data.id
    end
  end

  # The reader is held to failing too: each thing the document refuses in a request or an answer is
  # refused, by name, so that a spec that reads the SDK's requests as fitting can fail.

  SIGNED = { 'Authorization' => ["Bearer #{API_KEY}"], 'Xip-Version' => [XipFax::API_VERSION] }.freeze
  AS_JSON = { 'Content-Type' => ['application/json'], 'Idempotency-Key' => ['add-letter-1'] }.freeze

  # Each request, its address, its headers and its body, with the operation it is and what in it the
  # reader refuses, by what it gets wrong.
  WRONG_REQUESTS = {
    'a request it takes' => ['GET', 'https://api.xipfax.com/quote?pages=3', SIGNED, '', 'getQuote', []],
    "no key, the version twice, a page past the most and a parameter it doesn't take" => [
      'GET', 'https://api.xipfax.com/quote?pages=251&color=red',
      { 'Xip-Version' => [XipFax::API_VERSION, XipFax::API_VERSION] }, '', 'getQuote',
      [
        'Authorization is [], not one bearer key',
        format('Xip-Version is ["%<version>s" "%<version>s"], not %<version>s', version: XipFax::API_VERSION),
        'header Xip-Version is sent 2 times',
        'query pages is 251, past its maximum of 250',
        'query color is no parameter of getQuote'
      ]
    ],
    "a body with a member it doesn't take, a size under the least and no name" => [
      'POST', 'https://api.xipfax.com/draft/documents', SIGNED.merge(AS_JSON), '{"size_bytes":0,"colour":"red"}',
      'addDocument',
      ['body.colour is no member it takes', 'body.size_bytes is 0, past its minimum of 1', 'body.name is missing']
    ],
    'a name that ends in a line break' => [
      'POST', 'https://api.xipfax.com/draft/documents', SIGNED.merge(AS_JSON),
      '{"name":"letter.pdf\n","url":"https://example.com/letter.pdf"}', 'addDocument',
      ['body.name is "letter.pdf\n", not of the pattern ^[^\p{Cc}\p{Zl}\p{Zp}]+$']
    ],
    'a body where the operation takes none' => [
      'DELETE', 'https://api.xipfax.com/draft/documents/doc_1', SIGNED, '{}', 'removeDocument',
      ['a body the operation takes none of']
    ],
    'another server' => [
      'GET', 'https://api.example.com/quote?pages=3', SIGNED, '', '',
      ['GET https://api.example.com/quote?pages=3 is no operation of the document']
    ]
  }.freeze

  WRONG_REQUESTS.each do |name, (verb, url, headers, body, id, refused)|
    define_method("test_the_reader_refuses_each_thing_a_request_gets_wrong: #{name}") do
      request = XipFaxSpecs::Request.new(verb: verb, url: url, headers: headers, body: body, options: nil)

      assert_equal [id, refused], document.read_request(request, XipFax::API_VERSION)
    end
  end

  # Each answer, to a request of its method and address, with its status and its body, and what in
  # it the reader refuses, by what it gets wrong.
  WRONG_ANSWERS = {
    "a fax whose pages are words and whose status the document doesn't list" => [
      'GET', 'https://api.xipfax.com/faxes/fax_1', 200, XipFaxSpecs::Answers.fax('pages' => 'two', 'status' => 'archived'),
      [
        'answer.pages is string, not [integer null]',
        'answer.status is archived, none of [draft sending delivered failed received]'
      ]
    ],
    "a status the operation doesn't give" => ['GET', 'https://api.xipfax.com/plan', 418, '', ['getPlan gives no 418']],
    'a body where the answer carries none' => [
      'DELETE', 'https://api.xipfax.com/draft/documents/doc_1', 204, '{}', ["removeDocument's 204 carries no body"]
    ]
  }.freeze

  WRONG_ANSWERS.each do |name, (verb, url, status, answer, refused)|
    define_method("test_the_reader_refuses_each_thing_an_answer_gets_wrong: #{name}") do
      request = XipFaxSpecs::Request.new(verb: verb, url: url, headers: {}, body: '', options: nil)

      assert_equal refused, document.read_answer(request, status, answer)
    end
  end

  def test_the_reader_refuses_a_schema_keyword_it_doesnt_read
    assert_equal ['value: the contract reads no oneOf, which its schema gives'],
                 document.check(JSON.parse('{"oneOf":[{"type":"string"}]}'), 'text', 'value')
  end
end
