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
