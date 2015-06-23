module TypeStore
    class NotFound < ArgumentError
    end

    class DuplicateType < ArgumentError
    end

    # Exception raised when TypeStore.from_ruby is called but the value cannot be
    # converted to the requested type
    class UnknownConversionRequested < ArgumentError
        attr_reader :value, :type
        def initialize(value, type)
            @value, @type = value, type
        end

        def pretty_print(pp)
            pp.text "conversion from #{value} of type #{value.class} to #{type} requested, but there are no known conversion that apply"
        end
    end

    # Exception raised when TypeStore.from_ruby encounters a value that has the
    # same type name than the requested type, but the types differ
    class ConversionToMismatchedType < UnknownConversionRequested
        def pretty_print(pp)
            pp.text "type mismatch when trying to convert #{value} to #{type}"
            pp.breakable
            pp.text "the value's definition is "
            value.class.pretty_print(pp, true)
            pp.breakable
            pp.text "the target type's definition is "
            type.pretty_print(pp, true)
        end
    end

    class DuplicateFieldError < RuntimeError; end

    class FieldNotFound < NotFound
    end
end
