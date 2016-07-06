module ModelKit::Types
    # Base class for all types
    #
    # Value objects are instances of Type's subclasses. Type itself is mostly
    # abstract
    class Type
        extend Models::Type

        # The buffer containing the encoded data
        #
        # @return [String]
        attr_reader :__buffer

        def initialize
            initialize_subtype
            reset_buffer(Buffer.new("\x0" * self.class.size))
        end

        # Initialization method in which subtypes should do the type-specific
        # initialization
        #
        # In some cases (namely, Models::Type#from_buffer and
        # Models::Type#wrap), the type {#initialize} method is not called
        # because the value is already initialized. However,
        # {#initialize_subtype} is still called.
        def initialize_subtype
        end

        # Sets {#__buffer} to the given value
        #
        # This should in general not validate the buffer. Validation must be
        # provided at the type level by overloading
        # {Models::Type#validate_buffer}.
        def reset_buffer(buffer)
            @__buffer = buffer
        end

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
                raise InvalidCast, "cannot cast #{self} to #{target_type}"
            end
            size = target_type.buffer_size_at(__buffer, 0)
            target_type.wrap!(self.__buffer.view(0, size))
        end

        # Creates a deep copy of this value.
        #
        # It is guaranteed that this value will be referring to a different
        # memory zone than +self+
        def dup
            self.class.wrap!(to_byte_array)
        end
        alias clone dup

        # Returns a string whose content is a marshalled representation of the memory
        # hold by self
        #
        # @return [String]
        def to_byte_array
            __buffer.to_str
        end

        def inspect
            to_s
        end

        def to_s
            "#<#{self.class}: buffer=0x#{__buffer.object_id.to_s(16)} size=#{__buffer.size}>"
        end

        # Copy the value of self into another value
        #
        # This method validates the type equality. Use {#copy_to!} to bypass the
        # (potentially expensive) test
        def copy_to(target)
            if self.class != target.class
                raise InvalidCopy, "cannot copy #{self} to #{target.class}"
            end
            copy_to!(target)
        end

        # Copy the value of self into another value without typechecking
        #
        # This method does not validate the type equality. Use {#copy_to} for
        # safety (i.e. if the check has not been done already by other means)
        def copy_to!(target)
            __buffer.copy_to(target.__buffer)
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
            to_simple_value(Hash[special_float_values: :nil].merge(options))
        end
    end
end
