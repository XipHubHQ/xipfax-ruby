# frozen_string_literal: true

require 'json'
require 'uri'

module XipFax
  # What a request raises where it fails: the generator's, with the API's refusal read from its body.
  class ApiError < StandardError
    # The API's refusal this error carries, its body read as an ApiErrorBody, whose error's code is
    # the one to branch on; nil where it carries none, as where the request never reached XipFax.
    #
    # @return [XipFax::ApiErrorBody, nil]
    def refusal
      return nil if response_body.nil? || response_body.empty?

      body = JSON.parse(response_body)
      body.is_a?(Hash) && body['error'].is_a?(Hash) ? ApiErrorBody.build_from_hash(body) : nil
    rescue JSON::ParserError, ArgumentError
      nil
    end
  end

  # A client of XipFax's API, made from your API key: each request it sends carries the key as a
  # bearer token and names XipFax::API_VERSION in its Xip-Version header. Its APIs are the API
  # reference's sections, as client.faxes.get_fax('fax_1').
  class Client
    # What a fax costs.
    attr_reader :quote
    # Your draft, the fax you prepare, and its send.
    attr_reader :draft
    # The faxes you sent and received.
    attr_reader :faxes
    # Your plan.
    attr_reader :plan
    # The government offices XipFax gives the fax numbers of.
    attr_reader :offices
    # The endpoints of your server XipFax posts each event to.
    attr_reader :webhook_endpoints

    # Makes a client of XipFax's API from your API key, xipfax_key_live_ and 32 more characters,
    # which you make in the developer console and keep on your server.
    #
    # @param api_key [String] your API key
    # @param base_url [String, nil] where the API answers, or nil for https://api.xipfax.com
    # @yieldparam config [XipFax::Configuration] the client's own settings, before its first
    #   request: its Faraday connection, by config.configure_faraday_connection, among them
    # @raise [ArgumentError] if the key is nil, empty or only spaces, or the address isn't an http
    #   or https one
    def initialize(api_key, base_url: nil)
      if api_key.nil? || api_key.strip.empty?
        raise ArgumentError, 'no API key: make one in the developer console, https://developer.xipfax.com/console/'
      end

      config = Configuration.new
      at(config, base_url) unless base_url.nil?
      yield config if block_given?

      api_client = ApiClient.new(config)
      api_client.default_headers['Authorization'] = "Bearer #{api_key}"
      api_client.default_headers['Xip-Version'] = API_VERSION

      @quote = QuoteApi.new(api_client)
      @draft = DraftApi.new(api_client)
      @faxes = FaxesApi.new(api_client)
      @plan = PlanApi.new(api_client)
      @offices = OfficesApi.new(api_client)
      @webhook_endpoints = WebhookEndpointsApi.new(api_client)
    end

    private

    # Points config at base_url, as https://api.example.com/ or http://localhost:8080/v1.
    def at(config, base_url)
      address = begin
        URI.parse(base_url)
      rescue URI::InvalidURIError
        nil
      end
      unless address.is_a?(URI::HTTP) && address.host && !address.host.empty?
        raise ArgumentError, "#{base_url} isn't an http or https address"
      end

      config.scheme = address.scheme
      config.host = address.port == address.default_port ? address.host : "#{address.host}:#{address.port}"
      config.base_path = address.path
    end
  end
end
