# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../examples/quickstart'

# The quickstart, walked against a stand-in of the API that answers as the document says: its free
# steps first, its charged step said before it and taken only on send, and each request it sends
# read against the document, as each answer the stand-in gives is.
class QuickstartTest < Minitest::Test
  API_KEY = 'xipfax_key_live_example'
  FAX_NUMBER = '+1 202 555 0143'
  PDF_LINK = 'https://example.com/letter.pdf'

  # The API as the quickstart meets it: its draft holds the draft's documents, and gains those added
  # on xipfax.com once the quickstart adds its own; the fax it sends is delivered on its second read.
  class Api
    def initialize(draft, added_on_xipfax)
      @documents = draft.dup
      @added_on_xipfax = added_on_xipfax
      @reads = 0
    end

    # The API's answer to a route, as the API would give it to the quickstart: its status and its
    # body.
    def answer(route, body)
      case route
      when 'GET /quote' then [200, XipFaxSpecs::Answers::QUOTE]
      when 'GET /offices' then [200, %({"data":[#{XipFaxSpecs::Answers::OFFICE}],"has_more":false,"next_cursor":null})]
      when 'GET /draft' then [200, draft]
      when 'POST /draft/documents' then add
      when 'DELETE /draft/documents/doc_1' then remove
      when 'POST /draft/send' then send_draft(body)
      when 'GET /faxes/fax_1' then read
      when 'GET /faxes/fax_1/confirmation' then [200, '{"url":"https://example.com/confirmation.pdf"}']
      else [404, '']
      end
    end

    private

    def draft
      listed = @documents.map { |id| XipFaxSpecs::Answers.document(id, 'letter.pdf') }
      %({"id":"fax_1","documents":[#{listed.join(',')}]})
    end

    def add
      @documents += ['doc_1'] + @added_on_xipfax
      [201, %({"document":#{XipFaxSpecs::Answers.document('doc_1', 'letter.pdf')},"upload":null})]
    end

    def remove
      @documents -= ['doc_1']
      [204, '']
    end

    # As the API does, it sends a draft only where the send names its documents, in order.
    def send_draft(body)
      sent = begin
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end
      unless sent.is_a?(Hash) && sent['document_ids'] == @documents
        return [409, XipFaxSpecs::Answers.refusal(
          'draft_changed', 'Your fax changed since this page showed it. Look it over, then send it again.'
        )]
      end

      fax = XipFaxSpecs::Answers.fax('status' => 'sending', 'step' => 'queued', 'finished_at' => nil)
      [200, %({"fax":#{fax},"paid_by":"plan","confirm_url":null})]
    end

    def read
      @reads += 1
      return [200, XipFaxSpecs::Answers.fax('status' => 'sending', 'step' => 'sending', 'finished_at' => nil)] if @reads < 2

      [200, XipFaxSpecs::Answers.fax]
    end
  end

  # What a walk of the quickstart did: each request it sent, by its route, and each line it said and
  # question it asked, in their order; the requests themselves; the seconds of each pause; and the
  # API's refusal that stopped it, or nil.
  Walk = Struct.new(:events, :requests, :pauses, :refused, keyword_init: true)

  # Walks the quickstart against the API, its draft holding the draft's documents and gaining those
  # added on xipfax.com once the quickstart adds its own, the typed text being what you type when it
  # asks; and reads each request it sent and each answer it was given against the document.
  def walk(draft:, added_on_xipfax:, typed:, to:, pdf_url:)
    document = XipFaxSpecs::Document.load(File.expand_path('../openapi.json', __dir__))
    api = Api.new(draft, added_on_xipfax)
    events = []
    pauses = []
    faults = []
    stand_in = XipFaxSpecs::StandIn.new do |request|
      route = "#{request.verb} #{URI.parse(request.url).path}"
      events << route
      status, answer = api.answer(route, request.body)
      refused = document.read_answer(request, status, answer)
      faults << "the stand-in's answer to #{route} is refused: #{refused.join('; ')}" unless refused.empty?
      XipFaxSpecs::StandIn.answer(status, answer)
    end

    quickstart = Quickstart.new(
      stand_in.client(API_KEY),
      to: to,
      pdf_url: pdf_url,
      say: ->(line) { events << "say: #{line}" },
      ask: lambda do |question|
        events << "ask: #{question}"
        typed
      end,
      pause: ->(seconds) { pauses << seconds }
    )
    refused = nil
    begin
      quickstart.run
    rescue XipFax::ApiError => e
      refused = e
    end

    stand_in.requests.each do |request|
      _, wrong = document.read_request(request, XipFax::API_VERSION)
      faults << "#{request.verb} #{request.url}: #{wrong.join('; ')}" unless wrong.empty?
    end
    assert_equal [], faults
    Walk.new(events: events, requests: stand_in.requests, pauses: pauses, refused: refused)
  end

  # The walk's requests alone, by their routes.
  def requests_of(walked)
    walked.events.reject { |event| event.start_with?('say: ', 'ask: ') }
  end

  # The body of the walk's POST /draft/send.
  def sent_of(walked)
    request = walked.requests.find { |each| each.verb == 'POST' && URI.parse(each.url).path == '/draft/send' }
    flunk 'the walk sent no POST /draft/send' if request.nil?
    JSON.parse(request.body)
  end

  # The index of the first event that is the event, or that starts with it where it ends in a space.
  def index_of(events, event)
    events.index { |seen| seen == event || (event.end_with?(' ') && seen.start_with?(event)) } || -1
  end

  def test_the_quickstart_takes_the_free_steps_alone_where_it_has_no_number_or_pdf
    walked = walk(draft: [], added_on_xipfax: [], typed: 'send', to: '', pdf_url: '')

    assert_nil walked.refused
    assert_equal ['GET /quote', 'GET /offices'], requests_of(walked)
    assert_equal(-1, index_of(walked.events, 'ask: '), 'it asked, with no number or PDF')
  end

  def test_the_quickstart_says_the_fax_is_real_and_charged_sends_it_only_once_send_is_typed_and_follows_it
    walked = walk(draft: [], added_on_xipfax: [], typed: 'send', to: FAX_NUMBER, pdf_url: PDF_LINK)

    assert_nil walked.refused
    assert_equal [
      'GET /quote',
      'GET /offices',
      'GET /draft',
      'POST /draft/documents',
      'POST /draft/send',
      'GET /faxes/fax_1',
      'GET /faxes/fax_1',
      'GET /faxes/fax_1/confirmation'
    ], requests_of(walked)
    added = index_of(walked.events, 'POST /draft/documents')
    warned = index_of(walked.events, "say: #{Quickstart::REAL_AND_CHARGED}")
    asked = index_of(walked.events, 'ask: ')
    sent = index_of(walked.events, 'POST /draft/send')
    assert added >= 0 && warned > added && asked > warned && sent > asked,
           "it added at #{added}, warned at #{warned}, asked at #{asked} and sent at #{sent}"
    assert_includes walked.events, 'say: Added letter.pdf, 2 pages.', "it didn't say what it added"
    assert_equal [Quickstart::READ_EVERY, Quickstart::READ_EVERY], walked.pauses, 'it read the fax without waiting between reads'

    assert_equal({ 'document_ids' => ['doc_1'], 'fax_number' => FAX_NUMBER }, sent_of(walked))
    posts = walked.requests.select { |request| request.verb == 'POST' }
    keys = posts.map { |request| request.header('Idempotency-Key') }
    assert keys.all? { |values| values.size == 1 }, "a POST named other than one key: #{keys.inspect}"
    assert_equal posts.size, keys.uniq.size, "#{posts.size} POSTs named other than as many keys"
  end

  def test_the_quickstart_sends_nothing_on_any_other_answer_and_takes_its_document_back_out_of_the_draft
    walked = walk(draft: [], added_on_xipfax: [], typed: 'no', to: FAX_NUMBER, pdf_url: PDF_LINK)

    assert_nil walked.refused
    assert_equal ['GET /quote', 'GET /offices', 'GET /draft', 'POST /draft/documents', 'DELETE /draft/documents/doc_1'],
                 requests_of(walked)
  end

  def test_the_quickstart_names_only_the_document_it_added_so_a_draft_that_gained_another_on_xipfax_is_refused
    walked = walk(draft: [], added_on_xipfax: ['doc_2'], typed: 'send', to: FAX_NUMBER, pdf_url: PDF_LINK)

    assert_instance_of XipFax::ApiError, walked.refused, "it answered, not the API's refusal"
    assert_equal 'draft_changed', walked.refused.refusal.error.code
    assert_equal ['GET /quote', 'GET /offices', 'GET /draft', 'POST /draft/documents', 'POST /draft/send'],
                 requests_of(walked)
    assert_equal({ 'document_ids' => ['doc_1'], 'fax_number' => FAX_NUMBER }, sent_of(walked))
  end

  def test_the_quickstart_adds_nothing_to_a_draft_that_already_holds_documents
    walked = walk(draft: ['doc_0'], added_on_xipfax: [], typed: 'send', to: FAX_NUMBER, pdf_url: PDF_LINK)

    assert_nil walked.refused
    assert_equal ['GET /quote', 'GET /offices', 'GET /draft'], requests_of(walked)
  end

  # Each link, with the name the quickstart gives the document it adds by it.
  LINKS = {
    'a name' => ['https://example.com/letter.pdf', 'letter.pdf'],
    'a name percent-encoded' => ['https://example.com/forms/Form%202848.pdf', 'Form 2848.pdf'],
    'a folder' => ['https://example.com/forms/', 'forms'],
    'no path' => ['https://example.com', 'document.pdf'],
    'an encoding of no text' => ['https://example.com/%FF.pdf', '%FF.pdf'],
    'a name past 255 characters' => ["https://example.com/#{'é' * 300}", 'é' * 255]
  }.freeze

  LINKS.each do |name, (link, named)|
    define_method("test_the_document_is_named_as_its_link_ends: #{name}") do
      assert_equal named, Quickstart.name_of(link)
    end
  end
end
