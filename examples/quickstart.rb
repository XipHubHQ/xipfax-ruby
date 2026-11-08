# frozen_string_literal: true

# Runs XipFax's quickstart in your terminal, from a clone of this repository, after bundle install:
#
#     XIPFAX_API_KEY=xipfax_key_live_… bundle exec ruby examples/quickstart.rb
#
# That takes the free steps alone. To send a fax too, real and charged, name a fax number of yours
# and a public link to a PDF:
#
#     XIPFAX_TO='+1 202 555 0143' XIPFAX_PDF_URL=https://example.com/letter.pdf XIPFAX_API_KEY=… bundle exec ruby examples/quickstart.rb

require 'securerandom'
require 'xipfax-sdk'

# XipFax's quickstart through the SDK, the steps of https://developer.xipfax.com/docs/guides/quickstart/
# in their order. The free steps come first: a quote, and the offices that take a form. Then, only
# where you name a fax number of yours and a PDF, a real fax, charged, which it says before it sends,
# and sends only once you type send. Run as a script, this file runs it in your terminal.
class Quickstart
  # How long the quickstart waits between reads of the fax, in seconds.
  READ_EVERY = 10

  # How many reads of the fax the quickstart makes at most.
  READS = 30

  # What the step that sends says first, as the docs' quickstart says it.
  REAL_AND_CHARGED = 'This step sends a real fax, and it’s charged. It goes to the number you name, so name one ' \
                     'of your own. Its pages count on your plan, or where you have no plan its price is held on ' \
                     'the card you saved, and taken once it’s delivered. A fax that fails costs nothing.'

  # @param client [XipFax::Client] the client that sends each request
  # @param to [String] a fax number of yours, where the fax goes; without it, only the free steps run
  # @param pdf_url [String] a public https link to a PDF, the fax's pages; without it, only the free
  #   steps run
  # @param say [#call] tells you a line
  # @param ask [#call] asks you a question, answering what you typed
  # @param pause [#call] waits so many seconds between reads of the fax
  def initialize(client, to:, pdf_url:, say:, ask:, pause:)
    @client = client
    @to = to
    @pdf_url = pdf_url
    @say = say
    @ask = ask
    @pause = pause
  end

  # Takes the quickstart's steps. The API's refusal stops it, raised as the XipFax::ApiError whose
  # refusal is the API's own, which the script prints.
  #
  # @raise [XipFax::ApiError] where the API refuses a step
  def run
    take_the_free_steps
    return if @to.empty? || @pdf_url.empty?

    # 3. Your draft, the fax you prepare. This sends only its own document, so it starts empty.
    unless @client.draft.get_draft.documents.empty?
      say('Your draft already holds documents. Send or remove them on xipfax.com first, so that this sends only its own.')
      return
    end

    # 4. Add the PDF by its link. Each POST names a key of its own, so a retry can't add it twice.
    added = @client.draft.add_document(
      SecureRandom.uuid, XipFax::NewDocument.new(name: self.class.name_of(@pdf_url), url: @pdf_url)
    )
    document = added.document
    say("Added #{document.name}#{pages_of(document)}.")

    fax = send_it(document)
    follow(fax) unless fax.nil?
  end

  # The PDF's name, as its link ends: letter.pdf, or document.pdf where its path names none.
  def self.name_of(link)
    name = 'document.pdf'
    # The link's path, as RFC 3986 reads it, whatever characters it holds.
    path = link[%r{\A(?:[^:/?#]+:)?(?://[^/?#]*)?([^?#]*)}, 1].to_s
    segments = path.split('/').reject(&:empty?)
    unless segments.empty?
      name = segments.last
      # A link whose name isn't percent-encoded text keeps it as it is.
      unless name.match?(/%(?![0-9A-Fa-f]{2})/)
        text = name.b.gsub(/%[0-9A-Fa-f]{2}/) { |escape| escape[1, 2].hex.chr }.force_encoding(Encoding::UTF_8)
        name = text if text.valid_encoding?
      end
    end
    name.length > 255 ? name[0, 255] : name
  end

  private

  # 1. What a fax costs. This costs nothing, and it shows your key works.
  # 2. Where a form goes: the offices that take Form 2848 from Ohio, and their numbers. Also free.
  def take_the_free_steps
    quote = @client.quote.get_quote(1)
    say("A one-page fax costs #{quote.price_shown} without a plan: #{quote.terms}")

    @client.offices.list_offices(search: 'Form 2848', place: 'OH', limit: 3).data.each do |office|
      say("#{office.name} takes Form 2848 at #{office.fax_number}.")
    end
  end

  # 5. Send it, a real fax, charged: said first, and sent only once you type send. Answers the fax it
  # sent, or nil where it sent none.
  def send_it(document)
    say(REAL_AND_CHARGED)
    answer = @ask.call("Type send to fax it to #{@to}, or anything else to stop: ")
    unless answer.to_s.strip.downcase == 'send'
      @client.draft.remove_document(document.id)
      say('Nothing was sent, and the document is out of your draft again.')
      return nil
    end

    # The send names the documents to send: the one this added, alone. A draft whose documents
    # aren't these is refused, so that nothing you didn't name is sent.
    sent = @client.draft.send_draft(
      SecureRandom.uuid, XipFax::SendDraft.new(fax_number: @to, document_ids: [document.id])
    )
    confirm_url = sent.confirm_url
    if confirm_url && !confirm_url.empty?
      say("Nothing was sent or held: the fax waits for you on xipfax.com, #{confirm_url}")
      return nil
    end
    say("Sent, paid by #{sent.paid_by}: fax #{sent.fax.id}.")
    sent.fax
  end

  # 6. Follow the fax until it's delivered or fails, then read its confirmation.
  def follow(fax)
    shown = ''
    READS.times do
      break if %w[delivered failed].include?(fax.status)

      @pause.call(READ_EVERY)
      fax = @client.faxes.get_fax(fax.id)
      stands = fax.step.to_s.empty? ? fax.status : "#{fax.status}: #{fax.step}"
      say(stands) unless stands == shown
      shown = stands
    end
    case fax.status
    when 'delivered'
      say("Its confirmation, readable for a few minutes: #{@client.faxes.get_confirmation(fax.id).url}")
    when 'failed'
      say("It failed, #{fax.failure}, so it costs nothing.")
    else
      say("It's still #{fax.status}. Read it later: client.faxes.get_fax('#{fax.id}').")
    end
  end

  def say(line)
    @say.call(line)
  end

  # A document's pages, once XipFax has counted them.
  def pages_of(document)
    case document.page_count
    when nil then ''
    when 1 then ', 1 page'
    else ", #{document.page_count} pages"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    client = XipFax::Client.new(ENV.fetch('XIPFAX_API_KEY', ''))
  rescue ArgumentError
    warn 'Set XIPFAX_API_KEY to a key you made in the developer console: https://developer.xipfax.com/console/'
    exit 1
  end
  to = ENV.fetch('XIPFAX_TO', '')
  pdf_url = ENV.fetch('XIPFAX_PDF_URL', '')

  quickstart = Quickstart.new(
    client,
    to: to,
    pdf_url: pdf_url,
    say: ->(line) { puts line },
    ask: lambda do |question|
      print question
      $stdout.flush
      # A terminal that closes answers what was typed before it did, which sends only if that was send.
      $stdin.gets.to_s
    end,
    pause: ->(seconds) { sleep seconds }
  )

  begin
    quickstart.run
  rescue XipFax::ApiError => e
    refusal = e.refusal
    warn(refusal ? "XipFax refused it, #{refusal.error.code}: #{refusal.error.message}" : e.message)
    exit 1
  rescue StandardError => e
    warn e.message
    exit 1
  end
  if to.empty? || pdf_url.empty?
    puts 'Those steps cost nothing. To send a fax too, run it again with XIPFAX_TO, a fax number of yours, ' \
         'and XIPFAX_PDF_URL, a public link to a PDF.'
  end
end
