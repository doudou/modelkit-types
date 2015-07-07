module TypeStore
    module CXX
        # Convenience registry class that adds the builtin C++ types at construction
        # time
        class Registry < TypeStore::Registry
            def initialize
                super
                register_container_model StdVector
                register_container_model BasicString
                create_numeric '/char', integer: true, unsigned: false, size: 1
                create_container BasicString, get('/char'), typename: '/std/string'
            end

            def create_enum(typename, size: 4, **options, &block)
                super
            end
        end
    end
end
