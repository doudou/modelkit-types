module ModelKit::Types
    # Base class for all dynamic containers
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class ContainerType < SequenceType
        extend Models::ContainerType

        def reset_buffer(buffer)
            if buffer.empty?
                buffer = ([0].pack("Q>")).to_types_buffer
            end
            element_count = buffer[0, 8].unpack("Q>").first
            super(buffer, element_count, 8)
        end

        def __make_content_header
            [size].pack("Q>")
        end

        def to_byte_array(data_only: false)
            result = super
            if data_only
                result[8..-1]
            else result
            end
        end

        def to_ruby
            map(&:to_ruby)
        end

        def from_ruby(value)
            buffer = [value.size].pack("Q>")
            value.each do |v|
                buffer.concat(__element_type.from_ruby(v).to_byte_array)
            end
            reset_buffer(Buffer.new(buffer))
        end

        # Remove all elements from this container
        def clear
            __elements.clear
        end

        # Adds a new value at the end of the sequence
        def push(value)
            __elements << (new_element = value.dup)
            new_element
        end

        # Appends a new element to this container
        def <<(value)
            push(value)
        end

        # Add an enumeration of elements at the end of this container
        def concat(array)
            __elements.concat(array.map(&:dup))
            self
        end

        # Resize the container to match the given size
        def resize(new_size)
            if new_size < size
                @__elements.slice!(new_size, size)
            else
                (new_size - size).times do
                    push(__element_type.new)
                end
            end
        end

        # Deletes the elements for which a block returns true
        #
        # @yieldparam [Type] element an element
        # @yieldreturn [Boolean] true if the element should be removed and false
        #   otherwise
        def delete_if
            removed_elements = 0
            size.times do |i|
                i -= removed_elements
                e = (__elements[i] || get(i))
                if yield(e)
                    if i < __element_access.size
                        __element_access.delete_at(i)
                    end
                    __elements.delete_at(i)
                    removed_elements += 1
                else
                    __elements[i] = e
                end
            end
        end

        def pretty_print(pp)
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
    end
end
