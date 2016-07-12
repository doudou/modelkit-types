module ModelKit::Types
    # Base class for all enumeration types. Enumerations
    # are mappings from strings to integers
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class EnumType < Type
        extend Models::EnumType

        # The pack code used to marshal this enum's numerical value
        attr_reader :__pack_code

        # The size of the marshalled code
        attr_reader :__size

        def initialize_subtype
            @__size = self.class.size
            @__pack_code = NumericType.compute_pack_code(size: __size, integer: true, unsigned: false)
            if !__size
                raise AbstractType, "cannot create values of #{self.class}: no size specified"
            elsif !__pack_code
                raise AbstractType, "cannot create values of #{self.class}: pack code unknown"
            end
            @__value_to_symbol = self.class.value_to_symbol
            @__symbol_to_value = self.class.symbol_to_value
        end

        # Sets this enum's value based on the given symbol
        #
        # @param [Symbol,String] symbol
        def from_ruby(symbol)
            value = @__symbol_to_value.fetch(symbol.to_sym)
            __buffer[0, __size] = [value].pack(__pack_code)
        rescue KeyError
            raise InvalidEnumValue, "#{symbol} is not a known symbol in #{self}"
        end

        # Returns the symbol that is represented by this enum's value
        #
        # @return [Symbol]
        def to_ruby
            value = __buffer.unpack(__pack_code).first
            @__value_to_symbol.fetch(value)
        rescue KeyError
            raise InvalidEnumValue, "#{value} is not a known symbol in #{self}"
        end

        # (see Type#to_simple_value)
        #
        # Enums are returned as their symbolic representation (a string)
        def to_simple_value(**options)
            to_ruby.to_s
        end
    end
end
