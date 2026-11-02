require "zip"
require "zlib"

module Processador
  # Rubyzip supplies the parsed directory and local header. Inflate small
  # compressed chunks: a highly compressible chunk can expand by ~1000x.
  class EntryStream
    COMPRESSED_CHUNK = 1024

    def initialize(path, entry)
      @file = File.open(path, "rb")
      @file.seek(entry.local_header_offset)
      raise IOError, "invalid ZIP header" unless Zip::Entry.read_local_entry(@file)
      @remaining = @compressed_size = entry.compressed_size
      @inflater = case entry.compression_method
      when Zip::COMPRESSION_METHOD_STORE then nil
      when Zip::COMPRESSION_METHOD_DEFLATE then Zlib::Inflate.new(-Zlib::MAX_WBITS)
      else raise IOError, "unsupported ZIP compression"
      end
      @buffer = +"".b
      @offset = 0
      @finished = false
    rescue StandardError
      @file&.close
      raise
    end

    def readpartial(maxlen, output = nil)
      raise ArgumentError, "invalid read size" unless maxlen.is_a?(Integer) && maxlen.positive?

      fill while @offset == @buffer.bytesize && !@finished
      raise EOFError if @offset == @buffer.bytesize

      length = [maxlen, @buffer.bytesize - @offset].min
      chunk = @buffer.byteslice(@offset, length)
      @offset += length
      output ? output.replace(chunk) : chunk
    end

    def read(maxlen, output = nil)
      readpartial(maxlen, output)
    rescue EOFError
      nil
    end

    def close
      @inflater&.close
      @file.close
    end

    private

    def fill
      if @remaining.zero?
        if @inflater && (!@inflater.finished? || @inflater.total_in != @compressed_size)
          raise IOError, "invalid ZIP member"
        end
        @buffer = +"".b
        @offset = 0
        @finished = true
        return
      end

      compressed = @file.read([@remaining, COMPRESSED_CHUNK].min)
      raise IOError, "truncated ZIP member" if compressed.nil? || compressed.empty?
      @remaining -= compressed.bytesize
      @buffer = @inflater ? @inflater.inflate(compressed) : compressed
      @offset = 0
    end
  end
end
