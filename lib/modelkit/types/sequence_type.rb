module ModelKit::Types
    # Common functionality for {ContainerType} and {ArrayType}
    class SequenceType < IndirectType
        include Enumerable

        attr_reader :__element_type
        attr_reader :__element_access
        attr_reader :__elements
        attr_predicate :__element_fixed_buffer_size?

        def initialize_subtype
            super
            @__element_type = self.class.deference
            @__element_fixed_buffer_size = __element_type.fixed_buffer_size?
        end

        def reset_buffer(buffer, element_count, offset)
            super(buffer)
            @__elements = Array.new(element_count)
            @__element_access = ValueSequence.new(buffer.view(offset), self.class.deference, element_count)
        end

        def apply_changes_fixed_size
            new_size = __elements.size
            old_size = __element_access.size
            if new_size == old_size
                return
            end

            contents = __buffer.to_str
            content_header = __make_content_header
            contents[0, content_header.size] = content_header
            element_size = __element_type.size
            if new_size < old_size
                # Elements got removed, we just need to resize the buffer
                contents.slice!(8 + __elements.size * element_size, contents.size)
            else
                # We need to concatenate the new elements at the end of the
                # buffer, reset our own backing buffer (so that we own it)
                # and then update all existing elements
                #
                # Note that the new elements are guaranteed to have detached
                # buffers
                __elements[old_size...new_size].each do |el|
                    contents.concat(el.to_byte_array)
                end
            end
            elements = @__elements
            reset_buffer(root_buffer = Buffer.new(contents))
            @__elements = elements

            offset = content_header.size
            __elements.each do |el|
                if el
                    el.reset_buffer(root_buffer.view(offset, element_size))
                end
                offset += element_size
            end
        end

        def apply_changes_variable_size
            new_contents = __make_content_header

            @__elements.each_with_index do |el, i|
                if el
                    new_contents.concat(el.to_byte_array)
                else
                    new_contents.concat(__element_access.get(i).__buffer)
                end
            end
            elements = @__elements
            reset_buffer(Buffer.new(new_contents))
            @__elements = elements
        end

        def apply_changes
            if __element_fixed_buffer_size?
                apply_changes_fixed_size
            else
                apply_changes_variable_size
            end
        end

        def to_byte_array(data_only: false)
            apply_changes
            super()
        end

        def size
            __elements.size
        end

        # True if this container is empty
        def empty?
            __elements.empty?
        end

        def validate_range(index, size)
            self_size = self.size
            if index < 0
                raise RangeError, "#{index} is negative"
            elsif index > self_size
                raise RangeError, "#{index} is out of bounds (#{self_size})"
            elsif index + size > self_size
                raise RangeError, "#{index + size} is out of bounds (#{self_size})"
            end
        end

        def set(index, value)
            validate_range(index, 1)
            if !__element_fixed_buffer_size?
                if e = __elements[index]
                    value.copy_to(e)
                else
                    __elements[index] = value.dup
                end
            else
                value.copy_to(get(index))
            end
        end

        def get(index)
            validate_range(index, 1)
            if element = __elements[index]
                element
            else
                from_buffer = __element_access.get(index)
                __elements[index] = 
                    if __element_fixed_buffer_size?
                        from_buffer
                    else
                        from_buffer.dup
                    end
            end
        end

        def [](index, size = nil)
            if size
                range = (index...(index + size))
            elsif index.kind_of?(Range)
                range = index
            end

            if range
                range.map do |element_i|
                    get(element_i)
                end
            else
                get(index)
            end
        end

        def []=(index, value)
            set(index, value)
        end

        # Enumerates the elements of this container
        def each
            return enum_for(:each) if !block_given?

            i = 0
            __elements.map! do |e|
                e ||= __element_access.get(i)
                yield(e)
                i += 1
                e
            end
        end

        # (see Type#to_simple_value)
        #
        # Container types are returned as either an array of their converted
        # elements, or the hash described for the :pack_simple_arrays option. In
        # the latter case, a 'size' field is added with the number of elements
        # in the container to allow for validation on the receiving end.
        def to_simple_value(pack_simple_arrays: false, **options)
            if pack_simple_arrays && __element_type.respond_to?(:pack_code)
                Hash[pack_code: __element_type.pack_code,
                     size: size,
                     data: Base64.strict_encode64(to_byte_array(data_only: true))]
            else
                map { |v| v.to_simple_value(pack_simple_arrays: pack_simple_arrays, **options) }
            end
        end
    end
end
