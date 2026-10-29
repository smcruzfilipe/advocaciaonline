require "loofah"
require_relative "errors"

module Processador
  module Sanitizer
    # Only the publication text is presentation markup. Identifiers, hashes,
    # matching fields and URLs retain the exact types and values from DJEN.
    def self.publication(item)
      text = item["texto"]
      return item unless text.is_a?(String)

      fragment = Loofah.html5_fragment(text)
      fragment.css("script, style, template, noscript").remove
      plain_text = fragment.scrub!(:strip).scrub!(:unprintable)
        .to_text(encode_special_chars: false).tr("\u00a0", " ").strip
      item.merge("texto" => plain_text)
    rescue ArgumentError, Nokogiri::XML::SyntaxError
      raise SourceError, "DJEN publication text could not be sanitized", cause: nil
    end
  end
end
