# frozen_string_literal: true

require 'json'

module XipFaxSpecs
  # The API's answers the specs are given, in JSON, each as the document gives it.
  module Answers
    # GET /quote's answer for a fax of one page.
    QUOTE = '{"pages":1,"price":{"amount_minor":100,"currency":"USD"},"price_shown":"$1.00","terms":"The stand-in’s terms.","price_list":"stand-in"}'

    # An office of GET /offices, which takes Form 2848 from Ohio.
    OFFICE = '{"id":"stand-in-office","name":"A stand-in office","fax_number":"+12025550143","fax_number_from_abroad":null,"applies_to":["Ohio"],"takes":["Form 2848"],"signed_in_ink":false,"confidential_cover":false,"sources":[{"title":"A stand-in page","url":"https://example.com/office"}],"checked_on":"2026-11-01"}'

    # GET /plan's answer for a client with no plan.
    NO_PLAN = '{"plan":null}'

    # fax_1, a fax you sent that was delivered.
    FAX = {
      'id' => 'fax_1',
      'direction' => 'sent',
      'status' => 'delivered',
      'step' => nil,
      'office_id' => nil,
      'to_number' => '+12025550143',
      'from_number' => '+12025550100',
      'pages' => 2,
      'price' => nil,
      'sent_at' => '2026-11-07T02:00:00Z',
      'finished_at' => '2026-11-07T02:03:00Z',
      'retry_at' => nil,
      'failure' => nil,
      'time_zone' => 'America/New_York',
      'sender_name' => nil,
      'cover_confidential' => false
    }.freeze

    # A document of the draft, ready, by its id and its name.
    def self.document(id, name)
      JSON.generate(
        'id' => id,
        'name' => name,
        'size_bytes' => 20_480,
        'page_count' => 2,
        'status' => 'ready',
        'url' => "https://example.com/#{id}.pdf"
      )
    end

    # fax_1, with each member the changes name in place of its own, and each other they name after
    # its own.
    def self.fax(changes = {})
      JSON.generate(FAX.merge(changes))
    end

    # The API's refusal, by its code and its sentence.
    def self.refusal(code, message)
      JSON.generate(
        'error' => { 'code' => code, 'message' => message, 'details' => [], 'request_id' => 'req_1', 'doc_url' => nil }
      )
    end
  end
end
