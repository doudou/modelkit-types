module TypeStore
    module CXX
        # Convenience registry class that adds the builtin C++ types at construction
        # time
        class Registry < TypeStore::Registry
            def initialize
                super
                register_container_kind StdVector
                register_container_kind BasicString
                #Registry.add_standard_cxx_types(self)
            end

            def create_enum(typename, size: 4, **options, &block)
                super
            end
        end
    end
end
