module ModelKit::Types
    module CXX
        # Convenience registry class that adds the builtin C++ types at construction
        # time
        class Registry < ModelKit::Types::Registry
            def initialize
                super

                create_character '/char', size: 1
                create_character '/wchar_t', size: 4
                [1, 2, 4, 8].each do |size|
                    create_numeric NumericType.default_numeric_typename(size, true, false), size: size, integer: true, unsigned: false
                    create_numeric NumericType.default_numeric_typename(size, true, true), size: size, integer: true, unsigned: true
                end
                [4, 8].each do |size|
                    create_numeric NumericType.default_numeric_typename(size, false, false), size: size, integer: false
                end

                register_container_model StdVector
                register_container_model BasicString
            end

            def create_enum(typename, size: 4, **options, &block)
                super
            end
        end
    end
end
