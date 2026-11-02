require "loofah"
require "uri"
require_relative "errors"

module Processador
  module Sanitizer
    # Only the publication text is presentation markup. Identifiers, hashes,
    # matching fields and URLs retain the exact types and values from DJEN.
    def self.publication(item)
      item = item.reject { |key, _| %w[texto_parts texto_plain].include?(key) }
      text = item["texto"]
      return item unless text.is_a?(String)

      fragment = Loofah.html5_fragment(text)
      fragment.css("script, style, template, noscript").remove
      plain_text = readable_text(fragment.dup)
      result = item.merge("texto" => plain_text)
      parts = linked_parts(fragment, plain_text)
      result["texto_parts"] = parts if parts
      result
    rescue ArgumentError, Nokogiri::XML::SyntaxError
      raise SourceError, "DJEN publication text could not be sanitized", cause: nil
    end

    def self.presentation(item)
      sanitized = publication(item)
      result = item.reject { |key, _| %w[texto_parts texto_plain].include?(key) }
      if sanitized["texto_parts"]
        result.merge("texto_parts" => sanitized.fetch("texto_parts"), "texto_plain" => sanitized.fetch("texto"))
      else
        result
      end
    end

    def self.readable_text(fragment)
      fragment.scrub!(:strip).scrub!(:unprintable)
        .to_text(encode_special_chars: false).tr("\u00a0", " ").strip
    end
    private_class_method :readable_text

    def self.safe_href(value)
      return unless value.is_a?(String)

      value = value.strip
      return unless value.match?(/\Ahttps?:\/\//i) && !value.match?(/[[:cntrl:]]/)

      url = URI.parse(value)
      value if %w[http https].include?(url.scheme&.downcase) && url.host && !url.userinfo
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :safe_href

    def self.linked_parts(fragment, plain_text)
      anchors = fragment.css("a").filter_map do |anchor|
        href = safe_href(anchor["href"])
        [anchor, href] if href
      end
      return if anchors.empty?

      # Text markers survive Loofah's paragraph handling without interpreting
      # source markup in the client. Choose a prefix absent from decoded text.
      prefix = "AO_PUBLICATION_LINK_"
      prefix += "_" while plain_text.include?(prefix)
      markers = {}
      anchors.each_with_index do |(anchor, href), index|
        start = "#{prefix}#{index}_START"
        finish = "#{prefix}#{index}_END"
        markers[start] = href
        markers[finish] = nil
        anchor.add_previous_sibling(Nokogiri::XML::Text.new(start, fragment.document))
        anchor.add_next_sibling(Nokogiri::XML::Text.new(finish, fragment.document))
      end
      marked = readable_text(fragment)
      href = nil
      parts = []
      marked.split(/(#{Regexp.escape(prefix)}\d+_(?:START|END))/).each do |text|
        if markers.key?(text)
          href = markers[text]
        elsif !text.empty?
          parts << (href ? { "text" => text, "href" => href } : { "text" => text })
        end
      end
      # Markers at the outside of an anchor must not preserve leading/trailing
      # whitespace that the ordinary text sanitizer removes.
      while parts.first
        parts.first["text"] = parts.first.fetch("text").lstrip
        break unless parts.first.fetch("text").empty?
        parts.shift
      end
      while parts.last
        parts.last["text"] = parts.last.fetch("text").rstrip
        break unless parts.last.fetch("text").empty?
        parts.pop
      end
      return unless parts.map { |part| part.fetch("text") }.join == plain_text

      parts
    end
    private_class_method :linked_parts
  end
end
