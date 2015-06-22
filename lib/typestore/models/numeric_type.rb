module TypeStore
    module Models
        module NumericType
            include Type

            # Whether this represents an integer or floating-point type
            attr_predicate :integer?, true
            # Whether this represents a signed or unsigned integer
            attr_predicate :unsigned?, true

            DEFAULT_TYPENAMES =
                Hash[[true, true] => '/uint',
                     [true, false] => '/int',
                     [false, true] => '/float',
                     [false, false] => '/float']

            def default_numeric_typename(size, integer, unsigned)
                "#{DEFAULT_TYPENAMES[[integer,unsigned]]}#{size * 8}"
            end

            def setup_submodel(submodel,  size: 0, integer: true, unsigned: false,
                typename: default_numeric_typename(size, integer, unsigned), &block)
                super(submodel, typename: typename, size: size, &block)

                submodel.integer = integer
                submodel.unsigned = unsigned
                pack_code = submodel.pack_code
                if submodel.integer?
                    convert_to_ruby(Numeric) { |value| value.buffer.unpack(pack_code).first }
                else
                    convert_to_ruby(Float) { |value| value.buffer.unpack(pack_code).first }
                end
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { 'name' => TypeName,
            #      'class' => 'EnumType',
            #      'integer' => Boolean,
            #      # Only for integral types
            #      'unsigned' => Boolean,
            #      # Unlike with the other types, the 'size' field is always present
            #      'size' => SizeOfTypeInBytes 
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                info = super
                info[:size] = size
                if integer?
                    info[:integer] = true
                    info[:unsigned] = unsigned?
                else
                    info[:integer] = false
                end
                info
            end

            # Pack codes as [size, unsigned?, big_endian?] => code
            INTEGER_PACK_CODES = Hash[
                # a.k.a. /(u)int8_t
                [1, true, false]  => 'C',
                [1, true, true]   => 'C',
                [1, false, false] => 'c',
                [1, false, true]  => 'c',
                # a.k.a. /(u)int16_t
                [2, true, false]  => 'S<',
                [2, true, true]   => 'S>',
                [2, false, false] => 's<',
                [2, false, true]  => 's>',
                # a.k.a. /(u)int32_t
                [4, true, false]  => 'L<',
                [4, true, true]   => 'L>',
                [4, false, false] => 'l<',
                [4, false, true]  => 'l>',
                # a.k.a. /(u)int64_t
                [8, true, false]  => 'Q<',
                [8, true, true]   => 'Q>',
                [8, false, false] => 'q<',
                [8, false, true]  => 'q>']
            FLOAT_PACK_CODES = Hash[
                # a.k.a. /float
                [4, false]  => 'e',
                [4, true]   => 'g',
                # a.k.a. /double
                [8, false]  => 'E',
                [8, true]   => 'G']

            # Returns the Array#pack code that matches this type
            #
            # The endianness is the one of the local OS
            def pack_code
                if integer?
                    INTEGER_PACK_CODES[[size, unsigned?, TypeStore.big_endian?]]
                else
                    FLOAT_PACK_CODES[[size, TypeStore.big_endian?]]
                end
            end

            def initialize_base_class
                super
                self.name = "TypeStore::NumericType"
            end
        end
    end
end


