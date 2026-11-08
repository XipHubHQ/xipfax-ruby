# frozen_string_literal: true

require 'faraday'
require 'xipfax-sdk'
require_relative 'request'

module XipFaxSpecs
  # Answers the SDK's requests in place of the API, in the specs: Faraday's adapter, under the
  # client's own connection, which keeps each request it is given, with its body and its options, and
  # answers it as its answer says. Nothing it does reaches a network.
  class StandIn
    # Faraday's adapter in place of the one that reaches a network: it hands each request to its
    # stand-in, and answers what the stand-in answers.
    class Adapter < Faraday::Adapter
      def initialize(app = nil, stand_in = nil, options = {}, &block)
        super(app, options, &block)
        @stand_in = stand_in
      end

      def call(env)
        super
        headers = {}
        env.request_headers.each { |name, value| (headers[name] ||= []) << value.to_s }
        status, body, answered = @stand_in.answer_to(
          Request.new(verb: env[:method].to_s.upcase, url: env.url.to_s, headers: headers,
                      body: env.request_body.to_s, options: env.request)
        )
        save_response(env, status, body, answered)
        @app.call(env)
      end
    end

    # Each request the stand-in was given, in its order.
    attr_reader :requests

    # A stand-in whose answer to each request is the block's: given the request, it answers the
    # status, the body and the headers, as StandIn.answer gives them, or raises what Faraday raises
    # where a request never reaches the API.
    def initialize(&answer)
      @answer = answer
      @requests = []
    end

    # A stand-in that answers every request with one status and one JSON body; an empty one answers
    # none.
    def self.same(status, body)
      new { StandIn.answer(status, body) }
    end

    # An answer of a status and a body, its Content-Type application/json where it carries one and the
    # headers name none, and its other headers, such as a redirect's Location.
    def self.answer(status, body = '', headers = {})
      headers = { 'Content-Type' => 'application/json' }.merge(headers) unless body.empty?
      [status, body, headers]
    end

    # Keeps the request, and answers it as the stand-in's answer says.
    def answer_to(request)
      @requests << request
      @answer.call(request)
    end

    # A client of the key whose every request goes to the stand-in, its settings given to the block
    # before its first request, as XipFax::Client gives them.
    def client(api_key, base_url: nil)
      stand_in = self
      XipFax::Client.new(api_key, base_url: base_url) do |config|
        config.configure_faraday_connection { |connection| connection.adapter(Adapter, stand_in) }
        yield config if block_given?
      end
    end
  end
end
