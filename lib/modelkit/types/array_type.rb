module ModelKit::Types
    # Base class for static-length arrays
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class ArrayType < IndirectType
        extend Models::ArrayType

        attr_reader :element_t

        def typestore_initialize
            super
            @element_t = self.class.deference
            @elements = Array.new
        end

	def pretty_print(pp) # :nodoc:
            apply_changes_from_converted_types
	    all_fields = enum_for(:each_with_index).to_a

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

        def raw_each
            if !block_given?
                return enum_for(:raw_each)
            end

            self.class.length.times do |i|
                yield(raw_get(i))
            end
        end

        def each
            if !block_given?
                return enum_for(:each)
            end
            raw_each do |el|
                yield(ModelKit::Types.to_ruby(el, element_t))
            end
        end

        def raw_get_cached(index)
            @elements[index]
        end

        def raw_each_cached(&block)
            @elements.compact.each(&block)
        end

        def raw_get(index)
            @elements[index] ||= do_get(index)
        end

        def raw_set(index, value)
            if value.kind_of?(Type)
                attribute = raw_get(index)
                # If +value+ is already a modelkit/types value, just do a plain copy
                if attribute.kind_of?(ModelKit::Types::Type)
                    return ModelKit::Types.copy(attribute, value)
                end
            end
            do_set(index, value)
        end

        def [](index, range = nil)
            if range
                result = []
                range.times do |i|
                    result << ModelKit::Types.to_ruby(raw_get(i + index), element_t)
                end
                result
            else
                ModelKit::Types.to_ruby(raw_get(index), element_t)
            end
        end

        def []=(index, value)
            raw_set(index, ModelKit::Types.from_ruby(value, element_t))
        end

        # (see Type#to_simple_value)
        #
        # Array types are returned as either an array of their converted
        # elements, or the hash described for the :pack_simple_arrays option.
        def to_simple_value(options = Hash.new)
            if options[:pack_simple_arrays] && element_t.respond_to?(:pack_code)
                Hash[pack_code: element_t.pack_code,
                     size: self.class.length,
                     data: Base64.strict_encode64(to_byte_array)]
            else
                raw_each.map { |v| v.to_simple_value(options) }
            end
        end

        include Enumerable
    end
end
