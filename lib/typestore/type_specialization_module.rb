module TypeStore
    # Internal proxy class that is used to offer a nice way to get hold on types
    # in #specialize blocks.
    #
    # The reason of the existence of that class is that, in principle,
    # specialize block should not rely on the global availability of a type,
    # i.e. they should not rely on the fact that the underlying type registry
    # has been exported in a particular namespace.
    #
    # However, it also means that in every method in specialize blocks, one
    # would have to do type tricks like
    #
    #   self['field_name'].deference.deference
    #
    # which is not nice.
    #
    # This class is used so that the following scheme is possible instead:
    #
    #   TypeStore.specialize type_name do
    #      Subtype = self['field_name']
    #
    #      def my_method
    #        Subtype.new
    #      end
    #   end
    #
    class TypeSpecializationModule < Module # :nodoc:
        def included(obj)
            @base_type = obj
        end

        class TypeDefinitionAccessor # :nodoc:
            def initialize(specialization_module, ops)
                @specialization_module = specialization_module
                @ops = ops
            end

            def deference
                TypeDefinitionAccessor.new(@specialization_module, @ops + [[:deference]])
            end

            def [](name)
                TypeDefinitionAccessor.new(@specialization_module, @ops + [[:[], name]])
            end

            def method_missing(*mcall, &block)
                if !@type
                    base_type = @specialization_module.instance_variable_get(:@base_type)
                    if base_type
                        @type = @ops.inject(base_type) do |type, m|
                            type.send(*m)
                        end
                    end
                end

                if !@type
                    super
                else
                    @type.send(*mcall, &block)
                end
            end
        end

        def deference
            TypeDefinitionAccessor.new(self, [[:deference]])
        end

        def [](name)
            TypeDefinitionAccessor.new(self, [[:[], name]])
        end
    end
end

