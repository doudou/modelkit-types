module TypeStore
    # Module included in container types that offer random access
    # functionality
    module RandomAccessContainer
        # Private version of the getters, to bypass the index boundary
        # checks
        def raw_get_no_boundary_check(index)
            @elements[index] ||= do_get(index, true)
        end

        # Private version of the getters, to bypass the index boundary
        # checks
        def get_no_boundary_check(index)
            if @elements[index]
                return __element_to_ruby(@elements[index])
            else
                value = do_get(index, false)
                if value.kind_of?(TypeStore::Type)
                    @elements[index] = value
                    __element_to_ruby(value)
                else value
                end
            end
        end

        def raw_get(index)
            if index < 0
                raise ArgumentError, "index out of bounds (#{index} < 0)"
            elsif index >= size
                raise ArgumentError, "index out of bounds (#{index} >= #{size})"
            end
            raw_get_no_boundary_check(index)
        end

        def raw_get_cached(index)
            @elements[index]
        end

        def get(index)
            self[index]
        end

        # Returns the value at the given index
        def [](index, chunk_size = nil)
            if chunk_size
                if index < 0
                    raise ArgumentError, "index out of bounds (#{index} < 0)"
                elsif (index + chunk_size) > size
                    raise ArgumentError, "index out of bounds (#{index} + #{chunk_size} >= #{size})"
                end
                result = self.class.new
                chunk_size.times do |i|
                    result.push(raw_get_no_boundary_check(index + i))
                end
                result
            else
                if index < 0
                    raise ArgumentError, "index out of bounds (#{index} < 0)"
                elsif index >= size
                    raise ArgumentError, "index out of bounds (#{index} >= #{size})"
                end

                get_no_boundary_check(index)
            end
        end

        def raw_set(index, value)
            if index < 0 || index >= size
                raise ArgumentError, "index out of bounds"
            end

            do_set(index, value)
        end

        def set(index, value)
            self[index] = value
        end

        def []=(index, value)
            v = __element_from_ruby(value)
            raw_set(index, v)
        end

        def raw_each
            return enum_for(:raw_each) if !block_given?
            for idx in 0...size
                yield(raw_get_no_boundary_check(idx))
            end
        end

        def each
            return enum_for(:each) if !block_given?
            for idx in 0...size
                yield(get_no_boundary_check(idx))
            end
        end
    end
end

