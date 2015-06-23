module TypeStore
    module Models
        module ContainerType
            include IndirectType

            # The type of container
            #
            # The container hierarchy is different from the other types, as
            # there is always one class between {ContainerType} and the actual
            # container class. This class characterizes what type of container
            # it is
            def container_kind
                supermodel
            end

            # Whether this container has random-access capabilities
            def random_access?
                false
            end

            def setup_submodel(submodel, random_access: false, deference: nil, registry: self.registry, typename: nil, size: 0)
                super(submodel, deference: deference, registry: registry, typename: typename, size: size)

                if random_access
                    submodel.include RandomAccessContainer
                end

                submodel.convert_from_ruby Array do |value, expected_type|
                    t = expected_type.new
                    t.concat(value)
                    t
                end
                submodel.convert_from_ruby DeepCopyArray do |value, expected_type|
                    t = expected_type.new
                    t.concat(value)
                    t
                end
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { name: TypeName,
            #      class: NameOfTypeClass, # CompoundType, ...
            #       # The content of 'element' is controlled by the :recursive option
            #      element: DescriptionOfArrayElement,
            #      size: SizeOfTypeInBytes # Only if :layout_info is true
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                info = super
                info[:kind] = info[:class]
                info[:class] = "TypeStore::ContainerType"
                if deference
                    info[:element] =
                        if options[:recursive]
                            deference.to_h(options)
                        else
                            deference.to_h_minimal(options)
                        end
                end
                info
            end

            def ruby_convertion_candidates_on(ruby_mappings)
                super + (ruby_mappings.from_container_basename[container_kind.name] || Array.new)
            end
        end
    end
end

