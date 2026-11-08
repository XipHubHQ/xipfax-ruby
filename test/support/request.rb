# frozen_string_literal: true

module XipFaxSpecs
  # A request as the specs read it: its method, its address, its headers, each name with its values
  # in their order, its body as it was sent, and the options it was sent with, Faraday's for a request
  # the SDK sent.
  Request = Struct.new(:verb, :url, :headers, :body, :options, keyword_init: true) do
    # The values of a header, whatever the case of its name.
    def header(name)
      headers.select { |key, _| key.casecmp?(name) }.values.flatten
    end
  end
end
