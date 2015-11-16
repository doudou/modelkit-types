module ModelKit::Types
    # Base class for all dynamic containers
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class ContainerType < IndirectType
        include Enumerable
        extend Models::ContainerType

        attr_reader :element_t

        def typestore_initialize
            super
            @element_t = self.class.deference
            @elements = []
        end

        # Remove all elements from this container
        def clear
            do_clear
        end

        # DEPRECATED. Use #push instead
        def insert(value) # :nodoc:
            ModelKit::Types.warn "ModelKit::Types::ContainerType#insert(value) is deprecated, use #push(value) instead"
            push(value)
        end

        # Adds a new value at the end of the sequence
        def push(*values)
            concat(values)
        end

        # This should return an object that allows to identify whether the
        # ModelKit::Types instances pointing to elements should be invalidated after
        # certain operations
        #
        # The default always returns nil, which means that no invalidation is
        # performed
        def contained_memory_id
        end

        def handle_container_invalidation
            memory_id    = self.contained_memory_id
            yield
        ensure
            if invalidated? 
                # All children have been invalidated already by #invalidate
            elsif memory_id && (memory_id != self.contained_memory_id)
                ModelKit::Types.debug { "invalidating all elements in #{raw_to_s}" }
                invalidate_children
            elsif @elements.size > self.size
                ModelKit::Types.debug { "invalidating #{@elements.size - self.size} trailing elements in #{raw_to_s}" }
                while @elements.size > self.size
                    if el = @elements.pop
                        el.invalidate
                    end
                end
            end
        end

        module ConvertToRuby
            def __element_to_ruby(value)
                ModelKit::Types.to_ruby(value, element_t)
            end
        end
        module ConvertFromRuby
            def __element_from_ruby(value)
                ModelKit::Types.from_ruby(value, element_t)
            end
        end

        def __element_to_ruby(value)
            value
        end

        def __element_from_ruby(value)
            value
        end

        def concat(array)
            # NOTE: no need to care about convertions to ruby here, as -- when
            # the elements require a convertion to ruby -- we convert the whole
            # container to Array
            allocating_operation do
                for v in array
                    do_push(__element_from_ruby(v))
                end
            end
            self
        end

        def raw_each_cached(&block)
            @elements.compact.each(&block)
        end

        def raw_each
            return enum_for(:raw_each) if !block_given?

            idx = 0
            do_each(true) do |el|
                yield(@elements[idx] ||= el)
                idx += 1
            end
        end

        # Enumerates the elements of this container
        def each
            return enum_for(:each) if !block_given?

            idx = 0
            do_each(false) do |el|
                if el.kind_of?(ModelKit::Types::Type)
                    el = (@elements[idx] ||= el)
                    el = __element_to_ruby(el)
                end

                yield(el)
                idx += 1
            end
        end

        # Erases an element from this container
        def erase(el)
            # NOTE: no need to care about convertions to ruby here, as -- when
            # the elements require a convertion to ruby -- we convert the whole
            # container to Array
            handle_invalidation do
                do_erase(__element_from_ruby(el))
            end
        end

        # Deletes the elements
        def delete_if
            # NOTE: no need to care about convertions to ruby here, as -- when
            # the elements require a convertion to ruby -- we convert the whole
            # container to Array
            handle_invalidation do
                do_delete_if do |el|
                    yield(__element_to_ruby(el))
                end
            end
        end

        # True if this container is empty
        def empty?; length == 0 end

        # Appends a new element to this container
        def <<(value); push(value) end

        def pretty_print(pp)
            apply_changes_from_converted_types
            index = 0
	    pp.text '['
	    pp.nest(2) do
		pp.breakable
		pp.seplist(enum_for(:each)) do |element|
		    pp.text "[#{index}] = "
		    element.pretty_print(pp)
                    index += 1
		end
	    end
	    pp.breakable
	    pp.text ']'
        end

        # (see Type#to_simple_value)
        #
        # Container types are returned as either an array of their converted
        # elements, or the hash described for the :pack_simple_arrays option. In
        # the latter case, a 'size' field is added with the number of elements
        # in the container to allow for validation on the receiving end.
        def to_simple_value(options = Hash.new)
            if options[:pack_simple_arrays] && element_t.respond_to?(:pack_code)
                Hash[pack_code: element_t.pack_code,
                     size: size,
                     data: Base64.strict_encode64(to_byte_array[8..-1])]
            else
                raw_each.map { |v| v.to_simple_value(options) }
            end
        end
    end
end
