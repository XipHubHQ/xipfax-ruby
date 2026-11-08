# frozen_string_literal: true

require_relative 'test_helper'

# XipFax::Client: the key and the version on every request, the settings the README names, and the
# API's refusals as they come.
class ClientTest < Minitest::Test
  # What a client made without a key says.
  NO_KEY = 'no API key: make one in the developer console, https://developer.xipfax.com/console/'

  def no_plan
    XipFaxSpecs::StandIn.same(200, XipFaxSpecs::Answers::NO_PLAN)
  end

  def test_it_refuses_to_start_without_a_key
    [nil, '', '   '].each do |api_key|
      refused = assert_raises(ArgumentError, "a client of #{api_key.inspect} started") { XipFax::Client.new(api_key) }
      assert_equal NO_KEY, refused.message
    end
  end

  def test_it_refuses_an_address_that_is_no_http_or_https_one
    ['ftp://files.example.com', 'api.example.com', 'not an address'].each do |address|
      refused = assert_raises(ArgumentError, "a client at #{address} started") do
        XipFax::Client.new('key-a', base_url: address)
      end
      assert_equal "#{address} isn't an http or https address", refused.message
    end
  end

  def test_it_sends_to_the_apis_own_address_unless_given_another
    own = no_plan
    own.client('key-a').plan.get_plan
    assert_equal 'https://api.xipfax.com/plan', own.requests[0].url

    {
      'https://api.example.com/' => 'https://api.example.com/plan',
      'http://localhost:8080/v1' => 'http://localhost:8080/v1/plan'
    }.each do |address, sent_to|
      other = no_plan
      other.client('key-a', base_url: address).plan.get_plan
      assert_equal sent_to, other.requests[0].url, "not the address named, #{address}"
    end
  end

  def test_each_client_keeps_its_key_to_itself
    a = no_plan
    b = no_plan
    first = a.client('key-a')
    second = b.client('key-b')

    first.plan.get_plan
    second.plan.get_plan

    [[a, 'Bearer key-a'], [b, 'Bearer key-b']].each do |stand_in, authorization|
      assert_equal 1, stand_in.requests.size, 'requests went where one should have'
      assert_equal [authorization], stand_in.requests[0].header('Authorization')
    end
  end

  def test_each_request_names_the_version_the_sdk_is_generated_from
    stand_in = no_plan
    stand_in.client('key-a').plan.get_plan

    assert_equal [XipFax::API_VERSION], stand_in.requests[0].header('Xip-Version')
  end

  def test_a_request_waits_60_seconds_unless_the_settings_name_another_time
    unset = no_plan
    unset.client('key-a').plan.get_plan
    assert_equal 60, unset.requests[0].options.timeout

    set = no_plan
    set.client('key-a') { |config| config.timeout = 30 }.plan.get_plan
    assert_equal 30, set.requests[0].options.timeout, 'the timeout the settings name is not the one sent'
  end

  def test_a_redirect_is_not_followed_so_the_key_goes_nowhere_else
    stand_in = XipFaxSpecs::StandIn.new do |request|
      if URI.parse(request.url).host == 'api.xipfax.com'
        XipFaxSpecs::StandIn.answer(302, '', 'Location' => 'https://elsewhere.example.com/plan')
      else
        XipFaxSpecs::StandIn.answer(200, XipFaxSpecs::Answers::NO_PLAN)
      end
    end

    refused = assert_raises(XipFax::ApiError) { stand_in.client('key-a').plan.get_plan }

    assert_equal 302, refused.code
    assert_nil refused.refusal
    assert_equal ['https://api.xipfax.com/plan'], stand_in.requests.map(&:url), 'the request went to another host'
  end

  def test_a_refusal_carries_the_apis_own_error
    stand_in = XipFaxSpecs::StandIn.same(
      401, XipFaxSpecs::Answers.refusal('authentication_failed', 'That key isn’t one of XipFax’s.')
    )

    refused = assert_raises(XipFax::ApiError) { stand_in.client('key-a').plan.get_plan }

    assert_equal 401, refused.code
    refusal = refused.refusal
    assert_instance_of XipFax::ApiErrorBody, refusal
    assert_equal 'authentication_failed', refusal.error.code
    assert_equal 'req_1', refusal.error.request_id
  end

  def test_a_refusal_the_reference_gives_no_status_of_still_carries_the_apis_error
    # GET /plan's reference gives no 429, and the API's error still comes in the refusal's body.
    stand_in = XipFaxSpecs::StandIn.same(
      429, XipFaxSpecs::Answers.refusal('rate_limited', 'Too many requests: try again in a minute.')
    )

    refused = assert_raises(XipFax::ApiError) { stand_in.client('key-a').plan.get_plan }

    assert_equal 429, refused.code
    assert_equal 'rate_limited', refused.refusal.error.code
  end

  def test_a_refusal_whose_body_is_no_error_of_the_apis_keeps_what_came
    page = '<html><body>Bad gateway</body></html>'
    stand_in = XipFaxSpecs::StandIn.new { XipFaxSpecs::StandIn.answer(502, page, 'Content-Type' => 'text/html') }

    refused = assert_raises(XipFax::ApiError) { stand_in.client('key-a').plan.get_plan }

    assert_equal 502, refused.code
    assert_nil refused.refusal
    assert_equal page, refused.response_body
  end

  def test_a_request_that_never_reached_xipfax_or_was_never_answered_raises_with_no_refusal
    [Faraday::ConnectionFailed.new('Connection refused'), Faraday::TimeoutError.new].each do |failure|
      stand_in = XipFaxSpecs::StandIn.new { raise failure }

      failed = assert_raises(XipFax::ApiError, "#{failure.class} answered") { stand_in.client('key-a').plan.get_plan }

      assert_nil failed.refusal
      assert_nil failed.code
      assert_nil failed.response_body
    end
  end

  def test_an_answer_that_gains_a_member_is_read_with_the_member_left_out
    # Within a version, an answer may gain a member, and an open set a new value. Here the fax gains
    # `tracking`, and its status is one the SDK has never seen: the SDK reads the status as the text
    # it is, and leaves the member it doesn't know out of the model it answers.
    gained = XipFaxSpecs::Answers.fax('status' => 'archived', 'tracking' => { 'carrier' => 'stand-in' })

    fax = XipFaxSpecs::StandIn.same(200, gained).client('key-a').faxes.get_fax('fax_1')

    assert_equal 'fax_1', fax.id
    assert_equal 'archived', fax.status
    refute fax.to_hash.key?(:tracking), 'the model keeps a member the SDK does not know'
  end

  def test_each_method_answers_its_status_and_its_headers_too_by_its_with_http_info_form
    answer, status, headers = no_plan.client('key-a').plan.get_plan_with_http_info

    assert_instance_of XipFax::PlanAnswer, answer
    assert_nil answer.plan
    assert_equal 200, status
    assert_equal 'application/json', headers['Content-Type']
  end
end
