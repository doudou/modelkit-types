module ModelKit::Types
    # Interpret a buffer that is a sequence of values of the same type
    #
    # The sequence is fixed-size. This class gives access to the elements, but
    # no way to modify it. It is only meant to interpret a buffer.
    class ValueSequence
        # The buffer holding the sequence
        #
        # @return [Buffer]
        attr_reader :buffer
        # The type of the elements in the sequence
        #
        # @return [Models::Type]
        attr_reader :type
        # The number of elements in the sequence
        #
        # @return [Integer]
        attr_reader :size

        attr_reader :elements
        attr_reader :element_offsets
        attr_reader :element_type
        attr_predicate :element_fixed_buffer_size?

        def initialize(buffer, type, size)
            @buffer = buffer
            @type   = type
            @size   = size
            @elements = Array.new
            @element_offsets = Array.new(size + 1)
            @element_offsets[0] = 0
            @element_type = type
            @element_fixed_buffer_size = type.fixed_buffer_size?
        end

        def delete_at(index)
            offset, size = offset_and_size_of(index)
            buffer.slice!(offset, size)
            @size -= 1
            @elements.delete_at(index)
            @elements[index..-1].each { |e| e.__buffer.shift(-size) if e }
            @element_offsets.delete_at(index)
            @element_offsets[index..-1] =
                @element_offsets[index..-1].map { |offset| (offset - size) if offset }
        end

        def next_element_offset(index, offset)
            element_offsets[index + 1] ||= (offset + element_type.buffer_size_at(buffer, offset))
        end

        def element_at(index, offset, size)
            elements[index] ||= element_type.wrap!(buffer.view(offset, size))
        end

        # Returns the offset of the given element in the buffer
        def offset_and_size_of(index)
            next_index = index + 1
            base_index = index
            while !(index_offset = element_offsets[base_index])
                base_index -= 1
            end
            next_offset = index_offset
            while base_index < next_index
                index_offset = next_offset
                next_offset = next_element_offset(base_index, index_offset)
                base_index += 1
            end
            return index_offset, next_offset - index_offset
        end

        def get(index)
            offset, size = offset_and_size_of(index)
            element_at(index, offset, size)
        end
    end
end

