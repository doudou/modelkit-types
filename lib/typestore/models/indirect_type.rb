module TypeStore
    module Models
        module IndirectType
            include Type

            # The type that is pointed-to by self
            attr_accessor :deference

            def setup_submodel(submodel, deference: nil, registry: self.registry, typename: nil, size: 0)
                submodel.deference = deference
                super(submodel, registry: registry, typename: typename, size: size)
                if deference
                    submodel.direct_dependencies << deference
                    submodel.contains_opaques = deference.contains_opaques? || deference.opaque?
                    submodel.contains_converted_types = deference.contains_converted_types? || deference.needs_convertion_to_ruby?
                end
            end
        end
    end
end

