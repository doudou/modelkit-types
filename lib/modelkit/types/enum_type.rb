module ModelKit::Types
    # Base class for all enumeration types. Enumerations
    # are mappings from strings to integers
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class EnumType < Type
        extend Models::EnumType

        # (see Type#to_simple_value)
        #
        # Enums are returned as their symbolic representation (a string)
        def to_simple_value(options = Hash.new)
            to_ruby.to_s
        end
    end
end
