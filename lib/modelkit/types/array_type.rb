module ModelKit::Types
    # Base class for static-length arrays
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class ArrayType < IndirectType
        extend Models::ArrayType

        attr_reader :__elements
        attr_reader :__element_access
        attr_predicate :__element_fixed_buffer_size?

        def initialize_subtype
            super
            @__elements = Array.new
            @__element_fixed_buffer_size = self.class.deference.fixed_buffer_size?
        end

        def reset_buffer(buffer)
            super
            @__element_access = ValueSequence.new(buffer, self.class.deference, self.class.length)
        end

        def each(&block)
            __element_access.each(&block)
        end

        def get(index)
            if e = @__elements[index]
                e
            else
                e = __element_access.get(index)
                @__elements[index] =
                    if __element_fixed_buffer_size?
                        e
                    else
                        e = e.dup
                    end
            end
        end

        def set(index, value)
            value.copy_to(get(index))
        end

        def set!(index, value)
            value.copy_to!(get(index))
        end

        def [](index, range = nil)
            __element_access[index, range]
        end

        def []=(index, value)
            set(index, value)
        end

        # (see Type#to_simple_value)
        #
        # Array types are returned as either an array of their converted
        # elements, or the hash described for the :pack_simple_arrays option.
        def to_simple_value(pack_simple_arrays: true, **options)
            if pack_simple_arrays && self.class.deference.respond_to?(:pack_code)
                Hash[pack_code: self.class.deference.pack_code,
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
