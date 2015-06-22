module TypeStore
    # Base class for pointer types
    #
    # When returned as fields of a structure, or as return values from a
    # function, pointers might be converted in the following cases:
    # * nil if it is NULL
    # * a String object if it is a pointer to char
    #
    # See the TypeStore module documentation for an overview about how types are
    # values are represented.
    class PointerType < IndirectType
        extend Models::PointerType
    end
end
