module STF
  class SourceUnavailable < StandardError; end
  class InvalidSource < StandardError; end
  class Interrupted < StandardError; end
  class LeaseLost < StandardError; end
end
