module TypeStore
    module CXX
        # Convenience registry class that adds the builtin C++ types at construction
        # time
        class Registry < TypeStore::Registry
            def initialize
                super
                Registry.add_standard_cxx_types(self)
            end
        end
    end
end
