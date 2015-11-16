module ModelKit::Types
    module CXX
        # Convenience registry class that adds the builtin C++ types at construction
        # time
        class Registry < ModelKit::Types::Registry
            def initialize
                super
                register_container_model StdVector
                register_container_model BasicString
            end

            def create_enum(typename, size: 4, **options, &block)
                super
            end
        end
    end
end
