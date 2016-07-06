module ModelKit::Types
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

        def each
            return enum_for(:each) if !block_given?

            offset = 0
            size.times do |element_i|
                next_offset = next_element_offset(element_i, offset)
                yield(element_at(element_i, offset, next_offset - offset))
                offset = next_offset
            end
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

        def [](index, range = nil)
            if range
                range = (index...(index + range))
            elsif index.kind_of?(Range)
                range = index
            end

            if range
                # This uses a property of offset_of, that is that it caches the
                # offsets of all the elements until the requested one
                offset, size = offset_and_size_of(range.first)

                range.map do |element_i|
                    element = (elements[element_i] ||= element_type.wrap!(buffer.view(offset, size)))
                    offset += size
                    size = element_type.buffer_size_at(buffer, offset)
                    element
                end
            else
                get(index)
            end
        end
    end
end

