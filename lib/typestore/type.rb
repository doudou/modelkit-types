module TypeStore
    # Base class for all types
    # Registry types are wrapped into subclasses of Type
    # or other Type-derived classes (Array, Pointer, ...)
    #
    # Value objects are wrapped into instances of these classes
    class Type
        extend Models::Type

        # Returns a new Type instance that contains the same value, but using a
        # different type object
        #
        # It raises ArgumentError if the cast is invalid.
        #
        # The ability to cast can be checked beforehand by using Type.casts_to?
        #
        # Note that the return value might be +self+, and that both objects
        # refer to the same memory zone. Therefore, if one of the two value
        # objects is used to modify the underlying value, that will be reflected
        # in the other. Moreover, both values should not be modified in two
        # different threads without proper locking.
        def cast(target_type)
            if !self.class.casts_to?(target_type)
                raise ArgumentError, "cannot cast #{self} to #{target_type}"
            end
            target_type.from_buffer(self.buffer)
        end

        # Called internally to apply any change from a converted value to the
        # underlying TypeStore value
        def apply_changes_from_converted_types
        end

        # Called internally to tell typelib that converted values should be
        # updated next time from the underlying TypeStore value
        # underlying TypeStore value
        def invalidate_changes_from_converted_types
        end

        # Creates a deep copy of this value.
        #
        # It is guaranteed that this value will be referring to a different
        # memory zone than +self+
	def dup
            self.class.from_buffer(to_byte_array)
	end
        alias clone dup

        # Reinitializes this value to match marshalled data
        #
        # @param [String] string the buffer with marshalled data
        def from_buffer(string, options = Hash.new)
            options = Type.validate_layout_options(options)
            from_buffer_direct(string,
                               options[:accept_pointers],
                               options[:accept_opaques],
                               options[:merge_skip_copy],
                               options[:remove_trailing_skips])
        end

        # "Raw" version of {#from_buffer}
        #
        # This is a version of #from_buffer without named parameters. It is
        # provided mainly for libraries that are unmarshalling a lot of
        # typestore samples, to remove the overhead of option validation
        def from_buffer_direct(string, accept_pointers = false, accept_opaques = false, merge_skip_copy = true, remove_trailing_skips = true)
            allocating_operation do
                do_from_buffer(string, 
                               accept_pointers,
                               accept_opaques,
                               merge_skip_copy,
                               remove_trailing_skips)
            end
            self
        end

        # Returns a string whose content is a marshalled representation of the memory
        # hold by +obj+
        #
        # @example marshalling and unmarshalling a value. {Type.from_buffer} can
        #   create the value back from the marshalled data. If non-default
        #   options are given to {#to_byte_array}, the same options must be used
        #   in from_buffer.
        #
        #   marshalled_data = result.to_byte_array
        #   value = my_registry.get('/base/Type').from_buffer(marshalled_data)
        # 
        # @option options [Boolean] accept_pointers (false) whether pointers, when
        #   present, should cause an exception to be raised or simply
        #   ignored
        # @option options [Boolean] accept_opaques (false) whether opaques, when
        #   present, should cause an exception to be raised or simply
        #   ignored
        # @option options [Boolean] merge_skip_copy (true) whether padding
        #   bytes should be marshalled as well when adjacent to non-padding
        #   bytes, to reduce CPU load at the expense of I/O. When set to
        #   false, padding bytes are removed completely.
        # @option options [Boolean] remove_trailing_skips (true) whether
        #   padding bytes at the end of the value should be marshalled or
        #   not.
        def to_byte_array(options = Hash.new)
            apply_changes_from_converted_types
            options = Type.validate_layout_options(options)
            do_byte_array(
                options[:accept_pointers],
                options[:accept_opaques],
                options[:merge_skip_copy],
                options[:remove_trailing_skips])
        end

        def typestore_initialize
        end

        def freeze_children
        end

        def invalidate_children
        end

        def to_ruby
            TypeStore.to_ruby(self, self.class)
        end

	# Check for value equality
        def ==(other)
	    # If other is also a type object, we first
	    # check basic constraints before trying conversion
	    # to Ruby objects
            if Type === other
		return TypeStore.compare(self, other)
	    else
                # +other+ is a Ruby type. Try converting +self+ to ruby and
                # check for equality in Ruby objects
		if (ruby_value = TypeStore.to_ruby(self)).eql?(self)
		    return false
		end
		other == ruby_value
	    end
        end

	# Returns a PointerType object which points to +self+. Note that
	# to_ptr.deference == self
        def to_ptr
            pointer = self.class.to_ptr.wrap(@ptr.to_ptr)
	    pointer.instance_variable_set(:@points_to, self)
	    pointer
        end
	
	def to_s # :nodoc:
	    if respond_to?(:to_str)
		to_str
	    elsif ! (ruby_value = to_ruby).eql?(self)
		ruby_value.to_s
	    else
                raw_to_s
	    end
	end

        def raw_to_s
            "#<#{self.class.name}: 0x#{address.to_s(16)} ptr=0x#{@ptr.zone_address.to_s(16)}>"
        end

	def pretty_print(pp) # :nodoc:
	    pp.text to_s
	end

        # Get the memory pointer for self
        #
        # @return [MemoryZone]
        def to_memory_ptr; @ptr end

	def is_a?(typename); self.class.is_a?(typename) end

        def inspect
            raw_to_s + ": " + to_simple_value.inspect
        end

        # Returns a representation of this type only into simple Ruby values,
        # that is strings, numbers and arrays / hashes.
        #
        # @option options [Boolean] :special_float_values () if :string, the
        #   floating point special values NaN and Infinity are converted to
        #   strings. If :nil, they are converted to nil. Otherwise, they are
        #   left as-is. This is required for marshalling formats that can't
        #   represent them.
        # @option options [Boolean] :pack_simple_arrays (true) if true, arrays
        #   and containers of numeric types will be packed into a hash of the form
        #   {size: size_in_elements, pack_code: code, data: packed_data}. The
        #   pack_code field describes the type of element in the array (from
        #   String#unpack or Array#pack), which tells both the type of the data
        #   and its endianness.
        #
        # @return [Object]
        def to_simple_value(options = Hash.new)
            raise NotImplementedError, "there is no way to convert a value of type #{self.class} into a simple ruby value"
        end

        # Returns a representation of this type that can be serialized with JSON
        #
        # This is calling to_simple_value with the :special_float_values option
        # set to :nil by default, as JSON cannot represent NaN and Infinity and
        # converting those to null is the behaviour specified in the JSON
        # documentation.
        # 
        # (see Type#to_simple_value)
        def to_json_value(options = Hash.new)
            to_simple_value(Hash[:special_float_values => :nil].merge(options))
        end

        def to_ruby
            @__typestore_converter.to_ruby(self)
        end

        def from_ruby(object)
            @__typestore_converter.from_ruby(self, object)
        end
    end
end
