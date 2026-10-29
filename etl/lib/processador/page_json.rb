require "oj"

module Processador
  # Oj's callback parser retains one publication, not the whole items array.
  # https://www.rubydoc.info/gems/oj/Oj/ScHandler
  class PageJson < Oj::ScHandler
    class InvalidPage < StandardError; end
    class ConsumerError < StandardError
      attr_reader :original

      def initialize(original)
        @original = original
        super("publication consumer failed")
      end
    end

    ROOT = Object.new.freeze
    ITEMS = Object.new.freeze
    DISCARD = Object.new.freeze
    private_constant :ROOT, :ITEMS, :DISCARD

    def self.read(io, &consumer)
      handler = new(&consumer)
      Oj.sc_parse(handler, io)
      handler.finish
    end

    def initialize(&consumer)
      @consumer = consumer
      @stack = []
      @documents = 0
      @count = 0
      @items_seen = false
      @items_key_seen = false
    end

    def hash_start
      parent = @stack.last
      value = if @stack.empty?
        raise InvalidPage if @documents.positive?
        ROOT
      elsif parent.equal?(DISCARD)
        DISCARD
      elsif parent.equal?(ROOT)
        raise InvalidPage if @key == "items"
        DISCARD
      else
        {}
      end
      @stack << value
      value
    end

    def hash_end
      @stack.pop
    end

    def hash_key(key)
      valid_string!(key)
      @key = key
    end

    def hash_set(hash, key, value)
      valid_string!(value)
      if hash.equal?(ROOT)
        if key == "items"
          raise InvalidPage if @items_key_seen
          @items_key_seen = true
          @items_seen = value.equal?(ITEMS)
        end
      elsif !hash.equal?(DISCARD)
        hash[key] = value
      end
    end

    def array_start
      parent = @stack.last
      raise InvalidPage if @stack.empty? || parent.equal?(ITEMS)
      value = if parent.equal?(DISCARD)
        DISCARD
      elsif parent.equal?(ROOT)
        @key == "items" ? ITEMS : DISCARD
      else
        []
      end
      @stack << value
      value
    end

    def array_end
      @stack.pop
    end

    def array_append(array, value)
      valid_string!(value)
      if array.equal?(ITEMS)
        raise InvalidPage unless value.is_a?(Hash)
        @count += 1
        begin
          @consumer&.call(value)
        rescue StandardError => error
          raise ConsumerError.new(error)
        end
      elsif !array.equal?(DISCARD)
        array << value
      end
    end

    def add_value(value)
      valid_string!(value)
      @documents += 1
      raise InvalidPage unless @documents == 1 && value.equal?(ROOT) && @items_seen
    end

    def finish
      raise InvalidPage unless @documents == 1
      @count
    end

    private

    def valid_string!(value)
      raise InvalidPage if value.is_a?(String) && !value.valid_encoding?
    end
  end
end
