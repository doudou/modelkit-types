module ModelKit::Types
    # Base class for static-length arrays
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class ArrayType < IndirectType
        extend Models::ArrayType

        # The type of one element
        attr_reader :__element_type
        # Cached resolved elements
        attr_reader :__elements
        # Cached offsets to elements in __buffer
        attr_reader :__element_offsets
        # Whether the in-buffer size of __element_type is independent of the
        # data that is inside the buffer or not
        #
        # In practice, this is governed by the presence of containers in the
        # type
        attr_predicate :__element_fixed_buffer_size?

        def initialize_subtype
            super
            @__elements = Array.new
            @__element_offsets = Array.new(self.class.length + 1)
            @__element_offsets[0] = 0
            @__element_type = self.class.deference
            @__element_fixed_buffer_size = __element_type.fixed_buffer_size?
        end

        def each
            return enum_for(__method__) if !block_given?

            offset = 0
            self.class.length.times do |element_i|
                next_offset = __next_element_offset(element_i, offset)
                yield(__element_at(element_i, offset, next_offset - offset))
                offset = next_offset
            end
        end

        def __next_element_offset(index, offset)
            __element_offsets[index + 1] ||= (offset + __element_type.buffer_size_at(__buffer, offset))
        end

        def __element_at(index, offset, size)
            __elements[index] ||= __element_type.wrap!(__buffer.slice(offset, size))
        end

        # Returns the offset of the given element in the buffer
        def __offset_and_size_of(index)
            next_index = index + 1
            base_index = index
            while !(index_offset = __element_offsets[base_index])
                base_index -= 1
            end
            next_offset = index_offset
            while base_index < next_index
                index_offset = next_offset
                next_offset = __next_element_offset(base_index, index_offset)
                base_index += 1
            end
            return index_offset, next_offset - index_offset
        end

        def get(index)
            offset, size = __offset_and_size_of(index)
            __element_at(index, offset, size)
        end

        def set(index, value)
            value.copy_to(get(index))
        end

        def set!(index, value)
            value.copy_to!(get(index))
        end

        def [](index, range = nil)
            if range
                range = (index...(index + range))
            elsif index.kind_of?(Range)
                range = index
            end

            if range
                # This uses a property of __offset_of, that is that it caches the
                # offsets of all the elements until the requested one
                offset, size = __offset_and_size_of(range.first)

                range.map do |element_i|
                    element = (__elements[element_i] ||= __element_type.wrap!(__buffer.slice(offset, size)))
                    offset += size
                    size = __element_type.buffer_size_at(__buffer, offset)
                    element
                end
            else
                get(index)
            end
        end

        def []=(index, value)
            set(index, value)
        end

        # (see Type#to_simple_value)
        #
        # Array types are returned as either an array of their converted
        # elements, or the hash described for the :pack_simple_arrays option.
        def to_simple_value(pack_simple_arrays: true, **options)
            if pack_simple_arrays && __element_type.respond_to?(:pack_code)
                Hash[pack_code: __element_type.pack_code,
                     size: self.class.length,
                     data: Base64.strict_encode64(__buffer.to_str)]
            else
                each.map { |v| v.to_simple_value(pack_simple_arrays: pack_simple_arrays, **options) }
            end
        end

        def pretty_print(pp) # :nodoc:
            all_fields = each_with_index.to_a

            pp.text '['
            pp.nest(2) do
                pp.breakable
                pp.seplist(all_fields) do |element|
                    element, index = *element 
                    pp.text "[#{index}] = "
                    element.pretty_print(pp)
                end
            end
            pp.breakable
            pp.text ']'
        end

        include Enumerable
    end
end
