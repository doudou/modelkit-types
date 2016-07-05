module ModelKit::Types
    # A buffer is a list of bytes that is shared and can be modified by multiple
    # Buffer objects
    class Buffer
        # The underling data
        # @return [String]
        attr_reader :backing_buffer
        # This buffer's offset in {#backing_buffer}
        # @return [Integer]
        attr_reader :offset
        # This buffer's size
        # @return [Integer]
        attr_reader :size

        def initialize(backing_buffer, offset = 0, size = backing_buffer.size)
            @backing_buffer = backing_buffer
            @offset = offset
            @size = size
        end

        # Create a different view on the same backing buffer
        #
        # The returned buffer object shares the same backing buffer, but
        # "viewing" only the slice at the given offset and size
        #
        # @return [Buffer]
        # @raise [RangeError]
        def slice(offset, size = self.size - offset)
            validate_slice(offset, size)
            self.class.new(backing_buffer, self.offset + offset, size)
        end

        # Returns a string that represents the same data than self
        #
        # The data is independent from the buffer(s) accessing {#backing_buffer}
        def to_str
            backing_buffer[offset, size]
        end

        # Copy data from self to the given buffer
        def copy_to(buffer)
            if buffer.size != size
                raise RangeError, "buffer sizes do not match"
            end

            buffer.backing_buffer[buffer.offset, size] =
                backing_buffer[offset, size]
        end

        # Validate that the given range is valid
        def validate_slice(index, size)
            if index >= self.size
                raise RangeError, "index #{index} out of bounds (#{self.size})"
            elsif index + size > self.size
                raise RangeError, "buffer range [#{index}, #{size}] crosses buffer boundary (#{self.size}]"
            end
        end

        # Returns the byte at the given index
        def [](index, size = 1)
            validate_slice(index, size)
            backing_buffer[offset + index, size]
        end

        # Sets the byte at the given index
        def []=(index, size = 1, value)
            validate_slice(index, size)
            backing_buffer[offset + index, size] = value
        end

        # Unpacks the binary data into raw values
        def unpack(code)
            backing_buffer.unpack("@#{offset}#{code}")
        end

        # Method used to convert various byte array representations to a Buffer
        def to_types_buffer
            self
        end
    end
end

class String
    # Returns a {ModelKit::Types::Buffer} object backed by self
    def to_types_buffer
        ModelKit::Types::Buffer.new(self)
    end
end
