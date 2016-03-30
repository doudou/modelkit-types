module ModelKit::Types
    class NotFound < ArgumentError; end
    class FieldNotFound < NotFound; end

    class InvalidTypeNameError < ArgumentError; end

    class UnknownFileTypeError < ArgumentError; end
    class DuplicateTypeNameError < ArgumentError; end
    class InvalidTypeNameError < ArgumentError; end
    class InvalidSizeSpecifiedError < ArgumentError; end

    # Exception raised when ModelKit::Types.from_ruby is called but the value cannot be
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

    # Exception raised when ModelKit::Types.from_ruby encounters a value that has the
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


    # Base class for all errors related to trying to merge registries that
    # cannot be merged together
    class InvalidMergeError < ArgumentError; end
    # Raised when attempting to merge two types that have different names
    class MismatchingTypeNameError < InvalidMergeError; end
    # Raised when attempting to merge two types that come from different base
    # models (e.g. CompoundType and EnumType)
    class MismatchingTypeModelError < InvalidMergeError; end
    # Raised when attempting to merge two types that have different sizes
    class MismatchingTypeSizeError < InvalidMergeError; end
    # Raised when attempting to merge two types that have different opaque flags
    class MismatchingTypeOpaqueFlagError < InvalidMergeError; end
    # Raised when attempting to merge two types that have different null flags
    class MismatchingTypeNullFlagError < InvalidMergeError; end
    # Raised when attempting to merge two compounds that have fields with the
    # same name but whose type names differ
    #
    # Only the type name is checked as the global consistency is ensured by
    # {Registry#merge}, not {Type#merge}
    class MismatchingFieldTypeError < InvalidMergeError; end
    # Raised when attempting to merge two compounds that have fields with the
    # same name but different offsets
    class MismatchingFieldOffsetError < InvalidMergeError; end
    # Raised when attempting to merge two compounds that have different sets of
    # fields
    class MismatchingFieldSetError < InvalidMergeError; end
    # Raised when attempting to merge two {IndirectType} that point to two
    # different types
    class MismatchingDeferencedTypeError < InvalidMergeError; end
    # Raised when attempting to merge two {EnumType} that have the same symbol
    # pointing to two different values
    class MismatchingEnumSymbolsError < InvalidMergeError; end
    # Raised when attempting to merge two {ContainerType} that are not from the
    # same container model
    class MismatchingContainerModel < InvalidMergeError; end
    # Raised when attempting to merge two {Registry} which use the same alias
    # for two different types
    class MismatchingAlias < InvalidMergeError; end

    # Raises when attempting an operation that required a type from a registry
    # (for a registry operation) or a type from the same registry as the
    # receiver (for a type operation), but passing a type from a different
    # registry
    class NotFromThisRegistryError < ArgumentError; end

    # Exception raised when a type is being setup with a buffer which does not
    # match the type's requirements
    class InvalidBuffer < ArgumentError; end
end
