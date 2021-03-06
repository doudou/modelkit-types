module ModelKit::Types
    module Models
        module IndirectType
            include Type

            # The type that is pointed-to by self
            attr_accessor :deference

            def ==(other)
                super && (deference == other.deference)
            end

            def setup_submodel(submodel, deference: nil, registry: self.registry, typename: nil, size: 0, opaque: false, null: false)
                submodel.deference = deference
                super(submodel, registry: registry, typename: typename, size: size, opaque: opaque, null: null)
                if deference
                    submodel.add_direct_dependency(deference)
                    submodel.fixed_buffer_size = deference.fixed_buffer_size?
                    submodel.contains_opaques = deference.contains_opaques? || deference.opaque?
                end
            end

            # Copies this type and all its dependent types to the given registry
            def copy_to(registry, **options)
                deference = (registry.find_by_name(self.deference.name) || self.deference.copy_to(registry))
                super(registry, deference: deference, **options)
            end

            def validate_merge(type)
                super
                if deference.name != type.deference.name
                    raise MismatchingDeferencedTypeError, "#{self} deferences to #{deference.name} and #{type} to #{type.deference.name}"
                end
            end
        end
    end
end

