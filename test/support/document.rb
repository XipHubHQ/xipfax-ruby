# frozen_string_literal: true

require 'json'
require 'uri'

module XipFaxSpecs
  # An operation of the API's document: its id, its method and its path, the status of its success,
  # its parameters, the schema of its JSON body, or nil where it takes none, the pattern of its path
  # on the document's server, the names of the path's parameters in their order, and its answers by
  # their statuses.
  Operation = Struct.new(:id, :verb, :path, :success, :parameters, :body, :pattern, :names, :responses,
                         keyword_init: true)

  # A parameter of an operation: its name, where it goes, query, header or path, whether the
  # operation requires it, and its schema.
  Parameter = Struct.new(:name, :location, :required, :schema, keyword_init: true)

  # The API's document, openapi.json, as the repository holds it, read so that the specs can read what
  # the SDK sends and is answered against it: the operation a request is, and each thing in it the
  # document refuses, from its address, its key and its version to each parameter and its body; and
  # what in an answer or an event's body the document's schema refuses. It reads the schema keywords
  # the document uses, and refuses a schema with one it doesn't read, so that a document that comes to
  # say more than this reads fails the specs rather than passing unread. A value is JSON as JSON.parse
  # reads it: an object is a Hash, and an array an Array.
  class Document
    # The methods a path's operations may have, in the order they are read.
    METHODS = %w[get put post delete options head patch trace].freeze

    # A parameter's place in a path, {fax_id}.
    PATH_PARAMETER = /\{([^}]+)\}/.freeze

    # The keywords that describe a value without constraining it.
    ANNOTATIONS = %w[description title default examples].freeze

    # ECMAScript's anchors outside a class, the text's very start and end, as Ruby writes them.
    ANCHORS = { '^' => '\A', '$' => '\z' }.freeze

    # The document's info.version, the version of the API it is.
    attr_reader :version

    # The document's operations, by their paths in order and the method within each.
    attr_reader :operations

    # The schema of the body each event posts, by the event's name.
    attr_reader :webhooks

    # Reads the document at the path.
    def self.load(path)
      new(path)
    end

    def initialize(path)
      raise "#{path} doesn't read" unless File.file?(path)

      begin
        @raw = JSON.parse(File.read(path, encoding: 'UTF-8'))
      rescue JSON::ParserError => e
        raise "#{path}: #{e.message}"
      end
      raise "#{path} is no JSON object" unless @raw.is_a?(Hash)

      info = @raw['info']
      @version = info.is_a?(Hash) && info['version'].is_a?(String) ? info['version'] : ''

      servers = @raw['servers']
      first = servers.is_a?(Array) ? servers[0] : nil
      raise "#{path} names no server" unless first.is_a?(Hash)

      begin
        @server = URI.parse(first['url'].is_a?(String) ? first['url'] : '')
      rescue URI::InvalidURIError => e
        raise "#{path}'s server: #{e.message}"
      end

      @operations = read_operations.freeze
      @webhooks = read_webhooks.freeze
    end

    # The operation of the id.
    def operation(id)
      found = @operations.find { |operation| operation.id == id }
      raise "the document has no operation #{id}" if found.nil?

      found
    end

    # Reads a request against the document: the id of the operation it is, and each thing in it the
    # document refuses, none where it fits. The version is the one its Xip-Version must name.
    def read_request(request, version)
      found = find(request)
      return ['', [no_operation(request)]] if found.nil?

      operation, values = found
      refused = []
      keys = request.header('Authorization')
      unless keys.size == 1 && keys[0].match?(/\ABearer \S+\z/)
        refused << "Authorization is #{quoted(keys)}, not one bearer key"
      end
      versions = request.header('Xip-Version')
      refused << "Xip-Version is #{quoted(versions)}, not #{version}" unless versions == [version]

      query = query_of(URI.parse(request.url).query.to_s)
      takes_query = {}
      operation.parameters.each do |parameter|
        takes_query[parameter.name] = true if parameter.location == 'query'
        refused.concat(read_parameter(parameter, given_of(parameter, request, query, values)))
      end
      query.keys.sort.each do |name|
        refused << "query #{name} is no parameter of #{operation.id}" unless takes_query.key?(name)
      end

      refused.concat(read_body(operation, request))
      [operation.id, refused]
    end

    # Reads an answer to a request against the document: what in it the operation's answer for its
    # status refuses, none where it fits. An empty body is an answer that carries none.
    def read_answer(request, status, body)
      found = find(request)
      return [no_operation(request)] if found.nil?

      operation = found[0]
      answer = operation.responses[status.to_s]
      return ["#{operation.id} gives no #{status}"] if answer.nil?

      begin
        response = resolve(answer)
      rescue RuntimeError => e
        return [e.message]
      end
      content = response['content']
      return body.empty? ? [] : ["#{operation.id}'s #{status} carries no body"] unless content.is_a?(Hash)

      media = content['application/json']
      schema = media.is_a?(Hash) ? media['schema'] : nil
      begin
        value = JSON.parse(body)
      rescue JSON::ParserError => e
        return ["#{operation.id}'s #{status} is no JSON: #{e.message}"]
      end
      check(schema.is_a?(Hash) ? schema : {}, value, 'answer')
    end

    # What the operation's Xip-Version parameter refuses in the version, none where it takes it.
    def version_refused(operation, version)
      parameter = operation.parameters.find { |each| each.location == 'header' && each.name == 'Xip-Version' }
      return ["#{operation.id} takes no Xip-Version"] if parameter.nil?

      check_text(parameter.schema, version, 'header Xip-Version')
    end

    # What the schema refuses in the value, each at its place from at; none where it fits.
    def check(schema, value, at)
      names(schema).flat_map { |keyword| check_keyword(schema, keyword, value, at) }
    end

    private

    def read_operations
      operations = []
      paths = @raw['paths']
      (paths.is_a?(Hash) ? names(paths) : []).each do |route|
        item = paths[route]
        next unless item.is_a?(Hash)

        METHODS.each do |method|
          entry = item[method]
          operations << operation_at(route, method, item, entry) if entry.is_a?(Hash)
        end
      end
      operations
    end

    def read_webhooks
      webhooks = {}
      posted = @raw['webhooks']
      (posted.is_a?(Hash) ? names(posted) : []).each do |name|
        item = posted[name]
        post = item.is_a?(Hash) ? item['post'] : nil
        begin
          schema = post.is_a?(Hash) ? body_schema(post) : nil
        rescue RuntimeError => e
          raise "the webhook #{name} posts no JSON body the document gives: #{e.message}"
        end
        raise "the webhook #{name} posts no JSON body the document gives" if schema.nil?

        webhooks[name] = schema
      end
      webhooks
    end

    # What one keyword of the schema refuses in the value.
    def check_keyword(schema, keyword, value, at)
      rule = schema[keyword]
      case keyword
      when '$ref' then check_reference(rule, value, at)
      when 'type' then type?(rule, value) ? [] : ["#{at} is #{type_of(value)}, not #{show(rule)}"]
      when 'enum' then in_list?(rule, value) ? [] : ["#{at} is #{show(value)}, none of #{show(rule)}"]
      when 'const' then same?(rule, value) ? [] : ["#{at} is #{show(value)}, not #{show(rule)}"]
      when 'minLength', 'maxLength' then check_length(keyword, rule, value, at)
      when 'pattern' then check_pattern(rule, value, at)
      when 'minimum', 'maximum' then check_bound(keyword, rule, value, at)
      when 'minItems', 'maxItems' then check_count(keyword, rule, value, at)
      when 'items' then check_items(rule, value, at)
      when 'properties' then check_properties(rule, value, at)
      when 'required' then check_required(rule, value, at)
      when 'additionalProperties' then check_additional(schema['properties'], rule, value, at)
      when 'propertyNames' then check_names(rule, value, at)
      when 'anyOf' then check_any_of(rule, value, at)
      else
        ANNOTATIONS.include?(keyword) ? [] : ["#{at}: the contract reads no #{keyword}, which its schema gives"]
      end
    end

    def check_reference(rule, value, at)
      target = begin
        pointer(show(rule))
      rescue RuntimeError => e
        return ["#{at}: #{e.message}"]
      end
      check(target, value, at)
    end

    def check_length(keyword, rule, value, at)
      return [] unless value.is_a?(String) && number?(rule)

      length = value.length
      return [] unless (keyword == 'minLength' && length < rule) || (keyword == 'maxLength' && length > rule)

      ["#{at} has #{length} characters, past its #{keyword} of #{show(rule)}"]
    end

    def check_pattern(rule, value, at)
      return [] unless value.is_a?(String)

      pattern = show(rule)
      expression = begin
        Regexp.new(ecmascript(pattern), Regexp::FIXEDENCODING)
      rescue RegexpError => e
        return ["#{at}: its pattern #{pattern} doesn't compile: #{e.message}"]
      end
      # A text that is no UTF-8 fits no pattern, as it fits no schema of text.
      text = value.dup.force_encoding(Encoding::UTF_8)
      return [] if text.valid_encoding? && expression.match?(text)

      ["#{at} is #{quote(value)}, not of the pattern #{pattern}"]
    end

    def check_bound(keyword, rule, value, at)
      return [] unless number?(value) && number?(rule)
      return [] unless (keyword == 'minimum' && value < rule) || (keyword == 'maximum' && value > rule)

      ["#{at} is #{show(value)}, past its #{keyword} of #{show(rule)}"]
    end

    def check_count(keyword, rule, value, at)
      return [] unless value.is_a?(Array) && number?(rule)

      count = value.size
      return [] unless (keyword == 'minItems' && count < rule) || (keyword == 'maxItems' && count > rule)

      ["#{at} has #{count} items, past its #{keyword} of #{show(rule)}"]
    end

    def check_items(rule, value, at)
      return [] unless value.is_a?(Array) && rule.is_a?(Hash)

      value.each_with_index.flat_map { |item, index| check(rule, item, "#{at}[#{index}]") }
    end

    def check_properties(rule, value, at)
      return [] unless value.is_a?(Hash) && rule.is_a?(Hash)

      names(rule).flat_map do |name|
        property = rule[name]
        value.key?(name) && property.is_a?(Hash) ? check(property, value[name], "#{at}.#{name}") : []
      end
    end

    def check_required(rule, value, at)
      return [] unless value.is_a?(Hash) && rule.is_a?(Array)

      rule.map { |name| show(name) }.reject { |name| value.key?(name) }.map { |name| "#{at}.#{name} is missing" }
    end

    def check_additional(properties, rule, value, at)
      return [] unless value.is_a?(Hash)

      names(value).flat_map do |name|
        if properties.is_a?(Hash) && properties.key?(name)
          []
        elsif rule == false
          ["#{at}.#{name} is no member it takes"]
        elsif rule.is_a?(Hash)
          check(rule, value[name], "#{at}.#{name}")
        else
          []
        end
      end
    end

    def check_names(rule, value, at)
      return [] unless value.is_a?(Hash) && rule.is_a?(Hash)

      names(value).flat_map { |name| check(rule, name, "#{at} name #{name}") }
    end

    def check_any_of(rule, value, at)
      members = rule.is_a?(Array) ? rule : []
      fits = members.any? { |member| member.is_a?(Hash) && check(member, value, at).empty? }
      fits ? [] : ["#{at} fits none of its anyOf"]
    end

    # The values a request gives a parameter, in their order: none where it gives it none.
    def given_of(parameter, request, query, values)
      case parameter.location
      when 'query' then query.fetch(parameter.name, [])
      when 'header' then request.header(parameter.name)
      when 'path' then values.key?(parameter.name) ? [values[parameter.name]] : []
      else []
      end
    end

    # What the parameter refuses in the values a request gives it.
    def read_parameter(parameter, given)
      at = "#{parameter.location} #{parameter.name}"
      return parameter.required ? ["#{at} is missing"] : [] if given.empty?
      return ["#{at} is sent #{given.size} times"] if given.size > 1

      check_text(parameter.schema, given[0], at)
    end

    # What the operation refuses in a request's body: one it takes is JSON its schema takes, and one
    # it takes none of is empty.
    def read_body(operation, request)
      if operation.body.nil?
        return request.body.empty? ? [] : ['a body the operation takes none of']
      end

      refused = []
      refused << 'the body is not sent as JSON' unless request.header('Content-Type').fetch(0, '').start_with?('application/json')
      begin
        refused.concat(check(operation.body, JSON.parse(request.body), 'body'))
      rescue JSON::ParserError => e
        refused << "the body is no JSON: #{e.message}"
      end
      refused
    end

    # The operation the request is, by its method and its path on the document's server, with the
    # values of its path's parameters; nil where it is none.
    def find(request)
      uri = begin
        URI.parse(request.url)
      rescue URI::InvalidURIError
        return nil
      end
      return nil unless uri.scheme == @server.scheme && uri.host == @server.host && uri.port == @server.port

      @operations.each do |operation|
        next unless operation.verb == request.verb

        match = operation.pattern.match(uri.path)
        next if match.nil?

        values = {}
        operation.names.each_with_index { |name, index| values[name] = percent_decoded(match[index + 1]) }
        return [operation, values]
      end
      nil
    end

    def operation_at(route, method, item, entry)
      id = entry['operationId'].is_a?(String) ? entry['operationId'] : ''

      body = begin
        body_schema(entry)
      rescue RuntimeError => e
        raise "#{id}: #{e.message}"
      end

      responses = entry['responses'].is_a?(Hash) ? entry['responses'] : {}
      success = names(responses).find { |status| status.match?(/\A[0-9]+\z/) && (200...300).cover?(status.to_i) }

      # The path on the document's server, each {name} in it a segment of its own.
      parts = (@server.path.to_s.chomp('/') + route).split(/\{[^}]+\}/, -1)
      pattern = Regexp.new("\\A#{parts.map { |part| Regexp.escape(part) }.join('([^/]+)')}\\z")

      Operation.new(
        id: id,
        verb: method.upcase,
        path: route,
        success: success.to_i,
        parameters: parameters_of(id, item, entry),
        body: body,
        pattern: pattern,
        names: route.scan(PATH_PARAMETER).map(&:first),
        responses: responses
      )
    end

    # The path's parameters and the operation's, one for each place and name, the operation's in
    # place of the path's.
    def parameters_of(id, item, entry)
      declared = {}
      [item, entry].each do |owner|
        list = owner['parameters']
        (list.is_a?(Array) ? list : []).each do |value|
          found = begin
            resolve(value)
          rescue RuntimeError => e
            raise "#{id}: #{e.message}"
          end
          parameter = Parameter.new(
            name: found['name'].is_a?(String) ? found['name'] : '',
            location: found['in'].is_a?(String) ? found['in'] : '',
            required: found['required'] == true,
            schema: found['schema'].is_a?(Hash) ? found['schema'] : {}
          )
          declared["#{parameter.location}:#{parameter.name.downcase}"] = parameter
        end
      end
      declared.values
    end

    # The schema of an operation's JSON body, or nil where it takes none.
    def body_schema(entry)
      return nil unless entry.key?('requestBody')

      body = resolve(entry['requestBody'])
      content = body['content']
      media = content.is_a?(Hash) ? content['application/json'] : nil
      raise 'its body is not JSON' unless media.is_a?(Hash)

      media['schema'].is_a?(Hash) ? media['schema'] : nil
    end

    # The object the $ref a value holds names in the document, through each $ref it holds; the value
    # where it holds none.
    def resolve(value)
      object = value.is_a?(Hash) ? value : {}
      object = pointer(object['$ref']) while object['$ref'].is_a?(String)
      object
    end

    # The object a local reference, #/components/schemas/Fax, names in the document.
    def pointer(ref)
      raise "#{ref} is no reference into the document" unless ref.start_with?('#/')

      value = @raw
      ref[2..-1].split('/', -1).each do |part|
        raise "#{ref} names nothing in the document" unless value.is_a?(Hash)

        value = value[part.gsub('~1', '/').gsub('~0', '~')]
      end
      raise "#{ref} names nothing in the document" unless value.is_a?(Hash)

      value
    end

    # Checks a parameter's text, read as its schema's type, against the schema.
    def check_text(schema, text, at)
      target = begin
        resolve(schema)
      rescue RuntimeError => e
        return ["#{at}: #{e.message}"]
      end
      return check(schema, text, at) unless target['type'] == 'integer'
      return ["#{at} is #{quote(text)}, no integer"] unless text.match?(/\A[+-]?[0-9]+\z/)

      check(schema, text.to_i, at)
    end

    def no_operation(request)
      "#{request.verb} #{request.url} is no operation of the document"
    end

    # A query's parameters, each name with the values it is given, in order, read as a form is: a + is
    # a space, and each name and value is percent-decoded.
    def query_of(query)
      parameters = {}
      query.split('&').each do |pair|
        next if pair.empty?

        name, value = pair.split('=', 2)
        (parameters[percent_decoded(name.tr('+', ' '))] ||= []) << percent_decoded(value.to_s.tr('+', ' '))
      end
      parameters
    end

    # The text with each of its percent-encoded bytes decoded, read as UTF-8.
    def percent_decoded(text)
      text.b.gsub(/%[0-9A-Fa-f]{2}/) { |escape| escape[1, 2].hex.chr }.force_encoding(Encoding::UTF_8)
    end

    # A pattern of the document as Ruby reads it: ECMAScript's ^ and $, outside a class, are the
    # text's very start and end, which Ruby writes \A and \z, its own ^ and $ being a line's.
    def ecmascript(pattern)
      source = +''
      in_class = false
      escaped = false
      pattern.each_char do |char|
        if escaped
          source << char
          escaped = false
        elsif char == '\\'
          source << char
          escaped = true
        elsif in_class
          in_class = false if char == ']'
          source << char
        elsif char == '['
          in_class = true
          source << char
        else
          source << ANCHORS.fetch(char, char)
        end
      end
      source
    end

    # Whether the value is of the type, or one of the types, a schema's type names.
    def type?(rule, value)
      return of_type?(rule, value) if rule.is_a?(String)

      (rule.is_a?(Array) ? rule : []).any? { |name| name.is_a?(String) && of_type?(name, value) }
    end

    def of_type?(name, value)
      case name
      when 'null' then value.nil?
      when 'boolean' then [true, false].include?(value)
      when 'string' then value.is_a?(String)
      when 'number' then number?(value)
      when 'integer' then value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.floor)
      when 'array' then value.is_a?(Array)
      when 'object' then value.is_a?(Hash)
      else false
      end
    end

    def number?(value)
      value.is_a?(Integer) || value.is_a?(Float)
    end

    def type_of(value)
      %w[null boolean integer number string array object].find { |name| of_type?(name, value) } || value.class.name
    end

    def in_list?(rule, value)
      (rule.is_a?(Array) ? rule : []).any? { |allowed| same?(allowed, value) }
    end

    # Whether two JSON values are the same, a number the same whether it is read as whole or not.
    def same?(one, other)
      return one == other if number?(one) && number?(other)
      if one.is_a?(Array) && other.is_a?(Array)
        return one.size == other.size && one.each_with_index.all? { |item, index| same?(item, other[index]) }
      end
      if one.is_a?(Hash) && other.is_a?(Hash)
        return names(one) == names(other) && names(one).all? { |name| same?(one[name], other[name]) }
      end

      !number?(one) && !number?(other) && one == other
    end

    # An object's member names, sorted as bytes.
    def names(object)
      object.keys.map(&:to_s).sort
    end

    # A value as a refusal gives it: text as it is, a list in brackets, an object as a map of its
    # members.
    def show(value)
      case value
      when nil then 'null'
      when true, false then value.to_s
      when Float then value.finite? && value == value.floor && value.abs < 1e15 ? value.to_i.to_s : value.to_s
      when Integer, String then value.to_s
      when Array then "[#{value.map { |item| show(item) }.join(' ')}]"
      when Hash then "map[#{names(value).map { |name| "#{name}:#{show(value[name])}" }.join(' ')}]"
      else value.class.name
      end
    end

    # Each text quoted, as a refusal gives a header's values: ["2026-11-03" "2026-11-03"].
    def quoted(texts)
      "[#{texts.map { |text| quote(text) }.join(' ')}]"
    end

    # A text quoted, each character JSON escapes escaped, and each byte that is no UTF-8 replaced.
    def quote(text)
      JSON.generate(text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("\u{FFFD}"))
    end
  end
end
