module ModelKit::Types
    # Base class for numeric types
    class NumericType < Type
        extend Models::NumericType

        # The code for Array#pack that allows to encode/decode a ruby value into
        # its buffer representation
        attr_reader :__pack_code

        # The size of the numeric in bytes
        attr_reader :__size

        def initialize
            super
            @__buffer = "\x0" * __size
        end

        def initialize_subtype
            @__pack_code = self.class.pack_code
            @__size = self.class.size
        end

        # Convert the encoded value into a Ruby value
        #
        # Unlike {#to_ruby}, it does not apply any user-defined conversions
        def to_ruby
            __buffer.unpack(__pack_code).first
        end

        # Updates the buffer with the given value
        #
        # Unlike {#from_ruby}, it does not apply any user-defined conversions
        def from_ruby(value)
            __buffer[0, __size] = [value].pack(__pack_code)
        end

        # (see Type#to_simple_value)
        def to_simple_value(pack_simple_arrays: true, special_float_values: nil)
            v = to_ruby
            return v if !special_float_values
            return v if self.class.integer?

            if special_float_values == :string
                if v.nan?
                    "NaN"
                elsif v.infinite?
                    if v > 0 then "Infinity"
                    else "-Infinity"
                    end
                else v
                end
            elsif special_float_values == :nil
                if v.nan? || v.infinite?
                    nil
                else v
                end
            else raise ArgumentError, ":special_float_values can only either be :string or :nil, found #{special_float_values.inspect}"
            end
        end

        def pretty_print(pp)
            pp.text to_ruby.to_s
        end
    end
end

