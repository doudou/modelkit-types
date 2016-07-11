module ModelKit::Types
    # Base class for static-length arrays
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class ArrayType < SequenceType
        extend Models::ArrayType

        def __make_content_header
            ""
        end

        # Resets this array to the values in a Ruby array
        #
        # If the Ruby array is smaller than self, the remainder will be
        # default-initialized
        #
        # @param [Array] value an array whose elements can be converted to this
        #   array's elements using {#deference} {#from_ruby}
        # @raise RangeError if the array is bigger than self
        def from_ruby(value)
            if value.size > size
                raise RangeError, "array provided too big (#{value.size} greater than #{size})"
            end
            buffer = ""
            value.each do |v|
                buffer.concat(__element_type.from_ruby(v).to_byte_array)
            end
            buffer.concat(__element_type.new.to_byte_array * (size - value.size))
            reset_buffer(Buffer.new(buffer))
        end

        def to_ruby
            map(&:to_ruby)
        end

        def reset_buffer(buffer)
            super(buffer, self.class.length, 0)
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
    end
end
